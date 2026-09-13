import 'dart:async';
import 'dart:io';

import 'package:rust_api/rust_api.dart';
import 'package:sororain/pages/error.dart';
import 'package:sororain/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application.dart';
import 'common/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (system.isDesktop) {
      await RustLib.init();
    }
    final version = await system.init();
    final container = await globalState.init(version);
    HttpOverrides.global = SororainHttpOverrides();
    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const Application(),
      ),
    );
  } catch (e, s) {
    runApp(
      MaterialApp(
        home: InitErrorScreen(error: e, stack: s),
      ),
    );
  }
}
