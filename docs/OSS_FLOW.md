# OSS 服务器地址获取逻辑

## 数据流

```
app_config.dart
  └── AppConfig.oss = [OSS_URL1, OSS_URL2]

       ↓ 请求 OSS 文件

base_url.txt (base64 编码)
  └── 内容: "eyJ1cmxzIjpbImh0dHA6Ly8xNzEuODAuMTAuODk6MTExMTEiLCJodHRwczovLzEwMS4xMzIuMjUzLjg4OjExMTExIiwiaHR0cHM6Ly8zOC43Ni4xOTQuMTA3OjExMTExIl19"

       ↓ base64 解码

{"urls":["http://171.80.10.89:11111","https://101.132.253.88:11111","https://38.76.194.107:11111"]}

       ↓ 逐个测试连通性

选中最快响应的可用服务器地址
  └── 自动填入登录页「服务器地址」框
```

## 触发时机

| 时机 | 行为 |
|------|------|
| **打开登录页** | 自动从 OSS 获取地址列表 → 逐个测试连通性 → 填入可用地址 |
| **点击刷新按钮** | 同上，重新拉取并测试 |
| **已有保存地址** | 先填入保存的地址，再异步执行 OSS 检测，如果找到更好的会替换 |

## 连通性检测

对每个服务器地址调用：

```
GET {server_url}/api/v1/guest/comm/config
```

- 超时时间: **5 秒**
- 返回 `200` → 该地址可用，停止检测
- 超时或非 200 → 继续测试下一个地址

## 配置源

定义在 `lib/common/app_config.dart`：

```dart
static const oss = [
  'https://iqoo.oss-cn-shanghai.aliyuncs.com/sororain/base_url.txt',
  'https://iqoo.tos-cn-shanghai.volces.com/sororain/base_url.txt',
];
```

- 第一个 OSS 地址请求失败时自动切换到第二个（双 OSS 备份）
- OSS 文件内容为 **base64 编码的 JSON**，格式固定为 `{"urls": ["...", "..."]}`

## 相关代码

| 文件 | 方法 | 说明 |
|------|------|------|
| `lib/pages/login.dart` | `_fetchOssUrl()` | 获取地址列表 + 连通性检测 + 自动填入 |
| `lib/pages/login.dart` | `_loadSavedInfo()` | 启动时调用 `_fetchOssUrl()` |
| `lib/common/app_config.dart` | `AppConfig.oss` | OSS 地址配置源 |
