import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'video_provider.dart';

const _comfyUiBridgePort = 20129;

final _manager = _WindowsComfyUiBridgeManager();

ComfyUiBridgeManager createComfyUiBridgeManager() => _manager;

Future<void> shutdownComfyUiBridge() => _manager.shutdown();

abstract interface class ComfyUiBridgeManager {
  Future<void> ensureReady({
    required String installationPath,
    required int comfyUiPort,
    required String bridgeToken,
  });

  Future<void> shutdown();
}

class _WindowsComfyUiBridgeManager implements ComfyUiBridgeManager {
  Process? _bridgeProcess;
  String? _activeInstallationPath;
  int? _activeComfyUiPort;
  String? _activeBridgeToken;
  Future<void>? _ensureFuture;
  Timer? _heartbeatTimer;
  http.Client? _heartbeatClient;

  @override
  Future<void> ensureReady({
    required String installationPath,
    required int comfyUiPort,
    required String bridgeToken,
  }) {
    final running = _ensureFuture;
    if (running != null) return running;
    final future = _ensureReady(
      installationPath: installationPath,
      comfyUiPort: comfyUiPort,
      bridgeToken: bridgeToken,
    );
    _ensureFuture = future;
    return future.whenComplete(() {
      if (identical(_ensureFuture, future)) _ensureFuture = null;
    });
  }

  Future<void> _ensureReady({
    required String installationPath,
    required int comfyUiPort,
    required String bridgeToken,
  }) async {
    if (!Platform.isWindows) {
      throw const VideoProviderException(
        'VIDEO_CONFIGURATION_ERROR',
        'ComfyUI auto-start is supported only on Windows. Start the bridge manually on this platform.',
      );
    }
    final token = bridgeToken.trim();
    if (token.length < 24 || token.length > 256) {
      throw const VideoProviderException(
        'VIDEO_CONFIGURATION_ERROR',
        'Local ComfyUI bridge token must contain 24 to 256 characters.',
      );
    }
    if (comfyUiPort < 1 || comfyUiPort > 65535) {
      throw const VideoProviderException(
        'VIDEO_CONFIGURATION_ERROR',
        'ComfyUI port is invalid.',
      );
    }

    final current = _bridgeProcess;
    if (current != null) {
      if (_activeInstallationPath != installationPath.trim() ||
          _activeComfyUiPort != comfyUiPort ||
          _activeBridgeToken != token) {
        await shutdown();
      } else {
        await _waitForHealth(token);
        _startHeartbeat(token);
        return;
      }
    }

    final runtime = await _runtimeDirectory();
    final script = await _extractBridgeScript(runtime);
    await _extractWorkflow(runtime);
    final python = await _findPython(installationPath);
    final comfyPath = installationPath.trim();
    if (comfyPath.isEmpty) {
      throw const VideoProviderException(
        'VIDEO_SETUP_REQUIRED',
        'Configure the ComfyUI installation path before starting the local bridge.',
      );
    }

    final process = await Process.start(
      python,
      [
        script.path,
        '--bridge-host',
        '127.0.0.1',
        '--bridge-port',
        '$_comfyUiBridgePort',
        '--comfyui-path',
        comfyPath,
        '--comfyui-port',
        '$comfyUiPort',
        '--runtime-dir',
        runtime.path,
        '--workflow',
        p.join(runtime.path, 'workflow_api.json'),
        '--parent-pid',
        '$pid',
        '--lease-seconds',
        '90',
      ],
      environment: {
        'VARIAN_COMFYUI_BRIDGE_TOKEN': token,
        'VARIAN_COMFYUI_PORT': '$comfyUiPort',
      },
      includeParentEnvironment: true,
      runInShell: false,
    );
    _bridgeProcess = process;
    _activeInstallationPath = comfyPath;
    _activeComfyUiPort = comfyUiPort;
    _activeBridgeToken = token;
    _drain(process.stdout);
    _drain(process.stderr);
    unawaited(
      process.exitCode.then((_) {
        if (identical(_bridgeProcess, process)) {
          _bridgeProcess = null;
          _activeInstallationPath = null;
          _activeComfyUiPort = null;
          _activeBridgeToken = null;
          _stopHeartbeat();
        }
      }),
    );

    try {
      await _waitForHealth(token);
      _startHeartbeat(token);
    } catch (_) {
      await shutdown();
      rethrow;
    }
  }

  void _startHeartbeat(String token) {
    _heartbeatTimer?.cancel();
    _heartbeatClient?.close();
    final client = http.Client();
    _heartbeatClient = client;
    var sending = false;
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (sending || _bridgeProcess == null) return;
      sending = true;
      unawaited(
        _postHeartbeat(client, token).whenComplete(() {
          sending = false;
        }),
      );
    });
  }

  Future<void> _postHeartbeat(http.Client client, String token) async {
    try {
      await client
          .post(
            Uri.parse('http://127.0.0.1:$_comfyUiBridgePort/health/heartbeat'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatClient?.close();
    _heartbeatClient = null;
  }

  Future<Directory> _runtimeDirectory() async {
    final support = await getApplicationSupportDirectory();
    final runtime = Directory(p.join(support.path, 'comfyui-bridge'));
    await runtime.create(recursive: true);
    return runtime;
  }

  Future<File> _extractBridgeScript(Directory runtime) async {
    final target = File(p.join(runtime.path, 'bridge.py'));
    final data = await rootBundle.load('tool/comfyui_video_bridge/bridge.py');
    await target.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return target;
  }

  Future<File> _extractWorkflow(Directory runtime) async {
    final target = File(p.join(runtime.path, 'workflow_api.json'));
    final data = await rootBundle.load(
      'tool/comfyui_video_bridge/workflow_api.json',
    );
    await target.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return target;
  }

  Future<String> _findPython(String installationPath) async {
    final configured = installationPath.trim();
    if (configured.isNotEmpty) {
      var root = Directory(configured);
      if (await File(configured).exists()) {
        root = Directory(p.dirname(configured));
      }
      final roots = [
        root,
        Directory(p.join(root.path, 'ComfyUI')),
        Directory(p.dirname(root.path)),
      ];
      for (final candidateRoot in roots) {
        final candidates = [
          File(p.join(candidateRoot.path, 'python_embeded', 'python.exe')),
          File(p.join(candidateRoot.path, 'venv', 'Scripts', 'python.exe')),
          File(p.join(candidateRoot.path, '.venv', 'Scripts', 'python.exe')),
        ];
        for (final candidate in candidates) {
          if (await candidate.exists()) return candidate.path;
        }
      }
    }
    for (final executable in ['python', 'py']) {
      try {
        final result = await Process.run(executable, ['--version']);
        if (result.exitCode == 0) return executable;
      } catch (_) {}
    }
    throw const VideoProviderException(
      'VIDEO_SETUP_REQUIRED',
      'A Python runtime for ComfyUI was not found. Install ComfyUI Portable or configure its path.',
    );
  }

  void _drain(Stream<List<int>> stream) {
    stream.listen((_) {}, onError: (_) {});
  }

  Future<void> _waitForHealth(String token) async {
    final client = http.Client();
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    try {
      while (DateTime.now().isBefore(deadline)) {
        try {
          final response = await client
              .get(
                Uri.parse('http://127.0.0.1:$_comfyUiBridgePort/health'),
                headers: {'Authorization': 'Bearer $token'},
              )
              .timeout(const Duration(seconds: 5));
          if (response.statusCode >= 200 && response.statusCode < 300) return;
          if (response.statusCode == 401 || response.statusCode == 403) {
            throw const VideoProviderException(
              'VIDEO_AUTH_ERROR',
              'Local ComfyUI bridge token was rejected.',
            );
          }
          if (response.statusCode == 503) {
            final message = _safeErrorMessage(response.body);
            if (message != null &&
                !message.toLowerCase().contains('starting')) {
              throw VideoProviderException('VIDEO_SETUP_ERROR', message);
            }
          }
        } on VideoProviderException {
          rethrow;
        } catch (_) {}
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      throw const VideoProviderException(
        'VIDEO_SETUP_ERROR',
        'ComfyUI bridge did not become ready before the startup timeout.',
      );
    } finally {
      client.close();
    }
  }

  String? _safeErrorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      final error = decoded is Map ? decoded['error'] : null;
      final message = error is Map ? error['message'] : null;
      final text = message?.toString().trim();
      return text == null || text.isEmpty || text.length > 240 ? null : text;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> shutdown() async {
    _stopHeartbeat();
    final process = _bridgeProcess;
    _bridgeProcess = null;
    _activeInstallationPath = null;
    _activeComfyUiPort = null;
    _activeBridgeToken = null;
    if (process == null) return;
    if (process.pid <= 0) return;
    try {
      await Process.run('taskkill', [
        '/PID',
        process.pid.toString(),
        '/T',
        '/F',
      ]).timeout(const Duration(seconds: 5));
    } catch (_) {
      process.kill(ProcessSignal.sigkill);
    }
  }
}
