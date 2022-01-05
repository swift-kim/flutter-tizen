// Copyright 2022 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/base/version.dart';
import 'package:flutter_tools/src/convert.dart';
import 'package:flutter_tools/src/device.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:process/process.dart';

import '../tizen_device.dart';
import '../tizen_sdk.dart';
import '../tizen_tpk.dart';
import '../vscode_helper.dart';

class TizenDebugNativeCommand extends FlutterCommand {
  TizenDebugNativeCommand({
    Platform platform,
    ProcessManager processManager,
    TizenSdk tizenSdk,
  })  : _platform = platform,
        _processManager = processManager,
        _tizenSdk = tizenSdk {
    requiresPubspecYaml();
  }

  @override
  String get name => 'debug-native';

  @override
  String get description => 'TestTestTest';

  @override
  String get category => FlutterCommandCategory.tools;

  final Platform _platform;
  final ProcessManager _processManager;
  final TizenSdk _tizenSdk;

  TizenDevice tizenDevice;

  @override
  Future<void> validateCommand() async {
    final Device device = await findTargetDevice();
    if (device == null) {
      throwToolExit(
        'No devices are connected. '
        'Ensure that `flutter doctor` shows at least one connected device',
      );
    }
    tizenDevice = device as TizenDevice;
    if (tizenDevice == null) {
      throwToolExit('Only Tizen devices are supported for native debugging.');
    }
    return super.validateCommand();
  }

  Future<bool> _installGdbServer() async {
    final Version platformVersion =
        Version.parse((await tizenDevice.sdkNameAndVersion).split(' ').last);
    String gdbServerVersion = '8.3.1';
    if (platformVersion != null && platformVersion < Version(6, 0, 0)) {
      gdbServerVersion = '7.8.1';
    }
    final String arch =
        getTizenBuildArch(tizenDevice.architecture, platformVersion);
    final String tarName = 'gdbserver_${gdbServerVersion}_$arch.tar';
    final File tarArchive =
        _tizenSdk.toolsDirectory.childDirectory('on-demand').childFile(tarName);
    if (!tarArchive.existsSync()) {
      globals.printError('The file ${tarArchive.path} could not be found.');
      return false;
    }
    globals.printTrace('Installing $tarName to $name.');

    const String sdkToolsPath = '/home/owner/share/tmp/sdk_tools';
    final String remoteArchivePath = '$sdkToolsPath/$tarName';
    try {
      final RunResult mkdirResult = await tizenDevice.runSdbAsync(<String>[
        'shell',
        'mkdir',
        '-p',
        sdkToolsPath,
      ]);
      if (mkdirResult.stdout.isNotEmpty) {
        mkdirResult.throwException(mkdirResult.stdout);
      }
      final RunResult pushResult = await tizenDevice.runSdbAsync(<String>[
        'push',
        tarArchive.path,
        remoteArchivePath,
      ]);
      if (!pushResult.stdout.contains('file(s) pushed')) {
        pushResult.throwException(pushResult.stdout);
      }
      final RunResult extractResult = await tizenDevice.runSdbAsync(<String>[
        'shell',
        'tar',
        '-xf',
        remoteArchivePath,
        '-C',
        sdkToolsPath
      ]);
      if (extractResult.stdout.isNotEmpty) {
        extractResult.throwException(extractResult.stdout);
      }
    } on ProcessException catch (error) {
      globals.printError('Error installing gdbserver: $error');
      return false;
    }
    // Remove a temporary file.
    await tizenDevice.runSdbAsync(<String>[
      'shell',
      'rm',
      remoteArchivePath,
    ], checked: false);

    return true;
  }

  @override
  Future<FlutterCommandResult> verifyThenRunCommand(String commandPath) async {
    final FlutterProject project = FlutterProject.current();
    final TizenTpk package = TizenTpk.fromProject(project);

    if (package.isDotnet) {
      globals.printError('Native debugging error: Not supported app type.');
      return FlutterCommandResult.fail();
    } else if (tizenDevice.usesSecureProtocol) {
      globals.printError('Native debugging error: Not supported device.');
      return FlutterCommandResult.fail();
    } else if (!await _installGdbServer()) {
      return FlutterCommandResult.fail();
    }

    return super.verifyThenRunCommand(commandPath);
  }

  Future<void> _launchGdbServer(String appId, int debugPort, String pid) async {
    final List<String> command = tizenDevice.sdbCommand(<String>[
      'launch',
      '-a',
      '"$appId"',
      '-p',
      '-e',
      '-m',
      'debug',
      '-P',
      '$debugPort',
      '-attach',
      pid,
    ]);
    final Process process = await _processManager.start(command);

    final Completer<void> completer = Completer<void>();
    final StreamSubscription<String> stdoutSubscription = process.stdout
        .transform<String>(const Utf8Decoder())
        .transform<String>(const LineSplitter())
        .listen((String line) {
      if (line.contains("Can't bind address") ||
          line.contains('Cannot attach to process')) {
        completer.completeError(line);
      } else if (line.contains('Listening on port')) {
        completer.complete();
      } else {
        // For debugging purpose.
        // Remove this when we obtain enough information on corner cases.
        globals.printError(line);
      }
    });
    final StreamSubscription<String> stderrSubscription = process.stderr
        .transform<String>(const Utf8Decoder())
        .transform<String>(const LineSplitter())
        .listen((String line) {
      completer.completeError(line);
    });

    // try {
    //   await completer.future.timeout(const Duration(seconds: 10));
    // } on Exception catch (error) {
    //   _logger.printError('Could not launch gdbserver: $error');
    //   await stdoutSubscription.cancel();
    //   await stderrSubscription.cancel();
    //   rethrow;
    // }
    await completer.future.timeout(const Duration(seconds: 15));
    await stdoutSubscription.cancel();
    await stderrSubscription.cancel();
  }

  @override
  Future<FlutterCommandResult> runCommand() async {
    final FlutterProject project = FlutterProject.current();
    final TizenTpk package = TizenTpk.fromProject(project);

    // Forward a port to allow communication between gdb and gdbserver.
    final int debugPort = await globals.os.findFreePort();
    await tizenDevice.portForwarder.forward(debugPort, hostPort: debugPort);

    final List<String> command = <String>['shell', 'app_launcher', '-S'];
    final RunResult result = await tizenDevice.runSdbAsync(command);

    final RegExp pattern = RegExp('${package.applicationId} \\(([0-9]+)\\)');
    final Match match = pattern.firstMatch(result.stdout);
    if (match == null) {
      globals.printError(result.stdout);
      return FlutterCommandResult.fail();
    }

    final String pid = match.group(1);
    await _launchGdbServer(package.applicationId, debugPort, pid);

    final File program = project.directory
        .childDirectory('build')
        .childDirectory('tizen')
        .childDirectory('tpk')
        .childDirectory('tpkroot')
        .childDirectory('bin')
        .childFile('runner');
    final File gdb = _tizenSdk.getGdbExecutable(tizenDevice.architecture);

    updateLaunchJsonWithRemoteDebuggingInfo(
      project,
      program: program,
      gdbPath: gdb.path,
      debugPort: debugPort,
    );

    final String escapeCharacter = _platform.isWindows ? '`' : r'\';
    globals.printStatus('''
gdbserver is listening for connection on port $debugPort.

(a) For CLI debugging:
    1. Open another console window.
    2. Launch GDB with the following command.
    ${gdb.path} $escapeCharacter
      "${program.path}" $escapeCharacter
      -ex "set pagination off" $escapeCharacter
      -ex "set auto-solib-add off" $escapeCharacter
      -ex "target remote :$debugPort" $escapeCharacter
      -ex "shared /opt/usr/globalapps"

(b) For debugging with VS Code:
    1. Open the project folder in VS Code.
    2. Click the Run and Debug icon in the left menu bar, and make sure "$kConfigNameGdb" is selected.
    3. Click ▷ or press F5 to start debugging.

For detailed instructions, see:
https://github.com/flutter-tizen/flutter-tizen/wiki/Debugging-app's-native-code''');

    //  onError: (Object error) {
    //   globals.printError('Could not launch gdbserver: $error');
    // });

    return FlutterCommandResult.success();
  }
}
