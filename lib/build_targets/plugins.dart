// Copyright 2021 Samsung Electronics Co., Ltd. All rights reserved.
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:package_config/package_config.dart';

import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/build_system/targets/common.dart';
import 'package:flutter_tools/src/dart/package_map.dart';
import 'package:flutter_tools/src/project.dart';

import '../../tizen_plugins.dart';

/// Source: [DartPluginRegistrantTarget] in `dart_plugin_registrant.dart`
class DartPluginRegistrant extends Target {
  const DartPluginRegistrant();

  @override
  String get name => 'tizen_dart_plugin_registrant';

  @override
  List<Source> get inputs => <Source>[
        const Source.pattern('{PROJECT_DIR}/.dart_tool/package_config_subset'),
      ];

  @override
  List<Source> get outputs => <Source>[
        const Source.pattern(
          '{PROJECT_DIR}/.dart_tool/flutter_build/generated_main.dart',
          optional: true,
        ),
      ];

  @override
  List<Target> get dependencies => <Target>[];

  @override
  Future<void> build(Environment environment) async {
    // TODO: assert(environment.generateDartPluginRegistry);
    final FlutterProject project =
        FlutterProject.fromDirectory(environment.projectDir);
    final List<TizenPlugin> dartPlugins =
        await findTizenPlugins(project, dartOnly: true);
    if (dartPlugins.isEmpty) {
      return;
    }

    final File packagesFile = environment.projectDir
        .childDirectory('.dart_tool')
        .childFile('package_config.json');
    final PackageConfig packageConfig = await loadPackageConfigWithLogging(
      packagesFile,
      logger: environment.logger,
    );
    final String targetFile = environment.defines[kTargetFile] ??
        environment.fileSystem.path.join('lib', 'main.dart');
    final File mainFile = environment.fileSystem.file(targetFile);
    final Uri mainFileUri = mainFile.absolute.uri;
    final Uri mainUri = packageConfig.toPackageUri(mainFileUri) ?? mainFileUri;
    final File newMainDart = environment.projectDir
        .childDirectory('.dart_tool')
        .childDirectory('flutter_build')
        .childFile('generated_main.dart');
    createMainDartWithPluginRegistrant(
      dartPlugins,
      packageConfig,
      mainUri.toString(),
      newMainDart,
      mainFile,
    );
  }

  @override
  bool canSkip(Environment environment) {
    // TODO: return !environment.generateDartPluginRegistry;
    return false;
  }
}
