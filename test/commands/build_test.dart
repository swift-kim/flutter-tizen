// Copyright 2021 Samsung Electronics Co., Ltd. All rights reserved.
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_tizen/commands/build.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:test/test.dart';

import '../src/common.dart';
import '../src/context.dart';

void main() {
  setUpAll(() {
    Cache.disableLocking();
  });

  group('build tpk command', () {
    FileSystem fileSystem;

    setUp(() {
      fileSystem = MemoryFileSystem.test();
    });

    // Creates the mock files necessary to look like a Flutter project.
    void setUpMockCoreProjectFiles() {
      fileSystem.file('pubspec.yaml').createSync();
      fileSystem.file('.packages').createSync();
      fileSystem
          .file(fileSystem.path.join('lib', 'main.dart'))
          .createSync(recursive: true);
    }

    testUsingContext('Tpk build fails when there is no Tizen project',
        () async {
      final TizenBuildCommand command = TizenBuildCommand();
      setUpMockCoreProjectFiles();

      expect(
          createTestCommandRunner(command)
              .run(const <String>['build', 'tpk', '--no-pub']),
          throwsToolExit(message: 'This project is not configured for Tizen.'));
    }, overrides: <Type, Generator>{
      FileSystem: () => fileSystem,
      ProcessManager: () => FakeProcessManager.any(),
    });
  });
}
