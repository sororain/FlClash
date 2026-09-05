# 内核产物清理指南

内核代码（`core/` 下的 Go 代码、`core/Clash.Meta` 子模块）或 JNI 桥接层（`android/core/src/main/cpp/`）发生改动后，
磁盘上已有的构建产物**不会自动删除或重编**。新旧产物混用会导致编译失败或打包出"半个新半个旧"的 APK。

> 真实案例（0.8.96 升级）：`--arch arm64` 只重编了 arm64 的 Go 核心，armeabi-v7a / x86_64 的
> 7 月旧头文件（声明 `invokeAction`）被同步给 C++ 编译层，与新 `core.cpp`（调用 `invokeMethod`）
> 对不上，报 `use of undeclared identifier 'invokeMethod'`。

## 一、需要清理的产物（Android）

| 目录 | 内容 | 作用 |
|---|---|---|
| `libclash/android/` | `go build -buildmode=c-shared` 的输出：`<abi>/libclash.so` + `<abi>/libclash.h` | Go 核心的中间产物，头文件会从这里分发到下面两处 |
| `android/core/src/main/jniLibs/` | `<abi>/libclash.so` | **打包进 APK** 的最终核心库 |
| `android/core/src/main/cpp/includes/` | `<abi>/libclash.h` | C++ JNI 层（`core.cpp`）编译时包含的头文件 |
| `android/core/.cxx/` | CMake 构建缓存 | 缓存了 configure 时的路径与参数 |

> 关联关系：`jniLibs` 的 `.so` 是打包进 APK 的核心本体；`cpp/includes` 的头文件决定 C++ 层能否编译通过。
> 两者必须来自**同一次**核心构建，否则要么编译失败，要么运行时 JNI 符号对不上。

## 二、何时需要清理

- `core/` 下任何 Go 代码改动后（包括 `core/Clash.Meta` 子模块升级）
- `android/core/src/main/cpp/` 下 JNI 桥接代码改动后
- 内核升级（合并新版本快照）之后、出正式包之前

**可以不清理的情况**：只改了 Flutter/Dart 层（`lib/`）、或只用 `--arch arm64` 出单架构包且不关心
其他 ABI 的残留（`--split-per-abi` + `--target-platform` 限制下，其他 ABI 不会被打进包里）。

## 三、清理命令

Git Bash：

```bash
rm -rf libclash/android \
       android/core/.cxx \
       android/core/src/main/jniLibs \
       android/core/src/main/cpp/includes
```

PowerShell：

```powershell
Remove-Item -Recurse -Force libclash\android,
  android\core\.cxx,
  android\core\src\main\jniLibs,
  android\core\src\main\cpp\includes
```

清理后重新构建（全量重编三个 ABI）：

```bash
dart setup.dart android
# 或只编单个 ABI（注意：见第四节）
dart setup.dart android --arch arm64
```

## 四、`--arch` 单架构构建的注意点

`--arch arm64` 只收窄 **Go 核心构建**，但 Flutter 打包环节的 C++ 编译
（`:core` 的 CMake 任务）仍会编译全部 ABI。因此单架构构建前，其他 ABI 的头文件
要么是新的、要么不存在——**旧的一定会编译失败**。

最稳妥的习惯：改完内核代码后，直接用不带 `--arch` 的命令全量重编一次，
让三个 ABI 的产物全部重新生成。

## 五、验证方法

清理并重编后，确认所有产物来自同一版本核心：

```bash
# 1. 头文件应声明新符号（0.8.96 协议为 invokeMethod）
grep -c invokeMethod android/core/src/main/cpp/includes/*/libclash.h

# 2. .so 应导出新符号、无旧符号（-a 用于二进制文件）
for so in android/core/src/main/jniLibs/*/libclash.so; do
  echo "$so: new=$(grep -ac invokeMethod $so) old=$(grep -ac invokeAction $so)"
done
```

判定符号以当前 `core/lib.go` 的 `//export` 声明为准（0.8.96 为 `invokeMethod`，
0.8.93 旧核心为 `invokeAction`）。未来内核协议再变时，请对照新版本 `lib.go` 更新判定符号。

## 六、桌面端对应产物

同样的"旧产物不自动消失"问题也存在于桌面端，内核改动后需要重编：

| 平台 | 产物 |
|---|---|
| Windows | `libclash/windows/SororainCore.exe`（由 `dart setup.dart windows` 重新生成） |
| macOS / Linux | `libclash/macos/`、`libclash/linux/` 下对应核心文件 |

桌面端没有独立头文件分发问题（C++ 层极少变动），一般只需注意别把旧 exe 打进安装包。
