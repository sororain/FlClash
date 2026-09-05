# Android 踩坑记录

## 1. 包名（Package Name）注意事项

### 概念区分

| 概念 | 值 | 作用 |
|---|---|---|
| `applicationId` | `com.sororain.clash` | 应用市场唯一标识，在 `build.gradle.kts` 中配置 |
| 源码包名 | `com.follow.clash` | Kotlin/Java 源码目录结构，**不能随意更改** |
| `Components.PACKAGE_NAME` | `com.follow.clash` | 必须匹配源码包名，用于 `ComponentName` 解析 Activity/Service |

### 为什么 `Components.PACKAGE_NAME` 不能改为新包名

`Components.PACKAGE_NAME` 被用于：
- `ComponentName(packageName, "${PACKAGE_NAME}.MainActivity")` — 通知点击打开 Activity
- `ComponentName(packageName, "${PACKAGE_NAME}.BroadcastReceiver")` — 广播接收器
- 如果改为 `com.sororain.clash`，系统会找不到 `com.sororain.clash.MainActivity`（实际类在 `com.follow.clash` 包下）

### 为什么 `packageName` 常量（Dart）不能改为新包名

`constant.dart` 中的 `packageName` 被用于 MethodChannel 名称：
- `$packageName/app` — Flutter ↔ 原生通信
- `$packageName/service` — 核心服务通信
- `$packageName/tile` — 快捷开关

原生端使用 `Components.PACKAGE_NAME` 注册同名的 MethodChannel，**两端必须一致**，否则核心无法连接。

### 结论

| 字段 | 是否可改 | 原因 |
|---|---|---|
| `applicationId` | ✅ | Play Store 标识，独立于源码结构 |
| `Components.PACKAGE_NAME` | ❌ | 必须匹配源码 `com.follow.clash` 目录 |
| `constant.dart packageName` | ❌ | 必须匹配 `Components.PACKAGE_NAME` |
| `build.gradle.kts namespace` | ❌ | 必须匹配源码 `com.follow.clash` 目录 |

---

## 2. Firebase/Crashlytics 清理

### 删除的文件

- `android/app/google-services.json` — 空壳 Firebase 配置

### 修改的文件

| 文件 | 修改内容 |
|---|---|
| `app/build.gradle.kts` | 移除 `google-services` 和 `crashlytics` 插件 + 依赖 |
| `settings.gradle.kts` | 移除两个 Firebase 插件声明 |
| `common/build.gradle.kts` | 移除 Firebase 依赖 |
| `GlobalState.kt` | 移除 `setCrashlytics` 方法和 Firebase 导入 |
| `RemoteService.kt` | 移除 `setCrashlytics` 重写 |
| `IRemoteInterface.aidl` | 移除 `setCrashlytics` 接口 |
| `Service.kt` | 移除 `setCrashlytics` 方法 |
| `State.kt` | 移除两处 `setCrashlytics` 调用 |

### 残留（不影响构建）

- `libs.versions.toml` — 版本号定义，无模块引用

---

## 3. 构建常见错误

### `No matching client found for package name 'com.sororain.clash.dev'`

**原因**：`google-services.json` 中 `package_name` 与 `applicationId` + `.dev` 后缀不匹配。

**解决**：删除 `google-services.json` 或更新其中的 package name。

### `Unresolved reference: firebase / FirebaseApp / FirebaseCrashlytics`

**原因**：Kotlin 代码引用了 Firebase 类，但依赖已被移除。

**解决**：彻底清理所有 Firebase 引用（见上表）。

### `Connect to firebasecrashlyticssymbols.googleapis.com timed out`

**原因**：Crashlytics 插件尝试上传混淆映射文件，但网络不通。

**解决**：在 `build.gradle.kts` 中添加：

```kotlin
tasks.matching { it.name.startsWith("uploadCrashlytics") }.configureEach {
    enabled = false
}
```

或直接移除 Crashlytics 插件。

---

## 4. 通知栏问题

### 通知显示 "FlClash"

**涉及文件**（硬编码，需手动修改，不在同步列表中）：

| 文件 | 修改 |
|---|---|
| `VpnService.kt` | `setSession("Sororain")` |
| `NotificationModule.kt` | `setContentTitle("Sororain")` |
| `NotificationParams.kt` | `val title: String = "Sororain"` |
| `GlobalState.kt` | `NOTIFICATION_CHANNEL = "Sororain"` |

### 点击通知不进应用

**原因**：`Components.PACKAGE_NAME` 与实际的 Activity 类路径不匹配。

**解决**：`PACKAGE_NAME` 必须保持 `com.follow.clash`。

### 暂停按钮无效

需要检查 `QuickAction.STOP` 的 Intent 处理链路是否完整。

---

## 5. 同步脚本（setup.dart）注意事项

### 不应参与同步的文件/字段

| 文件 | 字段 | 原因 |
|---|---|---|
| `Components.kt` | `PACKAGE_NAME` | 必须匹配源码结构 `com.follow.clash` |
| `constant.dart` | `packageName` | 必须匹配 `Components.PACKAGE_NAME` 保证 MethodChannel 通信 |
| `build.gradle.kts` | `namespace` | 必须匹配源码结构 `com.follow.clash` |

### 当前同步的安卓条目

| 文件 | 同步内容 | 跟随字段 |
|---|---|---|
| `AndroidManifest.xml` (main) | `android:label` | `appName` |
| `AndroidManifest.xml` (debug) | `android:label` | `appName` |
| `build.gradle.kts` | `applicationId` | `packageName`（略不同） |
| `GlobalState.kt` | `NOTIFICATION_CHANNEL` | `appName` |
| `VpnService.kt` | `setSession` | `appName` |
| `NotificationModule.kt` | `setContentTitle` | `appName` |
| `NotificationParams.kt` | `val title` | `appName` |
