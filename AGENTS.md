# AGENTS.md

This file provides guidance for AI coding agents working with code in this repository.

## Project Overview

FlClash is a multi-platform proxy client based on ClashMeta (mihomo), built with Flutter. Supports Android, Windows,
macOS, and Linux. Material You design with Surfboard-like UI.

## Common Development Commands

### Building

```bash
# Update submodules first (ClashMeta Go core lives in core/Clash.Meta/)
git submodule update --init --recursive

# Full package build via setup.dart (core + helper are built by the Dart build hook
# while flutter_distributor runs `flutter build`, so there is no core-only step any more)
dart setup.dart macos
dart setup.dart linux
dart setup.dart windows
dart setup.dart android
dart setup.dart android --arch arm64
```

### Flutter Development

```bash
# Project is pinned with FVM (.fvmrc currently uses Flutter 3.35.7)
fvm flutter pub get
fvm flutter run
fvm flutter test

# Plain Flutter also works when your global SDK matches the project constraints
flutter pub get
flutter run        # Run on connected device/desktop
flutter test        # Run all tests (use flutter test, not dart test — models pull in Flutter types)
```

### Code Generation

Required after modifying models, providers, or database schema:

```bash
dart run build_runner build --delete-conflicting-outputs
dart run build_runner watch  # Continuous regeneration
```

Code generation covers: Riverpod providers (`riverpod_generator`), models (`freezed`, `json_serializable`), and database
tables (`drift_dev`).

### Testing

Tests use `flutter_test`; `mocktail` is the mocking framework when mocks are needed.

```bash
flutter test                      # Root package tests (currently test/core/desktop/, 31 tests)
flutter test test/core/desktop/   # Desktop core stack only
dart analyze lib                  # Baseline: 0 error / 0 warning / ~229 info (lints only)

# 插件包测试：可以从根目录按路径传入，但见下方前提
flutter test plugins/proxy/test/proxy_test.dart
flutter test plugins/setup/setup_hooks/test
```

Root `flutter test` only discovers the root package's `test/` directory by default. Include bundled plugin Dart tests by
passing their paths explicitly, or run `flutter test` from that plugin package directory. Native plugin tests under
platform folders (for example Windows C++ tests) are not run by `flutter test`.

**插件包测试的前提与现状（2026-09-12 实测，58 通过 / 2 失败）**：
- `plugins/setup/setup_hooks` 必须**先在该包内**跑一次 `flutter pub get`，否则会报 `Connection closed before test suite loaded`（`target_test.dart` 加载失败）—— 包内 `.dart_tool` 被删掉后就是这样；这是包级依赖解析，根目录的 `pub get` 不覆盖它。
- `plugins/tray_manager/packages/tray_manager/test/macos_tray_icon_source_test.dart` 目前在 Windows 上 `setUpAll` 阶段即失败（`firstWhere` 抛异常）。该文件与本次构建链迁移无关，失败原因未查。
- `plugins/rust_api/test_driver/integration_test.dart` 是 **integration test**（需要设备/驱动），不是单测。

**当前实际布局（2026-09-12 核实）**：根包只有 `test/core/desktop/` 三个文件 —— `helper_client_test.dart`（Helper 协议语义：ping 双校验、start 回显与失败码、stop 组合约束）、`launcher_test.dart`（Helper/直连的选择与回退策略）、`manager_test.dart`（`DesktopCoreManager` 状态机）。历史文档里写过的 `test/models`、`test/providers`、`test/common`、`test/database`、`test/widgets`、`test/setup_test.dart` 在本仓库中**并不存在**，不要按那些路径去跑测试。

**Mocking `CoreHandlerInterface`:** Use `CoreController.test(mock)` to inject a mock interface. Call
`CoreController.resetInstance()` in `tearDown` to clean up the singleton between tests. Remember to
`registerFallbackValue()` for freezed params used with `any()` matchers.

**Provider tests:** Use `ProviderContainer` directly (no widget tree needed for simple notifiers). The Riverpod
generated `update()` method takes a callback: `notifier.update((state) => newValue)`.

**Model round-trip tests:** Always go through `jsonEncode`/`jsonDecode` when testing freezed models with
nested objects — `toJson()` stores child objects directly (not as maps), so direct `fromJson(toJson())`
fails for nested freezed types.

**桌面栈测试的坑**：`DesktopCoreManager` 的状态流是 broadcast Stream，事件**异步派发**；断言状态序列前必须先
`await Future<void>.delayed(Duration.zero)`，否则只会看到第一个事件。另外用伪 HTTP 适配器给 `HelperClient` 造响应时
必须尊重真实编码 —— `/ping` 返回 `text/plain`，若标成 `application/json`，dio 会把 helper 路径当 JSON 解析并抛
`FormatException`，表现为 `notReady` 而掩盖真实原因。

**Mocking `CoreHandlerInterface`:** Use `CoreController.test(mock)` to inject a mock interface. Call
`CoreController.resetInstance()` in `tearDown` to clean up the singleton between tests. Remember to
`registerFallbackValue()` for freezed params used with `any()` matchers.

**Provider tests:** Use `ProviderContainer` directly (no widget tree needed for simple notifiers). The Riverpod
generated `update()` method takes a callback: `notifier.update((state) => newValue)`.

**Model round-trip tests:** Always go through `jsonEncode`/`jsonDecode` when testing freezed models with
nested objects — `toJson()` stores child objects directly (not as maps), so direct `fromJson(toJson())`
fails for nested freezed types.

### Build Dependencies

**Linux:** `sudo apt-get install libayatana-appindicator3-dev libkeybinder-3.0-dev`

**Windows:** GCC and Inno Setup. `ANDROID_NDK` env var for Android builds.

**macOS:** `npm install -g appdmg` for DMG creation.

## Architecture

### Core Integration (Go ClashMeta <-> Flutter)

This is the most important architectural concept. The Go proxy core (`core/`) operates in two modes:

- **Android (lib mode):** Go core compiled as C shared library (`libclash.so`) via `go build -buildmode=c-shared` with
  CGO. Flutter calls it via FFI through the `service` plugin. Dart-side: `lib/core/lib.dart` (`CoreLib` class).

- **Desktop (core mode):** Go core runs as a separate process with `CGO_ENABLED=0`. Flutter communicates via
  JSON-over-socket (Unix socket on macOS/Linux, TCP on Windows). Dart-side: `lib/core/service.dart` (`CoreService`
  class).

`lib/core/controller.dart` (`CoreController`) selects the implementation based on platform. `lib/core/interface.dart`
defines the shared `CoreHandlerInterface`.

Go core key files: `core/hub.go` (handler functions), `core/action.go` (dispatch), `core/lib.go` (CGO exports),
`core/server.go` (socket server).

### State Management (Riverpod)

Provider files in `lib/providers/`:

- `app.dart` - Runtime/UI state (logs, traffic, delays, loading, navigation)
- `config.dart` - Persistent config providers (app settings, theme, VPN, proxy style)
- `state.dart` - Derived/computed providers (navigation, proxy, tray, color scheme)
- `action.dart` - Business logic notifiers (setup, backup, core lifecycle, proxy selection)
- `database.dart` - Drift database provider wrappers

`globalState` (`lib/state.dart`) is a singleton holding app lifecycle, timers, theme, and the start/stop state.
Providers are generated into `lib/providers/generated/`.

### Database (Drift/SQLite)

Type-safe SQLite via Drift in `lib/database/`. Current schema version is 2. Tables are `Profiles`, `Scripts`, `Rules`,
`ProfileRuleLinks` (`profile_rule_mapping`), `ProxyGroups`, and `IconRecords` (`icon_records`). Rule scenes distinguish
global added rules, profile added rules, profile custom rules, and disabled links. Uses fractional indexing for rule and
proxy-group ordering.

Generated Drift output lives in `lib/database/generated/database.g.dart`. After schema changes, run code generation and
add/update focused database tests under `test/database/` when converter or migration behavior changes.

### Manager Stack (Widget Tree)

Managers are nested InheritedWidgets/StatefulWidgets in `lib/application.dart`:

```
AppEnvManager > StatusManager > ThemeManager
  > [Desktop: WindowManager > TrayManager > HotKeyManager > ProxyManager]
  > ConnectivityManager > CoreManager > AppStateManager
  > [Mobile: AndroidManager > VpnManager | Desktop: WindowHeaderContainer]
```

Each manager in `lib/manager/` handles a specific platform concern. Desktop-only managers are conditionally inserted.

### Core Controller + Actions

`lib/core/controller.dart` (`CoreController`) is a singleton facade over `CoreHandlerInterface`. All 25+ public methods
delegate to the platform-specific interface (Android FFI or desktop socket). Has `@visibleForTesting` constructor and
`resetInstance()` for test injection.

Business logic lives in Riverpod notifier classes in `lib/providers/action.dart` (~960 lines, should be split):

- `CommonAction` — update check, common UI operations
- `SetupAction` — config setup, TUN management
- `BackupAction` — backup/restore with WebDAV sync
- `CoreAction` — core lifecycle (init, connect, restart, shutdown)
- `SystemAction` — system integration (tray, exit, brightness)
- `StoreAction` — profile storage operations
- `ThemeAction` — theme state updates
- `ProxiesAction` — group management, proxy selection
- `ProfilesAction` — profile CRUD, auto-update, import

### Platform Managers (`lib/manager/`)

Desktop: `WindowManager`, `TrayManager`, `HotKeyManager`, `ProxyManager`
Mobile: `AndroidManager`, `TileManager`, `VpnManager`
Shared: `ConnectivityManager`, `CoreManager`, `AppStateManager`, `StatusManager`, `ThemeManager`

### Build System

`setup.dart` (project root) is the release build orchestrator:

1. Writes `env.json` (`APP_ENV` only), consumed via `--dart-define-from-file=env.json`.
2. Refuses to continue when some package has `hooks.user_defines.*.build_assets: false`
   (`packagesNotBuildingAssets` in `setup.dart`): that package's build hook is a no-op, so the package would ship
   without a core and the failure would otherwise be silent.
3. Activates the global `flutter_distributor` (pinned git ref `v0.6.11-flclash.2`) and runs it via
   `dart pub global run`. The `flutter build` inside that run triggers the Dart build hooks
   (`plugins/setup/hook/build.dart` → `setup_hooks`' `CoreBuilder`/`RustBuilder`): the Go core
   (`go build -ldflags=-w -s -tags=with_gvisor`, `-buildmode=c-shared` + NDK clang for Android lib mode, `.so` into
   `libclash/android/<abi>/` for Gradle to pick up) and, on Windows, the Rust helper
   (`cargo build --release --features windows-service` in `services/helper/` with `CORE_SHA256`/`CORE_NAME`). The hook
   also writes `libclash/<platform>/manifest.json`; `windows/CMakeLists.txt` installs core + helper + `manifest.json`
   next to the app executable, which is what the runtime SHA check reads.

There is no `core_sha256.json` any more — 0.8.97 dropped it and nothing reads it: the core SHA is computed by the build
hook (`plugins/setup/setup_hooks/lib/src/build.dart` → `calcSha256(core.primaryOutput)`) and is what it injects into the
helper and writes into `manifest.json`.

A Dart build hook is what builds core and helper now (the 0.8.97 model): `plugins/setup/hook/build.dart` → `setup_hooks`'
`CoreBuilder`/`RustBuilder` build core + helper and write `libclash/<platform>/manifest.json`, which `setup.dart` no
longer duplicates — it only writes `env.json`, guards against disabled build hooks, and invokes
flutter_distributor.

**Windows helper auth (release):** Core SHA256 is embedded into the Rust helper at compile time only
(`services/helper/build.rs` exports `cargo:rustc-env=CORE_SHA256` and `CORE_NAME`; it reads `CORE_SHA256` — what the Dart
build hook passes — with `TOKEN` kept only as a legacy fallback for hand-run builds). The Flutter app no longer carries
a `--dart-define` copy: at runtime both sides read the Core's `manifest.json` next to the executable
(`lib/core/desktop/core_manifest.dart` → `CoreManifest.readCoreSha256()`), which is why `globalState.coreSHA256` is gone.

**Helper protocol (v6):** `http://127.0.0.1:47890`, all replies carry `x-sororain-helper-protocol: 6`
(`helperProtocolVersionHeader`/`helperProtocolVersion`). Endpoints: `GET /ping?coreSha256=<64hex>` (200 = helper exe path
as `text/plain`; 409 `coreSha256Mismatch`; 409 without that code = Core executable not accessible), `POST /start
{address, sessionId}` (200 `{sessionId, pid}`; 400 `invalidRequest`; 409 `coreVerificationFailed`; 500
`processLaunchFailed` + `osError`; 500 `coreStopFailed`; 500 `internalError`), `POST /stop {sessionId}` (200
`{sessionId, stopped:true}`; 200 `{stopped:false, reason:'notRunning'}`; 409 `reason:'sessionMismatch'`), `GET /logs`
(text log tail). `/start` only accepts a Core address shaped `\\.\pipe\SororainCore_<32 lowercase hex>`
(`windowsPipeName` uses `_randomPipeId()`, not a short random number) and a 32-hex `sessionId`; the app's
`HelperClient`/`HelperLauncherResolver`/`FallbackCoreLauncher` treat exactly the two pre-spawn failures
(`coreVerificationFailed`, `processLaunchFailed`) as "fall back to a direct launch". The helper binds the Core into a
Windows Job Object with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`, so a helper that dies cannot orphan a Core (and its TUN).

**Windows helper auth (debug):** There is no debug bypass any more — the helper verifies the Core SHA256 in every build
mode, because the build hook injects `CORE_SHA256` for debug builds too. A helper built by hand (`cargo build` with no
env) carries an empty SHA and refuses to serve.

`plugins/setup/` is a build-harness package with no Dart API and no platform folders; it exists only to provide the Dart
build hook above (Go core + Rust helper compilation). It is **enabled**: `pubspec.yaml` → `hooks.user_defines.setup:
build_assets: true`. That is only possible because the desktop stack reads the Core SHA256 from `manifest.json` at
runtime (`lib/core/desktop/core_manifest.dart` → `CoreManifest.readCoreSha256()`); a compile-time `--dart-define` must
exist before `flutter build`, while the hook only runs during it, so the two cannot coexist.

Build configuration defaults live in `plugins/setup/setup_hooks/lib/src/options.dart` and can be overridden via
`build_config.yaml` in the project root.

Architecture detection is automatic (host arch via `uname -m` on Unix, `PROCESSOR_ARCHITECTURE` on Windows). The
`--description` flag passed to flutter_distributor adds arch suffix to artifact names (e.g.,
`FlClash-0.8.93-macos-arm64.dmg`).

### Local Plugins (`plugins/`)

- `setup` - Build harness package (Dart build hook that triggers Go/Rust compilation per platform)
- `rust_api` - Flutter Rust Bridge package built by a Dart build hook (no platform folders)
- `proxy` - System proxy configuration
- `rust_api` - Flutter Rust Bridge package built by a Dart build hook (no platform folders)
- `tray_manager` - System tray (forked/custom)
- `wifi_ssid` - Wi-Fi SSID detection
- `window_ext` - Window extensions

`flutter_distributor` is no longer vendored in `plugins/`; `setup.dart` activates it globally from a pinned git ref
and runs it via `dart pub global run`.

### Rust Helper Service (`services/helper/`)

Windows-only privileged helper for starting the core as admin and managing TUN. Built with
`cargo build --release --features windows-service`. Token-based auth with Flutter app.

### Localization

ARB files in `arb/`. Generated via `flutter_intl` into `lib/l10n/`. Use `AppLocalizations.of(context)!` for strings.

**Supported locales:** `en`, `zh_CN`, `ja`, `ru`

**Access patterns:**

- In widgets with BuildContext: `context.appLocalizations.key` (import `common.dart`)
- In controllers/providers/non-widget code: `currentAppLocalizations.key` (import `app_localizations.dart`)
