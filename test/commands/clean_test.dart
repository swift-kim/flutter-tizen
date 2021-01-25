// Copyright 2021 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_tizen/commands/clean.dart';
import 'package:flutter_tizen/tizen_project.dart';
import 'package:flutter_tools/src/project.dart';
import 'package:test/test.dart';

import '../../flutter/packages/flutter_tools/test/src/context.dart';

void main() {
  group('clean command', () {
    MemoryFileSystem fileSystem;
    TizenProject tizenProject;

    setUp(() {
      fileSystem = MemoryFileSystem();

      final Directory currentDirectory = fileSystem.currentDirectory;
      tizenProject = TizenProject.fromFlutter(
          FlutterProject.fromDirectory(currentDirectory));
      tizenProject.ephemeralDirectory.createSync(recursive: true);
      tizenProject.editableDirectory
          .childFile('Runner.csproj')
          .createSync(recursive: true);
      tizenProject.editableDirectory
          .childDirectory('bin')
          .createSync(recursive: true);
    });

    testUsingContext(
      '$TizenCleanCommand removes ephemeral directories',
      () async {
        await TizenCleanCommand().runCommand();

        expect(tizenProject.ephemeralDirectory.existsSync(), isFalse);
        expect(
          tizenProject.editableDirectory.childDirectory('bin').existsSync(),
          isFalse,
        );
      },
      overrides: <Type, Generator>{
        FileSystem: () => fileSystem,
        ProcessManager: () => FakeProcessManager.any(),
      },
    );
  });
}
