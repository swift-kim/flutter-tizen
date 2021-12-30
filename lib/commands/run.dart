// Copyright 2020 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/commands/run.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';

import '../tizen_cache.dart';
import '../tizen_device.dart';
import '../tizen_plugins.dart';

class TizenRunCommand extends RunCommand
    with DartPluginRegistry, TizenRequiredArtifacts {
  TizenRunCommand({bool verboseHelp = false})
      : super(verboseHelp: verboseHelp) {
    argParser.addFlag(
      'tizen-native-debugging',
      defaultsTo: false,
      help: 'Enable debugging of native code in a Tizen app by running it '
          'under gdbserver. This feature is currently experimental.',
    );
  }

  @override
  Future<FlutterCommandResult> runCommand() async {
    if (boolArg('tizen-native-debugging')) {
      if (getBuildMode() != BuildMode.debug) {
        throwToolExit('Native debugging is only supported in debug mode.');
      }
      TizenDevice.nativeDebuggingEnabled = true;
    }
    return super.runCommand();
  }
}
