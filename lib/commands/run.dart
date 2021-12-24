// Copyright 2020 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:flutter_tools/src/commands/run.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';

import '../tizen_cache.dart';
import '../tizen_debug_config.dart';
import '../tizen_plugins.dart';

class TizenRunCommand extends RunCommand
    with DartPluginRegistry, TizenRequiredArtifacts {
  TizenRunCommand({bool verboseHelp = false})
      : super(verboseHelp: verboseHelp) {
    argParser.addFlag(
      'enable-native-debugging',
      defaultsTo: false,
      help: 'blabla (Tizen-only)',
    );
  }

  @override
  Future<FlutterCommandResult> runCommand() async {
    tizenDebugConfig.enableNativeDebugging = boolArg('enable-native-debugging');
    return super.runCommand();
  }
}
