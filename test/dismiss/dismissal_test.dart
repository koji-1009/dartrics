import 'package:dartrics/src/dismiss/dismissal.dart';
import 'package:dartrics/src/models/analysis_report.dart';
import 'package:test/test.dart';

void main() {
  group('Dismissal', () {
    test('captures all fields including optional metadata', () {
      final at = DateTime.utc(2026, 5, 6, 19, 14);
      final d = Dismissal(
        file: 'lib/parser.dart',
        scope: 'parse',
        metricId: 'cyclomatic-complexity',
        reason: 'Recursive descent parser',
        source: DismissalSource.yaml,
        by: 'claude-opus-4-7',
        at: at,
      );
      expect(d.file, 'lib/parser.dart');
      expect(d.scope, 'parse');
      expect(d.metricId, 'cyclomatic-complexity');
      expect(d.reason, 'Recursive descent parser');
      expect(d.source, DismissalSource.yaml);
      expect(d.by, 'claude-opus-4-7');
      expect(d.at, at);
    });

    test('defaults metadata fields to null', () {
      const d = Dismissal(
        file: 'a.dart',
        scope: 'fn',
        metricId: 'method-length',
        reason: '',
        source: DismissalSource.comment,
      );
      expect(d.by, isNull);
      expect(d.at, isNull);
    });
  });

  group('MetricViolation dismissal fields', () {
    test('default constructor leaves dismissal fields empty', () {
      const v = MetricViolation(
        metricId: 'cyclomatic-complexity',
        severity: Severity.warning,
        threshold: 10,
      );
      expect(v.dismissed, isFalse);
      expect(v.dismissReason, isNull);
      expect(v.dismissedBy, isNull);
      expect(v.dismissedAt, isNull);
      expect(v.dismissedFrom, isNull);
      expect(v.dismissalRejected, isNull);
      expect(v.toJson(), isNot(contains('dismissed')));
      expect(v.toJson(), isNot(contains('dismissReason')));
      expect(v.toJson(), isNot(contains('dismissedFrom')));
    });

    test('toJson emits dismiss fields when set', () {
      final at = DateTime.utc(2026, 5, 6, 19, 14);
      final v = MetricViolation(
        metricId: 'cyclomatic-complexity',
        severity: Severity.warning,
        threshold: 10,
        dismissed: true,
        dismissReason: 'state machine',
        dismissedBy: 'claude',
        dismissedAt: at,
        dismissedFrom: DismissalSource.yaml,
      );
      final json = v.toJson();
      expect(json['dismissed'], isTrue);
      expect(json['dismissReason'], 'state machine');
      expect(json['dismissedBy'], 'claude');
      expect(json['dismissedAt'], at.toIso8601String());
      expect(json['dismissedFrom'], 'yaml');
    });

    test('toJson emits dismissalRejected without dismissed flag', () {
      const v = MetricViolation(
        metricId: 'cyclomatic-complexity',
        severity: Severity.warning,
        threshold: 10,
        dismissalRejected: 'reason too short (need >= 20)',
      );
      final json = v.toJson();
      expect(json.containsKey('dismissed'), isFalse);
      expect(json['dismissalRejected'], 'reason too short (need >= 20)');
    });
  });
}
