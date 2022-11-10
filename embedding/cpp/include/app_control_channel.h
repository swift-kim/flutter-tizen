// Copyright 2022 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_TIZEN_EMBEDDING_CPP_CHANNELS_APP_CONTROL_CHANNEL_H_
#define FLUTTER_TIZEN_EMBEDDING_CPP_CHANNELS_APP_CONTROL_CHANNEL_H_

#include <app.h>
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "binary_messenger_impl.h"

class AppControlChannel {
 public:
  explicit AppControlChannel(
      std::unique_ptr<flutter::BinaryMessenger> messenger) {
    method_channel_ =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            messenger.get(), "tizen/app_control_notify",
            &flutter::StandardMethodCodec::GetInstance());
  }
  ~AppControlChannel() {}

  void NotifyAppControl(app_control_h app_control) {
    // will be handled by tizen_app_control plugin
    int64_t address = reinterpret_cast<int64_t>(app_control);
    method_channel_->InvokeMethod(
        "notify", std::make_unique<flutter::EncodableValue>(address));
  }

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      method_channel_;
};

#endif /* FLUTTER_TIZEN_EMBEDDING_CPP_CHANNELS_APP_CONTROL_CHANNEL_H_ */
