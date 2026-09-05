# 核心业务逻辑文档

> 本文档记录项目三个核心业务逻辑的完整实现流程：
> 1. OSS 获取服务器地址
> 2. 订单支付
> 3. 同步订阅
>
> （已随 0.8.96 内核升级与 iqoo 模块重构更新，2026-08-28）

---

## 一、OSS 获取服务器地址逻辑

### 概述

通过阿里云 OSS/火山云 TOS 上的加密文件获取可用服务器地址列表，用于动态切换 V2Board API 服务器地址，解决服务器变更问题。

### 数据源

```dart
// lib/iqoo/config/app_config.dart
AppConfig.oss = [
  'https://oss.example.com/path/to/base_url.txt',
  'https://tos.example.com/path/to/base_url.txt',
];
```

OSS 文件内容为 **Base64 编码的 JSON**，解码后结构：
```json
{"urls": ["https://server1.com", "https://server2.com"]}
```

### 触发场景

| 场景 | 调用位置 | 触发时机 |
|------|---------|---------|
| **登录页加载** | `lib/iqoo/pages/login.dart:_fetchOssUrl()` | 用户打开登录页时 |
| **登录后检查** | `lib/iqoo/app_lifecycle.dart:checkAndRefreshServerUrl()` | 恢复会话成功后，检测并切换最优地址 |

### 流程

```
┌─────────────────────────────────────────────────────────────┐
│                     OSS 获取服务器地址流程                      │
└─────────────────────────────────────────────────────────────┘

登录页加载 / 服务器不可用
        │
        ▼
┌─────────────────────────────┐
│  遍历 AppConfig.oss URL 列表  │
│  (2 个地址，优先 OSS)         │
└─────────────┬───────────────┘
        │
        ▼
┌─────────────────────────────┐
│  GET 请求获取文件内容          │
│  - timeout: 8s              │
│  - 支持 HTTPS (跳过证书验证)   │
│  - User-Agent: 浏览器 UA     │
└─────────────┬───────────────┘
        │
        ▼
┌─────────────────────────────┐
│  Base64 解码 + JSON 解析     │
│  提取 urls 列表              │
└─────────────┬───────────────┘
        │
        ▼
┌─────────────────────────────┐
│  遍历 urls，逐个测试连通性     │
│  GET /api/v1/guest/comm/config│
│  - timeout: 5s              │
│  - statusCode == 200 即可用  │
└─────────────┬───────────────┘
        │
        ▼
┌─────────────────────────────┐
│  用第一个可用的地址            │
│  登录页: 填入 serverUrl 输入框 │
│  后台刷新: 更新 apiClient     │
└─────────────────────────────┘
```

### 关键代码位置

| 文件 | 方法 | 说明 |
|------|------|------|
| `lib/iqoo/config/app_config.dart` | `AppConfig.oss` | OSS URL 常量（需手动更新） |
| `lib/iqoo/config/feature_flags.dart` | `enableAppConfig` | 功能开关（控制是否启用 OSS） |
| `lib/iqoo/pages/login.dart` | `_fetchOssUrl()` / `_loadSiteConfig()` | 登录页 OSS 获取 + 站点配置加载 |
| `lib/iqoo/app_lifecycle.dart` | `checkAndRefreshServerUrl()` | 登录后检查并刷新服务器地址 |
| `lib/iqoo/services/oss_service.dart` | `fetchBestUrl()` / `_testServerUrl()` | OSS 列表获取与连通性测试（统一实现） |

---

## 二、订单支付逻辑

### 概述

用户选购套餐 → 提交订单 → 选择支付方式 → 发起支付 → 轮询支付结果 → 同步订阅。

### 流程

```
┌─────────────────────────────────────────────────────────────┐
│                      订单支付完整流程                          │
└─────────────────────────────────────────────────────────────┘

用户选购套餐
        │
        ▼
┌─────────────────────────────┐
│     _OrderPage (confirm.dart)   │
│  1. 选择购买周期              │
│  2. 输入优惠码（可选）         │
│  3. 查看金额明细              │
│  4. 点击「提交订单」           │
└─────────────┬───────────────┘
        │
        ▼
┌─────────────────────────────┐
│   ShopService.submitOrder() │
│   POST /user/order/save     │
│   {plan_id, period,         │
│    coupon_code?}             │
└─────────────┬───────────────┘
        │
        ▼
┌─────────────────────────────┐
│   跳转到 OrderDetailPage     │
│   (orders.dart)              │
│   显示订单详情 + 支付方式      │
└─────────────┬───────────────┘
        │
        ▼
┌─────────────────────────────┐
│   用户选择支付方式             │
│   调用 _pay(methodId)        │
└─────────────┬───────────────┘
        │
        ▼
┌─────────────────────────────┐
│  ShopService.checkoutOrder()│
│  POST /user/order/checkout   │
│  {trade_no, method}          │
└─────────────┬───────────────┘
        │
        ├── type == 1 (URL 支付)
        │   └── launchUrl(URL, externalApplication)
        │
        └── type == 0 (二维码支付)
            └── 显示二维码弹窗
        │
        ▼
┌─────────────────────────────┐
│   开始轮询支付结果            │
│   _startPolling()            │
│   每 5 秒一次，最多 30 次      │
│   GET /user/order/check      │
└─────────────┬───────────────┘
        │
        ├── status == 3 (已完成)
        │   ├── 停止轮询
        │   ├── 显示"支付成功"弹窗
        │   ├── 3次×5秒重试同步订阅
        │   └── 返回订单列表
        │
        ├── status == 2 (已取消)
        │   └── 停止轮询
        │
        └── 轮询超时 (30次)
            └── 提示手动检测
```

### 充值流程

```
钱包页面 (wallet.dart)
    │
    ▼
┌─────────────────────────────┐
│  输入金额 → 点击立即充值      │
│  ShopService.createDeposit() │
│  POST /user/order/save       │
│  {period: 'deposit',         │
│   deposit_amount, plan_id:0} │
└─────────────┬───────────────┘
        │
        ▼
┌─────────────────────────────┐
│  创建成功 → SnackBar 提示    │
│  → 直接跳转 OrderDetailPage  │
│  （复用订单支付流程）          │
└─────────────────────────────┘
```

### API 接口清单

| 接口 | 方法 | 路径 | 说明 |
|------|------|------|------|
| 获取套餐 | GET | `/user/plan/fetch` | 获取所有可用套餐 |
| 验证优惠码 | POST | `/user/coupon/check` | 验证优惠码有效性 |
| 提交订单 | POST | `/user/order/save` | 创建订单 |
| 获取支付方式 | GET | `/user/order/getPaymentMethod` | 获取可用支付方式 |
| 发起支付 | POST | `/user/order/checkout` | 获取支付链接/二维码 |
| 检查订单状态 | GET | `/user/order/check` | 轮询支付结果 |
| 获取订单详情 | GET | `/user/order/detail` | 获取订单详细信息 |
| 取消订单 | POST | `/user/order/cancel` | 取消未支付订单 |
| 获取订单列表 | GET | `/user/order/fetch` | 获取历史订单 |

### 关键代码位置

| 文件 | 类/方法 | 说明 |
|------|---------|------|
| `lib/iqoo/services/shop_service.dart` | `ShopService` | 所有支付相关 API 调用 |
| `lib/iqoo/shop/confirm.dart` | `_OrderPage` | 订单确认页（选择周期+优惠码+提交） |
| `lib/iqoo/pages/orders.dart` | `OrderDetailPage` / `OrderDetailPageState` | 订单详情+支付方式选择+轮询 |
| `lib/iqoo/pages/orders.dart` | `_pay()` | 发起支付并启动轮询 |
| `lib/iqoo/pages/orders.dart` | `_startPolling()` / `_doPoll()` | 支付结果轮询 |
| `lib/iqoo/pages/orders.dart` | `_handlePaymentSuccess()` | 支付成功处理 |
| `lib/iqoo/pages/wallet.dart` | `_deposit()` | 充值入口 |
| `lib/iqoo/shop/plans.dart` | `_PlanCard` → `_navigateToOrder()` | 套餐卡片 → 订单页 |

---

## 三、同步订阅逻辑

### 概述

将 V2Board 订阅链接同步到本地代理配置文件中，使 Clash 核心能获取最新的节点列表。

### 触发场景

| 场景 | 代码位置 | 说明 |
|------|---------|------|
| **登录后自动同步** | `lib/iqoo/app_lifecycle.dart:checkAuth()` | 登录/恢复会话后自动执行 |
| **定时自动同步** | `lib/iqoo/app_lifecycle.dart:autoUpdateProfilesTask()` | 每 20 分钟定时执行 |
| **配置为空补拉** | `lib/iqoo/app_lifecycle.dart:init()` | 当前配置为空时延时补拉一次 |
| **支付成功后同步** | `lib/iqoo/pages/orders.dart:_handlePaymentSuccess()` | 支付成功后重试同步 |
| **用户手动同步** | `lib/iqoo/pages/user.dart:_syncSubscription()` | 用户页面点击「同步订阅」 |

### 流程

```
┌─────────────────────────────────────────────────────────────┐
│                       同步订阅流程                             │
└─────────────────────────────────────────────────────────────┘

触发同步
    │
    ▼
┌─────────────────────────────────────────┐
│  syncSubscriptionNow() (profilesAction)  │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│  1. 从订阅服务获取订阅链接               │
│     fetchSubscribeUrl()                 │
│     → baseUrl + /api/v1/client/subscribe│
│       ?token=xxx                        │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│  2. 获取当前配置 (currentProfileProvider) │
│                                          │
│     ├── 已有配置 → 更新其 URL 并调用     │
│     │   updateProfile() 更新订阅         │
│     │                                    │
│     └── 无配置 → 创建新 Profile          │
│         Profile.normal(url: url).update()│
│         并保存 (putProfile)              │
└─────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│  3. updateProfile 内部流程               │
│     ① 更新数据库中的 profile URL         │
│     ② 触发 applyProfile (应用配置到核心) │
│     ③ 重新获取节点列表                   │
└─────────────────────────────────────────┘
```

### 订阅链接构造

```dart
// lib/iqoo/services/subscription_service.dart
String? fetchSubscribeUrl() {
  final base = requestService.baseUrl;
  final token = requestService.token;
  if (base != null && token != null) {
    return '$base/api/v1/client/subscribe?token=$token';
  }
  return null;
}
```

### 自动更新机制

```dart
// lib/iqoo/app_lifecycle.dart
// 定时同步订阅（每 20 分钟，带并发防重入）
autoUpdateProfilesTask() → Timer.periodic(syncSubscriptionNow)

// 启动时自动同步（恢复会话后）
checkAuth() → OSS 竞速 + 拉取配置 + 刷新 token + 自动同步
```

### 关键代码位置

| 文件 | 方法 | 说明 |
|------|------|------|
| `lib/providers/action.dart` | `syncSubscriptionNow()` | 同步订阅入口（失败自动刷新 token 重试一次） |
| `lib/iqoo/services/subscription_service.dart` | `fetchSubscribeUrl()` / `refreshTokenFromUserInfo()` | 订阅链接构造、token 刷新 |
| `lib/iqoo/help/update_helper.dart` | `autoCheckUpdate()` | 应用自更新检查 |
| `lib/providers/action.dart` | `updateProfile()` | 更新配置 |
| `lib/iqoo/app_lifecycle.dart` | `checkAuth()` / `autoUpdateProfilesTask()` | 启动自动同步、20 分钟定时同步 |
| `lib/iqoo/pages/orders.dart` | `_handlePaymentSuccess()` | 支付成功后同步订阅 |

---

## 四、关联关系图

```
                    ┌──────────────────┐
                    │    OSS 获取地址    │
                    │  (登录页/后台刷新) │
                    └────────┬─────────┘
                             │ 服务器地址
                             ▼
                    ┌──────────────────┐
                    │  V2Board API 调用  │
                    │  (requestService) │
                    └────────┬─────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
              ▼              ▼              ▼
     ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
     │  登录/Auth   │ │  订单支付     │ │  同步订阅     │
     │  auth_service│ │  shop_service│ │ profilesAction│
     │  login.dart  │ │  orders.dart │ │  user.dart   │
     └──────────────┘ └──────────────┘ └──────────────┘
              │              │              │
              │              │ 支付成功      │
              └──────────────┼──────────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │  syncSubscription│
                    │  拉取最新配置     │
                    └────────┬─────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │  Clash 核心加载   │
                    │  显示节点列表     │
                    └──────────────────┘
```
