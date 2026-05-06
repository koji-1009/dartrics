import 'package:dartrics/src/dismiss/dismissal.dart';
import 'package:dartrics/src/dismiss/dismissal_index.dart';
import 'package:test/test.dart';

void main() {
  Dismissal d({
    String file = 'lib/a.dart',
    String scope = 'fn',
    String metric = 'cyclomatic-complexity',
    DismissalSource source = DismissalSource.comment,
    String reason = 'r',
    String? by,
  }) => Dismissal(
    file: file,
    scope: scope,
    metricId: metric,
    reason: reason,
    source: source,
    by: by,
  );

  test('empty index returns null for any lookup', () {
    final idx = DismissalIndex.empty();
    expect(idx.isEmpty, isTrue);
    expect(idx.lookup(file: 'lib/a.dart', scope: 'fn', metricId: 'cc'), isNull);
  });

  test('matches an entry on (file, scope, metric)', () {
    final idx = DismissalIndex.build(
      comments: [d(reason: 'why-c')],
      yaml: const [],
    );
    final hit = idx.lookup(
      file: 'lib/a.dart',
      scope: 'fn',
      metricId: 'cyclomatic-complexity',
    );
    expect(hit, isNotNull);
    expect(hit!.reason, 'why-c');
    expect(hit.source, DismissalSource.comment);
  });

  test('different file / scope / metric all miss', () {
    final idx = DismissalIndex.build(comments: [d()], yaml: const []);
    expect(idx.lookup(file: 'lib/b.dart', scope: 'fn', metricId: 'cc'), isNull);
    expect(
      idx.lookup(file: 'lib/a.dart', scope: 'other', metricId: 'cc'),
      isNull,
    );
    expect(
      idx.lookup(file: 'lib/a.dart', scope: 'fn', metricId: 'method-length'),
      isNull,
    );
  });

  test('YAML entry beats a colliding comment entry', () {
    final idx = DismissalIndex.build(
      comments: [d(reason: 'comment-side')],
      yaml: [d(source: DismissalSource.yaml, reason: 'yaml-side', by: 'me')],
    );
    final hit = idx.lookup(
      file: 'lib/a.dart',
      scope: 'fn',
      metricId: 'cyclomatic-complexity',
    );
    expect(hit!.source, DismissalSource.yaml);
    expect(hit.reason, 'yaml-side');
    expect(hit.by, 'me');
  });

  test('later YAML entry beats earlier YAML entry on the same key', () {
    final idx = DismissalIndex.build(
      comments: const [],
      yaml: [
        d(source: DismissalSource.yaml, reason: 'first'),
        d(source: DismissalSource.yaml, reason: 'second'),
      ],
    );
    final hit = idx.lookup(
      file: 'lib/a.dart',
      scope: 'fn',
      metricId: 'cyclomatic-complexity',
    );
    expect(hit!.reason, 'second');
  });
}
