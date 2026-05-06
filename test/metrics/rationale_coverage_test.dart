import 'package:dartrics/src/metrics/class/default_class_metrics.dart';
import 'package:dartrics/src/metrics/function/default_function_metrics.dart';
import 'package:dartrics/src/metrics/library/default_library_metrics.dart';
import 'package:test/test.dart';

void main() {
  test('every default function metric ships a non-empty rationale + hints', () {
    for (final m in defaultFunctionMetrics) {
      expect(m.rationale, isNotEmpty, reason: '${m.id} rationale');
      expect(m.refactorHints, isNotEmpty, reason: '${m.id} refactorHints');
      for (final hint in m.refactorHints) {
        expect(hint.trim(), isNotEmpty, reason: '${m.id} hint blank');
      }
    }
  });

  test('every default class metric ships a non-empty rationale + hints', () {
    for (final m in defaultClassMetrics) {
      expect(m.rationale, isNotEmpty, reason: '${m.id} rationale');
      expect(m.refactorHints, isNotEmpty, reason: '${m.id} refactorHints');
    }
  });

  test('every default library metric ships a non-empty rationale + hints', () {
    for (final m in defaultLibraryMetrics) {
      expect(m.rationale, isNotEmpty, reason: '${m.id} rationale');
      expect(m.refactorHints, isNotEmpty, reason: '${m.id} refactorHints');
    }
  });
}
