import 'package:dartrics/src/reporters/ai_reporter.dart';
import 'package:dartrics/src/reporters/console_reporter.dart';
import 'package:dartrics/src/reporters/json_reporter.dart';
import 'package:dartrics/src/reporters/md_reporter.dart';
import 'package:dartrics/src/reporters/reporters.dart';
import 'package:dartrics/src/reporters/sarif_reporter.dart';
import 'package:test/test.dart';

void main() {
  test('every supported name resolves to its concrete reporter', () {
    expect(pickReporter('json'), isA<JsonReporter>());
    expect(pickReporter('md'), isA<MdReporter>());
    expect(pickReporter('ai'), isA<AiReporter>());
    expect(pickReporter('sarif'), isA<SarifReporter>());
    expect(pickReporter('console'), isA<ConsoleReporter>());
  });
}
