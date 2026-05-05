import 'dart:convert';
import 'dart:io';

import 'package:dartrics/src/reporters/sarif_reporter.dart';
import 'package:test/test.dart';

import '_test_report.dart';

void main() {
  test('emits SARIF 2.1.0 envelope with one result per violation/unused',
      () async {
    final tmp = Directory.systemTemp.createTempSync();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final out = File('${tmp.path}/r.sarif');
    final sink = out.openWrite();
    SarifReporter().report(buildSampleReport(), sink);
    await sink.close();

    final doc = jsonDecode(out.readAsStringSync()) as Map<String, Object?>;
    expect(doc['version'], '2.1.0');
    final runs = doc['runs'] as List;
    expect(runs, hasLength(1));
    final results = (runs.first as Map)['results'] as List;
    // 1 metric violation + 1 unused = 2 results
    expect(results, hasLength(2));
    final ruleIds = results.map((r) => (r as Map)['ruleId']).toSet();
    expect(ruleIds, containsAll(['cyclomatic-complexity', 'unused-declaration']));
  });
}
