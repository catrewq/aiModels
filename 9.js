import Vue from "vue";
import { Toast } from "vant";
import axios from "axios";

Vue.use(Toast);

axios.defaults.headers["Content-Type"] = "application/json;charset=UTF-8";
axios.defaults.headers.common["appid"] = 3;

const service = axios.create({
  baseURL: process.env.VUE_APP_URL,
  timeout: 30000,
});

service.interceptors.request.use(
  (config) => {
    const sessionId = sessionStorage.getItem("sessionId");
    if (sessionId) {
      config.headers.ssessionid = sessionId;
    }
    return config;
  },
  (error) => Promise.reject(error)
);

service.interceptors.response.use(
  (res) => {
    const success = res.data.success;
    if (success) {
      if (res.headers["ssessionid"]) {
        const sessionId = res.headers["ssessionid"];
        sessionStorage.setItem("sessionId", sessionId);
      }
      return res.data;
    } else {
      Toast(res.data.message);
      return res.data;
    }
  },
  (error) => {
    console.log(error);

    if (String(error).includes("timeout")) {
      Toast.fail("请求超时");
    } else if (error.response && error.response.status === 417) {
      Toast.fail(error?.response?.data?.message);
      console.log(error.response);
    } else {
      Toast.fail("请求错误");
    }

    // ❗ 在报错时重置 sessionId
    sessionStorage.removeItem("sessionId");

    return Promise.reject(error);
  }
);

export default service;
