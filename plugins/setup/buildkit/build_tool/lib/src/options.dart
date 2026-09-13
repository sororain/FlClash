import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

final _log = Logger('options');

class BuildConfig {
  final String tags;
  final String goLdflags;
  final String coreDir;
  final String coreName;
  final String libName;
  final String outputDir;
  final String helperDir;
  final String helperName;
  final String distDir;

  const BuildConfig({
    required this.tags,
    required this.goLdflags,
    required this.coreDir,
    required this.coreName,
    required this.libName,
    required this.outputDir,
    required this.helperDir,
    required this.helperName,
    required this.distDir,
  });

  static const _defaults = BuildConfig(
    tags: 'with_gvisor',
    goLdflags: '-w -s',
    coreDir: 'core',
    coreName: 'SororainCore',
    libName: 'libclash',
    outputDir: 'libclash',
    helperDir: 'services/helper',
    helperName: 'SororainHelperService',
    distDir: 'dist',
  );

  static BuildConfig load({required String rootDir}) {
    final configPath = p.join(rootDir, 'build_config.yaml');
    final file = File(configPath);
    if (!file.existsSync()) {
      return _fromAppConfig(rootDir);
    }
    final yaml = loadYaml(file.readAsStringSync()) as YamlMap?;
    if (yaml == null) return _fromAppConfig(rootDir);
    return BuildConfig(
      tags: yaml['tags'] as String? ?? _defaults.tags,
      goLdflags: yaml['go_ldflags'] as String? ?? _defaults.goLdflags,
      coreDir: yaml['core_dir'] as String? ?? _defaults.coreDir,
      coreName: yaml['core_name'] as String? ?? _defaults.coreName,
      libName: yaml['lib_name'] as String? ?? _defaults.libName,
      outputDir: yaml['output_dir'] as String? ?? _defaults.outputDir,
      helperDir: yaml['helper_dir'] as String? ?? _defaults.helperDir,
      helperName: yaml['helper_name'] as String? ?? _defaults.helperName,
      distDir: yaml['dist_dir'] as String? ?? _defaults.distDir,
    );
  }

  static BuildConfig _fromAppConfig(String rootDir) {
    var coreName = _defaults.coreName;
    var helperName = _defaults.helperName;
    try {
      final appConfig = File(p.join(rootDir, 'app_config.json'));
      if (appConfig.existsSync()) {
        final value = jsonDecode(appConfig.readAsStringSync());
        if (value is Map) {
          final name = value['coreName'];
          if (name is String && name.isNotEmpty) coreName = name;
          final helper = value['helperName'];
          if (helper is String && helper.isNotEmpty) helperName = helper;
        }
      }
    } on Object {
      _log.fine('app_config.json unreadable, using default names');
    }
    return BuildConfig(
      tags: _defaults.tags,
      goLdflags: _defaults.goLdflags,
      coreDir: _defaults.coreDir,
      coreName: coreName,
      libName: _defaults.libName,
      outputDir: _defaults.outputDir,
      helperDir: _defaults.helperDir,
      helperName: helperName,
      distDir: _defaults.distDir,
    );
  }

  Map<String, String> toFingerprintMap() => {
        'tags': tags,
        'go_ldflags': goLdflags,
        'core_dir': coreDir,
        'core_name': coreName,
        'lib_name': libName,
        'output_dir': outputDir,
        'helper_dir': helperDir,
        'helper_name': helperName,
        'dist_dir': distDir,
      };
}
