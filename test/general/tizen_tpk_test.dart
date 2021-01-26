// Copyright 2021 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:file/src/interface/file.dart';
import 'package:flutter_tizen/tizen_project.dart';
import 'package:flutter_tizen/tizen_tpk.dart';
import 'package:flutter_tools/src/application_package.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/project.dart';
import 'package:mockito/mockito.dart';

import '../../flutter/packages/flutter_tools/test/src/common.dart';
import '../../flutter/packages/flutter_tools/test/src/testbed.dart';

class MockTizenTpk extends Mock implements TizenTpk {}

void main() {
  Testbed testbed;

  setUp(() {
    testbed = Testbed(overrides: <Type, Generator>{
      ApplicationPackageFactory: () => TpkFactory(),
    });
  });

  test(
    'Throws when failed to extract manifest',
    () => testbed.run(() async {
      expect(
        TizenTpk.fromTpk(globals.fs.file('app.tpk')),
        throwsToolExit(message: 'tizen-manifest.xml could not be found.'),
      );
    }),
  );

  test(
    'Returns the previously built tpk if exists',
    () => testbed.run(() async {
      final FlutterProject project = FlutterProject.current();
      final TizenProject tizenProject = TizenProject.fromFlutter(project);
      final File tpkFile = project.directory
          .childDirectory('build')
          .childDirectory('tizen')
          .childFile(tizenProject.outputTpkName)
            ..createSync(recursive: true);
      expect(
        ApplicationPackageFactory.instance
            .getPackageForPlatform(TargetPlatform.tester),
        throwsToolExit(message: 'tizen-manifest.xml could not be found.'),
      );
    }),
  );
}
