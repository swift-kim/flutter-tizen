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
import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/template.dart';
import 'package:flutter_tools/src/base/terminal.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/commands/config.dart';
import 'package:flutter_tools/src/commands/daemon.dart';
import 'package:flutter_tools/src/commands/devices.dart';
import 'package:flutter_tools/src/commands/doctor.dart';
import 'package:flutter_tools/src/commands/emulators.dart';
import 'package:flutter_tools/src/commands/format.dart';
import 'package:flutter_tools/src/commands/generate_localizations.dart';
import 'package:flutter_tools/src/commands/install.dart';
import 'package:flutter_tools/src/commands/logs.dart';
import 'package:flutter_tools/src/commands/packages.dart';
import 'package:flutter_tools/src/commands/screenshot.dart';
import 'package:flutter_tools/src/commands/symbolize.dart';
import 'package:flutter_tools/src/dart/pub.dart';
import 'package:flutter_tools/src/device.dart';
import 'package:flutter_tools/src/doctor.dart';
import 'package:flutter_tools/src/emulator.dart';
import 'package:flutter_tools/src/features.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/isolated/mustache_template.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart';

import 'commands/analyze.dart';
import 'commands/attach.dart';
import 'commands/build.dart';
import 'commands/clean.dart';
import 'commands/create.dart';
import 'commands/drive.dart';
import 'commands/precache.dart';
import 'commands/run.dart';
import 'commands/test.dart';
import 'tizen_cache.dart';
import 'tizen_device_discovery.dart';
import 'tizen_doctor.dart';
import 'tizen_emulator.dart';
import 'tizen_pub.dart';
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
  final bool daemon = args.contains('daemon');
  final bool runMachine =
      (args.contains('--machine') && args.contains('run')) ||
          (args.contains('--machine') && args.contains('attach'));

  final bool hasSpecifiedDeviceId =
      args.contains('-d') || args.contains('--device-id');

  args = <String>[
    '--suppress-analytics', // Suppress flutter analytics by default.
    '--no-version-check',
    if (!hasSpecifiedDeviceId) ...<String>['--device-id', 'tizen'],
    ...args,
  ];

  Cache.flutterRoot = join(rootPath, 'flutter');

  await runner.run(
    args,
    () => <FlutterCommand>[
      // Commands directly from flutter_tools.
      ConfigCommand(verboseHelp: verboseHelp),
      DaemonCommand(hidden: !verboseHelp),
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
      PackagesCommand(),
      ScreenshotCommand(),
      SymbolizeCommand(stdio: globals.stdio, fileSystem: globals.fs),
      // Commands extended for Tizen.
      TizenAnalyzeCommand(
        verboseHelp: verboseHelp,
        fileSystem: globals.fs,
        platform: globals.platform,
        processManager: globals.processManager,
        logger: globals.logger,
        terminal: globals.terminal,
        artifacts: globals.artifacts,
      ),
      TizenAttachCommand(verboseHelp: verboseHelp),
      TizenBuildCommand(verboseHelp: verboseHelp),
      TizenCleanCommand(verbose: verbose),
      TizenCreateCommand(verboseHelp: verboseHelp),
      TizenDriveCommand(
        verboseHelp: verboseHelp,
        fileSystem: globals.fs,
        logger: globals.logger,
        platform: globals.platform,
      ),
      TizenPrecacheCommand(
        verboseHelp: verboseHelp,
        cache: globals.cache,
        logger: globals.logger,
        platform: globals.platform,
        featureFlags: featureFlags,
      ),
      TizenRunCommand(verboseHelp: verboseHelp),
      TizenTestCommand(
        verboseHelp: verboseHelp,
        testWrapper: TizenTestWrapper(),
      ),
    ],
    verbose: verbose,
    verboseHelp: verboseHelp,
    muteCommandLogging: muteCommandLogging,
    reportCrashes: false,
    overrides: <Type, Generator>{
      ApplicationPackageFactory: () => TizenApplicationPackageFactory(
            androidSdk: globals.androidSdk,
            processManager: globals.processManager,
            logger: globals.logger,
            userMessages: globals.userMessages,
            fileSystem: globals.fs,
          ),
      Cache: () => TizenFlutterCache(
            fileSystem: globals.fs,
            logger: globals.logger,
            platform: globals.platform,
            osUtils: globals.os,
          ),
      DeviceManager: () => TizenDeviceManager(
            fileSystem: globals.fs,
            logger: globals.logger,
            platform: globals.platform,
            processManager: globals.processManager,
          ),
      DoctorValidatorsProvider: () => TizenDoctorValidatorsProvider(),
      EmulatorManager: () => TizenEmulatorManager(
            tizenSdk: tizenSdk,
            tizenWorkflow: tizenWorkflow,
            processManager: globals.processManager,
            logger: globals.logger,
            fileSystem: globals.fs,
          ),
      TemplateRenderer: () => const MustacheTemplateRenderer(),
      TizenSdk: () => TizenSdk.locateSdk(),
      TizenValidator: () => TizenValidator(
            logger: globals.logger,
            processManager: globals.processManager,
          ),
      TizenWorkflow: () => TizenWorkflow(
            tizenSdk: tizenSdk,
            operatingSystemUtils: globals.os,
          ),
      Pub: () => TizenPub(
            fileSystem: globals.fs,
            logger: globals.logger,
            processManager: globals.processManager,
            platform: globals.platform,
            botDetector: globals.botDetector,
            usage: globals.flutterUsage,
          ),
      Logger: () {
        final LoggerFactory loggerFactory = LoggerFactory(
          outputPreferences: globals.outputPreferences,
          terminal: globals.terminal,
          stdio: globals.stdio,
        );
        return loggerFactory.createLogger(
          daemon: daemon,
          machine: runMachine,
          verbose: verbose && !muteCommandLogging,
          windows: globals.platform.isWindows,
        );
      },
    },
  );
}

/// See: [Cache.defaultFlutterRoot] in `cache.dart`
String get rootPath {
  final String scriptPath = Platform.script.toFilePath();
  return normalize(join(
    scriptPath,
    scriptPath.endsWith('.snapshot') ? '../../..' : '../..',
  ));
}

/// An abstraction for instantiation of the correct logger type.
///
/// Our logger class hierarchy and runtime requirements are overly complicated.
class LoggerFactory {
  LoggerFactory({
    @required Terminal terminal,
    @required Stdio stdio,
    @required OutputPreferences outputPreferences,
    StopwatchFactory stopwatchFactory = const StopwatchFactory(),
  })  : _terminal = terminal,
        _stdio = stdio,
        _stopwatchFactory = stopwatchFactory,
        _outputPreferences = outputPreferences;

  final Terminal _terminal;
  final Stdio _stdio;
  final StopwatchFactory _stopwatchFactory;
  final OutputPreferences _outputPreferences;

  /// Create the appropriate logger for the current platform and configuration.
  Logger createLogger({
    @required bool daemon,
    @required bool machine,
    @required bool verbose,
    @required bool windows,
  }) {
    Logger logger;
    if (windows) {
      logger = WindowsStdoutLogger(
        terminal: _terminal,
        stdio: _stdio,
        outputPreferences: _outputPreferences,
        stopwatchFactory: _stopwatchFactory,
      );
    } else {
      logger = StdoutLogger(
          terminal: _terminal,
          stdio: _stdio,
          outputPreferences: _outputPreferences,
          stopwatchFactory: _stopwatchFactory);
    }
    if (verbose) {
      logger = VerboseLogger(logger, stopwatchFactory: _stopwatchFactory);
    }
    if (daemon) {
      return NotifyingLogger(verbose: verbose, parent: logger);
    }
    if (machine) {
      return AppRunLogger(parent: logger);
    }
    return logger;
  }
}
