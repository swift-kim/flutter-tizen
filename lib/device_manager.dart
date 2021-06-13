// Copyright 2020 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:flutter_tools/src/android/android_workflow.dart';
import 'package:flutter_tools/src/base/context.dart';
import 'package:flutter_tools/src/context_runner.dart';
import 'package:flutter_tools/src/custom_devices/custom_devices_config.dart';
import 'package:flutter_tools/src/device.dart';
import 'package:flutter_tools/src/features.dart';
import 'package:flutter_tools/src/flutter_device_manager.dart';
import 'package:flutter_tools/src/fuchsia/fuchsia_workflow.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/macos/macos_workflow.dart';
import 'package:flutter_tools/src/windows/windows_workflow.dart';

import 'tizen/tizen_device_discovery.dart';
import 'tizen/tizen_workflow.dart';

/// An extended [FlutterDeviceManager] for managing Tizen devices.
class TizenDeviceManager extends FlutterDeviceManager {
  /// Source: [runInContext] in `context_runner.dart`
  TizenDeviceManager()
      : super(
          logger: globals.logger,
          processManager: globals.processManager,
          platform: globals.platform,
          androidSdk: globals.androidSdk,
          iosSimulatorUtils: globals.iosSimulatorUtils,
          featureFlags: featureFlags,
          fileSystem: globals.fs,
          iosWorkflow: globals.iosWorkflow,
          artifacts: globals.artifacts,
          flutterVersion: globals.flutterVersion,
          androidWorkflow: androidWorkflow,
          config: globals.config,
          fuchsiaWorkflow: fuchsiaWorkflow,
          xcDevice: globals.xcdevice,
          userMessages: globals.userMessages,
          windowsWorkflow: windowsWorkflow,
          macOSWorkflow: context.get<MacOSWorkflow>(),
          operatingSystemUtils: globals.os,
          terminal: globals.terminal,
          customDevicesConfig: CustomDevicesConfig(
            fileSystem: globals.fs,
            logger: globals.logger,
            platform: globals.platform,
          ),
        );

  final TizenDeviceDiscovery _tizenDeviceDiscovery = TizenDeviceDiscovery(
    tizenWorkflow: tizenWorkflow,
    logger: globals.logger,
    processManager: globals.processManager,
  );

  @override
  List<DeviceDiscovery> get deviceDiscoverers => <DeviceDiscovery>[
        ...super.deviceDiscoverers,
        _tizenDeviceDiscovery,
      ];
}
