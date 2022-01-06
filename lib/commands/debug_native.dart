// Copyright 2022 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'dart:async';
import 'dart:convert';

import 'package:file/file.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/base/signals.dart';
import 'package:flutter_tools/src/base/terminal.dart';
import 'package:flutter_tools/src/convert.dart';
import 'package:flutter_tools/src/device.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:meta/meta.dart';

import '../tizen_device.dart';
import '../tizen_sdk.dart';
import '../tizen_tpk.dart';
import '../vscode_helper.dart';

const String kWikiUrl =
    "https://github.com/flutter-tizen/flutter-tizen/wiki/Debugging-app's-native-code";

class DebugNativeCommand extends FlutterCommand {
  DebugNativeCommand({
    @required Terminal terminal,
    @required TizenSdk tizenSdk,
  })  : _terminal = terminal,
        _tizenSdk = tizenSdk {
    requiresPubspecYaml();
  }

  @override
  String get name => 'debug-native';

  @override
  String get description => 'Attach gdbserver to a running app (Tizen-only).';

  @override
  String get category => FlutterCommandCategory.tools;

  final Terminal _terminal;
  final TizenSdk _tizenSdk;
  final Completer<int> _finished = Completer<int>();

  TizenDevice _device;
  FlutterProject _project;
  TizenTpk _package;
  StreamSubscription<void> _subscription;

  @override
  Future<void> validateCommand() async {
    final Device device = await findTargetDevice();
    if (device == null) {
      throwToolExit('No target device found.');
    }
    if (device is! TizenDevice) {
      throwToolExit('The selected device is not a Tizen device.');
    }
    _device = device as TizenDevice;
    if (_device.usesSecureProtocol) {
      throwToolExit('Not supported device.');
    }
    return super.validateCommand();
  }

  @override
  Future<FlutterCommandResult> verifyThenRunCommand(String commandPath) async {
    _project = FlutterProject.current();
    _package = TizenTpk.fromProject(_project);
    if (_package.isDotnet) {
      throwToolExit(
        'Not supported app language.\n\n'
        'See $kWikiUrl for detailed usage.',
      );
    }
    return super.verifyThenRunCommand(commandPath);
  }

  Future<void> _startGdbServer(
    String applicationId,
    int debugPort,
    String processId,
  ) async {
    final List<String> command = _device.sdbCommand(<String>[
      'launch',
      '-a',
      '"$applicationId"',
      '-p',
      '-e',
      '-m',
      'debug',
      '-P',
      '$debugPort',
      '-attach',
      processId,
    ]);
    final Process process = await globals.processManager.start(command);

    final Completer<void> completer = Completer<void>();
    final StreamSubscription<String> stdoutSubscription = process.stdout
        .transform<String>(const Utf8Decoder())
        .transform<String>(const LineSplitter())
        .listen((String line) {
      if (line.contains("Can't bind address") ||
          line.contains('Cannot attach to process')) {
        completer.completeError(line);
      } else if (line.contains('pkg api_version:')) {
        return;
      } else if (line.contains('Listening on port')) {
        completer.complete();
      } else {
        // Remove this line when appropriate in the future.
        globals.printError(line);
      }
    }, onDone: () {
      completer.complete();
    });
    final StreamSubscription<String> stderrSubscription = process.stderr
        .transform<String>(const Utf8Decoder())
        .transform<String>(const LineSplitter())
        .listen((String line) {
      completer.completeError(line);
    });

    try {
      await completer.future.timeout(const Duration(seconds: 10));
    } on Exception catch (error) {
      throwToolExit('Could not start gdbserver: $error');
    }
    await stdoutSubscription.cancel();
    await stderrSubscription.cancel();
  }

  @override
  Future<FlutterCommandResult> runCommand() async {
    final File program = _project.directory
        .childDirectory('build')
        .childDirectory('tizen')
        .childDirectory('tpk')
        .childDirectory('tpkroot')
        .childDirectory('bin')
        .childFile('runner');
    if (!program.existsSync()) {
      throwToolExit(
        'Could not find the runner executable.\n'
        'Did you build and install the app to your device?',
      );
    }

    // Forward a port to allow communication between gdb and gdbserver.
    final int debugPort = await globals.os.findFreePort();
    await _device.portForwarder.forward(debugPort, hostPort: debugPort);

    // Find the running app's process ID.
    final RunResult result =
        await _device.runSdbAsync(<String>['shell', 'app_launcher', '-S']);
    final RegExp pattern = RegExp('${_package.applicationId} \\(([0-9]+)\\)');
    final Match match = pattern.firstMatch(result.stdout);
    if (match == null) {
      throwToolExit('The app is not running.');
    }
    final String processId = match.group(1);

    if (!await _device.installGdbServer()) {
      return FlutterCommandResult.fail();
    }
    await _startGdbServer(_package.applicationId, debugPort, processId);

    final File gdb = _tizenSdk.getGdbExecutable(_device.architecture);
    updateLaunchJsonWithRemoteDebuggingInfo(
      _project,
      program: program,
      gdbPath: gdb.path,
      debugPort: debugPort,
    );

    final String escapeCharacter = globals.platform.isWindows ? '`' : r'\';
    globals.printStatus('''
gdbserver is listening for connection on port $debugPort.

Press Enter to launch GDB in the current window.

GDB launch command:
${gdb.path} $escapeCharacter
  "${program.path}" $escapeCharacter
  -ex "set pagination off" $escapeCharacter
  -ex "set auto-solib-add off" $escapeCharacter
  -ex "target remote :$debugPort" $escapeCharacter
  -ex "shared /opt/usr/globalapps"

Debugging with VS Code:
1. Open the project folder in VS Code.
2. Click the Run and Debug icon in the left menu bar, and make sure "$kConfigNameGdb" is selected.
3. Click ▷ or press F5 to start debugging.

See $kWikiUrl for detailed usage.''');

    _registerSignalHandlers(_stop);

    _terminal.singleCharMode = true;
    _subscription = _terminal.keystrokes.listen((String key) async {
      switch (key) {
        case '\r':
        case '\n':
          _stop();
          _finished.complete(await _runInProcess(<String>[
            gdb.path,
            program.path,
            '-ex',
            'set auto-solib-add off',
            '-ex',
            'target remote :$debugPort',
            '-ex',
            'shared /opt/usr/globalapps',
          ]));
          break;
        case 'q':
        case 'Q':
          _stop();
          _unregisterSignalHandlers();
          _finished.complete(0);
          break;
      }
    });

    final int exitCode = await _finished.future;
    if (exitCode != 0) {
      return FlutterCommandResult.fail();
    }
    return FlutterCommandResult.success();
  }

  Future<int> _runInProcess(List<String> command) async {
    final Process process = await globals.processManager.start(
      command,
      includeParentEnvironment: true,
    );

    _unregisterSignalHandlers();
    _registerSignalHandlers((ProcessSignal signal) async {
      // TODO(swift-kim): Any better way to ignore the signal?
      await process.exitCode;
    });

    // TODO(swift-kim): This is a temporary workaround because stdio.stdin is
    // already subscribed by keystrokes and cannot be subscribed again.
    // Only Ascii characters can be passed to the process's stdin in this way.
    final Stream<List<int>> fakeStdin =
        _terminal.keystrokes.transform(const AsciiEncoder());
    unawaited(process.stdin.addStream(fakeStdin));
    unawaited(globals.stdio.addStdoutStream(process.stdout));
    unawaited(globals.stdio.addStderrStream(process.stderr));

    return process.exitCode;
  }

  void _stop([ProcessSignal signal]) {
    _terminal.singleCharMode = false;
    _subscription?.cancel();
  }

  final Map<ProcessSignal, Object> _signalTokens = <ProcessSignal, Object>{};

  void _registerSignalHandlers(SignalHandler onSignal) {
    _signalTokens[ProcessSignal.sigint] =
        globals.signals.addHandler(ProcessSignal.sigint, onSignal);
    _signalTokens[ProcessSignal.sigterm] =
        globals.signals.addHandler(ProcessSignal.sigterm, onSignal);
  }

  void _unregisterSignalHandlers() {
    for (final ProcessSignal signal in _signalTokens.keys) {
      globals.signals.removeHandler(signal, _signalTokens[signal]);
    }
    _signalTokens.clear();
  }
}
