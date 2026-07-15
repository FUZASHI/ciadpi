import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

enum ProxyStatus { disconnected, connecting, connected, error }
enum ProxyMode { proxy, vpn }

class ProxyManager {
  static final ProxyManager _instance = ProxyManager._internal();
  factory ProxyManager() => _instance;
  ProxyManager._internal();

  // Desktop (macOS/Windows) processes
  Process? _process;
  Process? _tun2socksProcess;

  // Android MethodChannel
  static const _channel = MethodChannel('com.digitalstorm.ciadpi/proxy');
  bool _androidChannelInitialized = false;

  ProxyStatus _status = ProxyStatus.disconnected;
  ProxyMode _mode = ProxyMode.proxy;
  final _statusController = StreamController<ProxyStatus>.broadcast();
  final _logController = StreamController<String>.broadcast();
  String? _binaryPath;
  String? _tun2socksPath;
  String? _supportDir;
  int _port = 1080;
  String? _originalGateway;
  String? _originalInterface;

  ProxyStatus get status => _status;
  ProxyMode get mode => _mode;
  Stream<ProxyStatus> get statusStream => _statusController.stream;
  Stream<String> get logStream => _logController.stream;
  int get port => _port;

  set mode(ProxyMode m) => _mode = m;

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

  Future<String> _getSupportDir() async {
    if (_supportDir != null) return _supportDir!;
    final dir = await getApplicationSupportDirectory();
    _supportDir = dir.path;
    return _supportDir!;
  }

  Future<String> _extractBinary() async {
    if (_binaryPath != null) {
      final f = File(_binaryPath!);
      if (await f.exists()) return _binaryPath!;
    }

    final dirPath = await _getSupportDir();
    final targetPath = '$dirPath${Platform.pathSeparator}$_binaryName';
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

  Future<String> _extractTun2socks() async {
    if (_tun2socksPath != null) {
      final f = File(_tun2socksPath!);
      if (await f.exists()) return _tun2socksPath!;
    }

    final dirPath = await _getSupportDir();
    final tun2socksTarget = '$dirPath${Platform.pathSeparator}tun2socks.exe';
    final wintunTarget = '$dirPath${Platform.pathSeparator}wintun.dll';

    // Extract tun2socks.exe
    _log('Extracting tun2socks.exe...');
    final tun2socksData = await rootBundle.load('assets/tun2socks.exe');
    await File(tun2socksTarget)
        .writeAsBytes(tun2socksData.buffer.asUint8List(), flush: true);

    // Extract wintun.dll (must be in same directory as tun2socks.exe)
    _log('Extracting wintun.dll...');
    final wintunData = await rootBundle.load('assets/wintun.dll');
    await File(wintunTarget)
        .writeAsBytes(wintunData.buffer.asUint8List(), flush: true);

    _log('tun2socks + wintun extracted');
    _tun2socksPath = tun2socksTarget;
    return tun2socksTarget;
  }

  // ---------- Start / Stop ----------

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

      // Enable system proxy or VPN mode
      if (_isWindows && _mode == ProxyMode.vpn) {
        await _startVpnMode(port);
      } else {
        await _enableSystemProxy(port);
      }

      _setStatus(ProxyStatus.connected);
      if (_mode == ProxyMode.vpn) {
        _log('✓ Connected — VPN mode, all traffic routed via 127.0.0.1:$port');
      } else {
        _log('✓ Connected — SOCKS5 proxy on 127.0.0.1:$port');
      }
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
    } catch (e) {
      _log('[ERR] Error stopping VPN: $e');
      _setStatus(ProxyStatus.disconnected);
    }
  }

  Future<void> _stopDesktop() async {
    // Stop VPN mode first (if active)
    if (_tun2socksProcess != null) {
      await _stopVpnMode();
    }

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

  // ---------- Windows VPN Mode (tun2socks) ----------

  Future<void> _startVpnMode(int port) async {
    _log('Starting VPN mode (tun2socks)...');

    // 1. Extract tun2socks + wintun
    final tun2socksPath = await _extractTun2socks();

    // 2. Save current default gateway to prevent routing loop
    await _saveDefaultGateway();

    // 3. Start tun2socks
    _log('Launching tun2socks...');
    _tun2socksProcess = await Process.start(
      tun2socksPath,
      ['--device', 'wintun', '--proxy', 'socks5://127.0.0.1:$port'],
      workingDirectory: _supportDir,
    );

    // Listen to tun2socks output
    _tun2socksProcess!.stdout.transform(const SystemEncoding().decoder).listen(
      (data) {
        for (final line in data.split('\n')) {
          if (line.trim().isNotEmpty) _log('[tun2socks] ${line.trim()}');
        }
      },
    );
    _tun2socksProcess!.stderr.transform(const SystemEncoding().decoder).listen(
      (data) {
        for (final line in data.split('\n')) {
          if (line.trim().isNotEmpty) _log('[tun2socks] ${line.trim()}');
        }
      },
    );

    // Monitor tun2socks exit
    _tun2socksProcess!.exitCode.then((code) {
      if (_status == ProxyStatus.connected) {
        _log('[ERR] tun2socks exited unexpectedly with code $code');
        _setStatus(ProxyStatus.error);
        _restoreRoutes();
      }
    });

    // 4. Wait for TUN adapter to be created
    _log('Waiting for wintun adapter...');
    await Future.delayed(const Duration(seconds: 2));

    // 5. Configure network routes
    await _configureVpnRoutes(port);
  }

  Future<void> _saveDefaultGateway() async {
    try {
      // Get the current default gateway
      final result = await Process.run('powershell', [
        '-Command',
        r"(Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1).NextHop",
      ]);
      final gateway = result.stdout.toString().trim();
      if (gateway.isNotEmpty && gateway != '') {
        _originalGateway = gateway;
        _log('Current default gateway: $gateway');
      }

      // Get the interface index for the gateway
      final ifResult = await Process.run('powershell', [
        '-Command',
        r"(Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1).InterfaceAlias",
      ]);
      final iface = ifResult.stdout.toString().trim();
      if (iface.isNotEmpty) {
        _originalInterface = iface;
        _log('Current interface: $iface');
      }
    } catch (e) {
      _log('[WARN] Could not detect default gateway: $e');
    }
  }

  Future<void> _configureVpnRoutes(int port) async {
    _log('Configuring VPN routes...');

    try {
      // 1. Set IP on the wintun adapter
      await _runRoute('netsh', [
        'interface', 'ip', 'set', 'address',
        'wintun', 'static', '10.0.85.1', '255.255.255.0',
      ]);

      // 2. Set DNS on wintun adapter
      await _runRoute('netsh', [
        'interface', 'ip', 'set', 'dnsservers',
        'wintun', 'static', '1.1.1.1', 'validate=no',
      ]);

      // 3. Add route for the SOCKS proxy itself via the REAL gateway
      //    This prevents a routing loop (proxy traffic must NOT go through the TUN)
      if (_originalGateway != null) {
        await _runRoute('route', [
          'add', '127.0.0.1', 'mask', '255.255.255.255',
          _originalGateway!, 'metric', '1',
        ]);
      }

      // 4. Add default route via the TUN adapter with lower metric
      await _runRoute('route', [
        'add', '0.0.0.0', 'mask', '128.0.0.0',
        '10.0.85.1', 'metric', '5',
      ]);
      await _runRoute('route', [
        'add', '128.0.0.0', 'mask', '128.0.0.0',
        '10.0.85.1', 'metric', '5',
      ]);

      _log('VPN routes configured — all traffic routed through TUN');
    } catch (e) {
      _log('[ERR] Failed to configure routes: $e');
      // Try to clean up on failure
      await _stopVpnMode();
      _setStatus(ProxyStatus.error);
    }
  }

  Future<void> _runRoute(String cmd, List<String> args) async {
    final result = await Process.run(cmd, args);
    final stdout = result.stdout.toString().trim();
    final stderr = result.stderr.toString().trim();
    if (stdout.isNotEmpty) _log('[route] $stdout');
    if (stderr.isNotEmpty && result.exitCode != 0) _log('[route ERR] $stderr');
  }

  Future<void> _stopVpnMode() async {
    _log('Stopping VPN mode...');

    // Restore routes first
    await _restoreRoutes();

    // Kill tun2socks
    if (_tun2socksProcess != null) {
      _tun2socksProcess!.kill();
      try {
        await _tun2socksProcess!.exitCode.timeout(const Duration(seconds: 3));
      } catch (_) {
        try {
          await Process.run(
              'taskkill', ['/F', '/PID', '${_tun2socksProcess!.pid}']);
        } catch (_) {}
      }
      _tun2socksProcess = null;
    }

    _log('VPN mode stopped');
  }

  Future<void> _restoreRoutes() async {
    _log('Restoring network routes...');
    try {
      // Remove our added routes
      await Process.run('route', ['delete', '0.0.0.0', 'mask', '128.0.0.0']);
      await Process.run('route', ['delete', '128.0.0.0', 'mask', '128.0.0.0']);
      if (_originalGateway != null) {
        await Process.run('route', [
          'delete', '127.0.0.1', 'mask', '255.255.255.255',
        ]);
      }
      _log('Routes restored');
    } catch (e) {
      _log('[WARN] Could not fully restore routes: $e');
    }
    _originalGateway = null;
    _originalInterface = null;
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
    if (_isWindows && _mode != ProxyMode.vpn) {
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
