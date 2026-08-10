<template>
  <div class="Profile">
    <div class="user">
      <div class="avatar">
        <img src="../assets/个人默认头像.png" alt="" />
        <span>HI,{{ name }} </span>
      </div>
      <div class="info">
        <p>{{ userInfo.name }}</p>
        <p :class="['status', 'status-' + userInfo.idNoStatus]">
          {{ statusObj[userInfo.idNoStatus] }}
        </p>
        <div class="btn" @click="$router.push('myInfo')">完善资料</div>
        <div class="btn" @click="getResetPwd">修改密码</div>
      </div>
    </div>

    <div class="entry">
      <van-cell-group :border="false">
        <van-cell is-link @click="$router.push('contract')">
          <template #title>
            <i class="icon icon-contract"></i>
            <span>合同管理</span>
          </template>
        </van-cell>
        <van-cell is-link @click="$router.push('sign')">
          <template #title>
            <i class="icon icon-sign"></i>
            <span>签约管理</span>
          </template>
          <span
            v-if="showBadge"
            style="background-color:red;border-radius:50%;color:white;display:inline-block;width:20px;height:20px;text-align:center;line-height:20px;"
          >
            {{ notSignContractCount }}
          </span>
        </van-cell>
      </van-cell-group>
    </div>

    <!-- 修改密码弹框 -->
    <van-dialog v-model="resetPwdVisible" title="修改密码" show-cancel-button>
      <van-form @submit="onSubmit">
        <van-field
          v-model="formData.password"
          name="password"
          required
          label="原密码"
          input-align="right"
          placeholder="请输入原密码"
          :rules="[{ required: true, message: '请输入原密码' }]"
        />
        <van-field
          v-model="formData.newPassword"
          name="newPassword"
          required
          label="新密码"
          input-align="right"
          placeholder="请输入新密码"
          :rules="[{ required: true, message: '请输入新密码' }]"
        />
        <van-field
          v-model="formData.confirmPassword"
          name="confirmPassword"
          required
          label="确认密码"
          input-align="right"
          placeholder="请再次输入新密码"
          :rules="[
            { required: true, message: '请输入确认密码' },
            { validator: val => val === formData.newPassword, message: '两次输入不一致' }
          ]"
        />
        <div style="margin:16px;">
          <!-- 确认按钮必须是 submit 类型 -->
          <van-button round block type="info" native-type="submit">
            确认
          </van-button>
        </div>
      </van-form>
    </van-dialog>
  </div>
</template>

<script>
import Vue from "vue";
import { mapState } from "vuex";
import { Cell, CellGroup, Toast, Form } from "vant";
import formatAmount from "../utils/formatAmount";

Vue.use(Cell).use(CellGroup).use(Toast).use(Form);

export default {
  name: "Profile",
  data() {
    return {
      formatAmount,
      statusObj: {
        0: "未认证",
        1: "已认证",
        2: "认证失败",
      },
      formData: {
        password: "",
        newPassword: "",
        confirmPassword: ""
      },
      name: null,
      notSignContractCount: 0,
      showBadge: false,
      resetPwdVisible: false,
    };
  },
  computed: {
    ...mapState({
      userInfo: (state) => state.userInfo,
    }),
  },
  created() {
    this.getUserInfo();
  },
  methods: {
    getResetPwd() {
      this.resetPwdVisible = true;
      this.formData = { password: "", newPassword: "", confirmPassword: "" };
    },
    // 表单提交
    onSubmit(values) {
      this.getResetConfirm(values);
    },
    async getResetConfirm(values) {
      const postData = {
        password: values.password,
        newPassword: values.newPassword,
      };
      const response = await this.$axios.put("/wechat/user/pwd/update", postData);
      if (response.success) {
        this.resetPwdVisible = false;
        Toast("密码修改成功");
        this.formData = { password: "", newPassword: "", confirmPassword: "" };
      }
    },
    async getUserInfo() {
      const data = await this.$axios.get("/wechat/user/info");
      if (data.success && data.data) {
        sessionStorage.setItem("userInfos", JSON.stringify(data.data));
        this.showBadge = data.data.notSignContractCount > 0;
        this.notSignContractCount = data.data.notSignContractCount || 0;
        this.name = data.data.name;
      } else {
        this.showBadge = false;
      }
    },
  },
};
</script>
