import 'package:dartrics/src/metrics/function/source_lines_of_code.dart';
import 'package:test/test.dart';

import '_helpers.dart';

void main() {
  const m = SourceLinesOfCode();

  test('strips line comments and blank lines', () {
    final input = inputFor('''
int f(int x) {
  // a comment

  var y = x + 1; // trailing
  /* block
     spanning */
  return y;
}
''', name: 'f');
    // braces (2) + var y line (1) + return y line (1) = 4
    expect(m.compute(input), 4);
  });

  test('expression body still counts', () {
    final input = inputFor('int f() => 1;', name: 'f');
    expect(m.compute(input), 1);
  });
}
