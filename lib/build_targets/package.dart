// Copyright 2021 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:file/file.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/base/terminal.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/project.dart';

import '../tizen_builder.dart';
import '../tizen_project.dart';
import '../tizen_sdk.dart';
import '../tizen_tpk.dart';
import 'utils.dart';

class DotnetTpk {
  DotnetTpk(this.buildInfo);

  final TizenBuildInfo buildInfo;

  final ProcessUtils _processUtils = ProcessUtils(
      logger: globals.logger, processManager: globals.processManager);

  Future<void> build(Environment environment) async {
    final FlutterProject project =
        FlutterProject.fromDirectory(environment.projectDir);
    final TizenProject tizenProject = TizenProject.fromFlutter(project);

    // Clean up the intermediate and output directories.
    final Directory ephemeralDir = tizenProject.ephemeralDirectory;
    if (ephemeralDir.existsSync()) {
      ephemeralDir.deleteSync(recursive: true);
    }
    final Directory resDir = ephemeralDir.childDirectory('res')
      ..createSync(recursive: true);
    final Directory libDir = ephemeralDir.childDirectory('lib')
      ..createSync(recursive: true);

    final Directory outputDir = environment.outputDir.childDirectory('tpk');
    if (outputDir.existsSync()) {
      outputDir.deleteSync(recursive: true);
    }
    outputDir.createSync(recursive: true);

    // Copy necessary files.
    final Directory flutterAssetsDir = resDir.childDirectory('flutter_assets');
    copyDirectory(
      environment.outputDir.childDirectory('flutter_assets'),
      flutterAssetsDir,
    );

    final BuildMode buildMode = buildInfo.buildInfo.mode;
    final Directory engineDir =
        getEngineArtifactsDirectory(buildInfo.targetArch, buildMode);
    final Directory commonDir = engineDir.parent.childDirectory('tizen-common');

    final File engineBinary = engineDir.childFile('libflutter_engine.so');
    final File embedder =
        engineDir.childFile('libflutter_tizen_${buildInfo.deviceProfile}.so');
    final File icuData =
        commonDir.childDirectory('icu').childFile('icudtl.dat');

    engineBinary.copySync(libDir.childFile(engineBinary.basename).path);
    // The embedder so name is statically defined in C# code and cannot be
    // provided at runtime, so the file name must be a constant.
    embedder.copySync(libDir.childFile('libflutter_tizen.so').path);
    icuData.copySync(resDir.childFile(icuData.basename).path);

    if (buildMode.isPrecompiled) {
      final File aotSharedLib = environment.buildDir.childFile('app.so');
      aotSharedLib.copySync(libDir.childFile('libapp.so').path);
    }

    final Directory pluginsDir =
        environment.buildDir.childDirectory('tizen_plugins');
    final File pluginsLib = pluginsDir.childFile('libflutter_plugins.so');
    if (pluginsLib.existsSync()) {
      pluginsLib.copySync(libDir.childFile(pluginsLib.basename).path);
    }
    final Directory pluginsUserLibDir = pluginsDir.childDirectory('lib');
    if (pluginsUserLibDir.existsSync()) {
      pluginsUserLibDir.listSync().whereType<File>().forEach(
          (File lib) => lib.copySync(libDir.childFile(lib.basename).path));
    }

    // Run the .NET build.
    if (dotnetCli == null) {
      throwToolExit(
        'Unable to locate .NET CLI executable.\n'
        'Install the latest .NET SDK from: https://dotnet.microsoft.com/download',
      );
    }
    RunResult result = await _processUtils.run(<String>[
      dotnetCli.path,
      'build',
      '-c',
      if (buildMode.isPrecompiled) 'Release' else 'Debug',
      '-o',
      '${outputDir.path}/', // The trailing '/' is needed.
      tizenProject.editableDirectory.path,
    ]);
    if (result.exitCode != 0) {
      throwToolExit('Failed to build .NET application:\n$result');
    }

    final File outputTpk = outputDir.childFile(tizenProject.outputTpkName);
    if (!outputTpk.existsSync()) {
      throwToolExit(
          'Build succeeded but the expected TPK not found:\n${result.stdout}');
    }

    // build-task-tizen signs the output TPK with a dummy profile by default.
    // We need to re-generate the TPK by signing with a correct profile.
    String securityProfile = buildInfo.securityProfile;
    assert(tizenSdk != null);

    if (securityProfile != null) {
      if (tizenSdk.securityProfiles == null ||
          !tizenSdk.securityProfiles.contains(securityProfile)) {
        throwToolExit('The profile $securityProfile does not exist.');
      }
    }
    securityProfile ??= tizenSdk.securityProfiles?.active;

    if (securityProfile != null) {
      environment.logger
          .printStatus('The $securityProfile profile is used for signing.');
      result = await _processUtils.run(<String>[
        tizenSdk.tizenCli.path,
        'package',
        '-t',
        'tpk',
        '-s',
        securityProfile,
        '--',
        outputTpk.path,
      ]);
      if (result.exitCode != 0) {
        throwToolExit('Failed to sign the TPK:\n$result');
      }
    } else {
      environment.logger.printStatus(
        'The TPK was signed with a default certificate. You can create one using Certificate Manager.\n'
        'https://github.com/flutter-tizen/flutter-tizen/blob/master/doc/install-tizen-sdk.md#create-a-tizen-certificate',
        color: TerminalColor.yellow,
      );
    }
  }
}

class NativeTpk {
  NativeTpk(this.buildInfo);

  final TizenBuildInfo buildInfo;

  final ProcessUtils _processUtils = ProcessUtils(
      logger: globals.logger, processManager: globals.processManager);

  Future<void> build(Environment environment) async {
    final FlutterProject project =
        FlutterProject.fromDirectory(environment.projectDir);
    final TizenProject tizenProject = TizenProject.fromFlutter(project);

    // Clean up the intermediate and output directories.
    final Directory tizenDir = tizenProject.editableDirectory;
    final Directory resDir = tizenDir.childDirectory('res');
    if (resDir.existsSync()) {
      resDir.deleteSync(recursive: true);
    }
    resDir.createSync(recursive: true);
    final Directory libDir = tizenDir.childDirectory('lib');
    if (libDir.existsSync()) {
      libDir.deleteSync(recursive: true);
    }
    libDir.createSync(recursive: true);

    final Directory outputDir = environment.outputDir.childDirectory('tpk');
    if (outputDir.existsSync()) {
      outputDir.deleteSync(recursive: true);
    }
    outputDir.createSync(recursive: true);

    // Copy necessary files.
    final Directory flutterAssetsDir = resDir.childDirectory('flutter_assets');
    copyDirectory(
      environment.outputDir.childDirectory('flutter_assets'),
      flutterAssetsDir,
    );

    final BuildMode buildMode = buildInfo.buildInfo.mode;
    final Directory engineDir =
        getEngineArtifactsDirectory(buildInfo.targetArch, buildMode);
    final Directory commonDir = engineDir.parent.childDirectory('tizen-common');

    final File engineBinary = engineDir.childFile('libflutter_engine.so');
    final File embedder =
        engineDir.childFile('libflutter_tizen_${buildInfo.deviceProfile}.so');
    final File icuData =
        commonDir.childDirectory('icu').childFile('icudtl.dat');

    engineBinary.copySync(libDir.childFile(engineBinary.basename).path);
    embedder.copySync(libDir.childFile(embedder.basename).path);
    icuData.copySync(resDir.childFile(icuData.basename).path);

    if (buildMode.isPrecompiled) {
      final File aotSharedLib = environment.buildDir.childFile('app.so');
      aotSharedLib.copySync(libDir.childFile('libapp.so').path);
    }

    final Directory pluginsDir =
        environment.buildDir.childDirectory('tizen_plugins');
    final File pluginsLib = pluginsDir.childFile('libflutter_plugins.so');
    if (pluginsLib.existsSync()) {
      pluginsLib.copySync(libDir.childFile(pluginsLib.basename).path);
    }
    final Directory pluginsUserLibDir = pluginsDir.childDirectory('lib');
    if (pluginsUserLibDir.existsSync()) {
      pluginsUserLibDir.listSync().whereType<File>().forEach(
          (File lib) => lib.copySync(libDir.childFile(lib.basename).path));
    }

    // Prepare for build.
    final Directory clientWrapperDir =
        commonDir.childDirectory('cpp_client_wrapper');
    final Directory publicDir = commonDir.childDirectory('public');
    final Directory embeddingDir = environment.fileSystem
        .directory(Cache.flutterRoot)
        .parent
        .childDirectory('embedding')
        .childDirectory('cpp');

    assert(tizenSdk != null);
    final TizenManifest tizenManifest =
        TizenManifest.parseFromXml(tizenProject.manifestFile);
    final Rootstrap rootstrap = tizenSdk.getFlutterRootstrap(
      profile: tizenManifest.profile,
      apiVersion: tizenManifest.apiVersion,
      arch: buildInfo.targetArch,
    );

    final String buildConfig = buildMode.isPrecompiled ? 'Release' : 'Debug';
    final Directory buildDir = tizenDir.childDirectory(buildConfig);
    if (buildDir.existsSync()) {
      buildDir.deleteSync(recursive: true);
    }

    // We need to build the C++ embedding separately because the absolute path
    // to the embedding directory may contain spaces.
    RunResult result = await tizenSdk.buildNative(
      embeddingDir.path,
      configuration: buildConfig,
      arch: getTizenCliArch(buildInfo.targetArch),
      extraOptions: <String>['-fPIC'],
      rootstrap: rootstrap.id,
    );
    final File embeddingLib = embeddingDir
        .childDirectory(buildConfig)
        .childFile('libembedding_cpp.a');
    if (result.exitCode != 0) {
      throwToolExit('Failed to build ${embeddingLib.basename}:\n$result');
    }
    const List<String> embeddingDependencies = <String>[
      'appcore-agent',
      'capi-appfw-app-common',
      'capi-appfw-application',
      'dlog',
    ];

    // Build the app.
    result = await tizenSdk.buildNative(
      tizenDir.path,
      configuration: buildConfig,
      arch: getTizenCliArch(buildInfo.targetArch),
      predefines: <String>[
        '${buildInfo.deviceProfile.toUpperCase()}_PROFILE',
      ],
      extraOptions: <String>[
        '-Wl,--unresolved-symbols=ignore-in-shared-libs',
        '-lflutter_tizen_${buildInfo.deviceProfile}',
        '-L${libDir.path.toPosixPath()}',
        '-I${clientWrapperDir.childDirectory('include').path.toPosixPath()}',
        '-I${publicDir.path.toPosixPath()}',
        '-I${embeddingDir.childDirectory('include').path.toPosixPath()}',
        '-Wl,--whole-archive',
        embeddingLib.path.toPosixPath(),
        '-Wl,--no-whole-archive',
        for (String lib in embeddingDependencies) '-l$lib',
        '-I${pluginsDir.childDirectory('include').path.toPosixPath()}',
        if (pluginsLib.existsSync()) '-lflutter_plugins',
      ],
      rootstrap: rootstrap.id,
    );
    if (result.exitCode != 0) {
      throwToolExit('Failed to build native application:\n$result');
    }

    // The output TPK is signed with an active profile unless otherwise
    // specified.
    String securityProfile = buildInfo.securityProfile;
    if (securityProfile != null) {
      if (tizenSdk.securityProfiles == null ||
          !tizenSdk.securityProfiles.contains(securityProfile)) {
        throwToolExit('The profile $securityProfile does not exist.');
      }
    }
    securityProfile ??= tizenSdk.securityProfiles?.active;

    if (securityProfile != null) {
      environment.logger
          .printStatus('The $securityProfile profile is used for signing.');
    }
    result = await _processUtils.run(<String>[
      tizenSdk.tizenCli.path,
      'package',
      '-t',
      'tpk',
      if (securityProfile != null) ...<String>['-s', securityProfile],
      '--',
      buildDir.path,
    ]);
    if (result.exitCode != 0) {
      throwToolExit('Failed to generate TPK:\n$result');
    }
    if (securityProfile == null) {
      environment.logger.printStatus(
        'The TPK was signed with a default certificate. You can create one using Certificate Manager.\n'
        'https://github.com/flutter-tizen/flutter-tizen/blob/master/doc/install-tizen-sdk.md#create-a-tizen-certificate',
        color: TerminalColor.yellow,
      );
    }

    final String tpkArch = buildInfo.targetArch
        .replaceFirst('arm64', 'aarch64')
        .replaceFirst('x86', 'i586');
    final File outputTpk = buildDir.childFile(
        tizenProject.outputTpkName.replaceFirst('.tpk', '-$tpkArch.tpk'));
    if (!outputTpk.existsSync()) {
      throwToolExit(
          'Build succeeded but the expected TPK not found:\n${result.stdout}');
    }

    // Copy and rename the output TPK.
    outputTpk.copySync(outputDir.childFile(tizenProject.outputTpkName).path);

    // Extract the contents of the TPK to support code size analysis.
    final Directory tpkrootDir = outputDir.childDirectory('tpkroot');
    globals.os.unzip(outputTpk, tpkrootDir);

    // Manually copy files if unzipping failed.
    // Issue: https://github.com/flutter-tizen/flutter-tizen/issues/121
    if (!tpkrootDir.existsSync()) {
      final File runner = buildDir.childFile('runner');
      final Directory sharedDir = tizenDir.childDirectory('shared');
      final File tizenManifest = tizenProject.manifestFile;
      runner.copySync(
          tpkrootDir.childDirectory('bin').childFile(runner.basename).path);
      copyDirectory(libDir, tpkrootDir.childDirectory('lib'));
      copyDirectory(resDir, tpkrootDir.childDirectory('res'));
      copyDirectory(sharedDir, tpkrootDir.childDirectory('shared'));
      tizenManifest.copySync(tpkrootDir.childFile(tizenManifest.basename).path);
    }
  }
}
