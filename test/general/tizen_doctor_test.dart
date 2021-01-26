// Copyright 2021 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_tizen/tizen_doctor.dart';
import 'package:flutter_tools/src/doctor.dart';

import '../../flutter/packages/flutter_tools/test/src/common.dart';
import '../../flutter/packages/flutter_tools/test/src/testbed.dart';

void main() {
  Testbed testbed;

  setUp(() {
    testbed = Testbed(overrides: <Type, Generator>{
      DoctorValidatorsProvider: () => TizenDoctorValidatorsProvider(),
      TizenWorkflow: () => TizenWorkflow(),
      TizenValidator: () => TizenValidator(),
    });
  });

  test(
    'doctor validators includes a Tizen validator',
    () => testbed.run(() {
      expect(
        DoctorValidatorsProvider.instance.validators,
        contains(isA<TizenValidator>()),
      );
    }),
  );

  test(
    '$TizenValidator validation fails if Tizen SDK is not installed',
    () => testbed.run(() async {
      expect(
        await tizenValidator.validate(),
        (ValidationResult r) => r.type == ValidationType.missing,
      );
    }),
  );
}
