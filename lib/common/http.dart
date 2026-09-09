import 'dart:io';

import 'package:sororain/common/common.dart';
import 'package:sororain/providers/providers.dart';
import 'package:sororain/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SororainHttpOverrides extends HttpOverrides {
  static String handleFindProxy(Uri url) {
    if ([localhost].contains(url.host)) {
      return 'DIRECT';
    }
    final ref = globalState.container;
    final isStart = ref.read(isStartProvider);
    final suspend = ref.read(suspendProvider);
    commonPrint.log('find $url proxy: $isStart');
    if (!isStart || suspend) return 'DIRECT';
    final mixedPort = ref.read(
      patchClashConfigProvider.select((state) => state.mixedPort),
    );
    return 'PROXY localhost:$mixedPort';
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (_, _, _) => true;
    client.findProxy = handleFindProxy;
    return client;
  }
}

