// Copyright 2022 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:file/memory.dart';
import 'package:file_testing/file_testing.dart';
import 'package:flutter_tizen/tizen_plugins.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';

import '../src/common.dart';
import '../src/context.dart';
import '../src/test_flutter_command_runner.dart';

void main() {
  FileSystem fileSystem;
  FlutterProject project;
  File pubspecFile;
  File packageConfigFile;

  setUpAll(() {
    Cache.disableLocking();
  });

  setUp(() {
    fileSystem = MemoryFileSystem.test();
    project = FlutterProject.fromDirectoryTest(fileSystem.currentDirectory);

    pubspecFile = fileSystem.file('pubspec.yaml')..createSync(recursive: true);
    packageConfigFile = fileSystem.file('.dart_tool/package_config.json')
      ..createSync(recursive: true);
    fileSystem.file('lib/main.dart').createSync(recursive: true);
    fileSystem.file('tizen/tizen-manifest.xml').createSync(recursive: true);
  });

  testUsingContext('Generates Dart plugin registrant', () async {
    final _DummyFlutterCommand command = _DummyFlutterCommand();
    final CommandRunner<void> runner = createTestCommandRunner(command);

    final Directory pluginDir = fileSystem.directory('/some_dart_plugin');
    pluginDir.childFile('pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
flutter:
  plugin:
    platforms:
      tizen:
        dartPluginClass: SomeDartPlugin
        fileName: some_dart_plugin.dart
''');
    pubspecFile.writeAsStringSync('''
dependencies:
  some_dart_plugin:
    path: ${pluginDir.path}
''');
    packageConfigFile.writeAsStringSync('''
{
  "configVersion": 2,
  "packages": [
    {
      "name": "some_dart_plugin",
      "rootUri": "${pluginDir.uri}",
      "packageUri": "lib/",
      "languageVersion": "2.12"
    }
  ]
}
''');
    await runner.run(<String>['dummy']);

    final File generatedMain =
        fileSystem.file('tizen/flutter/generated_main.dart');
    expect(generatedMain, exists);
    expect(generatedMain.readAsStringSync(), contains('''
import 'package:some_dart_plugin/some_dart_plugin.dart';

@pragma('vm:entry-point')
class _PluginRegistrant {
  @pragma('vm:entry-point')
  static void register() {
    SomeDartPlugin.register();
  }
}
'''));
  }, overrides: <Type, Generator>{
    FileSystem: () => fileSystem,
    ProcessManager: () => FakeProcessManager.any(),
  }, skip: Platform.isWindows);

  testUsingContext('Generates native plugin registrants', () async {
    final Directory pluginDir = fileSystem.directory('/some_native_plugin');
    pluginDir.childFile('pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
flutter:
  plugin:
    platforms:
      tizen:
        pluginClass: SomeNativePlugin
        fileName: some_native_plugin.h
''');
    pubspecFile.writeAsStringSync('''
dependencies:
  some_native_plugin:
    path: ${pluginDir.path}
''');
    packageConfigFile.writeAsStringSync('''
{
  "configVersion": 2,
  "packages": [
    {
      "name": "some_native_plugin",
      "rootUri": "${pluginDir.uri}",
      "packageUri": "lib/",
      "languageVersion": "2.12"
    }
  ]
}
''');
    await injectTizenPlugins(project);

    final File cppPluginRegistrant =
        fileSystem.file('tizen/flutter/generated_plugin_registrant.h');
    expect(cppPluginRegistrant, exists);
    expect(cppPluginRegistrant.readAsStringSync(), contains('''
#include "some_native_plugin.h"

// Registers Flutter plugins.
void RegisterPlugins(flutter::PluginRegistry *registry) {
  SomeNativePluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("SomeNativePlugin"));
}
'''));

    final File csharpPluginRegistrant =
        fileSystem.file('tizen/flutter/GeneratedPluginRegistrant.cs');
    expect(csharpPluginRegistrant, exists);
    expect(csharpPluginRegistrant.readAsStringSync(), contains('''
namespace Runner
{
    internal class GeneratedPluginRegistrant
    {
        [DllImport("flutter_plugins.so")]
        public static extern void SomeNativePluginRegisterWithRegistrar(
            FlutterDesktopPluginRegistrar registrar);

        public static void RegisterPlugins(IPluginRegistry registry)
        {
            SomeNativePluginRegisterWithRegistrar(
                registry.GetRegistrarForPlugin("SomeNativePlugin"));
        }
    }
}
'''));
  }, overrides: <Type, Generator>{
    FileSystem: () => fileSystem,
    ProcessManager: () => FakeProcessManager.any(),
  }, skip: Platform.isWindows);
}

class _DummyFlutterCommand extends FlutterCommand with DartPluginRegistry {
  _DummyFlutterCommand() {
    usesTargetOption();
  }

  @override
  String name = 'dummy';

  @override
  String description;

  @override
  Future<FlutterCommandResult> runCommand() async {
    return const FlutterCommandResult(ExitStatus.success);
  }
}
