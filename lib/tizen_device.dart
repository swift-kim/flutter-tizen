// Copyright 2020 Samsung Electronics Co., Ltd. All rights reserved.
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';
import 'package:flutter_tools/src/android/android_device.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/base/process.dart';
import 'package:flutter_tools/src/base/terminal.dart';
import 'package:flutter_tools/src/base/version.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/convert.dart';
import 'package:flutter_tools/src/device.dart';
import 'package:flutter_tools/src/device_port_forwarder.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/project.dart';
import 'package:flutter_tools/src/protocol_discovery.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart';
import 'package:process/process.dart';

import 'forwarding_log_reader.dart';
import 'tizen_build_info.dart';
import 'tizen_builder.dart';
import 'tizen_sdk.dart';
import 'tizen_tpk.dart';
import 'vscode_helper.dart';

/// Tizen device implementation.
///
/// See: [AndroidDevice] in `android_device.dart`
class TizenDevice extends Device {
  TizenDevice(
    String id, {
    required String modelId,
    required Logger logger,
    required Platform platform,
    required TizenSdk tizenSdk,
    required FileSystem fileSystem,
    required ProcessManager processManager,
  })  : _modelId = modelId,
        _logger = logger,
        _platform = platform,
        _tizenSdk = tizenSdk,
        _fileSystem = fileSystem,
        _processManager = processManager,
        _processUtils =
            ProcessUtils(logger: logger, processManager: processManager),
        super(id,
            category: Category.mobile,
            platformType: PlatformType.custom,
            ephemeral: true);

  static bool nativeDebuggingEnabled = false;

  final String _modelId;
  final Logger _logger;
  final Platform _platform;
  final TizenSdk _tizenSdk;
  final FileSystem _fileSystem;
  final ProcessManager _processManager;
  final ProcessUtils _processUtils;

  Map<String, String>? _capabilities;
  DeviceLogReader? _logReader;
  DevicePortForwarder? _portForwarder;

  List<String> _sdbCommand(List<String> args) {
    return <String>[_tizenSdk.sdb.path, '-s', id, ...args];
  }

  RunResult runSdbSync(
    List<String> params, {
    bool checked = true,
  }) {
    return _processUtils.runSync(_sdbCommand(params), throwOnError: checked);
  }

  /// See: [AndroidDevice.runAdbCheckedAsync] in `android_device.dart`
  Future<RunResult> runSdbAsync(
    List<String> params, {
    bool checked = true,
  }) async {
    return _processUtils.run(_sdbCommand(params), throwOnError: checked);
  }

  String getCapability(String name) {
    if (_capabilities == null) {
      final String stdout = runSdbSync(<String>['capability']).stdout.trim();

      final Map<String, String> capabilities = <String, String>{};
      for (final String line in LineSplitter.split(stdout)) {
        final List<String> splitLine = line.trim().split(':');
        if (splitLine.length >= 2) {
          capabilities[splitLine[0]] = splitLine[1];
        }
      }
      _capabilities = capabilities;
    }
    if (!_capabilities!.containsKey(name)) {
      throwToolExit(
          'Failed to read the $name capability value from device $id.');
    }
    return _capabilities![name]!;
  }

  bool get _isLocalEmulator => getCapability('cpu_arch') == 'x86';

  @override
  Future<bool> get isLocalEmulator async => _isLocalEmulator;

  @override
  Future<String?> get emulatorId async => _isLocalEmulator ? _modelId : null;

  @override
  Future<TargetPlatform> get targetPlatform async {
    // Use tester as a platform identifer for Tizen.
    // There's currently no other choice because getNameForTargetPlatform()
    // throws an error for unknown platform types.
    return TargetPlatform.tester;
  }

  @override
  Future<bool> supportsRuntimeMode(BuildMode buildMode) async {
    if (_isLocalEmulator) {
      return buildMode == BuildMode.debug;
    } else {
      return buildMode != BuildMode.jitRelease;
    }
  }

  late final String _platformVersion = () {
    final String version = getCapability('platform_version');

    // Truncate if the version string has more than 3 segments.
    final List<String> segments = version.split('.');
    if (segments.length > 3) {
      return segments.sublist(0, 3).join('.');
    }
    return version;
  }();

  @override
  Future<String> get sdkNameAndVersion async => 'Tizen $_platformVersion';

  @override
  String get name => 'Tizen $_modelId';

  String get deviceProfile => getCapability('profile_name');

  bool get usesSecureProtocol => getCapability('secure_protocol') == 'enabled';

  late final String architecture = () {
    final String cpuArch = getCapability('cpu_arch');
    if (_isLocalEmulator) {
      return cpuArch;
    } else if (usesSecureProtocol) {
      return cpuArch == 'armv7' ? 'arm' : 'arm64';
    } else {
      // Reading the cpu_arch capability value is not a reliable way to get the
      // runtime architecture from devices like Raspberry Pi. The following is a
      // little workaround.
      final String stdout =
          runSdbSync(<String>['shell', 'ls', '/usr/lib64']).stdout;
      return stdout.contains('No such file or directory') ? 'arm' : 'arm64';
    }
  }();

  /// See: [AndroidDevice.isAppInstalled] in `android_device.dart`
  @override
  Future<bool> isAppInstalled(TizenTpk app, {String? userIdentifier}) async {
    try {
      final List<String> command = usesSecureProtocol
          ? <String>['shell', '0', 'applist']
          : <String>['shell', 'app_launcher', '-l'];
      final RunResult result = await runSdbAsync(command);
      return result.stdout.contains("'${app.applicationId}'");
    } on Exception catch (error) {
      _logger.printError(error.toString());
      return false;
    }
  }

  Future<String?> _getDeviceAppSignature(TizenTpk app) async {
    final List<String> rootCandidates = <String>[
      '/opt/usr/apps',
      '/opt/usr/globalapps',
    ];
    for (final String root in rootCandidates) {
      final File signatureFile = _fileSystem.systemTempDirectory
          .createTempSync()
          .childFile('author-signature.xml');
      final RunResult result = await runSdbAsync(
        <String>[
          'pull',
          '$root/${app.id}/${signatureFile.basename}',
          signatureFile.path,
        ],
        checked: false,
      );
      if (result.exitCode == 0 && signatureFile.existsSync()) {
        final Signature? signature = Signature.parseFromXml(signatureFile);
        return signature?.signatureValue;
      }
    }
    return null;
  }

  /// Source: [AndroidDevice.isLatestBuildInstalled] in `android_device.dart`
  @override
  Future<bool> isLatestBuildInstalled(TizenTpk app) async {
    final String? installed = await _getDeviceAppSignature(app);
    return installed != null && installed == app.signature?.signatureValue;
  }

  /// Source: [AndroidDevice.installApp] in `android_device.dart`
  @override
  Future<bool> installApp(TizenTpk app, {String? userIdentifier}) async {
    final bool wasInstalled = await isAppInstalled(app);
    if (wasInstalled) {
      if (await isLatestBuildInstalled(app)) {
        _logger.printStatus('Latest build already installed.');
        return true;
      }
    }
    final bool isTvEmulator = usesSecureProtocol && _isLocalEmulator;
    _logger.printTrace('Installing TPK.');
    if (await _installApp(app, installTwice: !wasInstalled && isTvEmulator)) {
      return true;
    }
    _logger.printTrace('Warning: Failed to install TPK.');
    if (!wasInstalled) {
      return false;
    }
    _logger.printStatus('Uninstalling old version...');
    if (!await uninstallApp(app)) {
      _logger.printError('Error: Uninstalling old version failed.');
      return false;
    }
    if (!await _installApp(app, installTwice: isTvEmulator)) {
      _logger.printError('Error: Failed to install TPK again.');
      return false;
    }
    return true;
  }

  /// Set [installTwice] to `true` when installing TPK onto a TV emulator.
  /// On TV emulator, an app must be installed twice if it's being installed
  /// for the first time in order to prevent library loading error.
  /// Issue: https://github.com/flutter-tizen/flutter-tizen/issues/50
  ///
  /// See: [AndroidDevice._installApp] in `android_device.dart`
  Future<bool> _installApp(TizenTpk app, {bool installTwice = false}) async {
    if (!app.file.existsSync()) {
      _logger.printError('"${relative(app.file.path)}" does not exist.');
      return false;
    }

    final Version? platformVersion = Version.parse(_platformVersion);
    final Version? apiVersion = Version.parse(app.manifest.apiVersion);
    if (platformVersion != null &&
        apiVersion != null &&
        apiVersion > platformVersion) {
      _logger.printStatus(
        'Warning: The package API version ($apiVersion) is greater than the device API version ($platformVersion).\n'
        'Check "tizen-manifest.xml" of your Tizen project to fix this problem.',
        color: TerminalColor.yellow,
      );
    }

    final Status status =
        _logger.startProgress('Installing ${relative(app.file.path)}...');
    final RunResult result =
        await runSdbAsync(<String>['install', app.file.path], checked: false);
    if (result.exitCode != 0 ||
        result.stdout.contains('val[fail]') ||
        result.stdout.contains('install failed')) {
      status.stop();
      _logger.printError('Installing TPK failed:\n$result');
      return false;
    }
    if (installTwice) {
      await runSdbAsync(<String>['install', app.file.path], checked: false);
    }
    status.stop();

    if (usesSecureProtocol) {
      // It seems some post processing is done asynchronously after installing
      // an app. We need to put a short delay to avoid launch errors.
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return true;
  }

  @override
  Future<bool> uninstallApp(TizenTpk app, {String? userIdentifier}) async {
    final RunResult result =
        await runSdbAsync(<String>['uninstall', app.id], checked: false);
    if (result.exitCode != 0 || !result.stdout.contains('val[ok]')) {
      _logger.printError('sdb uninstall failed:\n$result');
      return false;
    }
    return true;
  }

  Future<void> _writeEngineArguments(
    List<String> arguments,
    String filename,
  ) async {
    final File localFile =
        _fileSystem.systemTempDirectory.createTempSync().childFile(filename);
    localFile.writeAsStringSync(arguments.join('\n'));
    final String remotePath = '/home/owner/share/tmp/sdk_tools/$filename';
    final RunResult result =
        await runSdbAsync(<String>['push', localFile.path, remotePath]);
    if (!result.stdout.contains('file(s) pushed')) {
      _logger.printError('Failed to push a file: $result');
    }
  }

  Future<bool> _installGdbServer() async {
    final Version? platformVersion = Version.parse(_platformVersion);
    String gdbServerVersion = '8.3.1';
    if (platformVersion != null && platformVersion < Version(6, 0, 0)) {
      gdbServerVersion = '7.8.1';
    }
    final String arch = getTizenBuildArch(architecture, platformVersion);
    final String tarName = 'gdbserver_${gdbServerVersion}_$arch.tar';
    final File tarArchive =
        _tizenSdk.toolsDirectory.childDirectory('on-demand').childFile(tarName);
    if (!tarArchive.existsSync()) {
      _logger.printError('The file ${tarArchive.path} could not be found.');
      return false;
    }
    _logger.printTrace('Installing $tarName to $name.');

    const String sdkToolsPath = '/home/owner/share/tmp/sdk_tools';
    final String remoteArchivePath = '$sdkToolsPath/$tarName';
    try {
      final RunResult mkdirResult = await runSdbAsync(<String>[
        'shell',
        'mkdir',
        '-p',
        sdkToolsPath,
      ]);
      if (mkdirResult.stdout.isNotEmpty) {
        mkdirResult.throwException(mkdirResult.stdout);
      }
      final RunResult pushResult = await runSdbAsync(<String>[
        'push',
        tarArchive.path,
        remoteArchivePath,
      ]);
      if (!pushResult.stdout.contains('file(s) pushed')) {
        pushResult.throwException(pushResult.stdout);
      }
      final RunResult extractResult = await runSdbAsync(<String>[
        'shell',
        'tar',
        '-xf',
        remoteArchivePath,
        '-C',
        sdkToolsPath
      ]);
      if (extractResult.stdout.isNotEmpty) {
        extractResult.throwException(extractResult.stdout);
      }
    } on ProcessException catch (error) {
      _logger.printError('Error installing gdbserver: $error');
      return false;
    }
    // Remove a temporary file.
    await runSdbAsync(<String>[
      'shell',
      'rm',
      remoteArchivePath,
    ], checked: false);

    return true;
  }

  Future<void> _launchGdbServer(String appId, int debugPort, String pid) async {
    final List<String> command = _sdbCommand(<String>[
      'launch',
      '-a',
      '"$appId"',
      '-p',
      '-e',
      '-m',
      'debug',
      '-P',
      '$debugPort',
      '-attach',
      pid,
    ]);
    final Process process = await _processManager.start(command);

    final Completer<void> completer = Completer<void>();
    final StreamSubscription<String> stdoutSubscription = process.stdout
        .transform<String>(const Utf8Decoder())
        .transform<String>(const LineSplitter())
        .listen((String line) {
      if (line.contains("Can't bind address") ||
          line.contains('Cannot attach to process')) {
        completer.completeError(line);
      } else if (line.contains('Listening on port')) {
        completer.complete();
      } else {
        // For debugging purpose.
        // Remove this when we obtain enough information on corner cases.
        _logger.printError(line);
      }
    });
    final StreamSubscription<String> stderrSubscription = process.stderr
        .transform<String>(const Utf8Decoder())
        .transform<String>(const LineSplitter())
        .listen((String line) {
      completer.completeError(line);
    });

    // try {
    //   await completer.future.timeout(const Duration(seconds: 10));
    // } on Exception catch (error) {
    //   _logger.printError('Could not launch gdbserver: $error');
    //   await stdoutSubscription.cancel();
    //   await stderrSubscription.cancel();
    //   rethrow;
    // }
    await completer.future.timeout(const Duration(seconds: 15));
    await stdoutSubscription.cancel();
    await stderrSubscription.cancel();
  }

  /// Source: [AndroidDevice.startApp] in `android_device.dart`
  @override
  Future<LaunchResult> startApp(
    TizenTpk package, {
    String? mainPath,
    String? route,
    required DebuggingOptions debuggingOptions,
    Map<String, Object?> platformArgs = const <String, Object>{},
    bool prebuiltApplication = false,
    bool ipv6 = false,
    String? userIdentifier,
  }) async {
    if (!debuggingOptions.buildInfo.isDebug && await isLocalEmulator) {
      _logger.printError(
          'Profile and release builds are not supported on emulator targets.');
      return LaunchResult.failed();
    }

    // Build project if target application binary is not specified explicitly.
    final FlutterProject project = FlutterProject.current();
    if (!prebuiltApplication) {
      _logger.printTrace('Building TPK');
      await tizenBuilder!.buildTpk(
        project: project,
        targetFile: mainPath ?? 'lib/main.dart',
        tizenBuildInfo: TizenBuildInfo(
          debuggingOptions.buildInfo,
          targetArch: architecture,
          deviceProfile: deviceProfile,
        ),
      );
      package = TizenTpk.fromProject(project);
    }

    if (nativeDebuggingEnabled) {
      if (package.isDotnet) {
        _logger.printError('Native debugging error: Not supported app type.');
        return LaunchResult.failed();
      } else if (usesSecureProtocol) {
        _logger.printError('Native debugging error: Not supported device.');
        return LaunchResult.failed();
      } else if (!await _installGdbServer()) {
        return LaunchResult.failed();
      }
    }

    _logger.printTrace("Stopping app '${package.name}' on $name.");
    if (await isAppInstalled(package)) {
      await stopApp(package, userIdentifier: userIdentifier);
    }

    if (!await installApp(package, userIdentifier: userIdentifier)) {
      return LaunchResult.failed();
    }

    final bool traceStartup = platformArgs['trace-startup'] as bool? ?? false;
    _logger.printTrace('$this startApp');

    final DeviceLogReader logReader = await getLogReader();
    ProtocolDiscovery? observatoryDiscovery;

    if (debuggingOptions.debuggingEnabled) {
      observatoryDiscovery = ProtocolDiscovery.observatory(
        logReader,
        portForwarder: portForwarder,
        hostPort: debuggingOptions.hostVmServicePort,
        devicePort: debuggingOptions.deviceVmServicePort,
        ipv6: ipv6,
        logger: _logger,
      );
    }

    final List<String> engineArgs = <String>[
      '--enable-dart-profiling',
      if (traceStartup) '--trace-startup',
      if (debuggingOptions.enableSoftwareRendering)
        '--enable-software-rendering',
      if (debuggingOptions.skiaDeterministicRendering)
        '--skia-deterministic-rendering',
      if (debuggingOptions.traceSkia) '--trace-skia',
      if (debuggingOptions.traceAllowlist != null) ...<String>[
        '--trace-allowlist',
        debuggingOptions.traceAllowlist!,
      ],
      if (debuggingOptions.traceSkiaAllowlist != null) ...<String>[
        '--trace-skia-allowlist',
        debuggingOptions.traceSkiaAllowlist!,
      ],
      if (debuggingOptions.endlessTraceBuffer) '--endless-trace-buffer',
      if (debuggingOptions.dumpSkpOnShaderCompilation)
        '--dump-skp-on-shader-compilation',
      if (debuggingOptions.cacheSkSL) '--cache-sksl',
      if (debuggingOptions.debuggingEnabled) ...<String>[
        '--enable-checked-mode',
        if (debuggingOptions.startPaused) '--start-paused',
        if (debuggingOptions.disableServiceAuthCodes)
          '--disable-service-auth-codes',
        if (debuggingOptions.dartFlags.isNotEmpty) ...<String>[
          '--dart-flags',
          debuggingOptions.dartFlags,
        ],
        if (debuggingOptions.useTestFonts) '--use-test-fonts',
        if (debuggingOptions.verboseSystemLogs) '--verbose-logging',
      ],
      if (logReader is ForwardingLogReader) ...<String>[
        '--tizen-logging-port',
        logReader.hostPort.toString(),
      ],
    ];

    // Pass engine arguments to the app by writing to a temporary file.
    // See: https://github.com/flutter-tizen/flutter-tizen/pull/19
    await _writeEngineArguments(engineArgs, '${package.applicationId}.rpm');

    List<String> command;
    if (usesSecureProtocol) {
      command = <String>['shell', '0', 'execute', package.applicationId];
    } else {
      // The gdbserver can only properly attach to an app launched without
      // loader process.
      command = nativeDebuggingEnabled
          ? <String>['shell', 'app_launcher', '-e', package.applicationId]
          : <String>['shell', 'app_launcher', '-s', package.applicationId];
    }
    final RunResult result = await runSdbAsync(command);

    final RegExp pattern = RegExp('successfully launched pid = ([0-9]+)');
    final Match? match = pattern.firstMatch(result.stdout);
    if (match == null) {
      _logger.printError(result.stdout);
      return LaunchResult.failed();
    }

    if (logReader is ForwardingLogReader) {
      await logReader.start();
    }

    if (!debuggingOptions.debuggingEnabled) {
      return LaunchResult.succeeded();
    }

    // Wait for the service protocol port here. This will complete once the
    // device has printed "Observatory is listening on...".
    _logger.printTrace('Waiting for observatory port to be available...');

    Uri? observatoryUri;
    try {
      if (debuggingOptions.buildInfo.isDebug ||
          debuggingOptions.buildInfo.isProfile) {
        observatoryUri = await observatoryDiscovery?.uri;
        if (observatoryUri == null) {
          _logger.printError(
            'Error waiting for a debug connection: '
            'The log reader stopped unexpectedly',
          );
          return LaunchResult.failed();
        }
      }
    } on Exception catch (error) {
      _logger.printError('Error waiting for a debug connection: $error');
      return LaunchResult.failed();
    } finally {
      await observatoryDiscovery?.cancel();
    }

    if (!prebuiltApplication && observatoryUri != null) {
      updateLaunchJsonWithObservatoryInfo(project, observatoryUri);
    }

    if (nativeDebuggingEnabled) {
      // Forward a port to allow communication between gdb and gdbserver.
      final int debugPort = await globals.os.findFreePort();
      await portForwarder.forward(debugPort, hostPort: debugPort);

      final String pid = match.group(1)!;
      unawaited(_launchGdbServer(package.applicationId, debugPort, pid).then(
          (void _) {
        final File program = project.directory
            .childDirectory('build')
            .childDirectory('tizen')
            .childDirectory('tpk')
            .childDirectory('tpkroot')
            .childDirectory('bin')
            .childFile('runner');
        final File gdb = _tizenSdk.getGdbExecutable(architecture);

        updateLaunchJsonWithRemoteDebuggingInfo(
          project,
          program: program,
          gdbPath: gdb.path,
          debugPort: debugPort,
        );

        final String escapeCharacter = _platform.isWindows ? '`' : r'\';
        _logger.printStatus('''
gdbserver is listening for connection on port $debugPort.

(a) For CLI debugging:
    1. Open another console window.
    2. Launch GDB with the following command.
    ${gdb.path} $escapeCharacter
      "${program.path}" $escapeCharacter
      -ex "set pagenation off"
      -ex "set auto-solib-add off"
      -ex "target remote :$debugPort" $escapeCharacter
      -ex "shared /opt/usr/globalapps"

(b) For debugging with VS Code:
    1. Open the project folder in VS Code.
    2. Click the Run and Debug icon in the left menu bar, and make sure "$kConfigNameGdb" is selected.
    3. Click ▷ or press F5 to start debugging.

For detailed instructions, see:
https://github.com/flutter-tizen/flutter-tizen/wiki/Debugging-app's-native-code''');
      }, onError: (Object error) {
        _logger.printError('Could not launch gdbserver: $error');
      }));
    }

    return LaunchResult.succeeded(observatoryUri: observatoryUri);
  }

  @override
  Future<bool> stopApp(TizenTpk app, {String? userIdentifier}) async {
    try {
      final List<String> command = usesSecureProtocol
          ? <String>['shell', '0', 'kill', app.applicationId]
          : <String>['shell', 'app_launcher', '-k', app.applicationId];
      final String stdout = (await runSdbAsync(command)).stdout;
      return stdout.contains('Kill appId') ||
          stdout.contains('Terminate appId') ||
          stdout.contains('is Terminated') ||
          stdout.contains('is already Terminated');
    } on Exception catch (error) {
      _logger.printError(error.toString());
      return false;
    }
  }

  @override
  void clearLogs() {}

  /// Source: [AndroidDevice.getLogReader] in `android_device.dart`
  @override
  FutureOr<DeviceLogReader> getLogReader({
    TizenTpk? app,
    bool includePastLogs = false,
  }) async {
    return _logReader ??= await ForwardingLogReader.createLogReader(this);
  }

  @visibleForTesting
  // ignore: use_setters_to_change_properties
  void setLogReader(DeviceLogReader logReader) {
    _logReader = logReader;
  }

  @override
  DevicePortForwarder get portForwarder {
    return _portForwarder ??= TizenDevicePortForwarder(
      device: this,
      logger: _logger,
    );
  }

  @visibleForTesting
  set portForwarder(DevicePortForwarder forwarder) {
    _portForwarder = forwarder;
  }

  @override
  bool isSupported() {
    final Version? platformVersion = Version.parse(_platformVersion);
    if (platformVersion == null) {
      return false;
    }
    if (deviceProfile == 'wearable') {
      return platformVersion >= Version(4, 0, 0);
    } else if (deviceProfile == 'tv') {
      return platformVersion >= Version(6, 0, 0);
    }
    return platformVersion >= Version(5, 5, 0);
  }

  @override
  bool get supportsScreenshot => false;

  @override
  bool isSupportedForProject(FlutterProject flutterProject) {
    return flutterProject.isModule &&
        flutterProject.directory.childDirectory('tizen').existsSync();
  }

  /// Source: [AndroidDevice.dispose] in `android_device.dart`
  @override
  Future<void> dispose() async {
    _logReader?.dispose();
    await _portForwarder?.dispose();
  }
}

/// A [DevicePortForwarder] implemented for Tizen devices.
///
/// Source: [AndroidDevicePortForwarder] in `android_device.dart`
class TizenDevicePortForwarder extends DevicePortForwarder {
  TizenDevicePortForwarder({
    required TizenDevice device,
    required Logger logger,
  })  : _device = device,
        _logger = logger;

  final TizenDevice _device;
  final Logger _logger;

  static int? _extractPort(String portString) {
    return int.tryParse(portString.trim().split(':')[1]);
  }

  @override
  List<ForwardedPort> get forwardedPorts {
    final List<ForwardedPort> ports = <ForwardedPort>[];

    String stdout;
    try {
      final RunResult result =
          _device.runSdbSync(<String>['forward', '--list']);
      stdout = result.stdout.trim();
    } on ProcessException catch (error) {
      _logger.printError('Failed to list forwarded ports: $error.');
      return ports;
    }

    for (final String line in LineSplitter.split(stdout)) {
      if (!line.startsWith(_device.id)) {
        continue;
      }
      final List<String> splitLine = line.split(RegExp(r'\s+'));
      if (splitLine.length != 3) {
        continue;
      }

      // Attempt to extract ports.
      final int? hostPort = _extractPort(splitLine[1]);
      final int? devicePort = _extractPort(splitLine[2]);
      if (hostPort == null || devicePort == null) {
        continue;
      }

      ports.add(ForwardedPort(hostPort, devicePort));
    }

    return ports;
  }

  @override
  Future<int> forward(int devicePort, {int? hostPort}) async {
    hostPort ??= await globals.os.findFreePort();
    if (hostPort == 0) {
      throwToolExit('No available port could be found on the host.');
    }

    final RunResult result = await _device.runSdbAsync(
      <String>['forward', 'tcp:$hostPort', 'tcp:$devicePort'],
      checked: false,
    );
    if (result.stderr.isNotEmpty) {
      result.throwException('sdb returned error:\n${result.stderr}');
    }
    if (result.exitCode != 0) {
      if (result.stdout.isNotEmpty) {
        result.throwException('sdb returned error:\n${result.stdout}');
      }
      result.throwException('sdb failed without a message.');
    }

    return hostPort;
  }

  @override
  Future<void> unforward(ForwardedPort forwardedPort) async {
    final RunResult result = await _device.runSdbAsync(
      <String>['forward', '--remove', 'tcp:${forwardedPort.hostPort}'],
      checked: false,
    );
    if (result.stderr.isEmpty) {
      return;
    }
    _logger.printError('Failed to unforward port: $result');
  }

  @override
  Future<void> dispose() async {
    for (final ForwardedPort port in forwardedPorts) {
      await unforward(port);
    }
  }
}
