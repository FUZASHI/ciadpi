import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

enum ProxyStatus { disconnected, connecting, connected, error }

class ProxyManager {
  static final ProxyManager _instance = ProxyManager._internal();
  factory ProxyManager() => _instance;
  ProxyManager._internal();

  Process? _process;
  ProxyStatus _status = ProxyStatus.disconnected;
  final _statusController = StreamController<ProxyStatus>.broadcast();
  final _logController = StreamController<String>.broadcast();
  String? _binaryPath;
  int _port = 1080;

  ProxyStatus get status => _status;
  Stream<ProxyStatus> get statusStream => _statusController.stream;
  Stream<String> get logStream => _logController.stream;
  int get port => _port;

  void _setStatus(ProxyStatus s) {
    _status = s;
    _statusController.add(s);
  }

  void _log(String message) {
    _logController.add('[${DateTime.now().toIso8601String().substring(11, 19)}] $message');
  }

  Future<String> _extractBinary() async {
    if (_binaryPath != null) {
      final f = File(_binaryPath!);
      if (await f.exists()) return _binaryPath!;
    }

    final dir = await getApplicationSupportDirectory();
    final targetPath = '${dir.path}/ciadpi_mac';
    final file = File(targetPath);

    _log('Extracting ciadpi binary...');
    final data = await rootBundle.load('assets/ciadpi_mac');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);

    // Make executable
    await Process.run('chmod', ['+x', targetPath]);
    _log('Binary extracted to $targetPath');

    _binaryPath = targetPath;
    return targetPath;
  }

  Future<void> start({
    required List<String> args,
    int port = 1080,
  }) async {
    if (_status == ProxyStatus.connected || _status == ProxyStatus.connecting) {
      _log('Proxy already running, stopping first...');
      await stop();
    }

    _setStatus(ProxyStatus.connecting);
    _port = port;

    try {
      final binaryPath = await _extractBinary();

      // Build full argument list
      final fullArgs = ['-p', port.toString(), '-x', '1', ...args];
      _log('Starting: ciadpi ${fullArgs.join(' ')}');

      _process = await Process.start(binaryPath, fullArgs);

      // Listen to stdout
      _process!.stdout.transform(const SystemEncoding().decoder).listen(
        (data) {
          for (final line in data.split('\n')) {
            if (line.trim().isNotEmpty) _log(line.trim());
          }
        },
        onDone: () {
          if (_status == ProxyStatus.connected) {
            _log('Process exited unexpectedly');
            _setStatus(ProxyStatus.error);
            _disableSystemProxy();
          }
        },
      );

      // Listen to stderr
      _process!.stderr.transform(const SystemEncoding().decoder).listen(
        (data) {
          for (final line in data.split('\n')) {
            if (line.trim().isNotEmpty) _log('[ERR] ${line.trim()}');
          }
        },
      );

      // Wait briefly to check it doesn't immediately crash
      await Future.delayed(const Duration(milliseconds: 500));

      final exitCode = _process?.exitCode;
      // Check if process is still alive (exitCode future hasn't completed)
      bool alive = true;
      _process!.exitCode.then((code) {
        if (_status == ProxyStatus.connecting) {
          alive = false;
          _log('Process exited during startup with code $code');
          _setStatus(ProxyStatus.error);
        }
      });

      await Future.delayed(const Duration(milliseconds: 300));
      if (_status == ProxyStatus.error) return;

      // Enable system proxy
      await _enableSystemProxy(port);
      _setStatus(ProxyStatus.connected);
      _log('✓ Connected — SOCKS5 proxy on 127.0.0.1:$port');
    } catch (e) {
      _log('Error starting proxy: $e');
      _setStatus(ProxyStatus.error);
    }
  }

  Future<void> stop() async {
    _log('Stopping proxy...');

    if (_process != null) {
      _process!.kill(ProcessSignal.sigterm);
      try {
        await _process!.exitCode.timeout(const Duration(seconds: 3));
      } catch (_) {
        _process!.kill(ProcessSignal.sigkill);
      }
      _process = null;
    }

    await _disableSystemProxy();
    _setStatus(ProxyStatus.disconnected);
    _log('Proxy stopped');
  }

  Future<void> _enableSystemProxy(int port) async {
    _log('Configuring system SOCKS proxy on Wi-Fi...');
    await Process.run('networksetup', [
      '-setsocksfirewallproxy', 'Wi-Fi', '127.0.0.1', port.toString(),
    ]);
    await Process.run('networksetup', [
      '-setsocksfirewallproxystate', 'Wi-Fi', 'on',
    ]);
    _log('System proxy enabled');
  }

  Future<void> _disableSystemProxy() async {
    _log('Disabling system SOCKS proxy...');
    await Process.run('networksetup', [
      '-setsocksfirewallproxystate', 'Wi-Fi', 'off',
    ]);
    _log('System proxy disabled');
  }

  void dispose() {
    stop();
    _statusController.close();
    _logController.close();
  }
}
