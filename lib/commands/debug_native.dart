// Copyright 2022 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/base/signals.dart';
import 'package:flutter_tools/src/base/terminal.dart';
import 'package:flutter_tools/src/convert.dart';
import 'package:flutter_tools/src/device.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:meta/meta.dart';
import 'package:process/process.dart';

import '../tizen_device.dart';
import '../tizen_sdk.dart';
import '../tizen_tpk.dart';
import '../vscode_helper.dart';

const String kWikiUrl =
    "https://github.com/flutter-tizen/flutter-tizen/wiki/Debugging-app's-native-code";

class DebugNativeCommand extends FlutterCommand {
  DebugNativeCommand({
    @required Platform platform,
    @required ProcessManager processManager,
    @required Terminal terminal,
    @required Signals signals,
    @required TizenSdk tizenSdk,
  })  : _platform = platform,
        _processManager = processManager,
        _terminal = terminal,
        _signals = signals,
        _tizenSdk = tizenSdk {
    requiresPubspecYaml();
  }

  @override
  String get name => 'debug-native';

  @override
  String get description => 'Attach gdbserver to a running app (Tizen-only).';

  @override
  String get category => FlutterCommandCategory.tools;

  final Platform _platform;
  final ProcessManager _processManager;
  final Terminal _terminal;
  final Signals _signals;
  final TizenSdk _tizenSdk;

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
    final Process process = await _processManager.start(command);

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

See $kWikiUrl for detailed usage.''');

    registerSignalHandlers();

    _terminal.singleCharMode = true;

    _subscription = _terminal.keystrokes.listen((String command) async {
      command = command.trim();

      switch (command) {
        case 'a':
          print('a');
          break;
        case 'r':
          _terminal.singleCharMode = false;
          // await Process.run(
          //   gdb.path,
          //   <String>[
          //     program.path,
          //     '-ex',
          //     'set auto-solib-add off',
          //     '-ex',
          //     'target remote :$debugPort',
          //     '-ex',
          //     'shared /opt/usr/globalapps',
          //   ],
          //   runInShell: true,
          // );
          // await _subscription.cancel();
          await go(<String>[
            gdb.path,
            program.path,
            '-ex',
            'set auto-solib-add off',
            '-ex',
            'target remote :$debugPort',
            '-ex',
            'shared /opt/usr/globalapps',
          ]);
          break;
        case 'q':
        case 'Q':
          stop();
          break;
      }
    });

    final int exitCode = await _finished.future;
    if (exitCode != 0) {
      return FlutterCommandResult.fail();
    }
    return FlutterCommandResult.success();
  }

  Future<void> go(List<String> command) async {
    await _subscription.cancel();
    final Process process = await _processManager.start(command);
    // _subscription = _terminal.keystrokes.listen((String stroke) async {
    //   process.stdin.write(stroke);
    // });

    final Stdin stdin = globals.stdio.stdin as Stdin;
    stdin.echoMode = true;
    stdin.lineMode = false;

    // stdin.pipe(streamConsumer)
    // process.stdin.addStream(globals.stdio.stdin);

    // _subscription = globals.stdio.stdin.listen((List<int> event) {
    //   process.stdin.write(event);
    // });
    process.stdout.listen((List<int> event) {
      // print('out');
      globals.stdio.stdout.write(event);
    });
    // stderr
  }

  final Completer<int> _finished = Completer<int>();

  final Map<ProcessSignal, Object> _signalTokens = <ProcessSignal, Object>{};

  void _addSignalHandler(ProcessSignal signal, SignalHandler handler) {
    _signalTokens[signal] = _signals.addHandler(signal, handler);
  }

  Future<void> _cleanUp(ProcessSignal signal) async {
    _terminal.singleCharMode = false;
    await _subscription?.cancel();
    globals.printStatus('Interrupted');
  }

  void registerSignalHandlers() {
    _addSignalHandler(ProcessSignal.sigint, _cleanUp);
    _addSignalHandler(ProcessSignal.sigterm, _cleanUp);
  }

  void stop() {
    for (final MapEntry<ProcessSignal, Object> entry in _signalTokens.entries) {
      _signals.removeHandler(entry.key, entry.value);
    }
    _signalTokens.clear();
    _subscription?.cancel();

    globals.printStatus('Bye!');
    _finished.complete(0);
  }
}
