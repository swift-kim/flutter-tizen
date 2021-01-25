// Copyright 2021 Samsung Electronics Co., Ltd. All rights reserved.
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_tizen/commands/build.dart';
import 'package:flutter_tizen/tizen_artifacts.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:test/test.dart';

import '../../flutter/packages/flutter_tools/test/src/common.dart';
import '../../flutter/packages/flutter_tools/test/src/context.dart';

void main() {
  setUpAll(() {
    Cache.disableLocking();
  });

  group('build tpk command', () {
    FileSystem fileSystem;
    ProcessManager processManager;

    setUp(() {
      fileSystem = MemoryFileSystem.test();
    });

    // Creates the mock files necessary to look like a Flutter project.
    void setUpMockCoreProjectFiles() {
      fileSystem.file('pubspec.yaml').createSync();
      fileSystem.file('.packages').createSync();
      fileSystem
          .directory('lib')
          .childFile('main.dart')
          .createSync(recursive: true);
    }

    // Creates the mock files necessary to run a build.
    void setUpMockProjectFilesForBuild() {
      setUpMockCoreProjectFiles();
      fileSystem
          .directory('tizen')
          .childFile('Runner.csproj')
          .createSync(recursive: true);
    }

    testUsingContext(
      'Tpk build fails when there is no Tizen project',
      () async {
        final TizenBuildCommand command = TizenBuildCommand();
        setUpMockCoreProjectFiles();

        expect(
          createTestCommandRunner(command)
              .run(const <String>['build', 'tpk', '--no-pub']),
          throwsToolExit(message: 'This project is not configured for Tizen.'),
        );
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => FakeProcessManager.any(),
      },
    );

    testUsingContext(
      '?????????????',
      () async {
        final TizenBuildCommand command = TizenBuildCommand();
        setUpMockProjectFilesForBuild();
        processManager = FakeProcessManager.list(<FakeCommand>[
          FakeCommand(
            command: const <String>['dotnet', 'build', '--release'],
            // workingDirectory: 'build/?',
            onRun: () {
              throw ArgumentError();
            },
          ),
        ]);

        expect(
          createTestCommandRunner(command)
              .run(const <String>['build', 'tpk', '--no-pub']),
          throwsToolExit(message: 'what the hell'),
        );
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => processManager,
        TizenArtifacts: () => TizenArtifacts(),
      },
    );
  });
}
