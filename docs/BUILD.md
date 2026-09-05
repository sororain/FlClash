# Sororain 构建指南

## 环境要求

| 工具 | 用途 |
|------|------|
| **Flutter** (SDK >=3.8.0) | Flutter UI 编译 |
| **Go** (>=1.20) | Clash.Meta 核心编译 |
| **Rust** (可选) | Windows Helper 服务编译 |
| **Visual Studio 2022** | Windows 原生编译 (C++) |
| **Android NDK** (可选) | Android 核心交叉编译 |

---

## 一、快速调试（推荐）

直接以 debug 模式运行应用，支持**热重载**：

```bash
# Windows
flutter run -d windows

# Linux
flutter run -d linux

# macOS
flutter run -d macos

# Android (需连接设备或模拟器)
flutter run -d android
```

> 首次运行会自动 `flutter pub get` 安装依赖。
> debug 模式下修改 Dart 代码后按 `r` 热重载，按 `R` 热重启。

---

## 二、仅打包 Flutter 端（不含核心）

```bash
# Debug 版 exe
flutter build windows --debug

# Release 版 exe
flutter build windows --release
```

输出位置：
- Debug: `build\windows\x64\runner\Debug\Sororain.exe`
- Release: `build\windows\x64\runner\Release\Sororain.exe`

> ⚠️ **注意**：这种方式**不会**编译 Go 核心！需要先手动构建核心放入 `libclash\windows\` 目录。

---

## 三、完整构建（核心 + Flutter 打包）

使用项目自带的 `setup.dart` 脚本，一次性完成 **Go 核心编译 → Flutter 打包** 全流程。

### 3.1 先拉取子模块（仅首次克隆后需要）

```bash
git submodule update --init --recursive
```

### 3.2 Windows (amd64)

```bash
# Release 构建（默认 pre 环境）
dart run setup.dart windows --arch amd64

# 指定环境
dart run setup.dart windows --arch amd64 --env stable
```

### 3.3 Windows (arm64)

```bash
dart run setup.dart windows --arch arm64
```

### 3.4 Linux

```bash
# amd64
dart run setup.dart linux --arch amd64

# arm64
dart run setup.dart linux --arch arm64
```

### 3.5 macOS

```bash
# Intel
dart run setup.dart macos --arch amd64

# Apple Silicon
dart run setup.dart macos --arch arm64
```

### 3.6 Android

```bash
# arm64-v8a
dart run setup.dart android --arch arm64

# armeabi-v7a
dart run setup.dart android --arch arm

# x86_64 (模拟器)
dart run setup.dart android --arch amd64
```

### 参数说明

| 参数 | 说明 | 可选值 |
|------|------|--------|
| `target` | 构建目标平台 | `windows`, `linux`, `macos`, `android` |
| `--arch` | 目标架构 | `amd64`, `arm64`, `arm` (仅 Android) |
| `--out` | 输出类型 | `app` (完整打包), `core` (仅核心) |
| `--env` | 构建环境 | `pre` (预览), `stable` (稳定版) |

---

## 四、仅编译 Go 核心（不打包 Flutter）

```bash
dart run setup.dart windows --arch amd64 --out core
```

输出位置：
- Windows: `libclash\windows\SororainCore.exe`
- Linux: `libclash\linux\SororainCore`
- macOS: `libclash\macos\SororainCore`
- Android: `libclash\android\armeabi-v7a\libclash.so` (等)

---

## 五、构建产物说明

```
libclash/                   核心输出目录
├── windows/
│   ├── SororainCore.exe      Go 核心
│   └── SororainHelperService.exe  (可选) Windows 辅助服务
├── linux/
│   └── SororainCore          Go 核心
├── macos/
│   └── SororainCore          Go 核心
└── android/
    ├── armeabi-v7a/
    │   └── libclash.so      动态库
    ├── arm64-v8a/
    │   └── libclash.so
    └── x86_64/
        └── libclash.so

dist/                       分发输出目录
└── [target]/
    └── *.exe / *.zip / *.deb / *.AppImage / *.dmg
```

---

## 六、常见问题

### Q: `Clash.Meta\go.mod` not found

子模块未拉取，运行：
```bash
git submodule update --init --recursive
```

### Q: `flutter_distributor` not found

运行以下命令安装：
```bash
dart pub global activate flutter_distributor
```

### Q: Go 编译提示 `CGO_ENABLED` 相关错误

Windows/Linux/macOS 的 `--out core` 模式使用 CGO_ENABLED=0（纯 Go），Android 使用 CGO_ENABLED=1（需要 NDK）。

### Q: Android 构建失败，提示 `ANDROID_NDK` 为空

Android 构建需要设置 `ANDROID_NDK` 环境变量：

```bash
# 设置 NDK 路径（根据实际安装位置）
set ANDROID_NDK=C:\Users\你的用户名\AppData\Local\Android\Sdk\ndk\版本号
```

并且必须指定 `--arch` 参数：

```bash
dart run setup.dart android --arch arm64
dart run setup.dart android --arch arm
dart run setup.dart android --arch amd64
```

### Q: 只想看 UI 效果，不想编译核心？

```bash
flutter run -d windows
```
这会跳过核心编译，直接运行 Flutter 界面（部分功能不可用）。
