# Sororain 修改与设计文档（相对上游 FlClash 的新增内容）

本文档描述本项目在 FlClash 之上新增的商业化能力与架构。上游 FlClash 的功能
（代理核心、配置、界面框架）之外，本项目新增了强制登录的 V2Board 商业化模块。

## 一、iqoo 商业化模块（`lib/iqoo/`）

### 1.1 服务层 `lib/iqoo/services/`

#### `request_service.dart` - API 客户端（单例）
- 基于 Dio，所有请求强制 `DIRECT` 代理（避免 VPN 干扰）、忽略 SSL 证书错误
- `Authorization` 头自动附加 auth_data；订阅 token 单独管理
- 认证失效判定与 web 主题一致：`403 + 响应体含 '未登录或登录已过期'` 才清凭证，
  本次会话只处理一次（`_authExpiredHandled`），重新登录（`setAuth`）复位
- 支持 POST / GET / 表单 / 字节下载；`clear()` 登出清理

#### `auth_service.dart` - 认证服务
- `login()` — `/passport/auth/login`（返回 token / auth_data / is_admin）
- `logout()` / `clearAuth()` — 清本地凭证（保留 base_url 供登录页回填）
- `getUserInfo()` — `/user/info` → `UserInfo` 模型
- `tryRestoreSession()` — 从 SharedPreferences 恢复会话
- 强制登出回调 `onForceLogout` → `AppLifecycle.forceLogout`（停 VPN + 跳登录页）

#### `subscription_service.dart` - 订阅
- `fetchSubscribeUrl()` — 拼 `/client/subscribe?token=` 订阅链接
- `refreshTokenFromUserInfo()` — 以 `/user/getSubscribe` 的 `data.token` 刷新本地 token

#### `shop_service.dart` - 商城
- 套餐（`/user/plan/fetch`）、优惠券（`/user/coupon/check`）、订单
 （save / checkout / check / detail / fetch / cancel）、支付方式、充值订单
- 模型：`Plan`（含 content 多格式解析）、`PriceOption`、`CouponResult`、
 `PaymentMethod`（手续费）、`PaymentCheckout`（二维码/URL）、`OrderItem`

#### `invite_service.dart` - 邀请与佣金
- 邀请数据 / 生成邀请码 / 佣金明细 / 划转到余额 / 提现（`/user/ticket/withdraw`）

#### `config_service.dart` - 站点配置
- `/guest/comm/config`（免登录）：邮箱白名单、注册验证、客服、官网
- `/user/comm/config`（登录）：Telegram 群链接、提现配置

#### `oss_service.dart` - OSS 竞速
- 从阿里云 / 火山双 OSS 拉取 base64 的服务器列表，并发测试连通性取最快

#### 其他
- `ticket_service.dart` 工单、`knowledge_service.dart` 知识库、`notice_service.dart`
  公告（含 HTML/Markdown 渲染弹窗）、`update_service.dart` + `help/update_helper.dart`
  应用自更新（`/client/app/getVersion`）

### 1.2 页面 `lib/iqoo/pages/`

- `login.dart` — 登录 / 注册 / 忘记密码三模式；邮箱白名单校验、邮箱验证码、邀请码；
  OSS 竞速自动填服务器地址
- `user.dart` — 个人中心（信息卡片、流量进度、重置流量、同步订阅、钱包/工单/文档入口）
- `wallet.dart` — 余额、充值、自动续费开关（`/user/update`）
- `orders.dart` / `tickets.dart` / `invite.dart` / `knowledge.dart` / `notices.dart`

### 1.3 商店 `lib/iqoo/shop/`

`shop.dart` 商城入口、`plans.dart` 套餐、`confirm.dart` 下单确认、`payment.dart`
支付（轮询 `/user/order/check`，每 5 秒 × 30 次，回前台立即校验一次）

### 1.4 配置 `lib/iqoo/config/`

- `app_config.dart` — 编译时内联（OSS 地址列表、Crisp 客服 ID），不读外部文件
- `feature_flags.dart` — **由 `setup.dart _syncNames()` 自动生成**，勿手改

### 1.5 生命周期 `lib/iqoo/app_lifecycle.dart`

启动流程：恢复会话 → OSS 竞速刷新服务器地址 → 拉站点/用户配置 → 刷新订阅 token →
自动更新订阅 + 20 分钟定时同步 → 应用自更新检查。未登录跳 `/login`，被封禁/凭证
失效强制登出。

### 1.6 其他

- `help/`：dialog_helper（统一确认弹窗）、error_helper（V2Board 错误消息提取）
- `widgets/dio_image.dart`：基于 Dio 的图片组件（自定义加载/错误占位）

## 二、UI/UX 要点

- 强制登录路由：`/login` → `/home`，导航页含 Shop / User（`lib/common/navigation.dart`）
- 登录页按钮分组、API 路径隐藏（默认 `/api/v1`）
- 公告内容自动识别 HTML / Markdown 渲染，链接过滤后外部打开

## 三、构建系统

- `setup.dart`：`--arch` 单 ABI 构建、`_syncNames()` 名称同步（状态文件
  `build/name_state.json` + 遗留名集合，详见 `docs/APP_CONFIG_AND_SETUP.md`）、
  FeatureFlags 生成
- 产物清理见 `docs/BUILD_ARTIFACTS_CLEANUP.md`

## 四、内核层

- Go 核心 / Clash.Meta 升级与 Dart-Go 协议（`MethodCall` / `MethodResponse`、
  `invokeMethod`、`clearEffect`）见 `docs/BUILD_ARTIFACTS_CLEANUP.md` 与
  `docs/CORE_LOGIC.md`
- 旧版防御闸门、Crashlytics 残留已全部移除（无任何数据收集）
