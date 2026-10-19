// Widget flotante: límites de uso de Claude y memoria del chat actual.
// Los datos se leen directamente (ver sources.dart), sin status line.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'sources.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const options = WindowOptions(
    size: Size(300, 250),
    minimumSize: Size(300, 250),
    alwaysOnTop: true,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setAsFrameless();
    await windowManager.setResizable(false);
    await windowManager.setAlignment(Alignment.bottomRight);
    await windowManager.show();
  });

  runApp(const ClaudeMeterApp());
}

class ClaudeMeterApp extends StatelessWidget {
  const ClaudeMeterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const MeterPage(),
    );
  }
}

class MeterPage extends StatefulWidget {
  const MeterPage({super.key});

  @override
  State<MeterPage> createState() => _MeterPageState();
}

class _MeterPageState extends State<MeterPage> {
  // Los límites se consultan a la API cada minuto; el chat se lee del disco
  // cada pocos segundos (es local y barato).
  static const _limitsEvery = Duration(seconds: 60);
  static const _chatEvery = Duration(seconds: 3);

  Limits? _limits;
  String? _limitsError;
  DateTime? _limitsAt;
  bool _fetching = false;
  ChatContext? _chat;
  final List<Timer> _timers = [];

  @override
  void initState() {
    super.initState();
    _refreshLimits();
    _refreshChat();
    _timers
      ..add(Timer.periodic(_limitsEvery, (_) => _refreshLimits()))
      ..add(Timer.periodic(_chatEvery, (_) => _refreshChat()))
      // Cuenta regresiva y "actualizado hace…".
      ..add(Timer.periodic(const Duration(seconds: 1), (_) => setState(() {})));
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  Future<void> _refreshLimits() async {
    if (_fetching) return;
    _fetching = true;
    try {
      _limits = await fetchLimits();
      _limitsError = null;
      _limitsAt = DateTime.now();
    } on LimitsError catch (e) {
      _limitsError = e.message; // se conservan los últimos datos buenos
    } finally {
      _fetching = false;
    }
    if (mounted) setState(() {});
  }

  Future<void> _refreshChat() async {
    try {
      _chat = await latestChat();
    } catch (_) {/* transcript a medio escribir: se reintenta */}
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = _limits;
    final c = _chat;
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white12),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(model: c?.modelName ?? 'Claude', onRefresh: _refreshLimits),
            _limitBar('Sesión (5 h)', l?.fiveHour, showDays: false),
            _limitBar('Semana', l?.sevenDay, showDays: true),
            _Bar(
              label: 'Memoria del chat',
              pct: c?.usedPct,
              detail: c == null
                  ? 'sin conversaciones'
                  : '${c.project} · ${_tokens(c.tokens, c.size)}',
            ),
            const Spacer(),
            Text(
              _limitsError ??
                  (_limitsAt == null ? 'Consultando…' : 'Actualizado ${_ago(_limitsAt!)}'),
              style: TextStyle(
                fontSize: 10,
                color: _limitsError == null ? Colors.white38 : Colors.amber,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _limitBar(String label, LimitWindow? w, {required bool showDays}) {
    if (w == null) {
      return _Bar(label: label, pct: null, detail: _limits == null ? '' : 'sin datos');
    }
    final left = w.resetsAt.difference(DateTime.now());
    if (left.isNegative) {
      return _Bar(label: label, pct: 0, detail: 'reiniciado ✓');
    }
    return _Bar(
      label: label,
      pct: w.usedPct,
      detail: 'reinicia en ${_countdown(left, showDays)}',
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _countdown(Duration d, bool showDays) {
    final days = d.inDays;
    final h = d.inHours % 24, m = d.inMinutes % 60, s = d.inSeconds % 60;
    if (showDays && days > 0) return '${days}d ${_two(h)}:${_two(m)}:${_two(s)}';
    return '${_two(d.inHours)}:${_two(m)}:${_two(s)}';
  }

  static String _tokens(int used, int size) {
    String k(int n) => n >= 1000000
        ? '${(n / 1000000).toStringAsFixed(1)}M'
        : '${(n / 1000).round()}k';
    return '${k(used)} / ${k(size)}';
  }

  static String _ago(DateTime t) {
    final s = DateTime.now().difference(t).inSeconds;
    if (s < 60) return 'hace ${s.clamp(0, 59)} s';
    if (s < 3600) return 'hace ${s ~/ 60} min';
    return 'hace ${s ~/ 3600} h';
  }
}

class _Header extends StatelessWidget {
  final String model;
  final VoidCallback onRefresh;
  const _Header({required this.model, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          // Arrastra la ventana desde aquí.
          child: DragToMoveArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Claude · $model',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Actualizar',
          iconSize: 16,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.refresh),
          onPressed: onRefresh,
        ),
        IconButton(
          tooltip: 'Cerrar',
          iconSize: 16,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close),
          onPressed: () => windowManager.close(),
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final String label;
  final double? pct; // porcentaje usado
  final String detail;

  const _Bar({required this.label, required this.pct, this.detail = ''});

  Color _color(double p) {
    if (p >= 90) return Colors.redAccent;
    if (p >= 70) return Colors.amber;
    return Colors.greenAccent;
  }

  @override
  Widget build(BuildContext context) {
    final p = pct?.clamp(0, 100).toDouble();
    const small = TextStyle(fontSize: 10, color: Colors.white54);
    return Padding(
      padding: const EdgeInsets.only(top: 7, right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
              const Spacer(),
              Text(
                p == null ? '--' : 'te queda ${(100 - p).round()} %',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: p == null ? Colors.white60 : _color(p),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: p == null ? 0 : p / 100,
              minHeight: 5,
              backgroundColor: Colors.white10,
              color: p == null ? Colors.white24 : _color(p),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(p == null ? '' : 'usado ${p.round()} %', style: small),
              const Spacer(),
              Text(detail, style: small),
            ],
          ),
        ],
      ),
    );
  }
}
