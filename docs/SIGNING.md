# Android 签名配置指南

## 为什么要签名

Android 应用必须经过签名才能安装和发布。未签名的 Release APK 包名带 `.dev` 后缀，只能用于测试。

## 第一步：生成签名文件

在项目根目录下运行：

```powershell
keytool -genkey -v -keystore android/app/keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias sororain
```

### 参数说明

| 参数 | 含义 |
|---|---|
| `-genkey` | 生成密钥对（公钥+私钥） |
| `-v` | 详细输出 |
| `-keystore android/app/keystore.jks` | 签名文件输出路径 |
| `-keyalg RSA` | 加密算法 |
| `-keysize 2048` | 密钥长度（安全标准） |
| `-validity 10000` | 有效期 10000 天（约 27 年） |
| `-alias sororain` | 密钥别名 |

### 交互式提示

执行后会依次询问：

1. **密钥库密码** — 两次输入（**务必记住**）
2. **姓名/组织信息** — 直接回车跳过或用拼音填写
3. **确认** — 输入 `y`
4. **密钥密码** — 直接回车（与密钥库密码相同）或单独设置

## 第二步：配置签名信息

打开 `android/local.properties`，追加三行：

```properties
storePassword=你设置的密钥库密码
keyAlias=sororain
keyPassword=你设置的密钥密码
```

### 完整示例

配置完成后 `local.properties` 类似这样：

```properties
sdk.dir=C:\\Users\\Sororain\\AppData\\Local\\Android\\sdk
flutter.sdk=D:\\Development\\flutter
flutter.buildMode=release
flutter.versionName=0.8.92
flutter.versionCode=2026020201
storePassword=123456
keyAlias=sororain
keyPassword=123456
```

## 验证签名

配置完成后，构建脚本会自动检测：

- `keystore.jks` 存在 ✅
- `storePassword` / `keyAlias` / `keyPassword` 已配置 ✅

→ `isRelease = true` → 构建产出**正式签名 Release APK**

### 构建命令

```powershell
dart run setup.dart android --arch arm64
```

或直接：

```powershell
flutter build apk --release --target-platform android-arm64 --dart-define-from-file=env.json
```

### 产物

```
build/app/outputs/flutter-apk/app-release.apk
```

包名：`com.sororain.clash`（无 `.dev` 后缀），可直接发布到应用商店。

## 注意事项

- 签名文件 **`keystore.jks`** 和 **密码**请妥善保管，丢失后无法更新已发布的应用
- 建议将 `keystore.jks` 加入 `.gitignore`，不要提交到代码仓库
- `local.properties` 也不要提交到代码仓库（已默认被 gitignore）
