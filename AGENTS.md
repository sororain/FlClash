# AGENTS.md

This file provides guidance for AI coding agents working with code in this repository.

## Project Overview

Sororain is a deep customization of FlClash — a V2Board subscription/payment client built on Flutter with the
ClashMeta (mihomo) Go core. Supports Android, Windows, macOS, and Linux. The customization layer lives in `lib/iqoo/`
(login, orders, payment, invite, tickets, wallet) which talks to a V2Board backend (`v2board/`, git-ignored local
reference). Material You design with Surfboard-like UI.

## Common Development Commands

### Build

```bash
# Update submodules first (ClashMeta Go core lives in core/Clash.Meta/)
git submodule update --init --recursive

# Full package build (Go core + Rust helper + Flutter + packaging)
dart setup.dart windows
dart setup.dart android
dart setup.dart linux
dart setup.dart macos

# Core only (Go core + helper on Windows; skip Flutter packaging)
dart setup.dart windows --out core
```

Cross builds are restricted: only the host platform, plus Android from any desktop host.

### Flutter Development

```bash
flutter pub get
flutter run --dart-define-from-file=env.json   # env.json is written by setup.dart
flutter run -d windows                         # or -d android / -d linux / -d macos
```

Flutter SDK is pinned to **3.44.9** (Dart 3.12.2). Do not upgrade to 3.47.x: the 3.47 Windows engine has a
crash (`InternalFlutterGpu_Texture_InitializeFromImage`, worker thread, ~20s after launch) that suspends the app.

### Code Generation

Required after modifying models, providers, or database schema:

```bash
dart run build_runner build --delete-conflicting-outputs
dart run build_runner watch  # Continuous regeneration
```

Code generation covers: Riverpod providers (`riverpod_generator`), models (`freezed`, `json_serializable`), and
database tables (`drift_dev`).

### Testing

The repository has no `test/` baseline. Verify changes with:
`flutter pub get` → `flutter analyze lib` (expect 0 errors; ~190 info-level lints from upstream code are noise)
→ `flutter build windows --debug` for a full compile sanity check.

### Build Dependencies

- **Windows:** Visual Studio 2022 (C++ workload), CMake, Inno Setup, Go 1.20+, Rust (cargo — helper service), Android NDK for Android builds.
- **Linux:** `sudo apt-get install libayatana-appindicator3-dev libkeybinder-3.0-dev`
- **macOS:** `npm install -g appdmg` for DMG creation.

## Architecture

### Core Integration (Go ClashMeta <-> Flutter)

Dart-side lives in `lib/core/` (flat files for shared bits + `lib/core/desktop/` for the desktop lifecycle):

- **Android (lib mode):** Go core compiled as C shared library (`libclash.so`) via `go build -buildmode=c-shared`.
  Flutter calls it via FFI through `lib/plugins/service.dart`; Dart side: `lib/core/lib.dart` (`CoreLib`).
- **Desktop (0.8.96-aligned form):** `lib/core/desktop/` holds the lifecycle (`lifecycle.dart`), transport
  (`transport.dart` — rust_api named pipe/local socket FFI), RPC client, helper client (Windows Helper v6
  protocol), launcher, and model layer. `service.dart` is a thin shell over `DesktopCoreLifecycle`.

`lib/core/controller.dart` (`CoreController`) picks the platform implementation. `lib/core/interface.dart` defines
the shared `CoreHandlerInterface` with lifecycle `start/restart/stop/close` and strongly-typed returns
(`Delay`, `Traffic`, `TrackerInfo`).

Go core key files: `core/hub.go` (handlers + method dispatch via `MethodCall`/`MethodResponse`), `core/server.go`
(named-pipe/TCP IPC server with `resumingWriter` for Modern-Standby half-frame stalls), `core/lib.go` (CGO exports via
`invokeMethod`), `core/ipc_test.go` (wire-level tests, run with `go test -tags with_gvisor ./...` in `core/`).

### State Management (Riverpod)

`lib/providers/action.dart` and `state.dart` are **part-sharded**:

- `lib/providers/actions/*.dart` — business logic: common, setup, backup, core, system (+`system_exit` exit
  coordinator), store, theme, proxies, profiles
- `lib/providers/state/*.dart` — derived providers: navigation, overwrite, profile, proxies (delay/pending),
  system, theme
- `lib/providers/app.dart` / `config.dart` / `database.dart` — runtime state, persistent settings, Drift wrappers

`globalState` (`lib/state.dart`) is a singleton holding app lifecycle, timers, theme, and the start/stop state.
Generated providers live in `lib/providers/generated/`. After touching providers/models/database, run `build_runner`.

### Database (Drift/SQLite)

Type-safe SQLite via Drift in `lib/database/`. Schema version 2. Tables: `Profiles`, `Scripts`, `Rules`,
`ProfileRuleLinks` (`profile_rule_mapping`), `ProxyGroups`, and `IconRecords` (`icon_records`). Rule scenes
distinguish global added rules, profile added rules, profile custom rules, and disabled links. Fractional indexing
orders rules and proxy groups. Generated Drift output in `lib/database/generated/database.g.dart`.

### Manager Stack (Widget Tree)

```
AppEnvManager > StatusManager > ThemeManager
  > [Desktop: WindowManager > TrayManager > HotKeyManager > ProxyManager]
  > ConnectivityManager > CoreManager > AppStateManager
  > [Mobile: AndroidManager > VpnManager | Desktop: WindowHeaderContainer]
```

Desktop-only managers are conditionally inserted in `lib/application.dart`.

### Core Controller + Actions

`lib/core/controller.dart` (`CoreController`) is a singleton facade over `CoreHandlerInterface` — Android FFI
(`CoreLib`) vs desktop (`CoreService`). Has a `@visibleForTesting` constructor and `resetInstance()` for injection.

`lib/core/method.dart` defines `CoreMethod` (wire enum), `CoreMethodCall/Response/Exception`, and
`coreFailureLogLevel`.

### Build System

`setup.dart` (project root) is the direct-call build orchestrator (not a hook pipeline):

1. `_syncNames()` — brand engine: derives all names from `app_config.json` (single source of truth) and rewrites
   30+ platform files (CMakeLists, Runner.rc, inno_setup.iss, Info.plist, Kotlin sources, etc.). State file
   `build/name_state.json` remembers the previous names for deterministic old→new replacements.
2. `Build.buildCore` — direct `go build` (tags `with_gvisor`, ldflags `-w -s`) per platform/arch matrix
   (`buildItems`).
3. On Windows: `Build.calcSha256` → `Build.buildHelper` which compiles the Rust helper with
   `CORE_SHA256`/`CORE_NAME` env vars (compile-time embedded into `service/hub.rs` via `build.rs`).
4. `writeCoreManifest` (via build_tool) writes `libclash/<platform>/manifest.json` — the installed app reads it for
   helper verification. No `core_sha256.json`, no `--dart-define CORE_SHA256`.
5. `env.json` (APP_ENV, ANDROID_ARCH) is consumed by `--dart-define-from-file=env.json` for `flutter` builds.
6. Packaging via flutter_distributor fork (`chen08209/flutter_distributor @ v0.6.11-flclash.2`, idempotent
   activation + `dart pub global run`). **Do not switch to `fastforge` 0.6.12** — its exe maker
   (`MakeExeConfig.fromJson`) parses `locales` as `List<String>` and breaks our `locales: [{lang, file}]` map
   (Chinese installer language).

`dart setup.dart android` bypasses the distributor (direct `flutter build apk --release --split-per-abi`).

Helper name/core name also derive from `app_config.json` via `plugins/setup/buildkit/build_tool/lib/src/options.dart`
(`BuildConfig._fromAppConfig` fallback when the root `build_config.yaml` is absent).

Brand deep-link scheme: `sororain` (Android `AndroidManifest.xml` scheme, macOS `Info.plist`,
`lib/common/window.dart` protocol.register). `clash`/`clashmeta` kept for external import compatibility.

### Local Plugins (`plugins/`)

- `setup` — build harness FFI plugin (hooks trigger Go/Rust compilation per platform)
- `proxy` — system proxy configuration
- `rust_api` — Flutter Rust Bridge FFI plugin (IPC transport)
- `wifi_ssid` — Wi-Fi SSID detection (Android package = `com.sororain.clash.wifi_ssid`)
- `window_ext` — window extensions

### Rust Helper Service (`services/helper/`)

Windows-only privileged helper for starting the core as admin and managing TUN (`cargo build --release --features
windows-service`). Auth: helper's compile-time `EXPECTED_CORE_SHA256` (from manifest.json served at install) is
checked against the `coreSha256` query param on `/ping`; pipe whitelist `is_allowed_core_pipe` only accepts
`\\.\pipe\SororainCore_<32-hex>` addresses. Tests: `cargo test --manifest-path services/helper/Cargo.toml`.

### Localization

ARB files in `arb/`. Generated via `intl_utils` into `lib/l10n/`.

**Supported locales:** `en`, `zh_CN`, `ja`, `ru`

**Access patterns:**

- In widgets with BuildContext: `context.appLocalizations.key` (import `common.dart`)
- In controllers/providers/non-widget code: `currentAppLocalizations.key` (import `app_localizations.dart`)

### iqoo ↔ v2board Alignment Rules

The local `v2board/` reference tree has been removed. The contract keys below were verified against
`app/Http/Routes/V1/UserRoute.php` and `app/Http/Controllers/V1/User/` of the upstream V2Board code and remain valid —
restore that reference tree before re-verifying against a specific backend build. Keys:

- Amount fields are **fen (cents)** — always integer; wallet/transfer/UI display uses `fenToYuan`.
- `order/check` returns `status` int (0–4); `cancel` is POST with `trade_no`.
- `coupon/check` is read-only and never participates in `limit_period` validation.
- `notify` may silently `return true` for non-pending orders (a chosen, permanently-closed gap).
- `telegram_discuss_link` in `comm/config` shows a "join group" card on the profile page; blank hides it (About-page
  Telegram hardcoded to the publisher's group instead).
- `connectivity_plus` pinned at **7.2.0** — 7.3.x crashes Windows builds via CP936/GBK encoding of C++ sources
  (C4819/C2220).
