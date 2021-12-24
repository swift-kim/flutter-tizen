// Copyright 2021 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tools/src/base/context.dart';

TizenDebugConfig? get tizenDebugConfig => context.get<TizenDebugConfig>();

class TizenDebugConfig {
  TizenDebugConfig();

  bool enableNativeDebugging = false;
}
