import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/presets.dart';
import 'core/proxy_manager.dart';

void main() {
  runApp(const CiaDpiApp());
}

class CiaDpiApp extends StatelessWidget {
  const CiaDpiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ByeByeDPI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E1A),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData.dark().textTheme,
        ),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF6C63FF),
          secondary: const Color(0xFF00D9FF),
          surface: const Color(0xFF121829),
          error: const Color(0xFFFF5252),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final ProxyManager _proxy = ProxyManager();
  final List<String> _logs = [];
  final ScrollController _logScrollController = ScrollController();
  final TextEditingController _customArgsController = TextEditingController();

  int _selectedPresetIndex = 1; // Default: Russia (Aggressive)
  bool _useCustomArgs = false;
  int _port = 1080;

  late AnimationController _pulseController;
  late AnimationController _orbRotationController;
  late Animation<double> _pulseAnimation;
  StreamSubscription<ProxyStatus>? _statusSub;
  StreamSubscription<String>? _logSub;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _orbRotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _statusSub = _proxy.statusStream.listen((status) {
      setState(() {});
      if (status == ProxyStatus.connected) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.reset();
      }
    });

    _logSub = _proxy.logStream.listen((msg) {
      setState(() {
        _logs.add(msg);
        if (_logs.length > 500) _logs.removeAt(0);
      });
      Future.delayed(const Duration(milliseconds: 50), () {
        if (_logScrollController.hasClients) {
          _logScrollController.animateTo(
            _logScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _logSub?.cancel();
    _pulseController.dispose();
    _orbRotationController.dispose();
    _logScrollController.dispose();
    _customArgsController.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_proxy.status == ProxyStatus.connected ||
        _proxy.status == ProxyStatus.connecting) {
      await _proxy.stop();
    } else {
      List<String> args;
      if (_useCustomArgs) {
        args = _customArgsController.text
            .trim()
            .split(RegExp(r'\s+'))
            .where((s) => s.isNotEmpty)
            .toList();
      } else {
        args = List.from(Presets.all[_selectedPresetIndex].args);
      }
      await _proxy.start(args: args, port: _port);
    }
  }

  Color get _statusColor {
    switch (_proxy.status) {
      case ProxyStatus.connected:
        return const Color(0xFF00E676);
      case ProxyStatus.connecting:
        return const Color(0xFFFFD740);
      case ProxyStatus.error:
        return const Color(0xFFFF5252);
      case ProxyStatus.disconnected:
        return const Color(0xFF455A64);
    }
  }

  String get _statusText {
    switch (_proxy.status) {
      case ProxyStatus.connected:
        return 'PROTECTED';
      case ProxyStatus.connecting:
        return 'CONNECTING...';
      case ProxyStatus.error:
        return 'ERROR';
      case ProxyStatus.disconnected:
        return 'DISCONNECTED';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A0E1A),
              Color(0xFF0F1628),
              Color(0xFF141E35),
              Color(0xFF0A0E1A),
            ],
            stops: [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: Row(
          children: [
            // Left panel: presets + config
            SizedBox(
              width: 320,
              child: _buildLeftPanel(),
            ),
            // Divider
            Container(
              width: 1,
              color: Colors.white.withValues(alpha: 0.06),
            ),
            // Right panel: orb + logs
            Expanded(child: _buildRightPanel()),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6C63FF), Color(0xFF00D9FF)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.shield_outlined, size: 20, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'ByeByeDPI',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'DPI Bypass for macOS',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.4),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),

        // Port config
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _GlassCard(
            child: Row(
              children: [
                Icon(Icons.lan_outlined,
                    size: 16, color: Colors.white.withValues(alpha: 0.5)),
                const SizedBox(width: 10),
                Text('Port',
                    style: GoogleFonts.inter(
                        fontSize: 13, color: Colors.white.withValues(alpha: 0.7))),
                const Spacer(),
                SizedBox(
                  width: 70,
                  height: 32,
                  child: TextField(
                    controller: TextEditingController(text: '$_port'),
                    onChanged: (v) => _port = int.tryParse(v) ?? 1080,
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 13, color: Colors.white),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: Color(0xFF6C63FF)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Presets header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Text(
                'PRESETS',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.35),
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              // Custom args toggle
              GestureDetector(
                onTap: () => setState(() => _useCustomArgs = !_useCustomArgs),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: _useCustomArgs
                        ? const Color(0xFF6C63FF).withValues(alpha: 0.2)
                        : Colors.white.withValues(alpha: 0.05),
                    border: Border.all(
                      color: _useCustomArgs
                          ? const Color(0xFF6C63FF).withValues(alpha: 0.4)
                          : Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Text(
                    'Custom',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _useCustomArgs
                          ? const Color(0xFF6C63FF)
                          : Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Preset list or custom args
        Expanded(
          child: _useCustomArgs ? _buildCustomArgs() : _buildPresetList(),
        ),
      ],
    );
  }

  Widget _buildPresetList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: Presets.all.length,
      itemBuilder: (context, index) {
        final preset = Presets.all[index];
        final selected = index == _selectedPresetIndex;

        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _selectedPresetIndex = index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: selected
                      ? preset.accentColor.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.02),
                  border: Border.all(
                    color: selected
                        ? preset.accentColor.withValues(alpha: 0.35)
                        : Colors.white.withValues(alpha: 0.04),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(preset.emoji, style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            preset.name,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w500,
                              color: selected
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                        if (selected)
                          Icon(Icons.check_circle,
                              size: 16, color: preset.accentColor),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      preset.description.split('\n').first,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color: Colors.black.withValues(alpha: 0.3),
                        ),
                        child: Text(
                          preset.argsString,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: preset.accentColor.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCustomArgs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enter custom ciadpi flags:',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _customArgsController,
            maxLines: 6,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.9),
            ),
            decoration: InputDecoration(
              hintText: '--fake -1 --ttl 8 --auto=torst',
              hintStyle: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.2),
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.03),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF6C63FF)),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'macOS supported flags:\n'
            '  --split, --disorder, --oob, --disoob\n'
            '  --fake, --ttl, --tlsrec, --mod-http\n'
            '  --auto, --timeout, --proto, --hosts\n'
            '\nNot supported on macOS:\n'
            '  --md5sig, --drop-sack, --transparent',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              height: 1.6,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel() {
    return Column(
      children: [
        // Connection orb area
        Expanded(
          flex: 3,
          child: Center(child: _buildConnectionOrb()),
        ),
        // Log panel
        Expanded(
          flex: 2,
          child: _buildLogPanel(),
        ),
      ],
    );
  }

  Widget _buildConnectionOrb() {
    final isConnected = _proxy.status == ProxyStatus.connected;
    final isConnecting = _proxy.status == ProxyStatus.connecting;
    final isError = _proxy.status == ProxyStatus.error;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Status text
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 300),
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 3,
            color: _statusColor.withValues(alpha: 0.8),
          ),
          child: Text(_statusText),
        ),
        const SizedBox(height: 24),

        // The orb
        GestureDetector(
          onTap: _toggle,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: SizedBox(
              width: 200,
              height: 200,
              child: AnimatedBuilder(
                animation: Listenable.merge([_pulseAnimation, _orbRotationController])!,
                builder: (context, child) {
                  final scale = isConnected ? _pulseAnimation.value : 1.0;
                  return Transform.scale(
                    scale: scale,
                    child: CustomPaint(
                      painter: _OrbPainter(
                        color: _statusColor,
                        rotation: _orbRotationController.value * 2 * pi,
                        isActive: isConnected,
                        isConnecting: isConnecting,
                        isError: isError,
                      ),
                      child: Center(
                        child: Icon(
                          isConnected
                              ? Icons.shield
                              : isConnecting
                                  ? Icons.hourglass_top_rounded
                                  : isError
                                      ? Icons.error_outline
                                      : Icons.power_settings_new_rounded,
                          size: 48,
                          color: _statusColor,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Subtitle
        Text(
          isConnected
              ? 'SOCKS5 on 127.0.0.1:${_proxy.port}'
              : isConnecting
                  ? 'Establishing connection...'
                  : 'Tap to connect',
          style: GoogleFonts.inter(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.35),
          ),
        ),
        if (isConnected) ...[
          const SizedBox(height: 6),
          Text(
            _useCustomArgs
                ? 'Custom flags'
                : Presets.all[_selectedPresetIndex].name,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: _statusColor.withValues(alpha: 0.5),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLogPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.black.withValues(alpha: 0.3),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Log header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(Icons.terminal_rounded,
                    size: 14, color: Colors.white.withValues(alpha: 0.3)),
                const SizedBox(width: 8),
                Text(
                  'LOGS',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _logs.clear()),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Icon(Icons.delete_outline,
                        size: 14, color: Colors.white.withValues(alpha: 0.2)),
                  ),
                ),
              ],
            ),
          ),
          Divider(
              height: 1, color: Colors.white.withValues(alpha: 0.06)),
          // Log entries
          Expanded(
            child: _logs.isEmpty
                ? Center(
                    child: Text(
                      'No logs yet',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _logScrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      final isError = log.contains('[ERR]');
                      final isSuccess = log.contains('✓');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          log,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            height: 1.5,
                            color: isError
                                ? const Color(0xFFFF5252).withValues(alpha: 0.8)
                                : isSuccess
                                    ? const Color(0xFF00E676)
                                        .withValues(alpha: 0.8)
                                    : Colors.white.withValues(alpha: 0.45),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// --- Glass card widget ---
class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: child,
    );
  }
}

// --- Animated orb painter ---
class _OrbPainter extends CustomPainter {
  final Color color;
  final double rotation;
  final bool isActive;
  final bool isConnecting;
  final bool isError;

  _OrbPainter({
    required this.color,
    required this.rotation,
    required this.isActive,
    required this.isConnecting,
    required this.isError,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Outer glow
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
    canvas.drawCircle(center, radius * 0.9, glowPaint);

    // Base circle
    final basePaint = Paint()
      ..color = color.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.7, basePaint);

    // Border ring
    final borderPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius * 0.7, borderPaint);

    // Rotating arc segments
    if (isActive || isConnecting) {
      final arcPaint = Paint()
        ..color = color.withValues(alpha: isConnecting ? 0.4 : 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rotation);
      canvas.translate(-center.dx, -center.dy);

      final arcRect = Rect.fromCircle(center: center, radius: radius * 0.82);
      canvas.drawArc(arcRect, 0, pi / 3, false, arcPaint);
      canvas.drawArc(arcRect, pi, pi / 3, false, arcPaint);

      // Inner arcs (counter-rotate)
      canvas.restore();
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-rotation * 0.7);
      canvas.translate(-center.dx, -center.dy);

      final innerArcPaint = Paint()
        ..color = color.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;

      final innerRect = Rect.fromCircle(center: center, radius: radius * 0.58);
      canvas.drawArc(innerRect, pi / 4, pi / 4, false, innerArcPaint);
      canvas.drawArc(innerRect, pi + pi / 4, pi / 4, false, innerArcPaint);

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _OrbPainter oldDelegate) =>
      oldDelegate.rotation != rotation ||
      oldDelegate.color != color ||
      oldDelegate.isActive != isActive ||
      oldDelegate.isConnecting != isConnecting;
}


