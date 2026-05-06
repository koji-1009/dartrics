import 'package:dartrics/src/unused/keep_alive_presets.dart';
import 'package:test/test.dart';

void main() {
  test('every shipped preset has at least one annotation', () {
    expect(keepAlivePresets, isNotEmpty);
    for (final entry in keepAlivePresets.entries) {
      expect(entry.value, isNotEmpty, reason: 'preset ${entry.key}');
    }
  });

  test('expandPresets unions known preset annotation sets', () {
    final expanded = expandPresets(['freezed', 'json_serializable']);
    expect(expanded, containsAll(keepAlivePresets['freezed']!));
    expect(expanded, containsAll(keepAlivePresets['json_serializable']!));
  });

  test('expandPresets silently ignores unknown preset names', () {
    final expanded = expandPresets(['no_such_preset', 'freezed']);
    expect(expanded, equals(keepAlivePresets['freezed']!.toSet()));
  });

  test('expandPresets returns empty for an empty input', () {
    expect(expandPresets(const []), isEmpty);
  });
}
