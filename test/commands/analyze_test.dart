// Copyright 2021 Samsung Electronics Co., Ltd. All rights reserved.
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/file.dart';
import 'package:flutter_tizen/commands/analyze.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/base/terminal.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/runner/flutter_command_runner.dart';
import 'package:process/process.dart';
import 'package:test/test.dart';

import '../../flutter/packages/flutter_tools/test/commands.shard/permeable/analyze_once_test.dart';
import '../../flutter/packages/flutter_tools/test/src/common.dart';
import '../../flutter/packages/flutter_tools/test/src/context.dart';

void main() {
  FileSystem fileSystem;
  BufferLogger logger;
  AnsiTerminal terminal;
  Directory tempDir;
  Directory projectDir;
  File libMain;

  setUp(() {
    Cache.disableLocking();
    Cache.flutterRoot = FlutterCommandRunner.defaultFlutterRoot;
    fileSystem = LocalFileSystem.instance;
    terminal = AnsiTerminal(platform: const LocalPlatform(), stdio: Stdio());
    logger = BufferLogger(
      outputPreferences: OutputPreferences.test(),
      terminal: terminal,
    );

    tempDir = fileSystem.systemTempDirectory
        .createTempSync('flutter_analyze_once_test_1.')
        .absolute;
    projectDir = tempDir.childDirectory('flutter_project');
    projectDir.childFile('pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync(pubspecYamlSrc);
    final StringBuffer flutterRootUri = StringBuffer('file://');
    final String canonicalizedFlutterRootPath =
        fileSystem.path.canonicalize(Cache.flutterRoot);
    flutterRootUri.write(canonicalizedFlutterRootPath);
    final String dotPackagesSrc = '''# Generated
flutter:$flutterRootUri/packages/flutter/lib/
sky_engine:$flutterRootUri/bin/cache/pkg/sky_engine/lib/
flutter_project:lib/
''';
    projectDir.childFile('.packages')
      ..createSync(recursive: true)
      ..writeAsStringSync(dotPackagesSrc);
    libMain = projectDir.childDirectory('lib').childFile('main.dart')
      ..createSync(recursive: true)
      // ..writeAsStringSync('abcde');
      ..writeAsStringSync(mainDartSrc);
  });

  tearDown(() {
    tryToDelete(tempDir);
  });

  testUsingContext('working directory', () async {
    final TizenAnalyzeCommand command = TizenAnalyzeCommand(
      workingDirectory: fileSystem.directory(projectDir.path),
    );

    try {
      await createTestCommandRunner(command).run(<String>[
        'analyze',
        '--no-pub',
        '--flutter-root=${Cache.flutterRoot}',
        libMain.path,
      ]);
    } on ToolExit catch (e) {
      expect(e.message, isEmpty);
    }
    expect(logger.statusText, contains('No issues found!'));
    expect(logger.errorText, isEmpty);

    logger.clear();
  }, overrides: <Type, Generator>{
    FileSystem: () => fileSystem,
    ProcessManager: () => const LocalProcessManager(),
    Terminal: () => terminal,
    Logger: () => logger,
  });
}
