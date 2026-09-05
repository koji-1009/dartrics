import 'package:dartrics/src/config/config.dart';
import 'package:dartrics/src/dismiss/dismissal.dart';
import 'package:dartrics/src/dismiss/dismissal_validator.dart';
import 'package:test/test.dart';

void main() {
  Dismissal yaml({
    String reason = 'a perfectly fine and lengthy reason',
    String? by,
    DateTime? at,
  }) => Dismissal(
    file: 'lib/foo.dart',
    scope: 'fn',
    metricId: 'cyclomatic-complexity',
    reason: reason,
    source: DismissalSource.yaml,
    by: by,
    at: at,
  );

  Dismissal comment({String reason = 'a perfectly fine and lengthy reason'}) =>
      Dismissal(
        file: 'lib/foo.dart',
        scope: 'fn',
        metricId: 'cyclomatic-complexity',
        reason: reason,
        source: DismissalSource.comment,
      );

  test('accepts a fully-specified YAML dismissal', () {
    final res = validateDismissal(
      yaml(by: 'claude', at: DateTime.utc(2026, 5, 6)),
      const DismissalConfig(
        commentSource: true,
        yamlSource: true,
        requireAuthor: true,
        requireTimestamp: true,
      ),
    );
    expect(res, isA<DismissalAccepted>());
  });

  test('rejects empty reason when requireReason is true', () {
    final res = validateDismissal(
      yaml(reason: '   '),
      const DismissalConfig(commentSource: true, yamlSource: true),
    );
    expect(res, isA<DismissalRejected>());
    expect((res as DismissalRejected).reason, 'reason missing');
  });

  test('rejects too-short reason against minReasonLength', () {
    final res = validateDismissal(
      yaml(reason: 'short'),
      const DismissalConfig(
        commentSource: true,
        yamlSource: true,
        minReasonLength: 20,
      ),
    );
    expect(res, isA<DismissalRejected>());
    expect((res as DismissalRejected).reason, 'reason too short (need >= 20)');
  });

  test('accepts empty reason when requireReason is false', () {
    final res = validateDismissal(
      yaml(reason: ''),
      const DismissalConfig(
        commentSource: true,
        yamlSource: true,
        requireReason: false,
      ),
    );
    expect(res, isA<DismissalAccepted>());
  });

  test('rejects YAML entry missing required by', () {
    final res = validateDismissal(
      yaml(),
      const DismissalConfig(
        commentSource: true,
        yamlSource: true,
        requireAuthor: true,
      ),
    );
    expect(res, isA<DismissalRejected>());
    expect(
      (res as DismissalRejected).reason,
      contains('missing required `by:`'),
    );
  });

  test('rejects YAML entry missing required at', () {
    final res = validateDismissal(
      yaml(by: 'claude'),
      const DismissalConfig(
        commentSource: true,
        yamlSource: true,
        requireAuthor: true,
        requireTimestamp: true,
      ),
    );
    expect(res, isA<DismissalRejected>());
    expect(
      (res as DismissalRejected).reason,
      contains('missing required `at:`'),
    );
  });

  test('comment entries skip author / timestamp gates', () {
    // requireAuthor is meaningful only against YAML entries; comment
    // dismissals never carry a `by` field so the validator must not
    // reject them on that basis.
    final res = validateDismissal(
      comment(),
      const DismissalConfig(
        commentSource: true,
        yamlSource: true,
        requireAuthor: true,
        requireTimestamp: true,
      ),
    );
    expect(res, isA<DismissalAccepted>());
  });

  group('checkDismissalMetricId', () {
    const known = {'cyclomatic-complexity', 'method-length'};

    Dismissal withId(String id) => Dismissal(
      file: 'lib/foo.dart',
      scope: 'fn',
      metricId: id,
      reason: 'a perfectly fine and lengthy reason',
      source: DismissalSource.yaml,
    );

    test('accepts an id in the catalogue', () {
      expect(checkDismissalMetricId(withId('method-length'), known), isNull);
    });

    test('rejects an id outside the catalogue', () {
      final res = checkDismissalMetricId(withId('made-up'), known);
      expect(res, isNotNull);
      expect(res!.reason, contains('unknown metric id "made-up"'));
      expect(res.reason, contains('dartrics rules'));
    });

    test('rejects `unused` with a pointer at the roots config', () {
      final res = checkDismissalMetricId(withId(unusedVerdictId), known);
      expect(res, isNotNull);
      expect(res!.reason, contains('reachability verdict'));
      expect(res.reason, contains('roots'));
      expect(res.reason, contains('entry-points'));
    });
  });
}
