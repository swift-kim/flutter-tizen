// Copyright 2021 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/build_info.dart';

/// The define to control which Tizen device is built for.
const String kDeviceProfile = 'DeviceProfile';

/// Whether to allow debugging of the output binaries.
const String kEnableNativeDebugging = 'EnableNativeDebugging';

/// See: [AndroidBuildInfo] in `build_info.dart`
class TizenBuildInfo {
  const TizenBuildInfo(
    this.buildInfo, {
    required this.targetArch,
    required this.deviceProfile,
    this.securityProfile,
  });

  final BuildInfo buildInfo;
  final String targetArch;
  final String deviceProfile;
  final String? securityProfile;
}
