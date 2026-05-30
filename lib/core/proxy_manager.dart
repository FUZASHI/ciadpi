import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

enum ProxyStatus { disconnected, connecting, connected, error }

class ProxyManager {
  static final ProxyManager _instance = ProxyManager._internal();
  factory ProxyManager() => _instance;
  ProxyManager._internal();

  // Desktop (macOS/Windows) process
  Process? _process;

  // Android MethodChannel
  static const _channel = MethodChannel('com.digitalstorm.ciadpi/proxy');
  bool _androidChannelInitialized = false;

  ProxyStatus _status = ProxyStatus.disconnected;
  final _statusController = StreamController<ProxyStatus>.broadcast();
  final _logController = StreamController<String>.broadcast();
  String? _binaryPath;
  int _port = 1080;

  ProxyStatus get status => _status;
  Stream<ProxyStatus> get statusStream => _statusController.stream;
  Stream<String> get logStream => _logController.stream;
  int get port => _port;

  bool get _isWindows => Platform.isWindows;
  bool get _isMacOS => Platform.isMacOS;
  bool get _isAndroid => Platform.isAndroid;

  void _setStatus(ProxyStatus s) {
    _status = s;
    _statusController.add(s);
  }

  void _log(String message) {
    _logController.add(
        '[${DateTime.now().toIso8601String().substring(11, 19)}] $message');
  }

  void _initAndroidChannel() {
    if (_androidChannelInitialized) return;
    _androidChannelInitialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onStatusChanged') {
        final status = call.arguments as String;
        switch (status) {
          case 'connected':
            _setStatus(ProxyStatus.connected);
            _log('✓ Connected — VPN active, SOCKS5 on 127.0.0.1:$_port');
            break;
          case 'disconnected':
            _setStatus(ProxyStatus.disconnected);
            _log('Proxy stopped');
            break;
          case 'failed':
            _setStatus(ProxyStatus.error);
            _log('[ERR] VPN service failed');
            break;
        }
      }
    });
  }

  // Desktop binary helpers
  String get _assetName => _isWindows ? 'assets/ciadpi.exe' : 'assets/ciadpi_mac';
  String get _binaryName => _isWindows ? 'ciadpi.exe' : 'ciadpi_mac';

  Future<String> _extractBinary() async {
    if (_binaryPath != null) {
      final f = File(_binaryPath!);
      if (await f.exists()) return _binaryPath!;
    }

    final dir = await getApplicationSupportDirectory();
    final targetPath = '${dir.path}${Platform.pathSeparator}$_binaryName';
    final file = File(targetPath);

    _log('Extracting $_binaryName...');
    final data = await rootBundle.load(_assetName);
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);

    // Make executable (macOS/Linux only)
    if (!_isWindows) {
      await Process.run('chmod', ['+x', targetPath]);
    }
    _log('Binary extracted to $targetPath');

    _binaryPath = targetPath;
    return targetPath;
  }

  Future<void> start({
    required List<String> args,
    int port = 1080,
  }) async {
    if (_status == ProxyStatus.connected ||
        _status == ProxyStatus.connecting) {
      _log('Proxy already running, stopping first...');
      await stop();
    }

    _setStatus(ProxyStatus.connecting);
    _port = port;

    if (_isAndroid) {
      await _startAndroid(args, port);
    } else {
      await _startDesktop(args, port);
    }
  }

  Future<void> _startAndroid(List<String> args, int port) async {
    try {
      _initAndroidChannel();
      _log('Starting VPN with: ${args.join(' ')}');

      await _channel.invokeMethod('startVpn', {
        'args': args,
        'port': port,
      });

      // Status will be updated via the callback from native side
    } catch (e) {
      _log('[ERR] Error starting VPN: $e');
      _setStatus(ProxyStatus.error);
    }
  }

  Future<void> _startDesktop(List<String> args, int port) async {
    try {
      final binaryPath = await _extractBinary();

      // Build full argument list
      final fullArgs = ['-p', port.toString(), '-x', '1', ...args];
      _log('Starting: $_binaryName ${fullArgs.join(' ')}');

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

      // Check if process is still alive
      _process!.exitCode.then((code) {
        if (_status == ProxyStatus.connecting) {
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

    if (_isAndroid) {
      await _stopAndroid();
    } else {
      await _stopDesktop();
    }
  }

  Future<void> _stopAndroid() async {
    try {
      await _channel.invokeMethod('stopVpn');
      // Status will be updated via the callback from native side
    } catch (e) {
      _log('[ERR] Error stopping VPN: $e');
      _setStatus(ProxyStatus.disconnected);
    }
  }

  Future<void> _stopDesktop() async {
    if (_process != null) {
      if (_isWindows) {
        _process!.kill();
        try {
          await _process!.exitCode.timeout(const Duration(seconds: 3));
        } catch (_) {
          try {
            await Process.run('taskkill', ['/F', '/PID', '${_process!.pid}']);
          } catch (_) {}
        }
      } else {
        // macOS/Linux
        _process!.kill(ProcessSignal.sigterm);
        try {
          await _process!.exitCode.timeout(const Duration(seconds: 3));
        } catch (_) {
          _process!.kill(ProcessSignal.sigkill);
        }
      }
      _process = null;
    }

    await _disableSystemProxy();
    _setStatus(ProxyStatus.disconnected);
    _log('Proxy stopped');
  }

  // ---------- System proxy configuration (desktop only) ----------

  Future<void> _enableSystemProxy(int port) async {
    if (_isWindows) {
      await _enableWindowsProxy(port);
    } else if (_isMacOS) {
      await _enableMacProxy(port);
    }
  }

  Future<void> _disableSystemProxy() async {
    if (_isWindows) {
      await _disableWindowsProxy();
    } else if (_isMacOS) {
      await _disableMacProxy();
    }
  }

  // --- macOS ---

  Future<void> _enableMacProxy(int port) async {
    _log('Configuring system SOCKS proxy on Wi-Fi...');
    await Process.run('networksetup', [
      '-setsocksfirewallproxy',
      'Wi-Fi',
      '127.0.0.1',
      port.toString(),
    ]);
    await Process.run('networksetup', [
      '-setsocksfirewallproxystate',
      'Wi-Fi',
      'on',
    ]);
    _log('System proxy enabled');
  }

  Future<void> _disableMacProxy() async {
    _log('Disabling system SOCKS proxy...');
    await Process.run('networksetup', [
      '-setsocksfirewallproxystate',
      'Wi-Fi',
      'off',
    ]);
    _log('System proxy disabled');
  }

  // --- Windows ---

  Future<void> _enableWindowsProxy(int port) async {
    _log('Configuring system proxy on Windows...');
    await Process.run('reg', [
      'add',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v', 'ProxyEnable',
      '/t', 'REG_DWORD',
      '/d', '1',
      '/f',
    ]);
    await Process.run('reg', [
      'add',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v', 'ProxyServer',
      '/t', 'REG_SZ',
      '/d', 'socks=127.0.0.1:$port',
      '/f',
    ]);
    _log('System proxy enabled (socks=127.0.0.1:$port)');
    _log('Tip: Configure your browser to use SOCKS5 proxy 127.0.0.1:$port');
  }

  Future<void> _disableWindowsProxy() async {
    _log('Disabling system proxy...');
    await Process.run('reg', [
      'add',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v', 'ProxyEnable',
      '/t', 'REG_DWORD',
      '/d', '0',
      '/f',
    ]);
    await Process.run('reg', [
      'delete',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v', 'ProxyServer',
      '/f',
    ]);
    _log('System proxy disabled');
  }

  void dispose() {
    stop();
    _statusController.close();
    _logController.close();
  }
}
