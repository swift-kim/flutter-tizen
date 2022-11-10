// Copyright 2021 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "include/flutter_app.h"

#include <flutter/binary_messenger.h>

#include <cassert>

#include "tizen_log.h"

bool FlutterApp::OnCreate() {
  TizenLog::Debug("Launching a Flutter application...");

  engine_ = FlutterEngine::Create(dart_entrypoint_);
  if (!engine_) {
    TizenLog::Error("Could not create a Flutter engine.");
    return false;
  }

#ifdef WEARABLE_PROFILE
  if (renderer_type_ == FlutterRendererType::kEGL) {
    TizenLog::Error(
        "FlutterRendererType::kEGL is not supported by this profile.");
    return false;
  }
#endif

  FlutterDesktopWindowProperties window_prop = {};
  window_prop.x = window_offset_x_;
  window_prop.y = window_offset_y_;
  window_prop.width = window_width_;
  window_prop.height = window_height_;
  window_prop.transparent = is_window_transparent_;
  window_prop.focusable = is_window_focusable_;
  window_prop.top_level = is_top_level_;
  window_prop.renderer_type =
      static_cast<FlutterDesktopRendererType>(renderer_type_);

  view_ = FlutterDesktopViewCreateFromNewWindow(window_prop,
                                                engine_->RelinquishEngine());
  if (!view_) {
    TizenLog::Error("Could not launch a Flutter application.");
    return false;
  }

  std::unique_ptr<flutter::BinaryMessenger> messenger =
      std::make_unique<flutter::BinaryMessengerImpl>(engine_->GetMessenger());
  app_control_channel_ =
      std::make_unique<AppControlChannel>(std::move(messenger));

  return true;
}

void FlutterApp::OnResume() {
  assert(IsRunning());
  engine_->NotifyAppIsResumed();
}

void FlutterApp::OnPause() {
  assert(IsRunning());
  engine_->NotifyAppIsPaused();
}

void FlutterApp::OnTerminate() {
  assert(IsRunning());
  FlutterDesktopViewDestroy(view_);
  engine_ = nullptr;
  view_ = nullptr;
}

void FlutterApp::OnAppControlReceived(app_control_h app_control) {
  assert(IsRunning());
  app_control_channel_->NotifyAppControl(app_control);
}

void FlutterApp::OnLowMemory(app_event_info_h event_info) {
  assert(IsRunning());
  engine_->NotifyLowMemoryWarning();
}

void FlutterApp::OnLanguageChanged(app_event_info_h event_info) {
  assert(IsRunning());
  engine_->NotifyLocaleChange();
}

void FlutterApp::OnRegionFormatChanged(app_event_info_h event_info) {
  assert(IsRunning());
  engine_->NotifyLocaleChange();
}

int FlutterApp::Run(int argc, char **argv) {
  ui_app_lifecycle_callback_s lifecycle_cb = {};
  lifecycle_cb.create = [](void *data) -> bool {
    auto *app = reinterpret_cast<FlutterApp *>(data);
    return app->OnCreate();
  };
  lifecycle_cb.resume = [](void *data) {
    auto *app = reinterpret_cast<FlutterApp *>(data);
    app->OnResume();
  };
  lifecycle_cb.pause = [](void *data) {
    auto *app = reinterpret_cast<FlutterApp *>(data);
    app->OnPause();
  };
  lifecycle_cb.terminate = [](void *data) {
    auto *app = reinterpret_cast<FlutterApp *>(data);
    app->OnTerminate();
  };
  lifecycle_cb.app_control = [](app_control_h app_control, void *data) {
    auto *app = reinterpret_cast<FlutterApp *>(data);
    app->OnAppControlReceived(app_control);
  };

  app_event_handler_h handler;
  ui_app_add_event_handler(
      &handler, APP_EVENT_LOW_MEMORY,
      [](app_event_info_h event, void *data) {
        auto *app = reinterpret_cast<FlutterApp *>(data);
        app->OnLowMemory(event);
      },
      this);
  ui_app_add_event_handler(
      &handler, APP_EVENT_LOW_BATTERY,
      [](app_event_info_h event, void *data) {
        auto *app = reinterpret_cast<FlutterApp *>(data);
        app->OnLowBattery(event);
      },
      this);
  ui_app_add_event_handler(
      &handler, APP_EVENT_LANGUAGE_CHANGED,
      [](app_event_info_h event, void *data) {
        auto *app = reinterpret_cast<FlutterApp *>(data);
        app->OnLanguageChanged(event);
      },
      this);
  ui_app_add_event_handler(
      &handler, APP_EVENT_REGION_FORMAT_CHANGED,
      [](app_event_info_h event, void *data) {
        auto *app = reinterpret_cast<FlutterApp *>(data);
        app->OnRegionFormatChanged(event);
      },
      this);
  ui_app_add_event_handler(
      &handler, APP_EVENT_DEVICE_ORIENTATION_CHANGED,
      [](app_event_info_h event, void *data) {
        auto *app = reinterpret_cast<FlutterApp *>(data);
        app->OnDeviceOrientationChanged(event);
      },
      this);

  int ret = ui_app_main(argc, argv, &lifecycle_cb, this);
  if (ret != APP_ERROR_NONE) {
    TizenLog::Error("Could not launch an application. (%d)", ret);
  }
  return ret;
}

FlutterDesktopPluginRegistrarRef FlutterApp::GetRegistrarForPlugin(
    const std::string &plugin_name) {
  if (engine_) {
    return engine_->GetRegistrarForPlugin(plugin_name);
  }
  return nullptr;
}
