# Git Safe Flow 脚本规范

## 1. 目标

用一套 PowerShell 脚本封装日常 Git 提交流程中高频、高危的操作，在**不改变现有工作习惯**的前提下，加入逐层校验和确认，避免以下问题：

- 误提交 dist 到业务分支
- 合并前未 review 实际 diff
- 远程分支被其他人推进后仍继续操作
- 工作区变更未经确认直接 commit
- 没有安全兜底（stash 残留、操作中断无法恢复）

## 2. 设计原则

| 原则 | 说明 |
|------|------|
| **单文件** | 一个 `.ps1`，无依赖，`$ErrorActionPreference = "Stop"` |
| **参数驱动** | 7 个动作通过 `-Action` 选择，行为由参数控制，无硬编码分支名 |
| **逐层校验** | 每一步操作前检查前置条件，不满足则中止 |
| **人工确认** | 关键节点要求用户输入指定关键字，`-AutoConfirm` 可跳过 |
| **安全兜底** | stash 保留到 commit/push 成功后才 drop，中断后可直接续跑 |

## 3. 参数清单

```
-Action          [必填] 动作名，7 选 1
-Remote          [可选] 远程仓库名，默认 "origin"
-BaseBranch      [可选] 基准分支名（SubmitSelf / SquashSelf 需要）
-SourceBranch    [可选] 源分支名（SubmitSelf / Promote / Check / SquashSelf 需要）
-TargetBranch    [可选] 目标分支名（PickToTarget / Promote / Check / Verify 需要）
-Message         [可选] 提交信息（SubmitSelf / PickToTarget 需要）
-PickBranch      [可选] pick 分支名（PickToTarget 需要）
-PickCommit      [可选] 要 cherry-pick 的 commit hash（PickToTarget 模式 B 需要）
-PatchPath       [可选] 补丁文件路径（PickToTarget 模式 A 需要）
-DistMode        [可选] dist 处理方式：Include（含 dist）或 Exclude（排除 dist），默认 Include
-BuildScript     [可选] 构建脚本名，如 "build:beta"，留空则不构建
-DistPath        [可选] dist 目录路径，默认 "dist"
-CreateSourceBranch [开关] SourceBranch 不存在时自动创建
-FullDiff        [开关] 显示完整 diff（默认只显示 stat）
-AutoConfirm     [开关] 跳过人工确认，全自动执行
```

## 4. 动作详解

### 4.1 SubmitSelf

**用途**：将当前工作区变更提交到指定的 `SourceBranch`，自动同步基准分支。

**前置条件**：
- 在业务开发分支上有未提交的变更（working tree 不干净或有未跟踪文件）

**执行流程**：

```
记录当前分支
  │
  ├─ 展示 working diff + staged diff（人工确认 STASH）
  │
  ├─ git stash push -u -m "git-safe-flow-before-pull-<SourceBranch>"
  │    记录 stash hash 作为安全标记
  │
  ├─ git fetch origin
  ├─ git switch BaseBranch
  ├─ git pull --ff-only origin BaseBranch
  │
  ├─ git switch SourceBranch（不存在则按 -CreateSourceBranch 处理）
  ├─ git pull --ff-only origin SourceBranch（如果远程存在）
  │
  ├─ git merge --no-edit origin/BaseBranch
  │
  ├─ git stash apply --index <stashHash>
  │    └─ 冲突时：DistMode=Exclude → 自动解决 dist 冲突并排除
  │         DistMode=Include → 报错，提示手动解决后运行 ContinueSubmitSelf
  │
  ├─ 展示恢复后的 working diff（人工确认 COMMIT）
  │
  ├─ DistMode=Exclude → git add -A -- . ':!dist'
  │   DistMode=Include → git add -A
  ├─ 检查暂存区 whitespace 错误
  │
  ├─ 展示 staged diff（人工确认 PUSHSELF）
  │
  ├─ git commit -m <Message>
  ├─ git fetch origin
  ├─ git push origin SourceBranch
  │
  └─ git stash drop stash@{0}（仅当 stash hash 未变时）
```

**关键安全机制**：
- stash 保留到 push 成功后才 drop
- 冲突时不会静默覆盖，明确要求手动解决
- DistMode=Exclude 模式下自动排除 dist 文件
- 提交前两次确认：一次确认 working tree 内容，一次确认 staged 内容

**输出**：`SourceBranch` 上新增一个 commit，工作区恢复原状

---

### 4.2 ContinueSubmitSelf

**用途**：SubmitSelf 中断后，手动解决冲突后继续提交。

**前置条件**：
- 当前分支已经是 `SourceBranch`
- 冲突已手动解决

**执行流程**：

```
├─ DistMode=Exclude → Resolve-DistConflictsAndRestore（自动 checkout --ours 解决 dist 冲突）
│   DistMode=Include → 检查无未合并文件
│
├─ 展示 working diff（人工确认 COMMIT）
├─ Stage-SubmitChanges（按 DistMode 决定是否排除 dist）
├─ 检查 whitespace
├─ 展示 staged diff（人工确认 PUSHSELF）
│
├─ git commit -m <Message>
├─ git fetch origin
└─ git push origin SourceBranch
```

**输出**：补完提交并推送

---

### 4.3 PickToTarget

**用途**：从目标分支创建 pick 分支，通过两种模式注入变更，推送后供合并。

**前置条件**：
- 提供 `-PickCommit`（模式 B cherry-pick）或 `-PatchPath`（模式 A 补丁 apply），二选一
- 模式 B 要求工作区干净

**执行流程**：

```
模式 A: 补丁 apply（-PatchPath）
─────────────────────────────────
├─ 读取补丁文件
├─ git switch TargetBranch
├─ git pull --ff-only origin TargetBranch
│   └─ 记录 remoteTargetBefore commit hash
│
├─ git switch -c PickBranch
│
├─ git apply --index <PatchPath>
│   └─ 检查 staged files 是否为空
│
├─ 展示 patch 的 files / diff stat（人工确认 PUSHPICK）
│
├─ git commit -m <Message>
├─ git fetch origin
└─ git push origin PickBranch


模式 B: cherry-pick（-PickCommit）
───────────────────────────────────
├─ git switch TargetBranch
├─ git pull --ff-only origin TargetBranch
│   └─ 记录 remoteTargetBefore commit hash
│
├─ git switch -c PickBranch
│
├─ 对每个 commit 执行 git cherry-pick <commit>
│   └─ 失败则中止，提示手动解决
│
├─ 检查 pick 范围内有 commits 且有 file changes
├─ 展示 picked commits / files / diff stat（人工确认 PUSHPICK）
│
├─ 检查 remote TargetBranch 是否推进（remoteTargetBefore == remoteTargetAfter）
├─ 检查远程是否已存在 PickBranch
│
└─ git push origin PickBranch
```

**关键安全机制**：
- pick 分支名必须唯一（本地和远程都不存在）
- push 前再次确认远程 TargetBranch 未推进
- 补丁模式跳过 working tree 检查（因为工作区已 stash）
- cherry-pick 模式严格检查 pick 后是否有实际 file changes

**输出**：远程创建 `PickBranch`，包含注入的变更

---

### 4.4 Promote-Branch

**用途**：将 `SourceBranch` 合并到 `TargetBranch`，可选构建 dist 并提交。

**前置条件**：
- 工作区干净
- SourceBranch 远程存在

**执行流程**：

```
├─ git fetch origin
├─ 检查 SourceBranch 远程存在
├─ git switch TargetBranch
│   └─ 远程存在 → git pull --ff-only origin TargetBranch
│
├─ 检查合并范围是否有 commits 和 file changes
├─ Show-PromotePreview（展示 commits / files / diff stat）
│
├─ 人工确认：MERGE
│
├─ git merge --no-edit origin/SourceBranch
│   └─ 检查 ORIG_HEAD..HEAD 有实际 file changes
│
├─ 展示实际 merge 的 files / diff stat
│
├─ 人工确认：PUSH（确认无静默覆盖）
│
├─ git fetch origin
│   └─ 检查 remote TargetBranch 未推进
│
├─ git push origin TargetBranch
│
└─ [可选] 构建 dist（-BuildScript 非空时）
    ├─ npm run <BuildScript>
    │   └─ 检查构建产物仅落在 DistPath 内
    ├─ git add -- <DistPath>
    ├─ git commit -m "build: <TargetBranch> dist"
    └─ git push origin TargetBranch
```

**关键安全机制**：
- merge 前展示完整 preview
- merge 后对比 ORIG_HEAD..HEAD，防止空合并
- push 前再次确认远程未推进
- 构建产物严格限定在 DistPath，超出则报错

**输出**：TargetBranch 合并了 SourceBranch 的变更，可能附带一个 build dist commit

---

### 4.5 Check-Only

**用途**：查看当前状态或预览即将合并的内容，不修改任何东西。

**执行流程**：

```
├─ git status -sb
│
├─ 如果提供了 SourceBranch 和 TargetBranch：
│   ├─ git fetch origin
│   ├─ 检查两个分支远程存在
│   ├─ git switch TargetBranch（本地不存在则 --track 创建）
│   ├─ git pull --ff-only origin TargetBranch
│   └─ Show-PromotePreview（展示 Source -> Target 的 preview）
│
└─ 否则仅展示 working diff
```

**输出**：只读信息，无副作用

---

### 4.6 Verify-Branch

**用途**：校验本地 `TargetBranch` 与远程完全同步，确保推送后双方一致。

**执行流程**：

```
├─ git status -sb（检查工作区干净）
├─ git fetch origin
├─ 检查 TargetBranch 远程存在且本地存在
│
├─ 展示 local / remote commit ids
│
├─ 检查本地是否落后远程（TargetBranch..origin/TargetBranch）
│   └─ 落后则报错，要求先 pull --ff-only
│
├─ 检查 local hash == remote hash
│   └─ 不一致则报错
│
└─ 展示最新 commit 详情
```

**输出**：校验通过则退出码 0，否则报错

---

### 4.7 Squash-Self

**用途**：将 SourceBranch 上相对于 BaseBranch 的所有 commit squashing 成一个。

**前置条件**：
- 工作区干净
- SourceBranch 上相对 BaseBranch 有多个 commit

**执行流程**：

```
├─ git fetch origin
├─ git switch SourceBranch
├─ 统计 <Remote/BaseBranch>..HEAD 的 commit 数量
│   └─ <= 1 则跳过
│
├─ 展示要 squash 的 commit 列表
├─ 人工确认：SQUASH
│
├─ git rebase -i <Remote/BaseBranch>
│   └─ 需要手动编辑 todo list（脚本提示手动操作）
│
└─ force-with-lease push（用户自行执行）
```

**注意**：由于 PowerShell 无法优雅处理交互式 rebase 的 sequence editor，此步骤需要用户手动在 GitLens 或终端中完成。

**输出**：SourceBranch 上的多个 commit 合并为一个

---

## 5. 辅助函数说明

| 函数 | 用途 |
|------|------|
| `Invoke-Git` | 统一执行 git 命令，失败时 throw |
| `Get-GitOutput` | 执行 git 命令并返回输出字符串 |
| `Test-GitRef` | 检查 ref 是否存在（本地或远程） |
| `Assert-GitRepository` | 确保在 git 仓库内 |
| `Assert-NoGitOperationInProgress` | 检查无 MERGE/REBASE/CHERRY-PICK/REVERT 进行中 |
| `Get-CurrentBranch` | 获取当前分支名，detached HEAD 时报错 |
| `Test-HasWorkingChanges` | 检查 working tree 是否有变更 |
| `Get-UntrackedFiles` | 获取未跟踪文件列表 |
| `Test-FileLooksBinary` | 判断文件是否二进制（用于 preview 时跳过） |
| `Show-UntrackedFiles` | 展示未跟踪文件（-FullDiff 时显示文本预览） |
| `Test-RevisionRangeHasCommits` | 检查 revision range 是否有 commit |
| `Test-RevisionRangeHasFileChanges` | 检查 revision range 是否有 file changes |
| `Show-WorkingDiff` | 展示 working tree 状态和 diff |
| `Show-CachedDiff` | 展示 staged 状态和 diff |
| `Confirm-Exact` | 要求用户输入指定关键字，-AutoConfirm 时跳过 |
| `Assert-Required` | 检查必填参数非空 |
| `Ensure-RemoteBranch` | 确保远程分支存在 |
| `Get-UnmergedFiles` | 获取冲突文件列表 |
| `Test-IsDistPath` | 判断路径是否属于 dist |
| `Assert-NoStagedDist` | 确保 staged 中无 dist 文件（DistMode=Exclude 时用） |
| `Assert-NoUnmergedFiles` | 确保无冲突文件 |
| `Resolve-DistConflictsAndRestore` | DistMode=Exclude 时自动解决 dist 冲突 |
| `Assert-HasStagedChanges` | 确保 staged 非空 |
| `Drop-SafeStash` | commit/push 成功后 drop stash（检查 hash 未变） |
| `Stage-SubmitChanges` | 按 DistMode 决定 add 范围 |
| `Switch-ToSourceBranch` | 切换/创建 SourceBranch |
| `Show-PromotePreview` | 展示 Source -> Target 的 preview |
| `Write-Section` | 输出带颜色标题 |

## 6. 覆盖的流程场景

### 6.1 日常开发提交流程

```
开发者在 dev 分支开发
  │
  ├─ git add .
  ├─ .\git-safe-flow.ps1 -Action SubmitSelf -BaseBranch "main" -SourceBranch "dev" -Message "feat: xxx"
  │     └─ 自动：stash → 同步 main → merge main into dev → restore stash → commit → push
  │
  └─ 完成
```

### 6.2 带 dist 排除的提交

```
开发者在 dev 分支开发，dist/ 是构建产物不应提交
  │
  ├─ .\git-safe-flow.ps1 -Action SubmitSelf -BaseBranch "main" -SourceBranch "dev" -DistMode Exclude -Message "feat: xxx"
  │     └─ 自动：git add -A -- . ':!dist'，排除 dist 文件
  │
  └─ 完成
```

### 6.3 冲突解决后继续提交

```
SubmitSelf 执行中 stash apply 冲突
  │
  ├─ 手动解决冲突
  ├─ .\git-safe-flow.ps1 -Action ContinueSubmitSelf -SourceBranch "dev" -Message "feat: xxx"
  │     └─ 自动：检查无冲突 → commit → push
  │
  └─ 完成
```

### 6.4 Pick 分支流程（cherry-pick 模式）

```
已有 commit hash 需要精确挑选到 beta
  │
  ├─ .\git-safe-flow.ps1 -Action PickToTarget -TargetBranch "beta" -PickBranch "pick/feat-xxx-beta-20260806" -PickCommit "abc1234" -Message "feat: xxx"
  │     └─ 自动：切 beta → 创建 pick 分支 → cherry-pick → 校验 → push
  │
  └─ 完成
```

### 6.5 Pick 分支流程（补丁模式）

```
工作区有未提交变更，通过补丁注入到 beta
  │
  ├─ 手动：git diff --cached --binary --output="C:\temp\patch.diff"
  ├─ 手动：git stash push -u -m "before-feat"
  │
  ├─ .\git-safe-flow.ps1 -Action PickToTarget -TargetBranch "beta" -PickBranch "pick/feat-xxx-beta-20260806" -PatchPath "C:\temp\patch.diff" -Message "feat: xxx"
  │     └─ 自动：切 beta → 创建 pick 分支 → apply 补丁 → 校验 → commit → push
  │
  ├─ .\git-safe-flow.ps1 -Action Promote -SourceBranch "pick/feat-xxx-beta-20260806" -TargetBranch "beta" -BuildScript "build:beta"
  │     └─ 自动：merge pick → beta → 构建 dist → commit → push
  │
  ├─ 手动：git switch dev
  └─ 手动：git stash apply --index stash@{0}
```

### 6.6 Promote 到 beta + 构建

```
pick 分支就绪，需要合并到 beta 并构建 dist
  │
  ├─ .\git-safe-flow.ps1 -Action Promote -SourceBranch "pick/feat-xxx-beta-20260806" -TargetBranch "beta" -BuildScript "build:beta"
  │     └─ 自动：merge → push beta → npm run build:beta → 校验仅 dist 变更 → commit dist → push
  │
  └─ 完成
```

### 6.7 Promote 到 production

```
beta 验证通过，需要发布到 production
  │
  ├─ .\git-safe-flow.ps1 -Action Promote -SourceBranch "pick/feat-xxx-beta-20260806" -TargetBranch "production"
  │     └─ 自动：merge → push production（无构建）
  │
  └─ 完成
```

### 6.8 查看合并预览

```
合并前想先看会合入什么内容
  │
  ├─ .\git-safe-flow.ps1 -Action Check -SourceBranch "dev" -TargetBranch "beta"
  │     └─ 自动：fetch → 展示 Source -> Target 的 preview
  │
  └─ 无副作用
```

### 6.9 校验分支同步

```
推送后需要确认本地与远程一致
  │
  ├─ .\git-safe-flow.ps1 -Action Verify -TargetBranch "beta"
  │     └─ 自动：检查本地/远程 commit hash 一致
  │
  └─ 通过则退出码 0，否则报错
```

### 6.10 压缩分支 commit

```
SourceBranch 上有多个零散 commit，需要 squashing
  │
  ├─ .\git-safe-flow.ps1 -Action Squash-Self -BaseBranch "main" -SourceBranch "dev"
  │     └─ 展示待 squash 的 commits → 人工确认 → 自动执行 rebase -i（GIT_SEQUENCE_EDITOR）→ 展示结果 → 人工确认 → force-with-lease push
  │
  └─ 完成，无需手动操作
```

### 6.11 首次创建远程分支

```
新功能需要创建远程分支并提交
  │
  ├─ .\git-safe-flow.ps1 -Action SubmitSelf -BaseBranch "main" -SourceBranch "feat/xxx" -CreateSourceBranch -Message "feat: xxx"
  │     └─ 自动：创建本地分支 feat/xxx → merge main → commit → push（首次 push 创建远程分支）
  │
  └─ 完成
```

### 6.12 全自动流程（CI/无人值守）

```
自动化场景，不需要人工确认
  │
  ├─ .\git-safe-flow.ps1 -Action SubmitSelf -BaseBranch "main" -SourceBranch "dev" -Message "feat: xxx" -AutoConfirm
  ├─ .\git-safe-flow.ps1 -Action Promote -SourceBranch "dev" -TargetBranch "beta" -BuildScript "build:beta" -AutoConfirm
  │
  └─ 完成
```

### 6.13 一键全流程（本地日常使用）

```
工作区有变更，需要走完"提交 → pick → promote → verify"全链路
  │
  ├─ 编辑 git-safe-flow-full.ps1 底部的配置区
  │   （Remote / BaseBranch / SourceBranch / Feature / TargetBranch / BuildScript）
  │
  ├─ .\git-safe-flow-full.ps1
  │     └─ 自动串联：
  │         步骤 1: SubmitSelf → 提交业务代码到 SourceBranch
  │         步骤 2: PickToTarget → 从 SourceBranch 创建 PickBranch 并推送
  │         步骤 3: Promote → 合并 PickBranch 到 TargetBranch（可选构建 dist）
  │         步骤 4: Verify → 校验 TargetBranch 与远程同步
  │
  └─ 无论成功失败，finally 块自动切回起始分支
```

**配置示例**（`git-safe-flow-full.ps1` 底部）：

```powershell
$Remote       = "origin"
$BaseBranch   = "main"
$SourceBranch = "dev"
$Feature      = "smart-image-gen"
$TargetBranch = "beta"
$BuildScript  = "build:beta"
$DistPath     = "dist"
$DistMode     = "Exclude"
```

---

## 7. 未覆盖的场景

| 场景 | 原因 | 替代方案 |
|------|------|---------|
| 多 remote 管理 | 脚本固定一个 `$Remote` | 手动切换 remote 后运行脚本 |
| tag 管理 | 发布打标不属于日常提交流程 | 手动 `git tag` + `git push --tags` |
| 回滚/ revert | 属于应急操作，需要逐案分析 | 手动 `git revert` |
| submodule 操作 | 超出脚本范围 | 手动 `git submodule` 命令 |

---

## 8. 已实现的优化

### 8.1 SquashSelf 全自动化

**实现方式**：创建临时 PowerShell 脚本作为 `GIT_SEQUENCE_EDITOR`，在 `git rebase -i` 启动时自动将 todo list 中非首行的 `pick` 替换为 `squash`。

```
旧流程：展示 commits → 人工确认 → 提示手动 rebase -i → 用户在 GitLens 编辑
新流程：展示 commits → 人工确认 → 自动 rebase -i（GIT_SEQUENCE_EDITOR）→ 展示结果 → 确认 → force-with-lease push
```

### 8.2 PickToTarget 自动导出补丁

**新增参数**：`-ExportPatch`（开关）

```
旧流程：手动 git add → git diff --cached --binary --output=xxx.patch → git stash → 运行 PickToTarget -PatchPath
新流程：git add → 运行 PickToTarget -ExportPatch -TargetBranch beta -Message "feat: xxx"
        └─ 自动：导出 staged changes 为 temp patch → apply 补丁 → commit → push
```

**自动补丁路径**：`<TempPath>\<feature-from-message>-<yyyyMMdd-HHmmss>.patch`

### 8.3 一键全流程 wrapper

**新增脚本**：`git-safe-flow-full.ps1`

```
串联四个步骤，finally 块确保切回起始分支：
  SubmitSelf → PickToTarget → Promote → Verify
```

任何一步失败都会中断，用户解决后可重新运行（已推送的分支不会重复操作）。

### 8.4 推荐的工作流配置

```powershell
# 方式一：分别执行（灵活控制每一步）
.\git-safe-flow.ps1 -Action SubmitSelf `
    -BaseBranch "main" -SourceBranch "dev" -Message "feat: xxx" -DistMode Exclude

.\git-safe-flow.ps1 -Action PickToTarget `
    -TargetBranch "beta" -PickBranch "pick/xxx-beta-20260806" `
    -SourceBranch "dev" -Message "feat: xxx"

.\git-safe-flow.ps1 -Action Promote `
    -SourceBranch "pick/xxx-beta-20260806" -TargetBranch "beta" -BuildScript "build:beta"

# 方式二：一键全流程（推荐日常使用）
# 编辑 git-safe-flow-full.ps1 底部的配置区，然后：
.\git-safe-flow-full.ps1
```

## 7. 未覆盖的场景

| 场景 | 原因 | 替代方案 |
|------|------|---------|
| 多 remote 管理 | 脚本固定一个 `$Remote` | 手动切换 remote 后运行脚本 |
| tag 管理 | 发布打标不属于日常提交流程 | 手动 `git tag` + `git push --tags` |
| 回滚/ revert | 属于应急操作，需要逐案分析 | 手动 `git revert` |
| submodule 操作 | 超出脚本范围 | 手动 `git submodule` 命令 |

---

## 8. 已实现的优化

### 8.1 SquashSelf 全自动化

**实现方式**：创建临时 PowerShell 脚本作为 `GIT_SEQUENCE_EDITOR`，在 `git rebase -i` 启动时自动将 todo list 中非首行的 `pick` 替换为 `squash`。

```
旧流程：展示 commits → 人工确认 → 提示手动 rebase -i → 用户在 GitLens 编辑
新流程：展示 commits → 人工确认 → 自动 rebase -i（GIT_SEQUENCE_EDITOR）→ 展示结果 → 确认 → force-with-lease push
```

### 8.2 PickToTarget 自动导出补丁

**新增参数**：`-ExportPatch`（开关）

```
旧流程：手动 git add → git diff --cached --binary --output=xxx.patch → git stash → 运行 PickToTarget -PatchPath
新流程：git add → 运行 PickToTarget -ExportPatch -TargetBranch beta -Message "feat: xxx"
        └─ 自动：导出 staged changes 为 temp patch → apply 补丁 → commit → push
```

**自动补丁路径**：`<TempPath>\<feature-from-message>-<yyyyMMdd-HHmmss>.patch`

### 8.3 一键全流程 wrapper

**新增脚本**：`git-safe-flow-full.ps1`

```
串联四个步骤，finally 块确保切回起始分支：
  SubmitSelf → PickToTarget → Promote → Verify
```

任何一步失败都会中断，用户解决后可重新运行（已推送的分支不会重复操作）。

### 8.4 推荐的工作流配置

```powershell
# 方式一：分别执行（灵活控制每一步）
.\git-safe-flow.ps1 -Action SubmitSelf `
    -BaseBranch "main" -SourceBranch "dev" -Message "feat: xxx" -DistMode Exclude

.\git-safe-flow.ps1 -Action PickToTarget `
    -TargetBranch "beta" -PickBranch "pick/xxx-beta-20260806" `
    -SourceBranch "dev" -Message "feat: xxx"

.\git-safe-flow.ps1 -Action Promote `
    -SourceBranch "pick/xxx-beta-20260806" -TargetBranch "beta" -BuildScript "build:beta"

# 方式二：一键全流程（推荐日常使用）
# 编辑 git-safe-flow-full.ps1 底部的配置区，然后：
.\git-safe-flow-full.ps1
```

## 9. 安全机制一览

```
执行前检查
├─ Assert-GitRepository         确保在 git 仓库内
├─ Assert-NoGitOperationInProgress 无进行中的 merge/rebase/cherry-pick
├─ Assert-Required               必填参数非空
├─ Ensure-RemoteBranch           远程分支存在
├─ Test-HasWorkingChanges        工作区状态检查
└─ Test-GitRef                   ref 存在性检查

执行中保护
├─ $ErrorActionPreference = "Stop"  任何错误立即中止
├─ Confirm-Exact                   关键节点人工确认
├─ 远程分支推进检测                 push 前再次检查 remoteTargetBefore/After
├─ pick 分支唯一性检查              本地和远程都不存在才允许创建
├─ 构建产物范围校验                 构建后检查变更是否超出 DistPath
└─ 空提交保护                      检查 staged / merged 后是否有实际 file changes

执行后兜底
├─ Drop-SafeStash                 仅当 stash hash 未变时 drop
├─ 工作区恢复                      SubmitSelf 失败后切回原分支
└─ 未合并文件检查                   冲突不自动覆盖，要求手动解决
```
