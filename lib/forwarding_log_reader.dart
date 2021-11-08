// Copyright 2021 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_tools/src/base/terminal.dart';
import 'package:flutter_tools/src/device.dart';
import 'package:flutter_tools/src/device_port_forwarder.dart';
import 'package:flutter_tools/src/globals.dart' as globals;

import 'tizen_device.dart';

class ForwardingLogReader extends DeviceLogReader {
  ForwardingLogReader._(this.name, this.hostPort, this.portForwarder)
      : assert(hostPort != null),
        assert(portForwarder != null);

  static Future<ForwardingLogReader> createLogReader(TizenDevice device) async {
    return ForwardingLogReader._(
      device.name,
      await globals.os.findFreePort(ipv6: false),
      device.portForwarder,
    );
  }

  @override
  final String name;

  final int hostPort;

  final DevicePortForwarder portForwarder;

  final StreamController<String> _linesController =
      StreamController<String>.broadcast();

  Socket _socket;

  @override
  Stream<String> get logLines => _linesController.stream;

  final RegExp _logFormat = RegExp(r'^(\[[IWEF]\]) .+');

  String _colorizePrefix(String message) {
    final Match match = _logFormat.firstMatch(message);
    if (match == null) {
      return message;
    }
    final String prefix = match.group(1);
    TerminalColor color;
    if (prefix == '[I]') {
      color = TerminalColor.cyan;
    } else if (prefix == '[W]') {
      color = TerminalColor.yellow;
    } else if (prefix == '[E]') {
      color = TerminalColor.red;
    } else if (prefix == '[F]') {
      color = TerminalColor.magenta;
    }
    return message.replaceFirst(prefix, globals.terminal.color(prefix, color));
  }

  final List<String> _filteredTexts = <String>[
    // Issue: https://github.com/flutter-tizen/engine/issues/91
    'xkbcommon: ERROR:',
    "couldn't find a Compose file for locale",
  ];

  Future<Socket> _connectAndListen() async {
    globals.printTrace('Connecting to localhost:$hostPort...');
    Socket socket = await Socket.connect('localhost', hostPort);

    const Utf8Decoder decoder = Utf8Decoder();
    final Completer<void> completer = Completer<void>();

    socket.listen(
      (Uint8List data) {
        String response = decoder.convert(data).trim();
        if (!completer.isCompleted) {
          if (response.startsWith('ACCEPTED')) {
            response = response.substring(8);
          } else {
            globals.printError(
                'Invalid message received from the device logger: $response');
            socket.destroy();
            socket = null;
          }
          completer.complete();
        }
        for (final String line in LineSplitter.split(response)) {
          if (line.isEmpty ||
              _filteredTexts.any((String text) => line.contains(text))) {
            continue;
          }
          _linesController.add(_colorizePrefix(line));
        }
      },
      onError: (Object error) {
        globals.printError(error.toString());
      },
      onDone: () {
        socket?.destroy();
        socket = null;
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
    );

    await completer.future;
    return socket;
  }

  Future<void> start() async {
    // The host port is also used as a device port. This could result in a
    // binding error if the port is already in use by another process on the
    // device.
    // The forwarded port will be automatically unforwarded when
    // TizenDevicePortForwarder is disposed.
    await portForwarder.forward(hostPort, hostPort: hostPort);

    int retryCount = 5;
    while (_socket == null && retryCount-- > 0) {
      _socket = await _connectAndListen();
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (_socket == null) {
      globals.printError(
        'Failed to connect to the device logger.\n'
        'Please open an issue in https://github.com/flutter-tizen/flutter-tizen/issues if the problem persists.',
      );
    } else {
      globals.printTrace(
          'The logging service started at ${_socket.remoteAddress.address}:${_socket.remotePort}.');
    }
  }

  @override
  void dispose() {
    _socket?.destroy();
    _linesController.close();
  }
}
