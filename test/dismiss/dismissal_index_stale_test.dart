import 'package:dartrics/src/dismiss/dismissal.dart';
import 'package:dartrics/src/dismiss/dismissal_index.dart';
import 'package:test/test.dart';

void main() {
  Dismissal mk({
    required String file,
    required String scope,
    required String metric,
    DismissalSource source = DismissalSource.yaml,
  }) => Dismissal(
    file: file,
    scope: scope,
    metricId: metric,
    reason: 'load-bearing',
    source: source,
  );

  test('staleEntries returns nothing on a fresh empty index', () {
    expect(DismissalIndex.empty().staleEntries(), isEmpty);
  });

  test('a successful lookup marks the entry as consumed', () {
    final index = DismissalIndex.build(
      comments: const [],
      yaml: [mk(file: 'lib/a.dart', scope: 'a', metric: 'x')],
    );
    expect(
      index.lookup(file: 'lib/a.dart', scope: 'a', metricId: 'x'),
      isNotNull,
    );
    expect(index.staleEntries(), isEmpty);
  });

  test('an unconsumed entry surfaces in staleEntries', () {
    final stale = mk(file: 'lib/gone.dart', scope: 'gone', metric: 'cc');
    final live = mk(file: 'lib/a.dart', scope: 'a', metric: 'x');
    final index = DismissalIndex.build(comments: const [], yaml: [live, stale]);
    // Look up only the live one.
    index.lookup(file: 'lib/a.dart', scope: 'a', metricId: 'x');
    final result = index.staleEntries();
    expect(result, hasLength(1));
    expect(result.single.file, 'lib/gone.dart');
    expect(result.single.scope, 'gone');
    expect(result.single.metricId, 'cc');
  });

  test('a missed lookup does not mark anything as consumed', () {
    final index = DismissalIndex.build(
      comments: const [],
      yaml: [mk(file: 'lib/a.dart', scope: 'a', metric: 'x')],
    );
    expect(
      index.lookup(file: 'lib/missing.dart', scope: 'm', metricId: 'y'),
      isNull,
    );
    // The single entry was never matched → still stale.
    expect(index.staleEntries(), hasLength(1));
  });
}
