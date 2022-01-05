// Copyright 2022 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:args/command_runner.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_tizen/commands/debug_native.dart';
import 'package:flutter_tizen/tizen_device.dart';
import 'package:flutter_tizen/tizen_sdk.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/device.dart';

import '../src/common.dart';
import '../src/context.dart';
import '../src/fake_tizen_sdk.dart';
import '../src/test_flutter_command_runner.dart';

void main() {
  FileSystem fileSystem;
  ProcessManager processManager;
  TizenSdk tizenSdk;
  DeviceManager deviceManager;

  setUpAll(() {
    Cache.disableLocking();
  });

  setUp(() {
    fileSystem = MemoryFileSystem.test();
    processManager = FakeProcessManager.any();
    tizenSdk = FakeTizenSdk(fileSystem);

    fileSystem.file('pubspec.yaml').createSync(recursive: true);
    fileSystem.file('tizen/tizen-manifest.xml')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
<manifest package="package_id" version="1.0.0" api-version="4.0">
    <profile name="common"/>
    <ui-application appid="app_id" exec="runner" type="capp"/>
</manifest>
''');

    final TizenDevice tizenDevice = TizenDevice(
      'TestDeviceId',
      modelId: 'TestModel',
      logger: BufferLogger.test(),
      processManager: FakeProcessManager.any(),
      tizenSdk: tizenSdk,
      fileSystem: fileSystem,
    );
    deviceManager = _FakeDeviceManager(<Device>[tizenDevice]);
  });

  testUsingContext('dddd', () async {
    final DebugNativeCommand command = DebugNativeCommand(
      platform: FakePlatform(),
      processManager: processManager,
      tizenSdk: tizenSdk,
    );
    final CommandRunner<void> runner = createTestCommandRunner(command);
    await runner.run(<String>['debug-native']);
  }, overrides: <Type, Generator>{
    FileSystem: () => fileSystem,
    ProcessManager: () => processManager,
    DeviceManager: () => deviceManager,
  });
}

class _FakeDeviceManager extends DeviceManager {
  _FakeDeviceManager(this._devices);

  final List<Device> _devices;

  @override
  List<DeviceDiscovery> get deviceDiscoverers => <DeviceDiscovery>[];

  @override
  Future<List<Device>> getAllConnectedDevices() async => _devices;
}


  // testUsingContext('TizenDevice.startApp fails when gdbserver is not found',
  //     () async {
  //   TizenDevice.nativeDebuggingEnabled = true;

  //   final TizenDevice device = _createTizenDevice(
  //     processManager: processManager,
  //     fileSystem: fileSystem,
  //     logger: testLogger,
  //   );
  //   final TizenManifest tizenManifest = _FakeTizenManifest();
  //   final TizenTpk tpk = TizenTpk(
  //     file: fileSystem.file('app.tpk')..createSync(),
  //     manifest: tizenManifest,
  //   );

  //   processManager.addCommands(<FakeCommand>[
  //     FakeCommand(
  //       command: _sdbCommand(<String>['capability']),
  //       stdout: <String>[
  //         'cpu_arch:armv7',
  //         'secure_protocol:disabled',
  //         'platform_version:4.0',
  //       ].join('\n'),
  //     ),
  //     FakeCommand(
  //       command: _sdbCommand(<String>['shell', 'ls', '/usr/lib64']),
  //       stdout: 'No such file or directory',
  //     ),
  //   ]);

  //   final LaunchResult launchResult = await device.startApp(
  //     tpk,
  //     prebuiltApplication: true,
  //     debuggingOptions: DebuggingOptions.enabled(BuildInfo.debug),
  //     platformArgs: <String, dynamic>{},
  //   );

  //   expect(launchResult.started, isFalse);
  //   expect(
  //     testLogger.errorText,
  //     contains('gdbserver_7.8.1_armel.tar could not be found.'),
  //   );
  // }, overrides: <Type, Generator>{
  //   FileSystem: () => fileSystem,
  //   ProcessManager: () => processManager,
  // });
