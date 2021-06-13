// Copyright 2021 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'dart:async';

import 'package:file/file.dart';
import 'package:flutter_tools/src/android/android_emulator.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/device.dart';
import 'package:flutter_tools/src/emulator.dart';
import 'package:meta/meta.dart';
import 'package:process/process.dart';
import 'package:xml/xml.dart';

import '../tizen/tizen_sdk.dart';
import '../tizen/tizen_workflow.dart';

/// See: [AndroidEmulators] in `android_emulator.dart`
class TizenEmulators extends EmulatorDiscovery {
  TizenEmulators({
    @required TizenSdk tizenSdk,
    @required TizenWorkflow tizenWorkflow,
    @required Logger logger,
    @required ProcessManager processManager,
  })  : _tizenSdk = tizenSdk,
        _tizenWorkflow = tizenWorkflow,
        _logger = logger,
        _processManager = processManager;

  final TizenSdk _tizenSdk;
  final TizenWorkflow _tizenWorkflow;
  final Logger _logger;
  final ProcessManager _processManager;

  @override
  bool get canListAnything => _tizenWorkflow.canListEmulators;

  @override
  bool get canLaunchAnything => _tizenWorkflow.canListEmulators;

  /// Tizen emulator supports all major platforms (Windows/macOS/Linux).
  @override
  bool get supportsPlatform => true;

  @override
  Future<List<Emulator>> get emulators async {
    if (!canListAnything) {
      return <Emulator>[];
    }

    // _tizenSdk is not null here.
    final Directory emulatorDir = _tizenSdk.sdkDataDirectory
        .childDirectory('emulator')
        .childDirectory('vms');
    if (!emulatorDir.existsSync()) {
      return <Emulator>[];
    }

    TizenEmulator loadEmulatorInfo(String id) {
      final File configFile =
          emulatorDir.childDirectory(id).childFile('vm_config.xml');

      final XmlDocument xmlDocument =
          XmlDocument.parse(configFile.readAsStringSync());
      final XmlElement deviceTemplate =
          xmlDocument.findAllElements('deviceTemplate').first;
      final String name = deviceTemplate.getAttribute('name');
      final XmlElement diskImage =
          xmlDocument.findAllElements('diskImage').first;
      final String profile = diskImage.getAttribute('profile');
      final String version = diskImage.getAttribute('version');

      final Map<String, String> properties = <String, String>{
        'name': name,
        'profile': profile,
        'version': version,
      };

      return TizenEmulator(
        id,
        properties: properties,
        logger: _logger,
        processManager: _processManager,
        tizenSdk: _tizenSdk,
      );
    }

    final List<Emulator> emulators = <Emulator>[];
    for (final FileSystemEntity entity in emulatorDir.listSync()) {
      if (entity is Directory &&
          entity.childFile('vm_config.xml').existsSync()) {
        final String id = entity.basename;
        emulators.add(loadEmulatorInfo(id));
      }
    }
    return emulators;
  }
}

/// See: [AndroidEmulator] in `android_emulator.dart`
class TizenEmulator extends Emulator {
  TizenEmulator(
    String id, {
    Map<String, String> properties,
    @required Logger logger,
    @required ProcessManager processManager,
    @required TizenSdk tizenSdk,
  })  : _properties = properties,
        _logger = logger,
        _processUtils =
            ProcessUtils(logger: logger, processManager: processManager),
        _tizenSdk = tizenSdk,
        super(id, properties != null && properties.isNotEmpty);

  final Map<String, String> _properties;
  final Logger _logger;
  final ProcessUtils _processUtils;
  final TizenSdk _tizenSdk;

  String _prop(String name) => _properties != null ? _properties[name] : null;

  @override
  String get name => _prop('name') ?? id;

  @override
  String get manufacturer => 'Samsung';

  // TODO(HakkyuKim): Consider subcategorizing into Tizen profiles.
  @override
  Category get category => Category.mobile;

  // TODO(HakkyuKim): Consider replacing it to Tizen.
  @override
  PlatformType get platformType => PlatformType.linux;

  @override
  Future<void> launch() async {
    final File emCli = _tizenSdk?.emCli;
    if (emCli == null || !emCli.existsSync()) {
      throwToolExit('Unable to locate Tizen Emulator Manager.');
    }

    final RunResult result =
        await _processUtils.run(<String>[emCli.path, 'launch', '--name', id]);
    if (result.exitCode == 0) {
      _logger.printStatus('Successfully launched Tizen emulator $id.');
    } else if (result.stdout.contains('is running now...')) {
      _logger.printStatus('Tizen emulator $id is already running.');
    } else {
      _logger.printError(result.stdout);
      _logger.printError('Could not launch Tizen emulator $id.');
    }
  }
}
