// Copyright 2020 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:flutter_tools/src/android/android_studio_validator.dart';
import 'package:flutter_tools/src/doctor.dart';
import 'package:flutter_tools/src/doctor_validator.dart';

import 'tizen/tizen_workflow.dart';

/// See: [_DefaultDoctorValidatorsProvider] in `doctor.dart`
class TizenDoctorValidatorsProvider extends DoctorValidatorsProvider {
  @override
  List<DoctorValidator> get validators {
    final List<DoctorValidator> validators =
        DoctorValidatorsProvider.defaultInstance.validators;
    for (final DoctorValidator validator in validators) {
      // Append before any IDE validators.
      if (validator is AndroidStudioValidator ||
          validator is NoAndroidStudioValidator) {
        validators.insert(validators.indexOf(validator), tizenValidator);
        break;
      }
    }
    return validators;
  }

  @override
  List<Workflow> get workflows => <Workflow>[
        ...DoctorValidatorsProvider.defaultInstance.workflows,
        tizenWorkflow,
      ];
}
