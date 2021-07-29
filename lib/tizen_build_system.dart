// Copyright 2021 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:file/file.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/build_system/build_system.dart';
import 'package:flutter_tools/src/build_system/targets/localizations.dart';
import 'package:flutter_tools/src/resident_runner.dart';
import 'package:meta/meta.dart';

import 'build_targets/plugins.dart';

class TizenBuildSystem extends FlutterBuildSystem {
  const TizenBuildSystem({
    @required FileSystem fileSystem,
    @required Platform platform,
    @required Logger logger,
  }) : super(
          fileSystem: fileSystem,
          platform: platform,
          logger: logger,
        );

  /// See: [ResidentRunner.runSourceGenerators] in `resident_runner.dart`
  @override
  Future<BuildResult> buildIncremental(
    Target target,
    Environment environment,
    BuildResult previousBuild,
  ) {
    // TODO: Check if the incremental build works on hot restart.
    // TODO: Update this later (replace DartPluginRegistrantTarget with TizenDartPluginRegistrant).
    if (target is GenerateLocalizationsTarget) {
      target = CompositeTarget(<Target>[
        target,
        const DartPluginRegistrant(),
      ]);
    }
    return super.buildIncremental(target, environment, previousBuild);
  }
}
