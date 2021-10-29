// Copyright 2021 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:file/memory.dart';
import 'package:flutter_tizen/tizen_sdk.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:test/fake.dart';

class FakeTizenSdk extends Fake implements TizenSdk {
  FakeTizenSdk({FileSystem fileSystem})
      : _fileSystem = fileSystem ?? MemoryFileSystem.test();

  final FileSystem _fileSystem;

  @override
  File get sdb => _fileSystem.file('sdb')..createSync();

  @override
  File get tizenCli => _fileSystem.file('tizen-cli')..createSync();
}
