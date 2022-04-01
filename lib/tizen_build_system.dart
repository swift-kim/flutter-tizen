// Copyright 2022 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/file.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/build_system/targets/dart_plugin_registrant.dart';
import 'package:flutter_tools/src/dart/package_map.dart';
import 'package:flutter_tools/src/flutter_plugins.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:package_config/package_config.dart';

class TizenBuildSystem extends FlutterBuildSystem {
  TizenBuildSystem({
    required FileSystem fileSystem,
    required Platform platform,
    required Logger logger,
  }) : super(fileSystem: fileSystem, platform: platform, logger: logger);

  @override
  Future<BuildResult> build(
    Target target,
    Environment environment, {
    BuildSystemConfig buildSystemConfig = const BuildSystemConfig(),
  }) {
    return super.build(
      CompositeTarget(<Target>[target, _DartPluginRegistrantTarget()]),
      environment,
      buildSystemConfig: buildSystemConfig,
    );
  }

  @override
  Future<BuildResult> buildIncremental(
    Target target,
    Environment environment,
    BuildResult? previousBuild,
  ) {
    return super.buildIncremental(
      CompositeTarget(<Target>[target, _DartPluginRegistrantTarget()]),
      environment,
      previousBuild,
    );
  }
}

/// Generates a new `./dart_tool/flutter_build/generated_main.dart`
/// based on the current dependency map in `pubspec.lock`.
class _DartPluginRegistrantTarget extends DartPluginRegistrantTarget {
  @override
  String get name => 'tizen_gen_dart_plugin_registrant';

  @override
  List<Source> get inputs => outputs; // NO!! include this file?

  @override
  bool canSkip(Environment environment) {
    if (!environment.generateDartPluginRegistry) {
      return true;
    }
    final String? platformName = environment.defines[kTargetPlatform];
    return platformName == null || !platformName.startsWith('android');
  }

  @override
  Future<void> build(Environment environment) async {
    final FlutterProject project =
        FlutterProject.fromDirectory(environment.projectDir);
    final PackageConfig packageConfig = await loadPackageConfigWithLogging(
      project.packageConfigFile,
      logger: environment.logger,
    );
    final String targetFilePath = environment.defines[kTargetFile] ??
        environment.fileSystem.path.join('lib', 'main.dart');
    final File mainFile = environment.fileSystem.file(targetFilePath);
    final Uri mainFileUri = mainFile.absolute.uri;
    final String mainFileUriString =
        packageConfig.toPackageUri(mainFileUri)?.toString() ??
            mainFileUri.toString();

    final File newMainDart = project.dartPluginRegistrant;
    newMainDart.writeAsStringSync('');

    // await generateMainDartWithPluginRegistrant(
    //   project,
    //   packageConfig,
    //   mainFileUriString,
    //   mainFile,
    // );
  }
}
