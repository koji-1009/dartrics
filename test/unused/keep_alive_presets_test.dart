import 'package:dartrics/src/unused/keep_alive_presets.dart';
import 'package:test/test.dart';

void main() {
  test('every shipped preset has at least one annotation', () {
    expect(keepAlivePresets, isNotEmpty);
    for (final entry in keepAlivePresets.entries) {
      expect(entry.value, isNotEmpty, reason: 'preset ${entry.key}');
    }
  });

  test('allKeepAliveAnnotations is the union of every preset', () {
    final expected = <String>{};
    for (final names in keepAlivePresets.values) {
      expected.addAll(names);
    }
    expect(allKeepAliveAnnotations, equals(expected));
  });
}
