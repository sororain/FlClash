# FlClash 开发中遇到的问题记录

## 1. Git 子模块未初始化

**问题**：`core/Clash.Meta/` 目录为空，缺少 `go.mod`，Go 编译失败。

**原因**：`git clone` 默认不拉取子模块（submodule），只创建空目录。

**解决**：
```bash
git submodule update --init --recursive
```
或克隆时加 `--recurse-submodules`。

---

## 2. 依赖包从 Git 改为 pub.dev 官方包

**问题**：`flutter_js` 和 `yaml_writer` 使用了 Git 依赖（chen08209 的 fork），可能导致版本锁定和构建问题。

**解决**：
- `flutter_js`: `git: chen08209/flutter_js @ c0e10a5` → `flutter_js: ^0.8.7`
- `yaml_writer`: `git: chen08209/yaml_writer @ 79c78a4` → `yaml_writer: ^2.1.0`

---

## 3. `setup.dart` 外部包依赖问题

**问题**：`setup.dart` 依赖 `args`、`crypto`、`path` 三个外部包，增加了构建时的依赖解析复杂度。

**解决**（FlClash_B 中的重构方案）：
- 移除 `package:args/command_runner.dart` — 改为手动解析 CLI 参数
- 移除 `package:crypto/crypto.dart` — 改用系统命令计算 SHA256（Windows: `certutil`, Linux/macOS: `sha256sum`）
- 移除 `package:path/path.dart` — 内联 `pathJoin()`、`pathBasename()` 实现

---

## 4. Flutter_distributor Android 构建 Bug

**问题**：Android APK 构建时，`flutter_distributor package` 报错：
```
type '_BuildAndroidApkResult' is not a subtype of type 'BuildWindowsResult'
```

**解决**：绕过 flutter_distributor，直接使用 `flutter build apk --release` 构建。

---

## 5. Rust Helper 干扰 Android 构建

**问题**：在 Windows 上构建 Android 时，构建脚本尝试将 Rust 编译的 `.exe` helper 复制到 Android 目录。

**解决**：在 `setup.dart` 中增加平台判断 `&& target == Target.windows`。

---

## 6. Gradle 网络问题（中国地区）

**问题**：`maven.google.com` 被屏蔽，Gradle 依赖下载超时导致 Android 构建失败。

**解决**：在 `android/build.gradle.kts` 和 `android/settings.gradle.kts` 中添加阿里云镜像：
```kotlin
maven { url = uri("https://maven.aliyun.com/repository/public") }
maven { url = uri("https://maven.aliyun.com/repository/google") }
maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
```

---

## 7. HTTP 请求通过系统代理导致 500 错误

**问题**：VPN 代理运行时，HTTP API 请求被路由到系统代理（如 Clash 自身），导致请求面板 API 时返回 500。

**解决**：所有面板 API 请求强制使用 `DIRECT` 直连：
```dart
client.findProxy = (uri) => 'DIRECT';
```

---

## 8. 客服按钮 `app_config.json` 文件路径问题

**问题**：客服按钮使用 `File('app_config.json')` 读取配置，生产环境下找不到文件（相对路径问题）。

**解决**：改为编译时内联常量 `AppConfig.crispId`（定义在 `lib/common/app_config.dart`）。

---

## 9. 资源目录引用无效

**问题**：`pubspec.yaml` 中引用了 `assets/images/avatar/` 目录，但该目录不存在，导致 `flutter pub get` 警告。

**解决**：从 `pubspec.yaml` 中移除该引用。

---

## 10. 登录页面括号嵌套错误

**问题**：调整登录页按钮布局（将联系客服/官网按钮移到创建账户/忘记密码按钮下方）时，`Center` 的闭合括号 `)` 缺失，导致编译错误。

**解决**：补上缺失的 `)`。

---

## 11. 用户信息流量数据获取

**问题**：`/user/info` 接口不返回流量使用数据（`u`/`d` 字段），需要从其他接口获取。

**解决**：优先级策略：
1. 优先从 `/user/getSubscribe` 获取（含 `plan.name`、`u`、`d`、`transfer_enable`）
2. 回退：从套餐列表匹配套餐名称
3. 再回退：从已同步的订阅信息获取流量数据

---

## 12. 导出文件未更新

**问题**：新建的页面文件（`login.dart`、`shop.dart` 等）未被添加到 `pages.dart` 和 `views.dart` 的导出中，也未注册到导航系统。

**解决**：
- 更新 `lib/pages/pages.dart` 添加 `export 'login.dart'`
- 更新 `lib/views/views.dart` 添加新视图的导出
- 更新 `application.dart` 添加登录认证流程和路由
- 更新 `enum/enum.dart` 添加新 `PageLabel`
- 更新 `common/navigation.dart` 添加新导航项
