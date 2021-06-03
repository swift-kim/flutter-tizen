# Writing a new plugin to use platform features

This document helps you understand how to get started with developing Flutter plugins for Tizen platform to enable platform-specific functionality. This document assumes you already have basic understanding of [how plugins are different from pure Dart packages](https://flutter.dev/docs/development/packages-and-plugins/developing-packages#types) and [how platform channels work in Flutter](https://flutter.dev/docs/development/platform-integration/platform-channels).

## Types of plugins

Flutter plugins written for Tizen can be classified into various types as follows.

### Implementation language

- C/C++ (based on platform channels)
- Dart (based on Dart FFI)

Most of Flutter plugins are written in their platform native languages, such as Java on Android and C/C++ on Linux. However, some Windows plugins like [`path_provider_windows`](https://github.com/flutter/plugins/tree/master/packages/path_provider/path_provider_windows) and Tizen plugins like [`url_launcher_tizen`](https://github.com/flutter-tizen/plugins/tree/master/packages/url_launcher) are written in Dart using [Dart FFI](https://dart.dev/guides/libraries/c-interop) without any native code. To learn more about FFI-based plugins, read [Binding to native code using dart:ffi](https://flutter.dev/docs/development/platform-integration/c-interop). This document only covers native type plugins written in Tizen's native language (C/C++).

### Targeting multiple platforms vs. Tizen only

A Flutter plugin may support more than one platforms such as Android, iOS, Tizen, Windows, and so on. Typical examples of plugins that target multiple platforms are [Flutter 1st-party plugins](https://github.com/flutter/plugins) created by the Flutter team. Most of their plugins have implementations for Android and iOS by default, and some of them are implemented for web, Windows, macOS, and Linux as well. The [federated plugins](https://flutter.dev/docs/development/packages-and-plugins/developing-packages#federated-plugins) structure is used as a modern standard when creating plugins that support various platforms. A federated plugin typically consists of an app-facing package, a **platform interface package**, and platform package(s) for each platform.

On the other hand, if necessary, you can create a plugin that only supports a single platform, e.g. [`flutter_plugin_android_lifecycle`](https://github.com/flutter/plugins/tree/master/packages/flutter_plugin_android_lifecycle) for Android and [`wearable_rotary`](https://github.com/flutter-tizen/plugins/tree/master/packages/wearable_rotary) for Tizen. Creating this type of plugin is practically not different from creating a federated plugin, except that you don't need to create multiple packages including a platform interface pacakge.

### Extending an existing plugin vs. creating a new plugin

Adding a new platform implementation to an existing federated plugin is simple: create a platform package that implements the platform interface of the target plugin. It is not strictly required for the new package to get endorsed by the original plugin author, and such package is called _unendorsed_ plugin. A developer can still use the unendorsed implementation of the plugin in their app, but must add the platform package to the app's pubspec file. For example, if there is a `foobar_tizen` implementation for the `foobar` plugin, the app's pubspec file must include both the `foobar` and `foobar_tizen` dependencies unless the original `foobar` author adds `foobar_tizen` as a dependency in the pubspec of `foobar`.

Note: Even if the original plugin is not a federated plugin (has no platform interface package), you can still create an unendorsed platform implementation of the plugin by implicitly implementing the plugin's platform channels.

Obviously, you can also create a plugin that has never existed in the world. The new plugin can be either a single package plugin or a federated plugin, depending on whether you want to target Tizen platform only or other platforms as well. The former is usually the case where the functionality that you want to implement is specific to Tizen, but not common to other platforms. 

## Creating a plugin project

If you're extending the existing `foobar` plugin for Tizen, it is common to add the `_tizen` suffix to the plugin name:

```sh
flutter-tizen create --template plugin foobar_tizen
```

Otherwise if you are creating a new plugin from scratch, pick a name that best describes the functionality while following the `lowercase_with_underscores` naming convention:

```sh
flutter-tizen create --template plugin plugin_name
```

Once the package is created, you will be prompted to 




Event channel
Method channel
Basic message channel
