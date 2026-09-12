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

# Full package build (Go core + Flutter + packaging) via setup.dart
dart setup.dart macos
dart setup.dart linux
dart setup.dart windows
dart setup.dart android

# Build only the Go core (+ Windows Rust helper) and stop before packaging
# (--out core; env.json is still written so the app keeps its compile-time SHA256)
dart setup.dart windows --out core
dart setup.dart macos --out core
dart setup.dart linux --out core
dart setup.dart android --out core --arch arm64
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

Tests use `package:test/test.dart` for pure Dart logic (common utils, models) and `flutter_test` for provider/widget tests.
`mocktail` is the mocking framework.

```bash
flutter test test/models/      # Model serialization & extension round-trip tests
flutter test test/core/        # CoreController tests (mocked CoreHandlerInterface)
flutter test test/providers/   # Riverpod provider tests (config & app state notifiers)
flutter test test/common/      # Utility function tests (utils, string, iterable, fixed, etc.)
flutter test test/database/    # Database type converter tests
flutter test test/widgets/     # Widget-level rendering/interaction tests
flutter test test/setup_test.dart
flutter test plugins/proxy/test/proxy_test.dart  # Dart tests for bundled plugin packages
```

Root `flutter test` only discovers the root package's `test/` directory by default. Include bundled plugin Dart tests by
passing their paths explicitly, or run `flutter test` from that plugin package directory. Native plugin tests under
platform folders (for example Windows C++ tests) are not run by `flutter test`.

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

1. Builds the Go core inline (`Build.buildCore` in `setup.dart`): `go build -ldflags=-w -s -tags=with_gvisor`, with
   `GOOS`/`GOARCH`/`CGO_ENABLED` per target. Android uses `-buildmode=c-shared` + NDK clang, then moves the `.so` into
   `libclash/android/<abi>/` (Gradle copies it on into `android/core/src/main/jniLibs/`).
2. On Windows, also builds the Rust helper (`Build.buildHelper`): `cargo build --release --features windows-service` in
   `services/helper/` with `TOKEN=<core sha256>`.
3. Writes `env.json` (`APP_ENV`, `CORE_SHA256`, `ANDROID_ARCH`), consumed via `--dart-define-from-file=env.json`.
4. Activates the global `flutter_distributor` (pinned git ref `v0.6.11-flclash.2`) for packaging, then runs it via
   `dart pub global run`. `--out core` stops after step 3 (no packaging).

There is no `core_sha256.json` any more — 0.8.97 dropped it and nothing reads it: the core SHA is computed by
`setup.dart` from the artifact it just built.

A Dart build hook also exists now (the 0.8.97 model): `plugins/setup/hook/build.dart` → `setup_hooks`'
`CoreBuilder`/`RustBuilder` build core + helper and write `libclash/<platform>/manifest.json`, which the app can read at
runtime via `CoreManifest`. It is currently **disabled** by `pubspec.yaml` → `hooks.user_defines.setup.build_assets:
false`, because the live desktop path still consumes the compile-time `CORE_SHA256` (a `--dart-define` must exist before
`flutter build`, while the hook only runs during it). Enable it only after the desktop core stack reads `manifest.json`
at runtime.

**Windows helper auth (release):** Core SHA256 is embedded in both the Flutter app (`--dart-define`) and the Rust helper
(`TOKEN` env var during cargo build; `services/helper/build.rs` also accepts `CORE_SHA256`, the variable the Dart build
hook passes). The Dart app pings the helper and verifies the token matches.

**Windows helper auth (debug):** The Rust helper skips token verification when built in debug mode
(`cfg!(debug_assertions)`), so `flutter run` works without any SHA256 dance.

`plugins/setup/` is a build-harness package with no Dart API and no platform folders; it exists only to provide the Dart
build hook above (Go core + Rust helper compilation).

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
