// Fuentes de datos del medidor. No dependen de la status line, así que
// funcionan igual con Claude Code en terminal, VS Code o la app de escritorio.
//
// - Límites (5 h y semanal): el mismo endpoint que usa /usage, autenticado
//   con el token que Claude Code guarda en ~/.claude/.credentials.json.
// - Memoria del chat: el uso de tokens del último mensaje de la conversación
//   más reciente en ~/.claude/projects/<proyecto>/<sesión>.jsonl.

import 'dart:convert';
import 'dart:io';

final String claudeDir =
    '${Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.'}'
    '${Platform.pathSeparator}.claude';

/// Una ventana de límite (5 h o semanal).
class LimitWindow {
  final double usedPct;
  final DateTime resetsAt;

  LimitWindow(this.usedPct, this.resetsAt);

  static LimitWindow? fromApi(dynamic j) {
    if (j is! Map || j['utilization'] is! num) return null;
    final resets = DateTime.tryParse('${j['resets_at']}');
    if (resets == null) return null;
    return LimitWindow((j['utilization'] as num).toDouble(), resets);
  }
}

class Limits {
  final LimitWindow? fiveHour;
  final LimitWindow? sevenDay;

  Limits(this.fiveHour, this.sevenDay);

  factory Limits.fromApi(Map j) =>
      Limits(LimitWindow.fromApi(j['five_hour']), LimitWindow.fromApi(j['seven_day']));
}

/// Error de [fetchLimits] con un mensaje para mostrar tal cual.
class LimitsError implements Exception {
  final String message;
  LimitsError(this.message);
}

Future<Limits> fetchLimits() async {
  String? token;
  try {
    final creds = jsonDecode(
        await File('$claudeDir${Platform.pathSeparator}.credentials.json').readAsString());
    token = creds['claudeAiOauth']?['accessToken'] as String?;
  } catch (_) {}
  if (token == null) throw LimitsError('Inicia sesión en Claude Code');

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(Uri.parse('https://api.anthropic.com/api/oauth/usage'));
    req.headers
      ..set('Authorization', 'Bearer $token')
      ..set('anthropic-beta', 'oauth-2025-04-20');
    final res = await req.close().timeout(const Duration(seconds: 15));
    final body = await res.transform(utf8.decoder).join();
    // El token caduca; Claude Code lo renueva solo la próxima vez que se usa.
    if (res.statusCode == 401) throw LimitsError('Abre Claude Code para renovar la sesión');
    if (res.statusCode != 200) throw LimitsError('Error ${res.statusCode} al consultar el uso');
    return Limits.fromApi(jsonDecode(body) as Map);
  } on LimitsError {
    rethrow;
  } catch (_) {
    throw LimitsError('Sin conexión');
  } finally {
    client.close();
  }
}

/// Contexto ocupado por la conversación más reciente.
class ChatContext {
  final String project;
  final String model;
  final int tokens;

  ChatContext(this.project, this.model, this.tokens);

  /// Ventana de contexto según el modelo.
  int get size => model.contains('haiku') ? 200000 : 1000000;

  double get usedPct => tokens * 100 / size;

  /// "claude-opus-5-5" -> "Opus 5.5"
  String get modelName {
    final m = RegExp(r'claude-([a-z]+)-(\d+)-(\d+)').firstMatch(model);
    if (m == null) return 'Claude';
    final name = m[1]!;
    return '${name[0].toUpperCase()}${name.substring(1)} ${m[2]}.${m[3]}';
  }

  /// Entrada del transcript con uso de tokens; null si no es un mensaje
  /// del asistente en la conversación principal.
  ///
  /// [projectDir] es el nombre de la carpeta en ~/.claude/projects: la ruta
  /// donde empezó la sesión con los separadores cambiados por '-'.
  static ChatContext? fromEntry(Map e, [String projectDir = '']) {
    if (e['type'] != 'assistant' || e['isSidechain'] == true) return null;
    final msg = e['message'];
    if (msg is! Map || msg['usage'] is! Map) return null;
    final u = msg['usage'] as Map;
    int n(String k) => (u[k] as num?)?.toInt() ?? 0;
    final tokens =
        n('input_tokens') + n('cache_creation_input_tokens') + n('cache_read_input_tokens');
    if (tokens == 0) return null; // mensajes sintéticos (errores, interrupciones)
    return ChatContext(
        _projectName('${e['cwd'] ?? ''}', projectDir), '${msg['model'] ?? ''}', tokens);
  }

  /// Nombre del proyecto aunque la sesión se haya movido a una subcarpeta:
  /// el prefijo de [cwd] que corresponde a [projectDir].
  static String _projectName(String cwd, String projectDir) {
    final parts = cwd.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).toList();
    String encode(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9]'), '-').toLowerCase();
    for (var i = parts.length; i > 0; i--) {
      if (encode(parts.take(i).join('/')) == projectDir.toLowerCase()) return parts[i - 1];
    }
    return parts.isEmpty ? '' : parts.last;
  }
}

Future<ChatContext?> latestChat() async {
  final projects = Directory('$claudeDir${Platform.pathSeparator}projects');
  if (!await projects.exists()) return null;

  // Solo los transcripts principales (los de subagentes están en subcarpetas).
  File? latest;
  DateTime? latestTime;
  await for (final dir in projects.list()) {
    if (dir is! Directory) continue;
    await for (final f in dir.list()) {
      if (f is! File || !f.path.endsWith('.jsonl')) continue;
      final t = await f.lastModified();
      if (latestTime == null || t.isAfter(latestTime)) {
        latest = f;
        latestTime = t;
      }
    }
  }
  if (latest == null) return null;

  // Basta con el final del archivo: ahí está el último mensaje.
  final raf = await latest.open();
  try {
    final len = await raf.length();
    const tail = 1 << 20;
    await raf.setPosition(len > tail ? len - tail : 0);
    final text = utf8.decode(await raf.read(tail), allowMalformed: true);
    final lines = const LineSplitter().convert(text);
    for (var i = lines.length - 1; i >= 0; i--) {
      if (!lines[i].contains('"usage"')) continue;
      try {
        final c = ChatContext.fromEntry(
            jsonDecode(lines[i]) as Map, latest.parent.uri.pathSegments.lastWhere((s) => s.isNotEmpty));
        if (c != null) return c;
      } catch (_) {/* línea cortada al inicio del bloque */}
    }
  } finally {
    await raf.close();
  }
  return null;
}
