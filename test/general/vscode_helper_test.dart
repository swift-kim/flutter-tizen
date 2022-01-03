// Copyright 2021 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:file/memory.dart';
import 'package:file_testing/file_testing.dart';
import 'package:flutter_tizen/vscode_helper.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/project.dart';

import '../src/common.dart';

const String _kLaunchJsonAttach = r'''
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "flutter-tizen: Attach",
            "request": "attach",
            "type": "dart",
            "deviceId": "flutter-tester",
            "cwd": "${workspaceFolder}",
            "observatoryUri": "http://127.0.0.1:12345"
        }
    ]
}''';

const String _kEmptyLaunchJson = r'''
{
    // This comment will be deleted.
    "version": "0.2.0",
    "configurations": []
}''';

void main() {
  FlutterProject project;

  setUp(() {
    final FileSystem fileSystem = MemoryFileSystem.test();
    project = FlutterProject.fromDirectoryTest(fileSystem.currentDirectory);
  });

  testWithoutContext('Can create launch.json file', () async {
    final File launchJsonFile =
        project.directory.childDirectory('.vscode').childFile('launch.json');
    expect(launchJsonFile, isNot(exists));

    updateLaunchJsonWithObservatoryInfo(
      project,
      Uri.parse('http://127.0.0.1:12345'),
    );

    expect(launchJsonFile, exists);
    expect(launchJsonFile.readAsStringSync(), equals(_kLaunchJsonAttach));
  });

  testWithoutContext('Can update launch.json file (Attach)', () async {
    final File launchJsonFile =
        project.directory.childDirectory('.vscode').childFile('launch.json')
          ..createSync(recursive: true)
          ..writeAsStringSync(_kEmptyLaunchJson);

    updateLaunchJsonWithObservatoryInfo(
      project,
      Uri.parse('http://127.0.0.1:12345'),
    );

    expect(launchJsonFile.readAsStringSync(), equals(_kLaunchJsonAttach));
  });

  testWithoutContext('Can update launch.json file (gdb)', () async {
    final File launchJsonFile =
        project.directory.childDirectory('.vscode').childFile('launch.json')
          ..createSync(recursive: true)
          ..writeAsStringSync(_kEmptyLaunchJson);

    updateLaunchJsonWithRemoteDebuggingInfo(
      project,
      programPath: 'test_program',
      gdbPath: '/path/to/gdb',
      debugPort: 12345,
    );

    expect(launchJsonFile.readAsStringSync(), equals(r'''
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "flutter-tizen: gdb",
            "request": "launch",
            "type": "cppdbg",
            "externalConsole": "false",
            "MIMode": "gdb",
            "sourceFileMap": {},
            "cwd": "${workspaceFolder}",
            "program": "test_program",
            "miDebuggerPath": "/path/to/gdb",
            "miDebuggerServerAddress": ":12345"
        }
    ]
}'''));
  });
}
