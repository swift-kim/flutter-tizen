// Copyright 2020 Samsung Electronics Co., Ltd. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:file/file.dart';
import 'package:flutter_tools/src/android/android_emulator.dart';
import 'package:flutter_tools/src/android/android_sdk.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/context.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:meta/meta.dart';

import 'tizen_tpk.dart';

TizenSdk get tizenSdk => context.get<TizenSdk>();

File get dotnetCli => globals.os.which('dotnet');

class TizenSdk {
  TizenSdk._(this.directory);

  /// See: [AndroidSdk.locateAndroidSdk] in `android_sdk.dart`
  factory TizenSdk.locateSdk() {
    Directory tizenHomeDir;
    final Map<String, String> environment = globals.platform.environment;
    final File sdb = globals.os.which('sdb');
    if (environment.containsKey('TIZEN_SDK')) {
      tizenHomeDir = globals.fs.directory(environment['TIZEN_SDK']);
    } else if (sdb != null && sdb.parent.basename == 'tools') {
      tizenHomeDir = sdb.parent.parent;
    } else if (globals.platform.isLinux || globals.platform.isMacOS) {
      if (globals.fsUtils.homeDirPath != null) {
        tizenHomeDir = globals.fs
            .directory(globals.fsUtils.homeDirPath)
            .childDirectory('tizen-studio');
      }
    } else if (globals.platform.isWindows) {
      if (environment.containsKey('SystemDrive')) {
        tizenHomeDir = globals.fs
            .directory(environment['SystemDrive'])
            .childDirectory('tizen-studio');
      }
    }
    if (tizenHomeDir == null || !tizenHomeDir.existsSync()) {
      return null;
    }
    return TizenSdk._(tizenHomeDir);
  }

  final Directory directory;

  Directory get platformsDirectory => directory.childDirectory('platforms');

  Directory get toolsDirectory => directory.childDirectory('tools');

  Directory get sdkDataDirectory {
    final File sdkInfo = directory.childFile('sdk.info');
    if (!sdkInfo.existsSync()) {
      return null;
    }
    // ignore: invalid_use_of_visible_for_testing_member
    final Map<String, String> info = parseIniLines(sdkInfo.readAsLinesSync());
    if (info.containsKey('TIZEN_SDK_DATA_PATH')) {
      return globals.fs.directory(info['TIZEN_SDK_DATA_PATH']);
    }
    return null;
  }

  /// The SDK version number in the "x.y[.z]" format, or null if not found.
  String get sdkVersion {
    final File versionFile = directory.childFile('sdk.version');
    if (!versionFile.existsSync()) {
      return null;
    }
    final Map<String, String> info =
        // ignore: invalid_use_of_visible_for_testing_member
        parseIniLines(versionFile.readAsLinesSync());
    if (info.containsKey('TIZEN_SDK_VERSION')) {
      return info['TIZEN_SDK_VERSION'];
    }
    return null;
  }

  File get sdb =>
      toolsDirectory.childFile(globals.platform.isWindows ? 'sdb.exe' : 'sdb');

  File get tizenCli => toolsDirectory
      .childDirectory('ide')
      .childDirectory('bin')
      .childFile(globals.platform.isWindows ? 'tizen.bat' : 'tizen');

  File get emCli => toolsDirectory
      .childDirectory('emulator')
      .childDirectory('bin')
      .childFile(globals.platform.isWindows ? 'em-cli.bat' : 'em-cli');

  File get packageManagerCli => directory
      .childDirectory('package-manager')
      .childFile(globals.platform.isWindows
          ? 'package-manager-cli.exe'
          : 'package-manager-cli.bin');

  File get securityProfilesFile =>
      sdkDataDirectory.childDirectory('profile').childFile('profiles.xml');

  SecurityProfiles get securityProfiles =>
      SecurityProfiles.parseFromXml(securityProfilesFile);

  String get defaultNativeCompiler => 'llvm-10.0';

  String get defaultGccVersion => '9.2';

  Rootstrap getFlutterRootstrap({
    @required String profile,
    @required String apiVersion,
    @required String arch,
  }) {
    assert(profile != null);
    assert(apiVersion != null);

    double versionToDouble(String versionString) {
      final double version = double.tryParse(versionString);
      if (version == null) {
        throwToolExit('The API version $versionString is invalid.');
      }
      return version;
    }

    if (profile == 'common') {
      // The headless profile is not supported.
      profile = 'iot-headed';
    }
    if (profile == 'tv') {
      // Use the wearable rootstrap because the TV native rootstrap is not
      // publicly available.
      profile = 'wearable';
    }

    String type = arch == 'x86' ? 'emulator' : 'device';
    if (arch == 'arm64') {
      // The arm64 build is only supported by iot-headed-6.0+ rootstraps.
      profile = 'iot-headed';
      if (versionToDouble(apiVersion) < 6.0) {
        apiVersion = '6.0';
      }
      type = 'device64';
    }

    final String name = '$profile-$apiVersion-$type';
    final Directory rootstrapsDir = platformsDirectory
        .childDirectory('tizen-$apiVersion')
        .childDirectory(profile)
        .childDirectory('rootstraps');
    final Directory rootstrapDir = rootstrapsDir.childDirectory('$name.core');
    final File rootstrapInfo =
        rootstrapsDir.childDirectory('info').childFile('$name.core.dev.xml');
    if (!rootstrapDir.existsSync() || !rootstrapInfo.existsSync()) {
      final String profileUpperCase =
          profile.toUpperCase().replaceAll('HEADED', 'Headed');
      throwToolExit(
        'The rootstrap definition for $name could not be found.\n'
        'To install missing package(s), run:\n'
        '${packageManagerCli.path} install $profileUpperCase-$apiVersion-NativeAppDevelopment-CLI',
      );
    }

    // Tizen SBI reads rootstrap definitions from this directory.
    final Directory pluginsDir = toolsDirectory
        .childDirectory('smart-build-interface')
        .childDirectory('plugins');
    final File manifestFile = pluginsDir.childFile('flutter-rootstrap.xml');
    final String rootstrapId = '$name.flutter';
    final String buildArch = getTizenBuildArch(arch);

    // libstdc++ shipped with Tizen 4.0 and 5.5 doesn't support C++17.
    // Original PR: https://github.com/flutter-tizen/flutter-tizen/pull/106
    final List<String> linkerFlags = <String>[];
    if (versionToDouble(apiVersion) < 6.0) {
      linkerFlags.add('-static-libstdc++');
    }

    manifestFile.writeAsStringSync('''
<?xml version="1.0"?>
<extension point="rootstrapDefinition">
  <rootstrap id="$rootstrapId" name="$name" version="flutter" architecture="$buildArch" path="${rootstrapDir.path}" supportToolchainType="tizen.core">
    <property key="DEV_PACKAGE_CONFIG_PATH" value="${rootstrapInfo.path}"/>
    <property key="LINKER_MISCELLANEOUS_OPTION" value="${linkerFlags.join(' ')}"/>
    <property key="COMPILER_MISCELLANEOUS_OPTION" value=""/>
    <toolchain name="gcc" version="$defaultGccVersion"/>
  </rootstrap>
</extension>
''');

    // Remove files created by the previous versions of the flutter-tizen tool.
    final Iterable<File> manifests = pluginsDir.listSync().whereType<File>();
    for (final File file in manifests) {
      if (file.basename.endsWith('.flutter.xml')) {
        file.deleteSync();
      }
    }

    return Rootstrap(rootstrapId, manifestFile);
  }
}

/// Tizen rootstrap definition.
///
/// The rootstrap (or sysroot), which is downloaded as part of Tizen native SDK,
/// contains a set of headers and libraries required for cross building Tizen
/// native apps and libraries.
class Rootstrap {
  const Rootstrap(this.id, this.manifestFile);

  final String id;
  final File manifestFile;
}

/// Converts [targetArch] to an arch name that corresponds to the `BUILD_ARCH`
/// value used by the Tizen native builder.
String getTizenBuildArch(String targetArch) {
  switch (targetArch) {
    case 'arm':
      return 'armel';
    case 'arm64':
      return 'aarch64';
    case 'x86':
      return 'i586';
    default:
      return targetArch;
  }
}
