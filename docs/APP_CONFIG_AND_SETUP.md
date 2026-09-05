# 应用名称配置指南

## 概述

项目名称和相关标识并非硬编码，而是通过 `app_config.json` + `setup.dart` 的机制来统一管理。修改名称时，只需编辑 `app_config.json`，然后运行 `setup.dart` 同步到各个配置文件中。

---

## 配置源文件

### `app_config.json`（项目根目录）

这是名称配置的**唯一数据源**，包含以下字段：

```json
{
  "appName": "Sororain",                      // 应用显示名称
  "coreName": "SororainCore",                 // 核心程序文件名
  "helperName": "SororainHelperService",      // Windows 帮助服务文件名
  "appId": "E8C6A6D2-02E6-4019-BEE2-36411DFC5DCB",  // Windows 打包 AppID
  "packageName": "com.sororain.clash",        // Android 包名
  "features": {                               // 功能开关
    "showServerUrlInput": false,
    "profileEditPreview": false,
    "enableAppConfig": true
  }
}
```

> ⚠️ **注意**：`app_config.json` 本身不会被构建工具直接读取。它只是一个数据源，需要通过 `setup.dart` 同步到各平台配置文件中。

---

## 同步脚本

### `setup.dart`（项目根目录）

这是一个 Dart 脚本，负责将 `app_config.json` 中的配置同步到项目的各个配置文件中。

#### 使用方法

```bash
# 只同步名称（推荐）
dart run setup.dart

# 同步名称并构建指定平台的核心
dart run setup.dart windows
dart run setup.dart android
dart run setup.dart linux
dart run setup.dart macos
```

#### 同步覆盖的文件

执行 `dart run setup.dart` 后，会自动修改以下文件中的名称：

| 文件 | 修改内容 |
|------|---------|
| `windows/CMakeLists.txt` | 项目名、BINARY_NAME、核心/服务文件名 |
| `windows/runner/Runner.rc` | 文件描述、产品名、原始文件名 |
| `windows/runner/main.cpp` | 窗口标题 |
| `windows/packaging/exe/make_config.yaml` | app_id、app_name、display_name、executable_name |
| `distribute_options.yaml` | app_name |
| `windows/packaging/exe/inno_setup.iss` | 安装包包含的文件列表 |
| `lib/common/path.dart` | 核心文件名、锁文件名 |
| `lib/common/constant.dart` | appName、appHelperService、unixSocketPath、isolate 名称 |
| `services/helper/src/service/windows.rs` | 服务名称 |
| `linux/CMakeLists.txt` | BINARY_NAME、核心文件名 |
| `linux/runner/my_application.cc` | 窗口标题 |
| `macos/Runner/Info.plist` | CFBundleExecutable、CFBundleName |
| `lib/common/window.dart` | URL scheme 注册名 |
| `core/tun/tun.go` | TUN 设备名 |
| `android/app/build.gradle.kts` | applicationId |
| `android/app/src/main/AndroidManifest.xml` | android:label |
| `android/app/src/debug/AndroidManifest.xml` | android:label |
| `android/common/.../GlobalState.kt` | 通知渠道名 |
| `android/service/.../VpnService.kt` | VPN session 名 |
| `android/service/.../NotificationModule.kt` | 通知标题 |
| `android/service/.../NotificationParams.kt` | 通知默认标题 |
| `lib/common/feature_flags.dart` → `lib/iqoo/config/feature_flags.dart` | **自动生成**功能开关代码 |
| `build/name_state.json` | **自动写入**本次同步的名字（下次运行的旧名来源） |

---

## 标准工作流程

### 修改名称

```bash
# 1. 编辑 app_config.json（修改名称等配置）

# 2. 同步名称到所有配置文件
dart run setup.dart

# 3. 构建核心（如果需要）
dart run setup.dart windows   # 示例：构建 Windows 核心

# 4. 打包应用
flutter_distributor package ...
```

### 首次使用 / 再次改名

```bash
# 1. 编辑 app_config.json（改成新名字）
# 2. 运行同步
dart run setup.dart
```

改名链路是自持的：`build/name_state.json` 记录上次写入的名字，下次运行时连同上游默认名
（FlClash*）一起被清扫成新名字。可以反复改名，不需要手动还原任何文件。

---

## 注意事项

### 1. 旧名识别机制（2026-08 重构后）

`_syncNames()` 不再从文件内容"猜"旧名，而是基于**遗留名集合**做精确替换：

- 上游默认名（`FlClashCore` / `FlClashHelperService` / `FlClash`）——覆盖上游合并后文件回退的情况
- `build/name_state.json` 记录的上次名字——覆盖正常改名链路

每次同步成功后状态文件自动更新。同步结束还有校验环节：回读关键文件确认新名已写入，
失败会打印 `[WARN]` 列表。

### 2. 不要手动修改同步覆盖的文件

被 `setup.dart` 覆盖的文件（见上表）**不应手动修改名称**，否则下次运行 `setup.dart` 时会覆盖掉手动修改的内容。所有名称修改应统一在 `app_config.json` 中。

### 3. 功能开关

`app_config.json` 中的 `features` 字段控制 UI 功能显隐，同步时会自动生成 `lib/iqoo/config/feature_flags.dart` 文件。修改后同样需要运行 `dart run setup.dart` 才能生效。

### 4. 打包不自动调用 setup.dart

`flutter build` 和 `flutter_distributor` **不会自动运行** `setup.dart`。修改 `app_config.json` 后，**必须先手动运行** `dart run setup.dart`，然后再打包。

### 5. ⚠️ 不可随意修改的配置

以下配置项与 Kotlin 源码的目录结构和包名绑定，**不要通过 `app_config.json` / `setup.dart` 修改**：

| 配置项 | 位置 | 固定值 | 原因 |
|--------|------|--------|------|
| `namespace` | `android/app/build.gradle.kts` | `com.follow.clash` | 必须匹配 Kotlin 源码目录 `com/follow/clash/` |
| `PACKAGE_NAME` | `android/common/.../Components.kt` | `com.follow.clash` | 用于 `ComponentName` 构造类路径 |
| `packageName` | `lib/common/constant.dart` | `com.follow.clash` | 用于 MethodChannel 名称，与 Kotlin 侧 `Components.PACKAGE_NAME` 一致 |
| Kotlin 源码目录 | `android/.../kotlin/com/follow/clash/` | `com.follow.clash` | 移动目录需要同步修改所有 Kotlin 文件的 `package` 声明 |

`setup.dart` 只同步**应用显示名称、核心文件名、包 ID** 等安全可改的配置。

---

## 常见问题

### Q: 改了 app_config.json，打包出来名称没变？

**原因**：没有运行 `dart run setup.dart`，打包工具使用的是配置文件中的硬编码值。

**解决**：
```bash
dart run setup.dart
# 然后再打包
```

### Q: 运行 setup.dart 后提示 [--]，文件没改？

**说明**：`[--] (already up to date)` 是正常状态——该文件里没有需要替换的旧名，内容已是最新。

### Q: 运行 setup.dart 后提示 [WARN] 缺少某名称？

**原因**：校验环节发现关键文件里没找到新名字，通常是上游合并改动了文件的格式，导致替换规则没匹配上。

**解决**：按 `[WARN]` 列出的文件检查，为新格式补充 `_syncNames()` 里的替换规则后重跑。

### Q: 全架构 APK 在模拟器上"网络检测中"，arm64-only 却正常？

**原因**：构建缓存中存在旧的 `libclash.so`，导致打包进了损坏的核心库。

**解决**：清理构建缓存后重新编译：
```bash
# 一键全清理
flutter clean
Remove-Item -Recurse -Force libclash, android/core/src/main/jniLibs -ErrorAction SilentlyContinue

# 重新构建
dart run setup.dart android --arch arm64 --out core
dart run setup.dart android --arch arm   --out core
dart run setup.dart android --arch amd64 --out core
flutter build apk --release --target-platform android-arm,android-arm64,android-x64 --dart-define-from-file=env.json
```

### Q: 改完名称后 Android 构建失败？

**原因**：可能是 `setup.dart` 没有成功更新 Android 清单文件中的包名或标签。

**解决**：手动检查 `android/app/build.gradle.kts` 和 `AndroidManifest.xml` 中的名称是否正确。

---

## 构建缓存说明

### 缓存目录一览

| 目录 | 内容 | 何时清理 |
|------|------|---------|
| `build/` | Flutter 编译产物（Dart AOT、Gradle 输出等） | ❓ 出问题时 |
| `libclash/` | Go 核心编译产物（`SororainCore.exe` / `libclash.so` + Android 头文件） | ⚠️ 改动 `core/` 后必须清（见 `docs/BUILD_ARTIFACTS_CLEANUP.md`） |
| `android/core/src/main/jniLibs/` | 打包进 APK 的 `.so`（build_tool 从 `libclash/` 复制） | ⚠️ 同上，与 `libclash/` 一同清理 |
| `android/core/src/main/cpp/includes/` | C++ JNI 层编译用的 cgo 头文件 | ⚠️ 同上，与 `libclash/` 一同清理 |
| `android/core/.cxx/` | CMake 构建缓存 | ❓ 出问题时 |
| `build/name_state.json` | 名称同步状态文件 | ❌ 不要清（清了会重新 bootstrap 检测旧名） |
| `.dart_tool/` | Dart 包解析缓存 | ✅ `flutter clean` 清理 |
| `services/helper/target/` | Rust helper 服务编译产物 | ❓ 改 helper 名后 |
| `windows/flutter/ephemeral/` | Windows Flutter 插件缓存 | ❌ 不影响 Android/Linux |

### 推荐清理方式

```bash
# 轻量清理（仅 Flutter 产物）
flutter clean

# 完整清理（Flutter + Go 核心 + jniLibs）
flutter clean
Remove-Item -Recurse -Force libclash, android/core/src/main/jniLibs

# 极端清理（连 Rust helper 一起清）
flutter clean
Remove-Item -Recurse -Force libclash, android/core/src/main/jniLibs, services/helper/target
```
