import 'package:flutter/foundation.dart';

import 'package:fl_clash/enum/enum.dart';

class CommonPrint {
  static CommonPrint? _instance;

  CommonPrint._internal();

  factory CommonPrint() {
    _instance ??= CommonPrint._internal();
    return _instance!;
  }

  void log(String? text, {LogLevel? logLevel}) {
    // release 下只保留 warning/error 级日志；info/debug 级仅在 debug 构建打印
    final isImportant = logLevel == LogLevel.warning || logLevel == LogLevel.error;
    if (!kDebugMode && !isImportant) return;
    debugPrint('[APP] $text');
  }
}

final commonPrint = CommonPrint();

