// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "include/binary_messenger_impl.h"

#include <cassert>
#include <iostream>
#include <variant>

namespace flutter {

// ========== binary_messenger_impl.h ==========

namespace {
// Passes |message| to |user_data|, which must be a BinaryMessageHandler, along
// with a BinaryReply that will send a response on |message|'s response handle.
//
// This serves as an adaptor between the function-pointer-based message callback
// interface provided by the C API and the std::function-based message handler
// interface of BinaryMessenger.
void ForwardToHandler(FlutterDesktopMessengerRef messenger,
                      const FlutterDesktopMessage* message, void* user_data) {
  auto* response_handle = message->response_handle;
  BinaryReply reply_handler = [messenger, response_handle](
                                  const uint8_t* reply,
                                  size_t reply_size) mutable {
    if (!response_handle) {
      std::cerr << "Error: Response can be set only once. Ignoring "
                   "duplicate response."
                << std::endl;
      return;
    }
    FlutterDesktopMessengerSendResponse(messenger, response_handle, reply,
                                        reply_size);
    // The engine frees the response handle once
    // FlutterDesktopSendMessageResponse is called.
    response_handle = nullptr;
  };

  const BinaryMessageHandler& message_handler =
      *static_cast<BinaryMessageHandler*>(user_data);

  message_handler(message->message, message->message_size,
                  std::move(reply_handler));
}
}  // namespace

BinaryMessengerImpl::BinaryMessengerImpl(
    FlutterDesktopMessengerRef core_messenger)
    : messenger_(core_messenger) {}

BinaryMessengerImpl::~BinaryMessengerImpl() = default;

void BinaryMessengerImpl::Send(const std::string& channel,
                               const uint8_t* message, size_t message_size,
                               BinaryReply reply) const {
  if (reply == nullptr) {
    FlutterDesktopMessengerSend(messenger_, channel.c_str(), message,
                                message_size);
    return;
  }
  struct Captures {
    BinaryReply reply;
  };
  auto captures = new Captures();
  captures->reply = reply;

  auto message_reply = [](const uint8_t* data, size_t data_size,
                          void* user_data) {
    auto captures = reinterpret_cast<Captures*>(user_data);
    captures->reply(data, data_size);
    delete captures;
  };
  bool result = FlutterDesktopMessengerSendWithReply(
      messenger_, channel.c_str(), message, message_size, message_reply,
      captures);
  if (!result) {
    delete captures;
  }
}

void BinaryMessengerImpl::SetMessageHandler(const std::string& channel,
                                            BinaryMessageHandler handler) {
  if (!handler) {
    handlers_.erase(channel);
    FlutterDesktopMessengerSetCallback(messenger_, channel.c_str(), nullptr,
                                       nullptr);
    return;
  }
  // Save the handler, to keep it alive.
  handlers_[channel] = std::move(handler);
  BinaryMessageHandler* message_handler = &handlers_[channel];
  // Set an adaptor callback that will invoke the handler.
  FlutterDesktopMessengerSetCallback(messenger_, channel.c_str(),
                                     ForwardToHandler, message_handler);
}

}  // namespace flutter
