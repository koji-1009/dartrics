import 'package:dartrics/src/reporters/yaml_scalar.dart';
import 'package:test/test.dart';

void main() {
  group('yamlInlineScalar', () {
    test('passes plain values through unquoted', () {
      expect(yamlInlineScalar('hello world'), 'hello world');
      expect(
        yamlInlineScalar('McCabe, T. J. (1976). A Complexity Measure.'),
        'McCabe, T. J. (1976). A Complexity Measure.',
      );
    });

    test('quotes an empty value', () {
      expect(yamlInlineScalar(''), '""');
    });

    test('quotes values containing `:` or `#`', () {
      expect(yamlInlineScalar('a: b'), '"a: b"');
      expect(yamlInlineScalar('count#3'), '"count#3"');
    });

    test('quotes a value that starts with a YAML indicator', () {
      expect(yamlInlineScalar('- pending'), '"- pending"');
      expect(yamlInlineScalar('[WIP] note'), '"[WIP] note"');
      expect(yamlInlineScalar('& anchor'), '"& anchor"');
    });

    test('quotes leading or trailing whitespace', () {
      expect(yamlInlineScalar(' leading'), '" leading"');
      expect(yamlInlineScalar('trailing '), '"trailing "');
    });

    test('quotes and escapes newlines and tabs', () {
      expect(yamlInlineScalar('a\nb'), r'"a\nb"');
      expect(yamlInlineScalar('a\tb'), r'"a\tb"');
    });

    test('quotes values a parser would read as null / bool', () {
      expect(yamlInlineScalar('null'), '"null"');
      expect(yamlInlineScalar('true'), '"true"');
      expect(yamlInlineScalar('off'), '"off"');
    });

    test('quotes number-like values so they stay strings', () {
      expect(yamlInlineScalar('15'), '"15"');
      expect(yamlInlineScalar('1.5'), '"1.5"');
    });

    test('escapes backslashes and double quotes inside a quoted value', () {
      expect(yamlInlineScalar(r'path: C:\x "y"'), r'"path: C:\\x \"y\""');
    });
  });
}
