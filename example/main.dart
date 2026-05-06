// Minimal example: compute a single function metric on inline source.
//
// Most users will run `dartrics analyze .` from the command line. This
// file shows how to drive an individual metric calculator from Dart for
// custom tooling — e.g. building a CI bot or an editor extension.

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:dartrics/dartrics.dart';

void main() {
  const source = '''
int classify(int x, int y) {
  if (x > 0 && y > 0) return 1;
  if (x < 0 || y < 0) return -1;
  return 0;
}
''';

  final unit = parseString(content: source).unit;
  final declaration = unit.declarations.whereType<FunctionDeclaration>().single;
  final input = FunctionMetricInput(
    context: (
      unit: unit,
      source: source,
      lineInfo: parseString(content: source).lineInfo,
    ),
    declaration: declaration,
  );

  // Each metric ships its own short rationale and a list of refactor hints
  // — `dartrics rules` emits them for the whole catalogue.
  const cc = CyclomaticComplexity();
  print('${cc.id} = ${cc.compute(input)}');
  print('rationale: ${cc.rationale}');
  print('refactor hints:');
  for (final hint in cc.refactorHints) {
    print('- $hint');
  }
  print('dartrics version: $dartricsVersion');
}
