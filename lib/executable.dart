// Copyright 2020 Samsung Electronics Co., Ltd. All rights reserved.
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'dart:io';

import 'package:flutter_tools/executable.dart' as flutter;
import 'package:flutter_tools/runner.dart' as runner;
import 'package:flutter_tools/src/application_package.dart';
import 'package:flutter_tools/src/base/context.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/template.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/commands/config.dart';
import 'package:flutter_tools/src/commands/devices.dart';
import 'package:flutter_tools/src/commands/emulators.dart';
import 'package:flutter_tools/src/commands/doctor.dart';
import 'package:flutter_tools/src/commands/format.dart';
import 'package:flutter_tools/src/commands/generate_localizations.dart';
import 'package:flutter_tools/src/commands/install.dart';
import 'package:flutter_tools/src/commands/logs.dart';
import 'package:flutter_tools/src/commands/screenshot.dart';
import 'package:flutter_tools/src/commands/symbolize.dart';
import 'package:flutter_tools/src/emulator.dart';
import 'package:flutter_tools/src/device.dart';
import 'package:flutter_tools/src/doctor.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/isolated/mustache_template.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:flutter_tools/src/version.dart';
import 'package:path/path.dart';

import 'commands/analyze.dart';
import 'commands/attach.dart';
import 'commands/build.dart';
import 'commands/clean.dart';
import 'commands/create.dart';
import 'commands/drive.dart';
import 'commands/packages.dart';
import 'commands/run.dart';
import 'commands/test.dart';
import 'tizen_artifacts.dart';
import 'tizen_device_discovery.dart';
import 'tizen_doctor.dart';
import 'tizen_emulator.dart';
import 'tizen_sdk.dart';
import 'tizen_tpk.dart';

/// Main entry point for commands.
///
/// Source: [flutter.main] in `executable.dart` (some commands and options were omitted)
Future<void> main(List<String> args) async {
  final bool veryVerbose = args.contains('-vv');
  final bool verbose =
      args.contains('-v') || args.contains('--verbose') || veryVerbose;

  final bool doctor = (args.isNotEmpty && args.first == 'doctor') ||
      (args.length == 2 && verbose && args.last == 'doctor');
  final bool help = args.contains('-h') ||
      args.contains('--help') ||
      (args.isNotEmpty && args.first == 'help') ||
      (args.length == 1 && verbose);
  final bool muteCommandLogging = (help || doctor) && !veryVerbose;
  final bool verboseHelp = help && verbose;

  final bool hasSpecifiedDeviceId =
      args.contains('-d') || args.contains('--device-id');

  args = <String>[
    '--suppress-analytics', // Suppress flutter analytics by default.
    '--no-version-check',
    if (!hasSpecifiedDeviceId) ...<String>['--device-id', 'tizen'],
    ...args,
  ];

  Cache.flutterRoot = join(_rootPath, 'flutter');

  await runner.run(
    args,
    () => <FlutterCommand>[
      // Commands directly from flutter_tools.
      ConfigCommand(verboseHelp: verboseHelp),
      DevicesCommand(verboseHelp: verboseHelp),
      DoctorCommand(verbose: verbose),
      EmulatorsCommand(),
      FormatCommand(),
      GenerateLocalizationsCommand(
        fileSystem: globals.fs,
        logger: globals.logger,
      ),
      InstallCommand(),
      LogsCommand(),
      ScreenshotCommand(),
      SymbolizeCommand(stdio: globals.stdio, fileSystem: globals.fs),
      // Commands extended for Tizen.
      TizenAnalyzeCommand(verboseHelp: verboseHelp),
      TizenAttachCommand(verboseHelp: verboseHelp),
      TizenBuildCommand(verboseHelp: verboseHelp),
      TizenCleanCommand(verbose: verbose),
      TizenCreateCommand(verboseHelp: verboseHelp),
      TizenDriveCommand(verboseHelp: verboseHelp),
      TizenPackagesCommand(),
      TizenRunCommand(verboseHelp: verboseHelp),
      TizenTestCommand(verboseHelp: verboseHelp),
    ],
    verbose: verbose,
    verboseHelp: verboseHelp,
    muteCommandLogging: muteCommandLogging,
    reportCrashes: false,
    overrides: <Type, Generator>{
      TemplateRenderer: () => const MustacheTemplateRenderer(),
      ApplicationPackageFactory: () => TizenApplicationPackageFactory(),
      DeviceManager: () => TizenDeviceManager(),
      DoctorValidatorsProvider: () => TizenDoctorValidatorsProvider(),
      TizenSdk: () => TizenSdk.locateSdk(),
      TizenArtifacts: () => TizenArtifacts(),
      TizenWorkflow: () => TizenWorkflow(
            tizenSdk: tizenSdk,
            operatingSystemUtils: globals.os,
          ),
      TizenValidator: () => TizenValidator(),
      EmulatorManager: () => TizenEmulatorManager(
            tizenSdk: tizenSdk,
            tizenWorkflow: tizenWorkflow,
            processManager: globals.processManager,
            logger: globals.logger,
            fileSystem: globals.fs,
          ),
      FlutterVersion: () => _FlutterVersion(),
      if (verbose && !muteCommandLogging)
        Logger: () => VerboseLogger(StdoutLogger(
              stdio: globals.stdio,
              terminal: globals.terminal,
              outputPreferences: globals.outputPreferences,
              stopwatchFactory: const StopwatchFactory(),
            )),
    },
  );
}

/// See: [Cache.defaultFlutterRoot] in `cache.dart`
String get _rootPath {
  final String scriptPath = Platform.script.toFilePath();
  return normalize(join(
    scriptPath,
    scriptPath.endsWith('.snapshot') ? '../../..' : '../..',
  ));
}

class _FlutterVersion extends FlutterVersion {
  _FlutterVersion();

  @override
  String get frameworkVersion => '${super.frameworkVersion} for Tizen';

  @override
  String get frameworkRevision =>
      _runGit('git -c log.showSignature=false log -n 1 --pretty=format:%H');

  @override
  String get frameworkAge =>
      _runGit('git -c log.showSignature=false log -n 1 --pretty=format:%ar');

  /// See: [Cache.getVersionFor] in `cache.dart`
  String getVersionFor(String artifactName) {
    final File versionFile = globals.fs
        .directory(_rootPath)
        .childDirectory('bin')
        .childDirectory('internal')
        .childFile('$artifactName.version');
    return versionFile.existsSync()
        ? versionFile.readAsStringSync().trim()
        : null;
  }

  @override
  String get engineRevision => getVersionFor('engine');

  String _repositoryUrl;

  /// See: [FlutterVersion.channel] in `version.dart`
  @override
  String get repositoryUrl {
    final String channel =
        _runGit('git rev-parse --abbrev-ref --symbolic @{u}');
    final int slash = channel.indexOf('/');
    if (slash != -1) {
      final String remote = channel.substring(0, slash);
      _repositoryUrl = _runGit('git ls-remote --get-url $remote');
    }
    return _repositoryUrl;
  }

  /// See: [_runGit] in `version.dart`
  String _runGit(String command) => globals.processUtils
      .runSync(command.split(' '), workingDirectory: _rootPath)
      .stdout
      .trim();
}
