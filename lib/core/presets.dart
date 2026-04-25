import 'package:flutter/material.dart';

class DpiPreset {
  final String name;
  final String emoji;
  final String description;
  final List<String> args;
  final Color accentColor;

  const DpiPreset({
    required this.name,
    required this.emoji,
    required this.description,
    required this.args,
    required this.accentColor,
  });

  String get argsString => args.join(' ');
}

class Presets {
  static const List<DpiPreset> all = [
    DpiPreset(
      name: 'Russia (Light)',
      emoji: '🇷🇺',
      description: 'Disorder + TLS record fragmentation.\nGentle bypass for moderate DPI.',
      args: ['--disorder', '1', '--auto=torst', '--tlsrec', '1+s', '--timeout', '3'],
      accentColor: Color(0xFF5C6BC0),
    ),
    DpiPreset(
      name: 'Russia (Aggressive)',
      emoji: '🇷🇺',
      description: 'Fake packets with TTL trick.\nFor aggressive SNI-based blocking.',
      args: ['--fake', '-1', '--ttl', '8', '--auto=torst', '--timeout', '3'],
      accentColor: Color(0xFFEF5350),
    ),
    DpiPreset(
      name: 'Russia (Combined)',
      emoji: '🇷🇺',
      description: 'Multi-strategy: split + disorder + OOB.\nMaximum bypass coverage.',
      args: [
        '--split', '1+s', '--disorder', '3+s',
        '--oob', '1+s', '--auto=torst', '--timeout', '3',
      ],
      accentColor: Color(0xFFAB47BC),
    ),
    DpiPreset(
      name: 'Generic (Split)',
      emoji: '🌍',
      description: 'Basic TCP splitting at positions 3 and 7.\nWorks against simple DPI.',
      args: ['--split', '3', '--split', '7'],
      accentColor: Color(0xFF26A69A),
    ),
    DpiPreset(
      name: 'Generic (Disorder)',
      emoji: '🌍',
      description: 'Packet reordering via TTL=1.\nConfuses stateful DPI.',
      args: ['--disorder', '1'],
      accentColor: Color(0xFF42A5F5),
    ),
    DpiPreset(
      name: 'Generic (TLS Record)',
      emoji: '🌍',
      description: 'TLS record layer fragmentation.\nSplits ClientHello SNI.',
      args: ['--tlsrec', '1+s', '--auto=torst', '--timeout', '3'],
      accentColor: Color(0xFF66BB6A),
    ),
    DpiPreset(
      name: 'Generic (OOB)',
      emoji: '🌍',
      description: 'Out-of-band data injection in SNI.\nBreaks DPI reassembly.',
      args: ['--oob', '1+s', '--auto=torst', '--timeout', '3'],
      accentColor: Color(0xFFFFA726),
    ),
    DpiPreset(
      name: 'Turkey',
      emoji: '🇹🇷',
      description: 'Disorder + fake packets with lower TTL.\nOptimized for Turkish ISPs.',
      args: [
        '--disorder', '1', '--fake', '-1',
        '--ttl', '6', '--auto=torst', '--timeout', '3',
      ],
      accentColor: Color(0xFFE53935),
    ),
  ];
}
