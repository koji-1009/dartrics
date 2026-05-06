import 'dart:io';

import 'package:dartrics/src/reporters/console_reporter.dart';
import 'package:test/test.dart';

import 'sample_report.dart';

void main() {
  test(
    'writes summary line plus per-violation and per-unused entries',
    () async {
      final dir = await Directory.systemTemp.createTemp('console_reporter_');
      addTearDown(() => dir.delete(recursive: true));
      final out = File('${dir.path}/r.txt');
      final sink = out.openWrite();
      ConsoleReporter().report(buildSampleReport(), sink);
      await sink.close();
      final body = await out.readAsString();
      expect(body, contains('analyzed'));
      expect(body, contains('cyclomatic-complexity'));
      expect(body, contains('Foo.bar'));
      expect(body, contains('_legacyFormatter'));
    },
  );
}
