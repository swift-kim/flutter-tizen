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

    // Create a dummy project in the build directory.
    final Directory rootDir = environment.buildDir
        .childDirectory('tizen_plugins')
          ..createSync(recursive: true);
    final Directory includeDir = rootDir.childDirectory('include')
      ..createSync(recursive: true);
    final Directory libDir = rootDir.childDirectory('lib')
      ..createSync(recursive: true);

    final BuildMode buildMode = buildInfo.buildInfo.mode;
    final String buildConfig = buildMode.isPrecompiled ? 'Release' : 'Debug';
    final Directory engineDir =
        getEngineArtifactsDirectory(buildInfo.targetArch, buildMode);
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
    final TizenManifest tizenManifest =
        TizenManifest.parseFromXml(tizenProject.manifestFile);
    final String profile = tizenManifest.profile;
    final String apiVersion = tizenManifest.apiVersion;
    final Rootstrap rootstrap = tizenSdk.getFlutterRootstrap(
      profile: profile,
      apiVersion: apiVersion,
      arch: buildInfo.targetArch,
    );
    inputs.add(tizenProject.manifestFile);

    final List<String> userLibs = <String>[];
    final List<String> pluginClasses = <String>[];

    for (final TizenPlugin plugin in nativePlugins) {
      // Create a copy of the plugin to allow editing its projectFile.
      final TizenPlugin pluginCopy = plugin.copyWith(
        directory: environment.fileSystem.systemTempDirectory.createTempSync(),
      );
      copyDirectory(plugin.directory, pluginCopy.directory);

      final List<String> properties = <String>[];
      for (String line in plugin.projectFile.readAsLinesSync()) {
        if (line.startsWith('type =')) {
          line = 'type = staticLib';
        }
        properties.add(line);
      }
      pluginCopy.projectFile.writeAsStringSync(properties.join('\n'));
      inputs.add(plugin.projectFile);

      final Map<String, String> variables = <String, String>{
        'PATH': getDefaultPathVariable(),
      };
      final List<String> extraOptions = <String>[
        '-fPIC',
        '-I"${clientWrapperDir.childDirectory('include').path.toPosixPath()}"',
        '-I"${publicDir.path.toPosixPath()}"',
        '-D${buildInfo.deviceProfile.toUpperCase()}_PROFILE',
      ];

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
        pluginCopy.directory.path,
      ], environment: variables);
      if (result.exitCode != 0) {
        throwToolExit('Failed to build ${plugin.name} plugin:\n$result');
      }

      final String libName =
          getLibNameForFileName(plugin.fileName.toLowerCase());
      final File libFile = pluginCopy.directory
          .childDirectory(buildConfig)
          .childFile('lib$libName.a');
      if (!libFile.existsSync()) {
        throwToolExit(
          'Build succeeded but the file ${libFile.path} is not found:\n'
          '${result.stdout}',
        );
      }
      libFile.copySync(libDir.childFile(libFile.basename).path);
      userLibs.add(libName);
      pluginClasses.add(plugin.pluginClass);

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

      // Copy user libs for later linking.
      final Directory pluginLibDir = plugin.directory.childDirectory('lib');
      final List<Directory> pluginLibDirs = <Directory>[
        pluginLibDir.childDirectory(buildInfo.targetArch),
        pluginLibDir.childDirectory(getTizenBuildArch(buildInfo.targetArch)),
        pluginLibDir,
      ];
      for (final Directory directory
          in pluginLibDirs.where((Directory d) => d.existsSync())) {
        for (final File lib in directory.listSync().whereType<File>()) {
          if (lib.basename.endsWith('.so') || lib.basename.endsWith('.a')) {
            final String libName = getLibNameForFileName(lib.basename);
            if (userLibs.contains(libName)) {
              continue;
            }
            lib.copySync(libDir.childFile(lib.basename).path);
            userLibs.add(getLibNameForFileName(lib.basename));

            inputs.add(lib);
            outputs.add(libDir.childFile(lib.basename));
          }
        }
      }

      // The plugin header is used by the native app builder.
      final File header = pluginIncludeDir.childFile(plugin.fileName);
      header.copySync(includeDir.childFile(header.basename).path);
      outputs.add(includeDir.childFile(header.basename));
    }

    final File projectDef = rootDir.childFile('project_def.prop');
    projectDef.writeAsStringSync('''
APPNAME = flutter_plugins
type = sharedLib
profile = $profile-$apiVersion

USER_SRCS = ${clientWrapperDir.childFile('*.cc').path}
USER_LFLAGS = -Wl,-rpath='\$\$ORIGIN'
USER_LIBS = ${userLibs.join(' ')}
''');

    final File embedder =
        engineDir.childFile('libflutter_tizen_${buildInfo.deviceProfile}.so');
    inputs.add(embedder);

    final Map<String, String> variables = <String, String>{
      'PATH': getDefaultPathVariable(),
    };
    final List<String> extraOptions = <String>[
      '-l${getLibNameForFileName(embedder.basename)}',
      '-L"${engineDir.path.toPosixPath()}"',
      '-I"${clientWrapperDir.childDirectory('include').path.toPosixPath()}"',
      '-I"${publicDir.path.toPosixPath()}"',
      '-L"${libDir.path.toPosixPath()}"',
      // Forces plugin entrypoints to be exported, because unreferenced
      // objects are not included in the output shared object by default.
      // Another option is to use the -Wl,--[no-]whole-archive flag with
      // -Wl,-unresolved-symbols=ignore-in-object-files.
      for (String className in pluginClasses)
        '-Wl,--undefined=${className}RegisterWithRegistrar',
    ];

    // Create a temp directory to use as a build directory.
    // This is a workaround for the long path issue on Windows:
    // https://github.com/flutter-tizen/flutter-tizen/issues/122
    final Directory tempDir =
        environment.fileSystem.systemTempDirectory.createTempSync();
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
      throwToolExit('Failed to build native plugins:\n$result');
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

    // Remove intermediate files.
    for (final File lib in libDir
        .listSync()
        .whereType<File>()
        .where((File f) => f.basename.endsWith('.a'))) {
      lib.deleteSync();
    }

    depfileService.writeToFile(
      Depfile(inputs, outputs),
      environment.buildDir.childFile('tizen_plugins.d'),
    );
  }
}
