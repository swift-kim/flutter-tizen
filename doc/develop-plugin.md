# Writing a new plugin to use platform features

This document helps you understand how to get started with developing Flutter plugins for Tizen platform to enable platform-specific functionality. This document assumes you already have basic understanding of [how plugins are different from pure Dart packages](https://flutter.dev/docs/development/packages-and-plugins/developing-packages#types) and [how platform channels work in Flutter](https://flutter.dev/docs/development/platform-integration/platform-channels).

## Types of plugins

Flutter plugins for Tizen can be classified into various types as follows.

### Implementation language

- C/C++ (based on platform channels)
- Dart (based on Dart FFI)

Most of Flutter plugins are written in their platform native languages, such as Java on Android and C/C++ on Linux. However, some Windows plugins like [`path_provider_windows`](https://github.com/flutter/plugins/tree/master/packages/path_provider/path_provider_windows) and Tizen plugins like [`url_launcher_tizen`](https://github.com/flutter-tizen/plugins/tree/master/packages/url_launcher) are written in Dart using [Dart FFI](https://dart.dev/guides/libraries/c-interop) without any native code. To learn more about FFI-based plugins, read [Flutter Docs: Binding to native code using dart:ffi](https://flutter.dev/docs/development/platform-integration/c-interop). This document only covers native type plugins written in Tizen's native language (C/C++).

### Targeting multiple platforms vs. Tizen only

A Flutter plugin may support more than one platforms such as Android, iOS, Tizen, Windows, and so on. Typical examples of plugins that target multiple platforms are [Flutter 1st-party plugins](https://github.com/flutter/plugins) created by the Flutter team. Most of their plugins have implementations for Android and iOS by default, and some of them are implemented for web, Windows, macOS, and Linux as well. The [federated plugins](https://flutter.dev/docs/development/packages-and-plugins/developing-packages#federated-plugins) structure is used as a modern standard when creating plugins that support various platforms. A federated plugin typically consists of an app-facing package, a **platform interface package**, and platform package(s) for each platform.

On the other hand, if necessary, you can create a plugin that only supports a single platform, e.g. [`flutter_plugin_android_lifecycle`](https://github.com/flutter/plugins/tree/master/packages/flutter_plugin_android_lifecycle) for Android and [`wearable_rotary`](https://github.com/flutter-tizen/plugins/tree/master/packages/wearable_rotary) for Tizen. Creating this type of plugin is practically not different from creating a federated plugin, except that you don't need to create multiple packages including a platform interface pacakge.

### Extending existing plugins vs. Creating new plugins

Adding a new platform implementation to an existing federated plugin is simple: create a platform package that implements the platform interface of the target plugin. It is not strictly required for the new package to get endorsed by the original plugin author, and such package is called _unendorsed_ plugin. A developer can still use the unendorsed implementation of the plugin in their app, but must add the platform package to the app's pubspec file. For example, if there is a `foobar_tizen` implementation for the `foobar` plugin, the app's pubspec file must include both the `foobar` and `foobar_tizen` dependencies unless the original `foobar` author adds `foobar_tizen` as a dependency in the pubspec of `foobar`.

Note: Even if the original plugin is not a federated plugin (has no platform interface package), you can still create an unendorsed platform implementation of the plugin by implicitly implementing the plugin's platform channels.

Obviously, you can also create a plugin that has never existed in the world. The new plugin can be either a single package plugin or a federated plugin, depending on whether you want to target Tizen platform only or other platforms as well. The former is usually the case where the functionality that you want to implement is specific to Tizen, but not common to other platforms. 

## Create a plugin package

If you're to extend an existing `foobar` plugin for Tizen, it is common to add the `_tizen` suffix to your package name:

```sh
flutter-tizen create --template plugin foobar_tizen
```

Otherwise if you are creating a new plugin from scratch, make sure the package name is in the `lowercase_with_underscores` format:

```sh
flutter-tizen create --template plugin plugin_name
```

Once the package is created, you will be prompted to add some information to the pubspec file. Open the main `plugin_name/` directory in VS Code, locate the `pubspec.yaml` file, and replace the `some_platform:` map with `tizen:` as suggested by the tool. This information is needed by the flutter-tizen tool to find and register the plugin when building an app that depends on the plugin.

```text
The `pubspec.yaml` under the project directory must be updated to support Tizen.
Add below lines to under the `platforms:` key.

tizen:
  pluginClass: PluginNamePlugin
  fileName: plugin_name_plugin.h
```

The created package contains an example app in the `example` directory. You can run the example app by using the `flutter-tizen run` command:

```sh
$ cd plugin_name/example
$ flutter-tizen run
```

## Implement the plugin

### 1. Define the package API (.dart)

The API of the plugin package is defined in Dart code. Locate the file `lib/plugin_name.dart` in VS Code, and then you will see the `platformVersion` method defined in the plugin main class. Invoking this method will invoke the `getPlatformVersion` method through a method channel named `plugin_name`.

### 2. Add Tizen platform code (.cc)

Before getting started, it is recommended to install the [C/C++ extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode.cpptools) and add the `flutter-tizen/bin/cache/artifacts/engine/common` directory to your workspace in VS Code.

The implementation of the plugin can be found in the `tizen/src/plugin_name_plugin.cc` file. In this file, you will see:

- `PluginNamePluginRegisterWithRegistrar()`: This function is called by an app that depends on this plugin on startup to set up the `plugin_name` channel.
- `HandleMethodCall()`: This method handles the `getPlatformVersion` method and returns the result to the caller.

The result of the method call can be either:

- `Success()`: Indicates that the call completed successfully. The argument can be either empty or of the `flutter::EncodableValue` type.
- `Error()`: Indicates that the call was understood but handling failed in some way. The error can be caught as a `PlatformException` instance by the caller.
- `NotImplemented()`

Any arguments to the method call can be retrieved from the `method_call` variable. For example, if a `map<String, dynamic>` is passed from Dart code:

```dart
await _channel.invokeMethod<void>(
  'create',
  <String, dynamic>{'cameraName': name},
);
```

it can be parsed by `HandleMethodCall()` in the following way:

```cpp
template <typename T>
bool GetValueFromEncodableMap(flutter::EncodableMap &map, std::string key,
                              T &out) {
  auto iter = map.find(flutter::EncodableValue(key));
  if (iter != map.end() && !iter->second.IsNull()) {
    if (auto pval = std::get_if<T>(&iter->second)) {
      out = *pval;
      return true;
    }
  }
  return false;
}

void HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  std::string method_name = method_call.method_name();

  if (method_name == "create") {
    if (method_call.arguments()) {
      flutter::EncodableMap arguments = 
          std::get<flutter::EncodableMap>(*method_call.arguments());
      std::string camera_name;
      if (!GetValueFromEncodableMap(arguments, "cameraName", camera_name)) {
        result->Error(...);
        return;
      }
      ...
    }
  }
}
```

#### Available APIs

Types such as `flutter::MethodCall` and `flutter::EncodableValue` are defined in `cpp_client_wrapper` headers. APIs that you can use in your plugin code include:

- C++17 standards
- `cpp_client_wrapper` APIs (in `flutter-tizen/bin/cache/artifacts/engine/common/cpp_client_wrapper/include/flutter`)
- Tizen native APIs ([Wearable API references](https://docs.tizen.org/application/native/api/wearable/latest/index.html))
- External (static/shared) libraries, if any

Note that the API references for Tizen TV are not publicly available. However, most of the Tizen core APIs are common for the wearable and TV profiles, so you may refer to the wearable API references to develop plugins for TV devices.

#### Channel types

You can use not only `MethodChannel` but also other types of platform channels for sending data between Dart and native code:

- [BasicMessageChannel](https://api.flutter.dev/flutter/services/BasicMessageChannel-class.html): For asynchronous message passing.
- [EventChannel](https://api.flutter.dev/flutter/services/EventChannel-class.html): For asynchronous event streaming.

## Publish the plugin

You can share your plugin with other developers by publishing it on pub.dev. Refer to these pages for detailed instructions:

- [Flutter Docs: Publishing your package](https://flutter.dev/docs/development/packages-and-plugins/developing-packages#publish)
- [Dart Docs: Publishing packages](https://dart.dev/tools/pub/publishing)

You can use `flutter-tizen pub` instead of `flutter pub` if `flutter` is not in your PATH.
