// Copyright 2020 Samsung Electronics Co., Ltd. All rights reserved.
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/os.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/base/version.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/project.dart';
import 'package:meta/meta.dart';

import 'tizen_plugins.dart';
import 'tizen_tpk.dart';

/// Source: [WindowsProject] in `project.dart`
class TizenProject extends FlutterProjectPlatform {
  TizenProject.fromFlutter(this.parent);

  final FlutterProject parent;

  @override
  String get pluginConfigKey => TizenPlugin.kConfigKey;

  Directory get editableDirectory => parent.directory.childDirectory('tizen');

  /// The directory in the project that is managed by Flutter. As much as
  /// possible, files that are edited by Flutter tooling after initial project
  /// creation should live here.
  Directory get managedDirectory => editableDirectory.childDirectory('flutter');

  /// The subdirectory of [managedDirectory] that contains files that are
  /// generated on the fly. All generated files that are not intended to be
  /// checked in should live here.
  Directory get ephemeralDirectory =>
      managedDirectory.childDirectory('ephemeral');

  bool get isDotnet =>
      editableDirectory.childFile('Runner.csproj').existsSync();

  File get projectFile => editableDirectory
      .childFile(isDotnet ? 'Runner.csproj' : 'project_def.prop');

  @override
  bool existsSync() =>
      editableDirectory.existsSync() && projectFile.existsSync();

  File get manifestFile => editableDirectory.childFile('tizen-manifest.xml');

  String get apiVersion => TizenManifest.parseFromXml(manifestFile).apiVersion;

  String get outputTpkName {
    final TizenManifest manifest = TizenManifest.parseFromXml(manifestFile);
    return '${manifest.packageId}-${manifest.version}.tpk';
  }

  Future<void> ensureReadyForPlatformSpecificTooling() async {
    if (isDotnet) {
      // Create a symlink to the embedidng (Tizen.Flutter.Embedding) directory
      // for reference by the app project. See Runner.csproj for details.
      final Link embeddingLink = managedDirectory.childLink('embedding');
      if (!embeddingLink.existsSync()) {
        final Directory embeddingDir = globals.fs
            .directory(Cache.flutterRoot)
            .parent
            .childDirectory('embedding')
            .childDirectory('csharp');
        try {
          embeddingLink.createSync(embeddingDir.path, recursive: true);
        } on FileSystemException catch (e) {
          handleSymlinkException(e, platform: globals.platform, os: globals.os);
        }
      }
    }
  }
}

/// Handler for symlink failures which provides specific instructions for known
/// failure cases.
///
/// Source: [handleSymlinkException] in `plugins.dart` (exact copy)
void handleSymlinkException(
  FileSystemException e, {
  @required Platform platform,
  @required OperatingSystemUtils os,
}) {
  if (platform.isWindows && (e.osError?.errorCode ?? 0) == 1314) {
    final String versionString =
        RegExp(r'[\d.]+').firstMatch(os.name)?.group(0);
    final Version version = Version.parse(versionString);
    // Windows 10 14972 is the oldest version that allows creating symlinks
    // just by enabling developer mode; before that it requires running the
    // terminal as Administrator.
    // https://blogs.windows.com/windowsdeveloper/2016/12/02/symlinks-windows-10/
    final String instructions =
        (version != null && version >= Version(10, 0, 14972))
            ? 'Please enable Developer Mode in your system settings. Run\n'
                '  start ms-settings:developers\n'
                'to open settings.'
            : 'You must build from a terminal run as administrator.';
    throwToolExit(
      'Building a Tizen project requires symlink support.\n\n' + instructions,
    );
  }
}

/// Used for parsing native plugin's `project_def.prop`.
class TizenLibrary {
  TizenLibrary(this.path);

  final String path;

  Directory get directory => globals.fs.directory(path).absolute;

  File get projectFile => directory.childFile('project_def.prop');

  bool get isValid => projectFile.existsSync();

  final RegExp _propertyFormat = RegExp(r'(\S+)\s*\+?=(.*)');

  Map<String, String> _properties;

  String getProperty(String key) {
    if (_properties == null) {
      if (!isValid) {
        return null;
      }
      _properties = <String, String>{};

      for (final String line in projectFile.readAsLinesSync()) {
        final Match match = _propertyFormat.firstMatch(line);
        if (match == null) {
          continue;
        }
        final String key = match.group(1);
        final String value = match.group(2).trim();
        _properties[key] = value;
      }
    }
    return _properties.containsKey(key) ? _properties[key] : null;
  }

  List<String> getPropertyAsAbsolutePaths(String key) {
    final String property = getProperty(key);
    if (property == null) {
      return <String>[];
    }

    final List<String> paths = <String>[];
    for (final String element in property.split(' ')) {
      if (globals.fs.path.isAbsolute(element)) {
        paths.add(element);
      } else {
        paths.add(globals.fs.path
            .normalize(globals.fs.path.join(directory.path, element)));
      }
    }
    return paths;
  }
}
