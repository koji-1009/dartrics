import 'dart:io';

import 'package:dartrics/src/coverage/lcov_reader.dart';
import 'package:test/test.dart';

void main() {
  test('parses a minimal SF/DA/end_of_record block', () {
    const lcov = '''
SF:/repo/lib/foo.dart
DA:1,3
DA:2,0
DA:3,7
end_of_record
''';
    final index = CoverageIndex.parse(lcov);
    expect(index.files.keys, contains('/repo/lib/foo.dart'));
    final fc = index.forFile('/repo/lib/foo.dart')!;
    expect(fc.lineHits, {1: 3, 2: 0, 3: 7});
    expect(fc.branchHits, isEmpty);
  });

  test('parses BRDA branch records, including `-` as 0', () {
    const lcov = '''
SF:/repo/lib/foo.dart
BRDA:5,0,0,3
BRDA:5,0,1,-
end_of_record
''';
    final fc = CoverageIndex.parse(lcov).forFile('/repo/lib/foo.dart')!;
    expect(fc.branchHits[(5, 0, 0)], 3);
    expect(fc.branchHits[(5, 0, 1)], 0);
  });

  test('keys BRDA by (line, block, branch) so branches in different '
      'blocks on one line do not collide', () {
    // Two blocks on line 7, each with branch ids 0 and 1. Keying on
    // (line, branch) alone would collapse the four records into two
    // (last-write-wins) and report 1/2 covered instead of 3/4.
    const lcov = '''
SF:/repo/lib/foo.dart
BRDA:7,0,0,1
BRDA:7,0,1,1
BRDA:7,1,0,1
BRDA:7,1,1,0
end_of_record
''';
    final fc = CoverageIndex.parse(lcov).forFile('/repo/lib/foo.dart')!;
    expect(fc.branchHits.length, 4);
    expect(fc.branchHits[(7, 0, 0)], 1);
    expect(fc.branchHits[(7, 1, 1)], 0);
    expect(fc.branchCoverageInRange(7, 7), 0.75);
  });

  test('lineCoverageInRange averages over the range', () {
    const lcov = '''
SF:/repo/lib/foo.dart
DA:10,1
DA:11,0
DA:12,5
DA:13,0
end_of_record
''';
    final fc = CoverageIndex.parse(lcov).forFile('/repo/lib/foo.dart')!;
    expect(fc.lineCoverageInRange(10, 13), 0.5);
    // Range with no executable lines → 1.0 (vacuous truth).
    expect(fc.lineCoverageInRange(100, 200), 1.0);
  });

  test('branchCoverageInRange returns null when no BRDA in range', () {
    const lcov = '''
SF:/repo/lib/foo.dart
DA:1,1
end_of_record
''';
    final fc = CoverageIndex.parse(lcov).forFile('/repo/lib/foo.dart')!;
    expect(fc.branchCoverageInRange(1, 5), isNull);
  });

  test('branchCoverageInRange averages within the range', () {
    const lcov = '''
SF:/repo/lib/foo.dart
BRDA:5,0,0,3
BRDA:5,0,1,0
BRDA:5,0,2,4
BRDA:5,0,3,0
end_of_record
''';
    final fc = CoverageIndex.parse(lcov).forFile('/repo/lib/foo.dart')!;
    expect(fc.branchCoverageInRange(1, 10), 0.5);
  });

  test('forFile returns null for unknown paths', () {
    final fc = CoverageIndex.parse('').forFile('/missing');
    expect(fc, isNull);
  });

  test('readFile loads from disk', () async {
    final tmp = await Directory.systemTemp.createTemp('lcov_test_');
    addTearDown(() => tmp.delete(recursive: true));
    final lcov = File('${tmp.path}/lcov.info');
    await lcov.writeAsString('SF:/x\nDA:1,1\nend_of_record\n');
    final index = await CoverageIndex.readFile(lcov.path);
    expect(index.forFile('/x'), isNotNull);
  });

  test('throws FormatException on malformed DA / BRDA lines', () {
    expect(
      () => CoverageIndex.parse('SF:/x\nDA:bogus\nend_of_record\n'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => CoverageIndex.parse('SF:/x\nBRDA:1,0\nend_of_record\n'),
      throwsA(isA<FormatException>()),
    );
  });

  test('ignores unknown lines (TN, FN, etc.)', () {
    const lcov = '''
TN:
FN:1,foo
FNDA:3,foo
SF:/repo/lib/foo.dart
DA:1,1
end_of_record
''';
    final fc = CoverageIndex.parse(lcov).forFile('/repo/lib/foo.dart')!;
    expect(fc.lineHits, {1: 1});
  });

  test('drops dangling SF when end_of_record never arrives', () {
    const lcov = '''
SF:/repo/lib/foo.dart
DA:1,1
SF:/repo/lib/bar.dart
DA:2,1
end_of_record
''';
    final index = CoverageIndex.parse(lcov);
    // Only bar.dart should land — foo.dart was abandoned mid-record.
    expect(index.files.keys, ['/repo/lib/bar.dart']);
  });
}
