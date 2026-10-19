import 'package:flutter_test/flutter_test.dart';

import 'package:claude_meter/sources.dart';

void main() {
  test('Limits.fromApi lee utilización y reinicio', () {
    final l = Limits.fromApi({
      'five_hour': {'utilization': 25.0, 'resets_at': '2026-10-14T18:19:59.53591-04:00'},
      'seven_day': null,
    });
    expect(l.fiveHour?.usedPct, 25);
    expect(l.fiveHour?.resetsAt, DateTime.utc(2026, 10, 14, 22, 19, 59, 535, 910));
    expect(l.sevenDay, isNull);
  });

  test('ChatContext.fromEntry suma los tokens de entrada', () {
    final c = ChatContext.fromEntry({
      'type': 'assistant',
      'cwd': r'C:\Users\U\Proyectos\Mcbomaps\backend',
      'message': {
        'model': 'claude-opus-5-5',
        'usage': {
          'input_tokens': 2,
          'cache_creation_input_tokens': 821,
          'cache_read_input_tokens': 490479,
          'output_tokens': 4864,
        },
      },
    }, 'C--Users-U-Proyectos-Mcbomaps')!;
    expect(c.tokens, 491302);
    expect(c.project, 'Mcbomaps');
    expect(c.modelName, 'Opus 5.5');
    expect(c.usedPct, closeTo(49.1, 0.1));
  });

  test('ChatContext.fromEntry ignora subagentes y mensajes de usuario', () {
    expect(ChatContext.fromEntry({'type': 'user'}), isNull);
    expect(
      ChatContext.fromEntry({
        'type': 'assistant',
        'isSidechain': true,
        'message': {'usage': {'input_tokens': 5}},
      }),
      isNull,
    );
  });
}
