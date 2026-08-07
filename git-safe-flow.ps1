<#
.SYNOPSIS
    Git Safe Flow - production 起始的 feature 分支交付流程
.DESCRIPTION
    固定流程：production -> feature -> (可选) dev -> beta -> 验收 -> production
    feature 只能从 production 创建；业务提交默认排除 dist；提交前必须 squash；
    dev 可选且不带 dist；beta 构建 dist；production 必须在 beta 后并明确确认。
.NOTES
    Author: xiongyonghua
    Version: 3.0.0
#>

[CmdletBinding()]
param()

$script:Remote = "origin"
$script:BaseBranch = "production"

function Invoke-Git {
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromRemainingArguments = $true)][string[]]$Arguments)
    & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') 执行失败，退出码：$LASTEXITCODE"
    }
}

function Get-CurrentBranch { return (git branch --show-current).Trim() }

function Test-LocalBranch {
    param([Parameter(Mandatory)][string]$BranchName)
    git show-ref --verify --quiet "refs/heads/$BranchName" 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Test-RemoteBranch {
    param([Parameter(Mandatory)][string]$BranchName)
    git show-ref --verify --quiet "refs/remotes/$($script:Remote)/$BranchName" 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Get-RemoteHead {
    param([Parameter(Mandatory)][string]$BranchName)
    $head = (git rev-parse "$($script:Remote)/$BranchName" 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $head) {
        throw "远程分支 $($script:Remote)/$BranchName 不存在，请先同步远程仓库。"
    }
    return $head
}

function Assert-WorkingTreeClean {
    param([string]$Context = "")
    $status = @(git status --short --untracked-files=all)
    if ($status) {
        $suffix = if ($Context) { "（$Context）" } else { "" }
        throw "工作区不干净$suffix，请先处理以下变更：$([Environment]::NewLine)$($status -join [Environment]::NewLine)"
    }
}

function Assert-FeatureBranch {
    param([Parameter(Mandatory)][string]$FeatureBranch)
    if ([string]::IsNullOrWhiteSpace($FeatureBranch)) { throw "FeatureBranch 不能为空。" }
    if (@("production", "beta", "dev", "main", "master") -contains $FeatureBranch) {
        throw "$FeatureBranch 是受保护分支，必须使用 feature 分支。"
    }
    if ($FeatureBranch -match '^origin/') {
        throw "FeatureBranch 不能填写远程引用，请填写本地分支名。"
    }
}

function Assert-CurrentFeature {
    param([Parameter(Mandatory)][string]$FeatureBranch)
    Assert-FeatureBranch -FeatureBranch $FeatureBranch
    $current = Get-CurrentBranch
    if ($current -ne $FeatureBranch) {
        throw "当前分支是 $current，不是指定的 feature 分支 $FeatureBranch。"
    }
}

function Sync-Remote {
    Invoke-Git fetch $script:Remote --prune
    [void](Get-RemoteHead -BranchName $script:BaseBranch)
}

function Get-ChangedPaths {
    param([Parameter(Mandatory)][string]$BaseRef, [Parameter(Mandatory)][string]$SourceRef)
    return @(git diff --name-only "$BaseRef...$SourceRef") | Where-Object { $_ } | Sort-Object -Unique
}

function Get-UntrackedAndChangedPaths {
    return @(
        git diff --name-only
        git diff --cached --name-only
        git ls-files --others --exclude-standard
    ) | Where-Object { $_ } | Sort-Object -Unique
}

function Test-IsDistPath {
    param([Parameter(Mandatory)][string]$Path)
    return ($Path -eq "dist" -or $Path -like "dist/*" -or $Path -like "dist\*")
}

function Confirm-SafeAction {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$Keyword,
        [switch]$AutoConfirm
    )
    if ($AutoConfirm) { return }
    $answer = Read-Host "$Prompt 请输入 $Keyword 继续"
    if ($answer -cne $Keyword) { throw "未输入 $Keyword，操作已取消。" }
}

function Save-WorkingTreeBackup {
    param([Parameter(Mandatory)][string]$Reason)
    $status = @(git status --short --untracked-files=all)
    if (-not $status) { return $null }
    $label = "git-safe-flow-backup-$Reason-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Invoke-Git stash push -u -m $label
    $hash = (git rev-parse "stash@{0}").Trim()
    if ($LASTEXITCODE -ne 0 -or -not $hash) { throw "安全 stash 创建失败，未继续操作。" }
    Write-Host "   🛡️ 已保留安全备份：$hash（$label）" -ForegroundColor Yellow
    return [pscustomobject]@{ Ref = "stash@{0}"; Hash = $hash }
}

function Restore-WorkingTreeBackup {
    param([Parameter(Mandatory)]$Backup)
    Write-Host "   ♻️ 恢复工作区安全备份 $($Backup.Hash)" -ForegroundColor Yellow
    Invoke-Git stash apply --index $Backup.Ref
}

function Remove-WorkingTreeBackup {
    param([Parameter(Mandatory)]$Backup)
    $currentHash = (git rev-parse "stash@{0}" 2>$null).Trim()
    if ($LASTEXITCODE -eq 0 -and $currentHash -eq $Backup.Hash) {
        Invoke-Git stash drop $Backup.Ref
        Write-Host "   ✅ 已在提交并推送成功后移除安全备份 $($Backup.Hash)" -ForegroundColor Green
    }
    else {
        Write-Host "   ⚠️ 安全备份未自动删除，请保留并人工确认：$($Backup.Hash)" -ForegroundColor Yellow
    }
}

function New-Feature {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$FeatureBranch, [string]$BaseBranch = "production")
    Assert-FeatureBranch -FeatureBranch $FeatureBranch
    if ($BaseBranch -cne $script:BaseBranch) {
        throw "新 feature 分支只能基于 production 创建，禁止使用 $BaseBranch。"
    }
    Assert-WorkingTreeClean -Context "创建 feature 分支前"
    Sync-Remote
    if (Test-LocalBranch -BranchName $FeatureBranch) {
        throw "本地分支 $FeatureBranch 已存在，脚本不会 reset 或删除它。"
    }
    if (Test-RemoteBranch -BranchName $FeatureBranch) {
        throw "远程分支 $($script:Remote)/$FeatureBranch 已存在，请换一个分支名。"
    }
    Invoke-Git switch -c $FeatureBranch "$($script:Remote)/$script:BaseBranch"
    Write-Host "✅ 已从 $($script:Remote)/$script:BaseBranch 创建 $FeatureBranch" -ForegroundColor Green
}

function Submit-Feature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FeatureBranch,
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("Exclude", "Include")][string]$DistMode = "Exclude",
        [switch]$AutoConfirm
    )
    Assert-CurrentFeature -FeatureBranch $FeatureBranch
    Sync-Remote
    $backup = $null
    try {
        $backup = Save-WorkingTreeBackup -Reason "submit"
        if (-not $backup) { throw "当前没有可提交的变更。" }
        Restore-WorkingTreeBackup -Backup $backup
        Invoke-Git reset
        if ($DistMode -eq "Exclude") {
            Invoke-Git add -A -- . ":(exclude)dist/**"
        }
        else { Invoke-Git add -A }
        $staged = @(git diff --cached --name-only) | Where-Object { $_ }
        if (-not $staged) { throw "排除 dist 后没有可提交的业务文件。" }
        if ($DistMode -eq "Exclude" -and @($staged | Where-Object { Test-IsDistPath $_ })) {
            throw "DistMode=Exclude 仍检测到 dist 暂存文件，已停止提交。"
        }
        Invoke-Git diff --cached --check
        Write-Host "$([Environment]::NewLine)📋 即将提交的文件：" -ForegroundColor Cyan
        $staged | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }
        Confirm-SafeAction -Prompt "确认提交当前 feature 业务变更？" -Keyword "COMMIT" -AutoConfirm:$AutoConfirm
        Invoke-Git commit -m $Message
        Invoke-Git fetch $script:Remote --prune
        Invoke-Git push -u $script:Remote $FeatureBranch
        Remove-WorkingTreeBackup -Backup $backup
        Write-Host "✅ feature 业务 commit 已提交并推送：$FeatureBranch" -ForegroundColor Green
    }
    catch {
        if ($backup) { Write-Host "⚠️ 操作中断，安全 stash 保留为 $($backup.Hash)，请勿删除。" -ForegroundColor Yellow }
        throw
    }
}

function Squash-Feature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FeatureBranch,
        [Parameter(Mandatory)][string]$Message,
        [switch]$AutoConfirm
    )
    Assert-CurrentFeature -FeatureBranch $FeatureBranch
    Assert-WorkingTreeClean -Context "squash 前"
    Sync-Remote
    $baseRef = "$($script:Remote)/$script:BaseBranch"
    $commitHashes = @(git rev-list --reverse "$baseRef..$FeatureBranch") | Where-Object { $_ }
    if (-not $commitHashes) { throw "$FeatureBranch 相对 $baseRef 没有业务 commit。" }
    $changedPaths = @(Get-ChangedPaths -BaseRef $baseRef -SourceRef $FeatureBranch)
    $distPaths = @($changedPaths | Where-Object { Test-IsDistPath $_ })
    if ($distPaths) {
        throw "feature 分支包含 dist 文件，不能进入业务 squash：$([Environment]::NewLine)$($distPaths -join [Environment]::NewLine)"
    }
    Write-Host "$([Environment]::NewLine)📦 $FeatureBranch 待压缩 commit 数：$($commitHashes.Count)" -ForegroundColor Cyan
    git log --oneline "$baseRef..$FeatureBranch"
    if ($commitHashes.Count -eq 1) {
        Write-Host "   已经是单个业务 commit，无需 squash。" -ForegroundColor Gray
        return
    }
    $oldHead = (git rev-parse $FeatureBranch).Trim()
    $safeName = $FeatureBranch -replace '[^A-Za-z0-9._-]', '-'
    $backupRef = "refs/backup/git-safe-flow/$safeName-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Invoke-Git update-ref $backupRef $oldHead
    Write-Host "   🛡️ 已保留提交历史备份：$backupRef -> $oldHead" -ForegroundColor Yellow
    Confirm-SafeAction -Prompt "确认把以上 $($commitHashes.Count) 个 commit 压成一个？" -Keyword "SQUASH" -AutoConfirm:$AutoConfirm
    Invoke-Git reset --soft $baseRef
    Invoke-Git diff --cached --check
    Invoke-Git commit -m $Message
    Invoke-Git push --force-with-lease $script:Remote $FeatureBranch
    $resultCount = @(git rev-list --reverse "$baseRef..$FeatureBranch") | Where-Object { $_ }
    if ($resultCount.Count -ne 1) {
        throw "squash 后检查失败：feature 相对 production 有 $($resultCount.Count) 个 commit。"
    }
    Write-Host "✅ feature 已压缩为 1 个业务 commit，备份保留在 $backupRef" -ForegroundColor Green
}

function Promote-Feature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FeatureBranch,
        [Parameter(Mandatory)][ValidateSet("dev", "beta", "production")][string]$Target,
        [switch]$AutoConfirm
    )
    Assert-FeatureBranch -FeatureBranch $FeatureBranch
    Assert-WorkingTreeClean -Context "合入目标分支前"
    Sync-Remote
    if (-not (Test-RemoteBranch -BranchName $FeatureBranch)) {
        throw "远程 feature 分支 $($script:Remote)/$FeatureBranch 不存在，请先 Submit-Feature。"
    }
    $baseRef = "$($script:Remote)/$script:BaseBranch"
    $featureRef = "$($script:Remote)/$FeatureBranch"
    $featureCommits = @(git rev-list --reverse "$baseRef..$featureRef") | Where-Object { $_ }
    if ($featureCommits.Count -ne 1) {
        throw "$FeatureBranch 尚未压缩为单个业务 commit（当前为 $($featureCommits.Count) 个），请先执行 Squash-Feature。"
    }
    $changedPaths = @(Get-ChangedPaths -BaseRef "$script:Remote/$Target" -SourceRef $featureRef)
    $distPaths = @($changedPaths | Where-Object { Test-IsDistPath $_ })
    if ($distPaths) {
        throw "业务 feature 不能把 dist 带入 $Target：$([Environment]::NewLine)$($distPaths -join [Environment]::NewLine)"
    }
    if ($Target -eq "production") {
        git merge-base --is-ancestor $featureRef "$script:Remote/beta" 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "production 合入被阻止：$FeatureBranch 尚未合入远程 beta，请先完成 beta 验收。"
        }
        Confirm-SafeAction -Prompt "确认 beta 已验收通过，并将 $FeatureBranch 发布到 production？" -Keyword "PRODUCTION" -AutoConfirm:$AutoConfirm
    }
    else {
        Confirm-SafeAction -Prompt "确认将 $FeatureBranch 合入 $Target？" -Keyword "MERGE" -AutoConfirm:$AutoConfirm
    }
    Invoke-Git switch $Target
    Invoke-Git pull --ff-only $script:Remote $Target
    Invoke-Git merge --no-ff $featureRef -m "merge: $FeatureBranch -> $Target"
    Invoke-Git push $script:Remote $Target
    Write-Host "✅ $FeatureBranch 已合入并推送到 $Target" -ForegroundColor Green
    if ($Target -eq "beta") {
        Write-Host "   下一步：在 beta 上执行 Build-Beta，构建并单独提交 dist。" -ForegroundColor Yellow
    }
}

function Build-Beta {
    [CmdletBinding()]
    param([switch]$AutoConfirm)
    Assert-WorkingTreeClean -Context "beta 构建前"
    Sync-Remote
    Invoke-Git switch beta
    Invoke-Git pull --ff-only $script:Remote beta
    Write-Host "$([Environment]::NewLine)🏗️ 执行 npm run build:beta" -ForegroundColor Cyan
    & npm run build:beta
    if ($LASTEXITCODE -ne 0) { throw "npm run build:beta 执行失败，未提交任何构建产物。" }
    $changed = @(Get-UntrackedAndChangedPaths)
    $outsideDist = @($changed | Where-Object { -not (Test-IsDistPath $_) })
    if ($outsideDist) {
        throw "beta 构建产生了 dist 以外的变更，已停止提交：$([Environment]::NewLine)$($outsideDist -join [Environment]::NewLine)"
    }
    if (-not $changed) {
        Write-Host "   ℹ️ 构建后没有新的文件变更。" -ForegroundColor Gray
        return
    }
    Invoke-Git add -- dist
    $staged = @(git diff --cached --name-only) | Where-Object { $_ }
    if (-not $staged -or @($staged | Where-Object { -not (Test-IsDistPath $_) })) {
        throw "beta 构建暂存区不是 dist-only，已停止提交。"
    }
    Invoke-Git diff --cached --check
    Confirm-SafeAction -Prompt "确认只提交 beta 的 dist 构建产物？" -Keyword "DIST" -AutoConfirm:$AutoConfirm
    Invoke-Git commit -m "build: update beta dist"
    Invoke-Git push $script:Remote beta
    Write-Host "✅ beta dist 已单独提交并推送" -ForegroundColor Green
}

function Get-FlowStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$FeatureBranch)
    Assert-FeatureBranch -FeatureBranch $FeatureBranch
    Sync-Remote
    $baseRef = "$($script:Remote)/$script:BaseBranch"
    Write-Host "$([Environment]::NewLine)📊 Git Safe Flow 状态" -ForegroundColor Cyan
    Write-Host "   当前分支：$(Get-CurrentBranch)" -ForegroundColor Gray
    Write-Host "   feature：$FeatureBranch" -ForegroundColor Gray
    if (Test-LocalBranch -BranchName $FeatureBranch) {
        $count = @(git rev-list --reverse "$baseRef..$FeatureBranch") | Where-Object { $_ }
        Write-Host "   相对 production 的 commit：$($count.Count)" -ForegroundColor Gray
        $paths = @(Get-ChangedPaths -BaseRef $baseRef -SourceRef $FeatureBranch)
        if ($paths) { $paths | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray } }
        else { Write-Host "      （无文件差异）" -ForegroundColor Gray }
    }
    foreach ($target in @("dev", "beta", "production")) {
        if (Test-RemoteBranch -BranchName $target -and Test-RemoteBranch -BranchName $FeatureBranch) {
            git merge-base --is-ancestor "$($script:Remote)/$FeatureBranch" "$($script:Remote)/$target" 2>$null
            $label = if ($LASTEXITCODE -eq 0) { "已包含" } else { "未包含" }
            Write-Host "   $target：$label" -ForegroundColor Gray
        }
    }
}

function Start-SafeFlow {
    param([Parameter(Mandatory)][string]$FeatureBranch)
    Assert-FeatureBranch -FeatureBranch $FeatureBranch
    Write-Host @"
标准流程：
  1. New-Feature -FeatureBranch "$FeatureBranch"
  2. 修改代码
  3. Submit-Feature -FeatureBranch "$FeatureBranch" -Message "feat: ..."
  4. Squash-Feature -FeatureBranch "$FeatureBranch" -Message "feat: ..."
  5. （可选）Promote-Feature -FeatureBranch "$FeatureBranch" -Target dev
  6. Promote-Feature -FeatureBranch "$FeatureBranch" -Target beta
  7. Build-Beta
  8. beta 验收通过后：Promote-Feature -FeatureBranch "$FeatureBranch" -Target production
"@ -ForegroundColor Cyan
}

function New-Personal { throw "旧的 xyh-personal 流程已停用，请使用 New-Feature。" }
function Pick-FromPersonal { throw "旧的 pick 流程已停用，请使用 Squash-Feature 和 Promote-Feature。" }
function Promote-Pick { throw "旧的 pick 流程已停用，请使用 Promote-Feature。" }

if ($MyInvocation.InvocationName -ne '.' -and $MyInvocation.InvocationName -ne '&') {
    Write-Host @"
Git Safe Flow v3.0 - production 起始的 feature 分支流程

标准顺序：production -> feature -> (可选) dev -> beta -> 验收 -> production

可用函数：
    New-Feature       只能从 production 创建 feature 分支
    Submit-Feature    提交 feature 业务代码，默认排除 dist
    Squash-Feature    提交前将 feature 压缩为一个业务 commit
    Promote-Feature   合入 dev / beta / production
    Build-Beta        构建 beta 并只提交 dist
    Get-FlowStatus    查看 feature 是否已进入各目标分支
    Start-SafeFlow    打印完整操作清单
"@ -ForegroundColor Cyan
}

