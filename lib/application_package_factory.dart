// Copyright 2020 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:file/file.dart';
import 'package:flutter_tools/src/application_package.dart';
import 'package:flutter_tools/src/flutter_application_package.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/project.dart';

import 'tizen/application_package.dart';

/// [FlutterApplicationPackageFactory] extended for Tizen.
class TizenApplicationPackageFactory extends FlutterApplicationPackageFactory {
  TizenApplicationPackageFactory()
      : super(
          androidSdk: globals.androidSdk,
          processManager: globals.processManager,
          logger: globals.logger,
          userMessages: globals.userMessages,
          fileSystem: globals.fs,
        );

  @override
  Future<ApplicationPackage> getPackageForPlatform(
    TargetPlatform platform, {
    BuildInfo buildInfo,
    File applicationBinary,
  }) async {
    if (platform == TargetPlatform.tester) {
      return applicationBinary == null
          ? await TizenTpk.fromTizenProject(FlutterProject.current())
          : await TizenTpk.fromTpk(applicationBinary);
    }
    return super.getPackageForPlatform(platform,
        buildInfo: buildInfo, applicationBinary: applicationBinary);
  }
}
