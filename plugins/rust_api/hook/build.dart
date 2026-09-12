import 'dart:io';

import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

/// Dart build hook (0.8.97 model): compiles the Rust crate under `rust/`
/// through Native Assets, so this package needs no platform folders.
///
/// Flutter runs this hook during every build and bundles the produced
/// `librust_api` into the app itself; there is no podspec/CMake/Gradle and no
/// cargokit anymore.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (input.userDefines['build_assets'] == false) {
      stdout.writeln('Skipping the Rust build: user-define build_assets=false');
      return;
    }
    await FlutterRustBridgeNativeAssetsBuilder(
      cratePath: 'rust',
    ).run(input: input, output: output);
  });
}

// 说明：上游 0.8.97 的同类 hook 还带一段 `_bindgenEnvironment`，在 Android 上
// 为 rquickjs 的 bindgen 指路 LIBCLANG_PATH。我们的 crate 只有
// flutter_rust_bridge + interprocess，没有 bindgen 需求，故不需要；
// 将来若引入上游的 script(rquickjs)/hotkey 源码，需要一并补回。
