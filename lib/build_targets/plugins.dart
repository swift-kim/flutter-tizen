// Copyright 2021 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:file/file.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/build_system/depfile.dart';
import 'package:flutter_tools/src/build_system/source.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/project.dart';

import '../tizen_builder.dart';
import '../tizen_plugins.dart';
import '../tizen_project.dart';
import '../tizen_sdk.dart';
import '../tizen_tpk.dart';
import 'utils.dart';

/// Compiles Tizen native plugins into a shared object.
class NativePlugins extends Target {
  NativePlugins(this.buildInfo);

  final TizenBuildInfo buildInfo;

  final ProcessUtils _processUtils = ProcessUtils(
      logger: globals.logger, processManager: globals.processManager);

  @override
  String get name => 'tizen_native_plugins';

  @override
  List<Source> get inputs => const <Source>[
        Source.pattern('{FLUTTER_ROOT}/../lib/tizen_build_target.dart'),
        Source.pattern('{PROJECT_DIR}/.packages'),
      ];

  @override
  List<Source> get outputs => const <Source>[];

  @override
  List<String> get depfiles => <String>[
        'tizen_plugins.d',
      ];

  @override
  List<Target> get dependencies => const <Target>[];

  @override
  Future<void> build(Environment environment) async {
    final List<File> inputs = <File>[];
    final List<File> outputs = <File>[];
    final DepfileService depfileService = DepfileService(
      fileSystem: environment.fileSystem,
      logger: environment.logger,
    );

    final FlutterProject project =
        FlutterProject.fromDirectory(environment.projectDir);
    final TizenProject tizenProject = TizenProject.fromFlutter(project);

    // Create a dummy project in the build directory.
    final Directory rootDir = environment.buildDir
        .childDirectory('tizen_plugins')
          ..createSync(recursive: true);
    final Directory includeDir = rootDir.childDirectory('include')
      ..createSync(recursive: true);
    final Directory libDir = rootDir.childDirectory('lib')
      ..createSync(recursive: true);
    final File projectDef = rootDir.childFile('project_def.prop');

    final TizenManifest tizenManifest =
        TizenManifest.parseFromXml(tizenProject.manifestFile);
    final String profile = tizenManifest.profile;
    final String apiVersion = tizenManifest.apiVersion;
    inputs.add(tizenProject.manifestFile);

    // Check if there's anything to build.
    final List<TizenPlugin> nativePlugins =
        await findTizenPlugins(project, nativeOnly: true);
    if (nativePlugins.isEmpty) {
      depfileService.writeToFile(
        Depfile(inputs, outputs),
        environment.buildDir.childFile('tizen_plugins.d'),
      );
      return;
    }

    // Prepare for build.
    final BuildMode buildMode = buildInfo.buildInfo.mode;
    final String buildConfig = buildMode.isPrecompiled ? 'Release' : 'Debug';
    final Directory engineDir =
        getEngineArtifactsDirectory(buildInfo.targetArch, buildMode);
    final File embedder =
        engineDir.childFile('libflutter_tizen_${buildInfo.deviceProfile}.so');
    inputs.add(embedder);

    final Directory commonDir = engineDir.parent.childDirectory('tizen-common');
    final Directory clientWrapperDir =
        commonDir.childDirectory('cpp_client_wrapper');
    final Directory publicDir = commonDir.childDirectory('public');
    clientWrapperDir
        .listSync(recursive: true)
        .whereType<File>()
        .forEach(inputs.add);
    publicDir.listSync(recursive: true).whereType<File>().forEach(inputs.add);

    assert(tizenSdk != null);
    final Rootstrap rootstrap = tizenSdk.getFlutterRootstrap(
      profile: profile,
      apiVersion: apiVersion,
      arch: buildInfo.targetArch,
    );

    final List<String> userLibs = <String>[];

    for (final TizenPlugin plugin in nativePlugins) {
      // TODO: Refine this.
      String projectDefContent = plugin.projectFile.readAsStringSync();
      projectDefContent = projectDefContent.replaceFirst(
          'type = sharedLib', 'type = staticLib');
      projectDefContent = projectDefContent.replaceFirst(
          'profile = common-5.5', 'profile = wearable-4.0');
      plugin.projectFile.writeAsStringSync(projectDefContent);

      final Map<String, String> variables = <String, String>{
        'PATH': getDefaultPathVariable(),
      };
      final List<String> extraOptions = <String>[
        '-I"${clientWrapperDir.childDirectory('include').path.toPosixPath()}"',
        '-I"${publicDir.path.toPosixPath()}"',
        '-D${buildInfo.deviceProfile.toUpperCase()}_PROFILE',
      ];

      // Run the native build.
      final RunResult result = await _processUtils.run(<String>[
        tizenSdk.tizenCli.path,
        'build-native',
        '-a',
        getTizenCliArch(buildInfo.targetArch),
        '-C',
        buildConfig,
        '-c',
        tizenSdk.defaultNativeCompiler,
        '-r',
        rootstrap.id,
        '-e',
        extraOptions.join(' '),
        '--',
        plugin.directory.path,
      ], environment: variables);
      if (result.exitCode != 0) {
        throwToolExit('Failed to build ${plugin.name} plugin:\n$result');
      }

      final String libName =
          plugin.fileName.replaceFirst('.h', '').toLowerCase();
      final File outputLib = plugin.directory
          .childDirectory(buildConfig)
          .childFile('lib$libName.a');
      if (!outputLib.existsSync()) {
        throwToolExit(
          'Build succeeded but the file ${outputLib.path} is not found:\n'
          '${result.stdout}',
        );
      }
      userLibs.add(libName);
      outputLib.copySync(libDir.childFile(outputLib.basename).path);

      inputs.add(plugin.projectFile);

      final Directory pluginIncludeDir = plugin.directory.childDirectory('inc');
      if (pluginIncludeDir.existsSync()) {
        pluginIncludeDir
            .listSync(recursive: true)
            .whereType<File>()
            .forEach(inputs.add);
      }
      final Directory pluginSourceDir = plugin.directory.childDirectory('src');
      if (pluginSourceDir.existsSync()) {
        pluginSourceDir
            .listSync(recursive: true)
            .whereType<File>()
            .forEach(inputs.add);
      }
      final Directory pluginLibDir = plugin.directory
          .childDirectory('lib')
          .childDirectory(getTizenBuildArch(buildInfo.targetArch));
      if (pluginLibDir.existsSync()) {
        pluginLibDir
            .listSync()
            .whereType<File>()
            .where((File f) => f.basename.endsWith('.so'))
            .forEach((File file) {
          inputs.add(file);
          file.copySync(libDir.childFile(file.basename).path);
          outputs.add(libDir.childFile(file.basename));
          // TODO: Refine this.
          // Do not read from USER_LIBS; cannot distinguish between static libs and shared libs.
          userLibs.add(
              file.basename.replaceFirst('lib', '').replaceFirst('.so', ''));
        });
      }

      // The plugin header is used when building native apps.
      final File header = pluginIncludeDir.childFile(plugin.fileName);
      header.copySync(includeDir.childFile(header.basename).path);
      outputs.add(includeDir.childFile(header.basename));
    }

    projectDef.writeAsStringSync('''
APPNAME = flutter_plugins
type = sharedLib
profile = $profile-$apiVersion

USER_SRCS = ${clientWrapperDir.childFile('*.cc').path}

USER_CPP_DEFS = TIZEN_DEPRECATION DEPRECATION_WARNING FLUTTER_PLUGIN_IMPL
USER_CPPFLAGS_MISC = -c -fmessage-length=0
USER_LFLAGS = -Wl,-rpath='\$\$ORIGIN'

USER_LIBS = ${userLibs.join(' ')}
''');

    final Map<String, String> variables = <String, String>{
      'PATH': getDefaultPathVariable(),
    };
    final List<String> extraOptions = <String>[
      '-lflutter_tizen_${buildInfo.deviceProfile}',
      '-L"${engineDir.path.toPosixPath()}"',
      '-fvisibility=hidden',
      '-I"${clientWrapperDir.childDirectory('include').path.toPosixPath()}"',
      '-I"${publicDir.path.toPosixPath()}"',
      // TODO: If we want to move this to project_def (USER_LIB_DIRS), we need to move the files to tempDir/lib.
      '-L"${libDir.path.toPosixPath()}"',
      '-D${buildInfo.deviceProfile.toUpperCase()}_PROFILE',
    ];

    // TODO: Is this still required? Replace '0' with something else.
    // Create a temp directory to use as a build directory.
    // This is a workaround for the long path issue on Windows:
    // https://github.com/flutter-tizen/flutter-tizen/issues/122
    final Directory tempDir = environment.fileSystem.systemTempDirectory
        .childDirectory('0')
          ..createSync(recursive: true);
    projectDef.copySync(tempDir.childFile(projectDef.basename).path);

    // Run the native build.
    final RunResult result = await _processUtils.run(<String>[
      tizenSdk.tizenCli.path,
      'build-native',
      '-a',
      getTizenCliArch(buildInfo.targetArch),
      '-C',
      buildConfig,
      '-c',
      tizenSdk.defaultNativeCompiler,
      '-r',
      rootstrap.id,
      '-e',
      extraOptions.join(' '),
      '--',
      tempDir.path,
    ], environment: variables);
    if (result.exitCode != 0) {
      throwToolExit('Failed to build Flutter plugins:\n$result');
    }

    final File outputLib =
        tempDir.childDirectory(buildConfig).childFile('libflutter_plugins.so');
    if (!outputLib.existsSync()) {
      throwToolExit(
        'Build succeeded but the file ${outputLib.path} is not found:\n'
        '${result.stdout}',
      );
    }

    final File outputLibCopy =
        outputLib.copySync(rootDir.childFile(outputLib.basename).path);
    outputs.add(outputLibCopy);

    // TODO: Is it right to do this here?
    for (final File staticLib in libDir
        .listSync()
        .whereType<File>()
        .where((File f) => f.basename.endsWith('.a'))) {
      staticLib.deleteSync();
    }

    depfileService.writeToFile(
      Depfile(inputs, outputs),
      environment.buildDir.childFile('tizen_plugins.d'),
    );
  }
}
