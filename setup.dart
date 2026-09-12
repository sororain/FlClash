// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:setup_hooks/setup_hooks.dart' as setup_hooks;

String get _current => Directory.current.path;

String pathJoin(String p1, String p2, [String? p3, String? p4, String? p5]) {
  final sep = Platform.pathSeparator;
  final buffer = StringBuffer(p1);
  for (final part in [p2, p3, p4, p5]) {
    if (part == null) break;
    if (!buffer.toString().endsWith(sep) && !part.startsWith(sep)) {
      buffer.write(sep);
    }
    buffer.write(part);
  }
  return buffer.toString();
}

String pathBasename(String path) {
  return path.split(Platform.pathSeparator).last;
}

// === 配置加载（从 app_config.json）===
Map<String, dynamic>? _buildConfig;

Future<void> _loadBuildConfig() async {
  final configFile = File(pathJoin(_current, 'app_config.json'));
  if (await configFile.exists()) {
    final jsonStr = await configFile.readAsString();
    _buildConfig = json.decode(jsonStr) as Map<String, dynamic>;
    print('Config loaded: ${_buildConfig!['appName']}');
  } else {
    _buildConfig = {};
    print('Warning: app_config.json not found, using defaults');
  }
}

String get _appName => _buildConfig?['appName'] as String? ?? 'Sororain';
String get _coreName => _buildConfig?['coreName'] as String? ?? 'SororainCore';
String get _helperName => _buildConfig?['helperName'] as String? ?? 'SororainHelperService';
String get _appId => _buildConfig?['appId'] as String? ?? '728B3532-C74B-4870-9068-BE70FE12A3E6';
String get _packageName => _buildConfig?['packageName'] as String? ?? 'com.sororain.clash';
Map<String, dynamic> get _features => _buildConfig?['features'] as Map<String, dynamic>? ?? {};

Future<String> _detectCurrentAppName() async {
  // 从 constant.dart 中读取当前的 appName
  final file = File(pathJoin(_current, 'lib', 'common', 'constant.dart'));
  if (await file.exists()) {
    final content = await file.readAsString();
    final reg = RegExp(r"const appName = '([^']+)'");
    final match = reg.firstMatch(content);
    if (match != null) return match.group(1)!;
  }
  return 'Sororain'; // 默认值
}

Future<String> _detectCurrentHelperName() async {
  final file = File(pathJoin(_current, 'lib', 'common', 'constant.dart'));
  if (await file.exists()) {
    final content = await file.readAsString();
    final reg = RegExp(r"const appHelperService = '([^']+)'");
    final match = reg.firstMatch(content);
    if (match != null) return match.group(1)!;
  }
  return 'SororainHelperService';
}

Future<String> _detectCurrentCoreName() async {
  // 从 path.dart 中检测当前 core 文件名
  final file = File(pathJoin(_current, 'lib', 'common', 'path.dart'));
  if (await file.exists()) {
    final content = await file.readAsString();
    final reg = RegExp(r"join\(executableDirPath, '(.+)Core");
    final match = reg.firstMatch(content);
    if (match != null) return '${match.group(1)}Core';
  }
  return 'SororainCore';
}

Future<String> _detectCurrentPackageName() async {
  // 从 android/app/build.gradle.kts 中检测当前包名
  final file = File(pathJoin(_current, 'android', 'app', 'build.gradle.kts'));
  if (await file.exists()) {
    final content = await file.readAsString();
    final reg = RegExp(r'applicationId = "([^"]+)"');
    final match = reg.firstMatch(content);
    if (match != null) return match.group(1)!;
  }
  return 'com.sororain.clash';
}

Future<Map<String, String>> _loadNameState() async {
  final file = File(pathJoin(_current, 'build', 'name_state.json'));
  if (!await file.exists()) return {};
  try {
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return json.map((k, v) => MapEntry(k, v.toString()));
  } catch (_) {
    return {};
  }
}

Future<void> _saveNameState(Map<String, String> state) async {
  final dir = Directory(pathJoin(_current, 'build'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final file = File(pathJoin(_current, 'build', 'name_state.json'));
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(state));
}

Future<void> _syncNames() async {
  final appName = _appName;
  final coreName = _coreName;
  final helperName = _helperName;
  final packageName = _packageName;
  final appId = _appId;

  // 旧名来源优先级：状态文件（上次写入的名字，确定性）> 文件检测（仅首次 bootstrap）
  final state = await _loadNameState();
  final hasState = state.isNotEmpty;
  String pick(String key, String detected) =>
      (hasState ? state[key] : null) ?? detected;

  final oldAppName = pick('appName', await _detectCurrentAppName());
  final oldHelperName = pick('helperName', await _detectCurrentHelperName());
  final oldCoreName = pick('coreName', await _detectCurrentCoreName());
  final oldPackageName = pick('packageName', await _detectCurrentPackageName());
  final oldAppNameLower = oldAppName.toLowerCase();

  // 规则模式使用 $oldXxx 插值,自替换对(oldStr == newStr)由下方统一跳过。

  print('=== Syncing names from app_config.json ===');
  if (!hasState) {
    print('  (build/name_state.json 不存在，本次从文件检测 bootstrap)');
  }
  print('  oldName=$oldAppName → newName=$appName');
  print('  oldCore=$oldCoreName → newCore=$coreName');
  print('  oldHelper=$oldHelperName → newHelper=$helperName');

  final tasks = <(String, List<(String, String)>)>[
    // windows/CMakeLists.txt
    (pathJoin(_current, 'windows', 'CMakeLists.txt'), [
      ('set(BINARY_NAME "$oldAppName")', 'set(BINARY_NAME "$appName")'),
      ('/$oldCoreName.exe"', '/$coreName.exe"'),
      ('/$oldHelperName.exe"', '/$helperName.exe"'),
      // install 段落 - 不同格式
      ('"\${CLASH_DIR}/$oldCoreName.exe"', '"\${CLASH_DIR}/$coreName.exe"'),
      ('"\${CLASH_DIR}/$oldHelperName.exe"', '"\${CLASH_DIR}/$helperName.exe"'),
    ]),
    // windows/runner/Runner.rc
    (pathJoin(_current, 'windows', 'runner', 'Runner.rc'), [
      ('VALUE "FileDescription", "$oldAppName"', 'VALUE "FileDescription", "$appName"'),
      ('VALUE "OriginalFilename", "$oldAppName.exe"', 'VALUE "OriginalFilename", "$appName.exe"'),
      ('VALUE "ProductName", "clash"', 'VALUE "ProductName", "$appName"'),
      ('VALUE "InternalName", "clash"', 'VALUE "InternalName", "$appName"'),
      ('VALUE "ProductName", "$oldAppName"', 'VALUE "ProductName", "$appName"'),
      ('VALUE "InternalName", "$oldAppName"', 'VALUE "InternalName", "$appName"'),
    ]),
    // windows/runner/main.cpp
    (pathJoin(_current, 'windows', 'runner', 'main.cpp'), [
      ('window.Create(L"$oldAppName"', 'window.Create(L"$appName"'),
    ]),
    // make_config.yaml
    (pathJoin(_current, 'windows', 'packaging', 'exe', 'make_config.yaml'), [
      ('app_id: 728B3532-C74B-4870-9068-BE70FE12A3E6', 'app_id: $_appId'),
      ('app_name: $oldAppName', 'app_name: $appName'),
      ('display_name: $oldAppName', 'display_name: $appName'),
      ('executable_name: $oldAppName.exe', 'executable_name: $appName.exe'),
      ('output_base_file_name: $oldAppName.exe', 'output_base_file_name: $appName.exe'),
      ('publisher: $oldAppName', 'publisher: $appName'),
    ]),
    // distribute_options.yaml
    (pathJoin(_current, 'distribute_options.yaml'), [
      ("app_name: '$oldAppName'", "app_name: '$appName'"),
    ]),
    // build_config.yaml
    (pathJoin(_current, 'build_config.yaml'), [
      ('core_name: $oldCoreName', 'core_name: $coreName'),
      ('helper_name: $oldHelperName', 'helper_name: $helperName'),
    ]),
    // inno_setup.iss
    (pathJoin(_current, 'windows', 'packaging', 'exe', 'inno_setup.iss'), [
      // 三个名字是一体的,成组替换
      (
        "['$oldAppName.exe', '$oldCoreName.exe', '$oldHelperName.exe']",
        "['$appName.exe', '$coreName.exe', '$helperName.exe']",
      ),
      // UnregisterHelperService:升级/卸载时清 SCM 注册的目标服务名
      // (iss 里是 Exec('sc', 'delete <helper>', …),可匹配的连续串以 delete 开头)
      ('delete $oldHelperName', 'delete $helperName'),
    ]),
    // lib/common/path.dart
    (pathJoin(_current, 'lib', 'common', 'path.dart'), [
      ("$oldCoreName\$executableExtension'", "$coreName\$executableExtension'"),
      ("'$oldAppName.lock'", "'\$appName.lock'"),
    ]),
    // lib/common/constant.dart
    (pathJoin(_current, 'lib', 'common', 'constant.dart'), [
      ("const appName = '$oldAppName'", "const appName = '$appName'"),
      ("'/tmp/${oldAppName}Socket_", "'/tmp/${appName}Socket_"),
      ("'${oldAppName}MainIsolate'", "'${appName}MainIsolate'"),
      ("'${oldAppName}ServiceIsolate'", "'${appName}ServiceIsolate'"),
      ("'$oldHelperName'", "'$helperName'"),
      // ⚠️ packageName 不随 app_config 更改，需与 Kotlin 源码目录结构一致
    ]),
    // services/helper/src/service/windows.rs
    (pathJoin(pathJoin(_current, 'services', 'helper', 'src', 'service'), 'windows.rs'), [
      ('"$oldHelperName"', '"$helperName"'),
    ]),
    // linux/CMakeLists.txt
    (pathJoin(_current, 'linux', 'CMakeLists.txt'), [
      ('set(BINARY_NAME "$oldAppName"', 'set(BINARY_NAME "$appName"'),
      ('$oldCoreName"', '$coreName"'),
    ]),
    // linux/runner/my_application.cc
    (pathJoin(_current, 'linux', 'runner', 'my_application.cc'), [
      ('gtk_header_bar_set_title(header_bar, "$oldAppName")',
       'gtk_header_bar_set_title(header_bar, "$appName")'),
      ('gtk_window_set_title(window, "$oldAppName")',
       'gtk_window_set_title(window, "$appName")'),
    ]),
    // linux/packaging/{appimage,deb,rpm}/make_config.yaml
    for (final pkg in const ['appimage', 'deb', 'rpm'])
      (
        pathJoin(_current, 'linux', 'packaging', pkg, 'make_config.yaml'),
        [
          ('display_name: $oldAppName', 'display_name: $appName'),
          ('package_name: $oldAppName', 'package_name: $appName'),
          ('generic_name: $oldAppName', 'generic_name: $appName'),
          ('  - $oldAppName', '  - $appName'),
        ],
      ),
    // macos/Runner/Info.plist
    (pathJoin(_current, 'macos', 'Runner', 'Info.plist'), [
      ('<key>CFBundleExecutable</key>\n\t<string>$oldAppName</string>',
       '<key>CFBundleExecutable</key>\n\t<string>$appName</string>'),
      ('<key>CFBundleName</key>\n\t<string>$oldAppName</string>',
       '<key>CFBundleName</key>\n\t<string>$appName</string>'),
      ('<string>$oldAppName needs location access', '<string>$appName needs location access'),
    ]),
    // macos/Runner/Configs/AppInfo.xcconfig
    (pathJoin(_current, 'macos', 'Runner', 'Configs', 'AppInfo.xcconfig'), [
      ('PRODUCT_NAME = $oldAppName', 'PRODUCT_NAME = $appName'),
      ('PRODUCT_BUNDLE_IDENTIFIER = $oldPackageName', 'PRODUCT_BUNDLE_IDENTIFIER = $_packageName'),
    ]),
    // macos/packaging/dmg/make_config.yaml
    (pathJoin(_current, 'macos', 'packaging', 'dmg', 'make_config.yaml'), [
      ('title: $oldAppName', 'title: $appName'),
      ('path: $oldAppName.app', 'path: $appName.app'),
    ]),
    // macos/Runner.xcodeproj/project.pbxproj (Copy Core 引用 + 显示名称)
    (pathJoin(_current, 'macos', 'Runner.xcodeproj', 'project.pbxproj'), [
      ('/* $oldCoreName */', '/* $coreName */'),
      ('name = $oldCoreName;', 'name = $coreName;'),
      ('path = ../libclash/macos/$oldCoreName;', 'path = ../libclash/macos/$coreName;'),
      ('$oldCoreName in Copy Core', '$coreName in Copy Core'),
      ('INFOPLIST_KEY_CFBundleDisplayName = $oldAppName', 'INFOPLIST_KEY_CFBundleDisplayName = $appName'),
      ('/* $oldAppName.app */', '/* $appName.app */'),
      ('path = $oldAppName.app;', 'path = $appName.app;'),
      ('PRODUCT_BUNDLE_IDENTIFIER = $oldPackageName.debug', 'PRODUCT_BUNDLE_IDENTIFIER = $_packageName.debug'),
      ('PRODUCT_BUNDLE_IDENTIFIER = $oldPackageName.RunnerTests', 'PRODUCT_BUNDLE_IDENTIFIER = $_packageName.RunnerTests'),
      ('/$oldAppName.app/\$(BUNDLE_EXECUTABLE_FOLDER_PATH)/$oldAppName',
       '/$appName.app/\$(BUNDLE_EXECUTABLE_FOLDER_PATH)/$appName'),
    ]),
    // lib/common/window.dart
    (pathJoin(_current, 'lib', 'common', 'window.dart'), [
      // 深链 scheme 固定为 flclash:对齐上游 0.8.96 与 AndroidManifest,保证外部导入链接兼容
      ("protocol.register('$oldAppNameLower')", "protocol.register('flclash')"),
      ("protocol.register('${appName.toLowerCase()}')", "protocol.register('flclash')"),
    ]),
    // core/tun/tun.go
    (pathJoin(_current, 'core', 'tun', 'tun.go'), [
      ('Device:              "$oldAppName"', 'Device:              "$appName"'),
    ]),
    // android/app/build.gradle.kts
    (pathJoin(_current, 'android', 'app', 'build.gradle.kts'), [
      // ⚠️ 只改 applicationId，namespace 必须与源码目录结构一致
      ('applicationId = "$oldPackageName"', 'applicationId = "$_packageName"'),
    ]),
    // android/app/src/main/AndroidManifest.xml
    (pathJoin(pathJoin(_current, 'android', 'app', 'src', 'main'), 'AndroidManifest.xml'), [
      // label 统一引用 @string/app_name(资源化,见 strings.xml)
      ('android:label="$oldAppName"', 'android:label="@string/app_name"'),
    ]),
    // android/app/src/debug/AndroidManifest.xml
    (pathJoin(pathJoin(_current, 'android', 'app', 'src', 'debug'), 'AndroidManifest.xml'), [
      ('android:label="$oldAppName Debug"', 'android:label="$appName Debug"'),
    ]),
    // android/common/src/main/java/.../GlobalState.kt
    (pathJoin(pathJoin(pathJoin(_current, 'android', 'common', 'src', 'main'), 'java', 'com', 'sororain', 'clash'), 'common', 'GlobalState.kt'), [
      ('NOTIFICATION_CHANNEL = "$oldAppName"', 'NOTIFICATION_CHANNEL = "$appName"'),
      ('Log.d("[$oldAppName]", text)', 'Log.d("[$appName]", text)'),
    ]),
    // android/service/src/main/java/.../VpnService.kt
    (pathJoin(pathJoin(pathJoin(_current, 'android', 'service', 'src', 'main'), 'java', 'com', 'sororain', 'clash'), 'service', 'VpnService.kt'), [
      ('setSession("$oldAppName")', 'setSession("$appName")'),
    ]),
    // android/service/src/main/java/.../NotificationModule.kt
    (pathJoin(pathJoin(pathJoin(_current, 'android', 'service', 'src', 'main'), 'java', 'com', 'sororain', 'clash'), 'service', 'modules', 'NotificationModule.kt'), [
      ('setContentTitle("$oldAppName")', 'setContentTitle("$appName")'),
    ]),
    // android/service/src/main/java/.../NotificationParams.kt
    (pathJoin(pathJoin(pathJoin(_current, 'android', 'service', 'src', 'main'), 'java', 'com', 'sororain', 'clash'), 'service', 'models', 'NotificationParams.kt'), [
      ('val title: String = "$oldAppName"', 'val title: String = "$appName"'),
    ]),
    // android/app/src/main/kotlin/.../models/State.kt(SharedState 兜底值,通知标题极端场景)
    (
      pathJoin(
        pathJoin(pathJoin(_current, 'android', 'app', 'src', 'main'), 'kotlin', 'com', 'sororain', 'clash'),
        'models',
        'State.kt',
      ), [
        (
          'val currentProfileName: String = "$oldAppName"',
          'val currentProfileName: String = "$appName"',
        ),
      ]),
    // android/common/src/main/res/values/strings.xml(应用名资源化,集中定义)
    (
      pathJoin(pathJoin(pathJoin(_current, 'android', 'common', 'src', 'main'), 'res', 'values'), 'strings.xml'), [
        (
          '<string name="app_name">$oldAppName</string>',
          '<string name="app_name">$appName</string>',
        ),
        (
          '<string name="service_channel_name">$oldAppName Service</string>',
          '<string name="service_channel_name">$appName Service</string>',
        ),
      ]),
    // plugins/setup/{windows,linux}/CMakeLists.txt、macos/setup.podspec、buildkit/**
    // 已随 0.8.97 式迁移删除：core/helper 改由 plugins/setup/hook/build.dart
    // (Dart build hook) 构建，包名从 build_config.yaml 读取，平台文件里不再有字面量需要替换。
  ];

  // 生成功能开关文件
  await _generateFeatureFlags();

  // 改名进行中才有意义:未改名时规则自替换对全部跳过,[MISS] 只会是噪音
  final renaming = oldAppName != appName ||
      oldCoreName != coreName ||
      oldHelperName != helperName ||
      oldPackageName != packageName;

  for (final (filePath, pairs) in tasks) {
    final file = File(filePath);
    if (!await file.exists()) {
      print('  [SKIP] ${pathBasename(filePath)} (not found)');
      continue;
    }
    final original = await file.readAsString();
    var content = original;
    final missed = <String>[];
    for (final (oldStr, newStr) in pairs) {
      // 检测出的旧名 == 目标名时会产生自替换对，跳过避免无变化的“已修改”标记
      if (oldStr == newStr) continue;
      if (content.contains(oldStr)) {
        content = content.replaceAll(oldStr, newStr);
      } else {
        missed.add('"$oldStr"');
      }
    }
    // 零命中亮牌:可能是「引导规则已转换过」(无害)或「格式漂移」(危险),
    // 真伪由下方残留终检裁决,这里只提供可见性
    if (renaming && missed.isNotEmpty) {
      print('  [MISS] ${pathBasename(filePath)}: ${missed.join(' | ')}');
    }
    if (content != original) {
      await file.writeAsString(content);
      print('  [OK] ${pathBasename(filePath)}');
    } else {
      print('  [--] ${pathBasename(filePath)} (already up to date)');
    }
  }

  // 校验：回读关键文件，确认新名确实写入（上游合并改动格式时能立刻发现）
  final checks = <(String, List<String>)>[
    (pathJoin(_current, 'lib', 'common', 'constant.dart'), [appName, helperName]),
    (pathJoin(_current, 'lib', 'common', 'path.dart'), [coreName]),
    (pathJoin(_current, 'build_config.yaml'), [coreName, helperName]),
    (
      pathJoin(pathJoin(_current, 'services', 'helper', 'src', 'service'), 'windows.rs'),
      [helperName],
    ),
    (
      pathJoin(
        pathJoin(pathJoin(_current, 'android', 'app', 'src', 'main'), 'kotlin', 'com', 'sororain', 'clash'),
        'models',
        'State.kt',
      ),
      [appName],
    ),
    (
      pathJoin(pathJoin(pathJoin(_current, 'android', 'common', 'src', 'main'), 'res', 'values'), 'strings.xml'),
      [appName],
    ),
  ];
  final failures = <String>[];
  for (final (filePath, tokens) in checks) {
    final file = File(filePath);
    if (!await file.exists()) continue;
    final content = await file.readAsString();
    for (final token in tokens) {
      if (!content.contains(token)) {
        failures.add('${pathBasename(filePath)} 缺少 "$token"');
      }
    }
  }
  if (failures.isNotEmpty) {
    print('  [WARN] 以下文件可能未同步成功（上游合并改动了格式？请补充替换规则）：');
    for (final failure in failures) {
      print('    - $failure');
    }
  }

  // 残留终检(硬门):纯改名完成后,托管文件里不允许残留任何旧名的独立词。
  // 这里是真正的正确性闸门——零命中亮牌只是可见性,残留才代表改名没做完
  // (漏写规则/新增落点未纳入),带着残留打包会产出错误品牌。
  final residueFailures = <String>[];
  final namePairs = <(String, String)>[
    (oldAppName, appName),
    (oldCoreName, coreName),
    (oldHelperName, helperName),
    (oldPackageName, packageName),
    (oldAppNameLower, appName.toLowerCase()),
  ];
  for (final (filePath, _) in tasks) {
    final file = File(filePath);
    if (!await file.exists()) continue;
    final content = await file.readAsString();
    for (final (oldName, newName) in namePairs) {
      if (oldName.isEmpty || oldName == newName) continue;
      // 新名包含旧名时,替换产物必然含旧名子串,跳过该对避免误报
      if (newName.contains(oldName)) continue;
      for (final match
          in RegExp('\\b${RegExp.escape(oldName)}\\b').allMatches(content)) {
        final line = content.substring(0, match.start).split('\n').length;
        residueFailures.add('${pathBasename(filePath)}:$line "$oldName"');
      }
    }
  }
  if (residueFailures.isNotEmpty) {
    print('  [FAIL] 名称同步存在残留(独立词匹配)——有遗漏的替换规则或新增落点未纳入:');
    for (final failure in residueFailures.take(20)) {
      print('    - $failure');
    }
    throw StateError(
        '名称同步存在残留(${residueFailures.length} 处),中止以免打包出错误品牌');
  }

  // 记录本次写入的名字，供下次运行作为旧名来源
  await _saveNameState({
    'appName': appName,
    'coreName': coreName,
    'helperName': helperName,
    'packageName': packageName,
    'appId': appId,
  });
  print('=== Name sync complete ===');
}

Future<void> _generateFeatureFlags() async {
  final features = _features;
  final buffer = StringBuffer();
  buffer.writeln('// 由 setup.dart _syncNames() 自动生成，请勿手动修改');
  buffer.writeln('// 功能开关，控制 UI 控件的显隐\n');
  buffer.writeln('class FeatureFlags {');
  for (final entry in features.entries) {
    final key = entry.key;
    final value = entry.value;
    if (value is bool) {
      buffer.writeln('  /// $key\n  static const bool $key = $value;\n');
    }
  }
  buffer.writeln('}');
  final file = File(pathJoin(_current, 'lib', 'iqoo', 'config', 'feature_flags.dart'));
  await file.writeAsString(buffer.toString());
  print('  [GEN] lib/iqoo/config/feature_flags.dart');
}

enum Target { windows, linux, android, macos }

extension TargetExt on Target {
  String get os {
    if (this == Target.macos) {
      return 'darwin';
    }
    return name;
  }

  bool get same {
    if (this == Target.android) {
      return true;
    }
    if (Platform.isWindows && this == Target.windows) {
      return true;
    }
    if (Platform.isLinux && this == Target.linux) {
      return true;
    }
    if (Platform.isMacOS && this == Target.macos) {
      return true;
    }
    return false;
  }

  String get dynamicLibExtensionName {
    final String extensionName;
    switch (this) {
      case Target.android || Target.linux:
        extensionName = '.so';
        break;
      case Target.windows:
        extensionName = '.dll';
        break;
      case Target.macos:
        extensionName = '.dylib';
        break;
    }
    return extensionName;
  }

  String get executableExtensionName {
    final String extensionName;
    switch (this) {
      case Target.windows:
        extensionName = '.exe';
        break;
      default:
        extensionName = '';
        break;
    }
    return extensionName;
  }
}

enum Mode { core, lib }

enum Arch { amd64, arm64, arm }

class BuildItem {
  Target target;
  Arch? arch;
  String? archName;

  BuildItem({required this.target, this.arch, this.archName});

  @override
  String toString() {
    return 'BuildLibItem{target: $target, arch: $arch, archName: $archName}';
  }
}

class Build {
  static List<BuildItem> get buildItems => [
    BuildItem(target: Target.macos, arch: Arch.arm64),
    BuildItem(target: Target.macos, arch: Arch.amd64),
    BuildItem(target: Target.linux, arch: Arch.arm64),
    BuildItem(target: Target.linux, arch: Arch.amd64),
    BuildItem(target: Target.windows, arch: Arch.amd64),
    BuildItem(target: Target.windows, arch: Arch.arm64),
    BuildItem(target: Target.android, arch: Arch.arm, archName: 'armeabi-v7a'),
    BuildItem(target: Target.android, arch: Arch.arm64, archName: 'arm64-v8a'),
    BuildItem(target: Target.android, arch: Arch.amd64, archName: 'x86_64'),
  ];

  static String get appName => _appName;

  static String get coreName => _coreName;

  static String get libName => 'libclash';

  static String get outDir => pathJoin(_current, libName);

  static String get _coreDir => pathJoin(_current, 'core');

  static String get _servicesDir => pathJoin(_current, 'services', 'helper');

  static String get distPath => pathJoin(_current, 'dist');

  static String _getCc(BuildItem buildItem) {
    final environment = Platform.environment;
    if (buildItem.target == Target.android) {
      final ndk = environment['ANDROID_NDK'];
      assert(ndk != null);
      final prebuiltDir = Directory(
        pathJoin(ndk!, 'toolchains', 'llvm', 'prebuilt'),
      );
      final prebuiltDirList = prebuiltDir
          .listSync()
          .where((file) => !pathBasename(file.path).startsWith('.'))
          .toList();
      final map = {
        'armeabi-v7a': 'armv7a-linux-androideabi21-clang',
        'arm64-v8a': 'aarch64-linux-android21-clang',
        'x86': 'i686-linux-android21-clang',
        'x86_64': 'x86_64-linux-android21-clang',
      };
      return pathJoin(prebuiltDirList.first.path, 'bin', map[buildItem.archName]);
    }
    return 'gcc';
  }

  static String get tags => 'with_gvisor';

  static Future<void> exec(
    List<String> executable, {
    String? name,
    Map<String, String>? environment,
    String? workingDirectory,
    bool runInShell = true,
  }) async {
    if (name != null) print('run $name');
    print('exec: ${executable.join(' ')}');
    print('env: ${environment.toString()}');
    final process = await Process.start(
      executable[0],
      executable.sublist(1),
      environment: environment,
      workingDirectory: workingDirectory,
      runInShell: runInShell,
    );
    process.stdout.listen((data) {
      print(utf8.decode(data, allowMalformed: true));
    });
    process.stderr.listen((data) {
      print(utf8.decode(data, allowMalformed: true));
    });
    final exitCode = await process.exitCode;
    if (exitCode != 0 && name != null) throw '$name error';
  }

  static Future<String> calcSha256(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      stderr.writeln('File not exists: $filePath');
      exit(1);
    }
    if (Platform.isWindows) {
      final result = await Process.run('certutil', [
        '-hashfile',
        filePath,
        'SHA256',
      ]);
      return result.stdout.toString().split('\n').skip(1).first.trim();
    } else {
      final result = await Process.run('sha256sum', [filePath]);
      return result.stdout.toString().split(' ').first.trim();
    }
  }

  /// 过渡桥：用 plugins/setup 的构建器（0.8.97 的 hook 逻辑）构建 Core/Helper。
  ///
  /// 与 [buildCore] 的差别：参数取自 build_config.yaml、带指纹缓存、会在
  /// `libclash/<platform>/` 写 manifest.json，且 helper 一并构建（env 传 CORE_SHA256）。
  /// 返回值保持与 [buildCore] 同形态（产物路径列表），供上层算 SHA 写 env.json，
  /// 这样桌面端的编译期 `CORE_SHA256` 时序不变，现有运行路径零影响。
  static Future<List<String>> buildCoreWithHooks({
    required Target target,
    required Arch arch,
  }) async {
    final hooksTarget = setup_hooks.Target.resolve(
      platform: target.name,
      goarch: arch.name,
    );
    final report = await setup_hooks.buildPlatform(
      setup_hooks.BuildRequest(rootDir: _current, target: hooksTarget),
    );

    final corePath = pathJoin(
      outDir,
      target.name,
      '$_coreName${target.executableExtensionName}',
    );
    if (!File(corePath).existsSync()) {
      stderr.writeln(
        'Core not found after build hook: $corePath\n'
        'Outputs reported: ${report.outputs.join(', ')}',
      );
      exit(1);
    }
    return [corePath];
  }

  static Future<List<String>> buildCore({
    required Mode mode,
    required Target target,
    Arch? arch,
  }) async {
    final isLib = mode == Mode.lib;

    final items = buildItems.where((element) {
      return element.target == target &&
          (arch == null ? true : element.arch == arch);
    }).toList();

    final List<String> corePaths = [];

    final targetOutFilePath = pathJoin(outDir, target.name);
    final targetOutFile = File(targetOutFilePath);
    if (await targetOutFile.exists()) {
      await targetOutFile.delete(recursive: true);
      await Directory(targetOutFilePath).create(recursive: true);
    }
    for (final item in items) {
      final outFilePath = pathJoin(targetOutFilePath, item.archName ?? '');
      final file = File(outFilePath);
      if (file.existsSync()) {
        file.deleteSync(recursive: true);
      }

      final fileName = isLib
          ? '$libName${item.target.dynamicLibExtensionName}'
          : '$coreName${item.target.executableExtensionName}';
      final realOutPath = pathJoin(outFilePath, fileName);
      corePaths.add(realOutPath);

      final Map<String, String> env = {};
      env['GOOS'] = item.target.os;
      if (item.arch != null) {
        env['GOARCH'] = item.arch!.name;
      }
      if (isLib) {
        env['CGO_ENABLED'] = '1';
        env['CC'] = _getCc(item);
        env['CFLAGS'] = '-O3 -Werror';
      } else {
        env['CGO_ENABLED'] = '0';
      }
      final execLines = [
        'go',
        'build',
        '-ldflags=-w -s',
        '-tags=$tags',
        if (isLib) '-buildmode=c-shared',
        '-o',
        realOutPath,
      ];
      await exec(
        execLines,
        name: 'build core',
        environment: env,
        workingDirectory: _coreDir,
      );
      if (isLib && item.archName != null) {
        await adjustLibOut(
          targetOutFilePath: targetOutFilePath,
          outFilePath: outFilePath,
          archName: item.archName!,
        );
      }
    }

    return corePaths;
  }

  static Future<void> adjustLibOut({
    required String targetOutFilePath,
    required String outFilePath,
    required String archName,
  }) async {
    final includesPath = pathJoin(targetOutFilePath, 'includes');
    final realOutPath = pathJoin(includesPath, archName);
    await Directory(realOutPath).create(recursive: true);
    final targetOutFiles = Directory(outFilePath).listSync();
    final coreFiles = Directory(_coreDir).listSync();
    for (final file in [...targetOutFiles, ...coreFiles]) {
      if (!file.path.endsWith('.h')) {
        continue;
      }
      final targetFilePath = pathJoin(realOutPath, pathBasename(file.path));
      final realFile = File(file.path);
      await realFile.copy(targetFilePath);
      if (coreFiles.contains(file)) {
        continue;
      }
      await realFile.delete();
    }
  }

  static Future<void> buildHelper(Target target, String token) async {
    await exec(
      ['cargo', 'build', '--release', '--features', 'windows-service'],
      environment: {'TOKEN': token},
      name: 'build helper',
      workingDirectory: _servicesDir,
    );
    final outPath = pathJoin(
      _servicesDir,
      'target',
      'release',
      'helper${target.executableExtensionName}',
    );
    final targetPath = pathJoin(
      outDir,
      target.name,
      '$_helperName${target.executableExtensionName}',
    );
    await File(outPath).copy(targetPath);
  }

  static List<String> getExecutable(String command) {
    return command.split(' ');
  }

  /// flutter_distributor 不再随仓库分发（对齐上游 0.8.97）：从固定 git ref
  /// 全局激活一次，然后统一用 `dart pub global run` 调用，以免依赖 PATH
  /// 上是否存在 pub 的全局 bin 目录。
  static Future<void> getDistributor() async {
    await exec(
      name: 'activate flutter_distributor',
      Build.getExecutable(
        'dart pub global activate -s git '
        'https://github.com/chen08209/flutter_distributor.git '
        '--git-ref v0.6.11-flclash.2 '
        '--git-path packages/flutter_distributor',
      ),
    );
  }

  static void copyFile(String sourceFilePath, String destinationFilePath) {
    final sourceFile = File(sourceFilePath);
    if (!sourceFile.existsSync()) {
      stderr.writeln('Source file not exists: $sourceFilePath');
      exit(1);
    }
    final destinationFile = File(destinationFilePath);
    final destinationDirectory = destinationFile.parent;
    if (!destinationDirectory.existsSync()) {
      destinationDirectory.createSync(recursive: true);
    }
    try {
      sourceFile.copySync(destinationFilePath);
      print('File copied successfully!');
    } catch (e) {
      print('Failed to copy file: $e');
    }
  }
}

class BuildCommand {
  Target target;
  String? archArg;
  String? outArg;
  String? envArg;
  String? targetsArg;
  bool verbose;

  BuildCommand({
    required this.target,
    this.archArg,
    this.outArg,
    this.envArg,
    this.targetsArg,
    this.verbose = false,
  });

  String get name => target.name;

  List<Arch> get arches => Build.buildItems
      .where((element) => element.target == target && element.arch != null)
      .map((e) => e.arch!)
      .toList();

  Future<void> _buildEnvFile(String env, {String? coreSha256, String? androidArch}) async {
    final data = {
      'APP_ENV': env,
      'CORE_SHA256': ?coreSha256,
      'ANDROID_ARCH': ?androidArch,
    };
    final envFile = File(pathJoin(_current, 'env.json'))..create();
    await envFile.writeAsString(json.encode(data));
  }

  Future<void> _getLinuxDependencies(Arch arch) async {
    await Build.exec(Build.getExecutable('sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt update -y'));
    await Build.exec(
      Build.getExecutable('sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt install -y ninja-build libgtk-3-dev'),
    );
    await Build.exec(
      Build.getExecutable('sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt install -y libayatana-appindicator3-dev'),
    );
    await Build.exec(
      Build.getExecutable('sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get install -y libkeybinder-3.0-dev'),
    );
    await Build.exec(Build.getExecutable('sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt install -y locate'));
    if (arch == Arch.amd64) {
      await Build.exec(Build.getExecutable('sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt install -y rpm patchelf'));
      await Build.exec(Build.getExecutable('sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt install -y libfuse2'));

      final downloadName = arch == Arch.amd64 ? 'x86_64' : 'aarch64';
      await Build.exec(
        Build.getExecutable(
          'wget -O appimagetool https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-$downloadName.AppImage',
        ),
      );
      await Build.exec(Build.getExecutable('chmod +x appimagetool'));
      await Build.exec(
        Build.getExecutable('sudo mv appimagetool /usr/local/bin/'),
      );
    }
  }

  Future<void> _getMacosDependencies() async {
    final which = Platform.isWindows ? 'where' : 'command';
    final args = Platform.isWindows ? ['appdmg'] : ['-v', 'appdmg'];
    final result = await Process.run(which, args);
    if (result.exitCode == 0) {
      print('appdmg already installed, skipping.');
      return;
    }
    print('Installing appdmg (DMG creator)...');
    await Build.exec(Build.getExecutable('npm install -g appdmg'));
  }

  Future<void> _buildDistributor({
    required Target target,
    required String targets,
    String args = '',
    required String env,
  }) async {
    await Build.getDistributor();
    final allFlutterArgs = verbose ? 'verbose,dart-define-from-file=env.json' : 'dart-define-from-file=env.json';
    await Build.exec(
      name: name,
      Build.getExecutable(
        'dart pub global run flutter_distributor:main package --skip-clean --platform ${target.name} --targets $targets --flutter-build-args=$allFlutterArgs$args',
      ),
    );
  }

  Future<void> run() async {
    final mode = target == Target.android ? Mode.lib : Mode.core;
    final String out = outArg ?? (target.same ? 'app' : 'core');
    final env = envArg ?? 'pre';

    // 说明：0.8.93 时代的构建脚本(plugins/setup/buildkit/*.sh)已随 Dart build hook
    // 迁移删除，这里不再需要清除 macOS 隔离属性。

    // 自动检测架构（0.8.93 方式）
    String? archName = archArg;
    if (archName == null) {
      if (Platform.isWindows) {
        final pa = Platform.environment['PROCESSOR_ARCHITECTURE'] ?? 'AMD64';
        archName = pa.toUpperCase() == 'ARM64' ? 'arm64' : 'amd64';
      } else {
        final result = await Process.run('uname', ['-m']);
        final machine = (result.stdout as String).trim();
        archName = machine == 'aarch64' ? 'arm64' : machine == 'x86_64' ? 'amd64' : machine;
      }
      print('Auto-detected architecture: $archName');
    }

    // Android 且未指定 --arch 时构建所有 ABI
    final Arch? arch;
    if (target == Target.android && archArg == null) {
      print('Android: no --arch specified, will build all ABIs');
      arch = null;
    } else {
      final matchingArches = arches
          .where((element) => element.name == archName)
          .toList();
      arch = matchingArches.isEmpty ? null : matchingArches.first;
      if (arch == null) {
        stderr.writeln('Invalid arch parameter: $archName. Valid: ${arches.map((a) => a.name).join(', ')}');
        exit(1);
      }
    }

    // 过渡桥：桌面平台改用 setup_hooks 的构建器（指纹缓存 + manifest）；
    // Android 仍走内联 go build（lib 模式还需 NDK 工具链，留到 B 阶段）。
    final viaHooks = target != Target.android;
    final corePaths = viaHooks
        ? await Build.buildCoreWithHooks(target: target, arch: arch!)
        : await Build.buildCore(target: target, arch: arch, mode: mode);

    String? coreSha256;

    if (Platform.isWindows && target == Target.windows) {
      coreSha256 = await Build.calcSha256(corePaths.first);
      // 走 hook 时 helper 已由 hook 用同一个 SHA 构建，重复构建会引入第二个 SHA 源。
      if (!viaHooks) {
        await Build.buildHelper(target, coreSha256);
      }
    }
    await _buildEnvFile(env, coreSha256: coreSha256, androidArch: arch?.name);
    if (out != 'app') {
      return;
    }

    switch (target) {
      case Target.windows:
        _buildDistributor(
          target: target,
          targets: targetsArg ?? 'exe,zip',
          args: ' --description $archName',
          env: env,
        );
        return;
      case Target.linux:
        final targetMap = {Arch.arm64: 'linux-arm64', Arch.amd64: 'linux-x64'};
        final targets = [
          'deb',
          if (arch == Arch.amd64) 'appimage',
          if (arch == Arch.amd64) 'rpm',
        ].join(',');
        final defaultTarget = targetMap[arch];
        await _getLinuxDependencies(arch!);
        _buildDistributor(
          target: target,
          targets: targets,
          args:
              ' --description $archName --build-target-platform $defaultTarget',
          env: env,
        );
        return;
      case Target.android:
        final targetMap = {
          Arch.arm: 'arm',
          Arch.arm64: 'arm64',
          Arch.amd64: 'x64',
        };
        final archTarget = arch != null ? targetMap[arch] : null;
        await Build.exec(
          name: 'build flutter apk',
          Build.getExecutable(
            'flutter build apk --release${archTarget != null ? ' --target-platform android-$archTarget' : ''} --split-per-abi --dart-define-from-file=env.json',
          ),
        );
        return;
      case Target.macos:
        await _getMacosDependencies();
        _buildDistributor(
          target: target,
          targets: targetsArg ?? 'dmg',
          args: ' --description $archName',
          env: env,
        );
        return;
    }
  }
}

void _showHelp() {
  print('''Usage: dart setup.dart <target> [options]

Targets:
  android    Build Android APK
  linux      Build Linux deb/appimage/rpm
  windows    Build Windows exe/zip
  macos      Build macOS dmg

Options:
  --arch <arch>      Target architecture (arm64, amd64, arm). Default: auto-detect
  --out <type>       Output type: app (full package) or core (Go core only)
  --env <name>       Environment: pre (default) or stable
  --targets <list>   Comma-separated package targets (e.g. exe,zip). Default per platform
  --verbose, -v      Show verbose Flutter build output
  --help, -h         Show this help message

Examples:
  dart setup.dart windows
  dart setup.dart android --arch arm64
  dart setup.dart linux --out core
  dart setup.dart macos --targets dmg
  dart setup.dart windows --targets exe
''');
}

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _showHelp();
    return;
  }

  await _loadBuildConfig();
  await _syncNames();

  if (args.isEmpty) {
    _showHelp();
    return;
  }

  final targetName = args[0];
  final target = Target.values.firstWhere(
    (t) => t.name == targetName,
    orElse: () {
      stderr.writeln('Invalid target: $targetName. Valid: android, linux, windows, macos');
      exit(1);
    },
  );

  // 交叉编译验证：只能构建当前平台或 Android
  final hostOs = Platform.operatingSystem;
  final targetOs = target.name;
  if (targetOs != hostOs && targetOs != 'android') {
    stderr.writeln('Cannot build "$targetOs" on $hostOs. Only android can be cross-built.');
    exit(1);
  }

  String? archValue;
  String? outValue;
  String? envValue;
  String? targetsValue;
  bool verbose = false;

  for (var i = 1; i < args.length; i++) {
    switch (args[i]) {
      case '--arch':
        archValue = args[++i];
        break;
      case '--out':
        outValue = args[++i];
        break;
      case '--env':
        envValue = args[++i];
        break;
      case '--targets':
        targetsValue = args[++i];
        break;
      case '--verbose':
      case '-v':
        verbose = true;
        break;
    }
  }

  final command = BuildCommand(
    target: target,
    archArg: archValue,
    outArg: outValue,
    envArg: envValue,
    targetsArg: targetsValue,
    verbose: verbose,
  );
  await command.run();
}
