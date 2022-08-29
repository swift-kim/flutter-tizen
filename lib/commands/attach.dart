// Copyright 2022 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:flutter_tools/src/commands/attach.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';

import '../tizen_device.dart';

class TizenAttachCommand extends AttachCommand {
  TizenAttachCommand({bool verboseHelp = false})
      : super(verboseHelp: verboseHelp);

  @override
  Future<FlutterCommandResult> verifyThenRunCommand(String commandPath) async {
    TizenDevice.shouldUseDlogReader = true;

    return super.verifyThenRunCommand(commandPath);
  }
}
