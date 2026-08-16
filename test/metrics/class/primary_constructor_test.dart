import 'package:dartrics/src/metrics/class/cbo.dart';
import 'package:dartrics/src/metrics/class/class_metric.dart';
import 'package:dartrics/src/metrics/class/lcom4.dart';
import 'package:dartrics/src/metrics/class/nom.dart';
import 'package:dartrics/src/metrics/class/rfc.dart';
import 'package:dartrics/src/metrics/class/wmc.dart';
import 'package:test/test.dart';

import 'class_helpers.dart';

/// Dart 3.13 primary constructors declare the constructor and its instance
/// variables in the class header. The class-scope lenses must read that header
/// exactly as they read the long form it replaces — otherwise a mechanical
/// rewrite to the new syntax would register as a metric regression on code
/// whose behaviour did not change.
void main() {
  const source = '''
class Pc(final Dep a, final Dep b) {
  int useA() { return a.value; }
  int useB() { return b.value; }
}

class Classic {
  Classic(this.a, this.b);

  final Dep a;
  final Dep b;

  int useA() { return a.value; }
  int useB() { return b.value; }
}

class Dep {
  int get value => 0;
}
''';

  // Hand-verified against the long form: two methods, neither branching (WMC
  // 2); `useA` and `useB` share no field, so they stay separate components
  // (LCOM4 2); `Dep` is the one external type reached, through the header
  // parameters and the method bodies (CBO 2 counts the declaration and the
  // invoked `value`); both methods answer one message each (RFC 2).
  // `class-length` is deliberately absent: the two forms differ in source
  // extent by design, and that difference is what the lens is meant to see.
  const expected = {
    'number-of-methods': (NumberOfMethods(), 2),
    'weighted-methods-per-class': (WeightedMethodsPerClass(), 2),
    'lcom4': (Lcom4(), 2),
    'coupling-between-objects': (CouplingBetweenObjects(), 2),
    'response-for-class': (ResponseForClass(), 2),
  };

  expected.forEach((id, entry) {
    final (ClassMetric metric, num value) = entry;
    test('$id reads a primary constructor as its long form', () {
      expect(metric.compute(inputFor(source, className: 'Pc')), value);
      expect(metric.compute(inputFor(source, className: 'Classic')), value);
    });
  });
}
