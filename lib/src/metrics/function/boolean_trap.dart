import 'package:analyzer/dart/ast/ast.dart';

import '../metric.dart';

/// Number of **positional** `bool`-typed formal parameters declared by
/// the function.
///
/// "Boolean-trap" is McConnell's *Code Complete* term (also Bloch's
/// *Effective Java* item 36) for a function whose call site reads as
/// `foo(true, false, true)` and forces every reader to jump to the
/// declaration to recover what each flag means. The antipattern is
/// **specifically about positional flags** — Dart's named-parameter
/// call-site `foo(animated: true, immediate: false)` puts the intent
/// on the spot, which dissolves the readability problem. The metric
/// therefore only counts positional bool parameters; named bool
/// parameters are intentionally ignored.
///
/// Detection is purely lexical on the type-annotation AST node — `bool`,
/// `bool?`, `core.bool`, and `dart.core.bool` all match. Untyped
/// parameters and parameters whose type is not literally `bool` are not
/// counted. Constructor `this.foo` and super-parameter forms are skipped
/// because their type lives on the field/super declaration; the metric
/// trips on the *user-facing* signature, which is where the call-site
/// ambiguity originates.
class BooleanTrap extends FunctionMetric {
  const BooleanTrap();

  @override
  String get id => 'boolean-trap';

  @override
  String get rationale =>
      'Boolean-trap counts the number of **positional** `bool`-typed '
      'parameters declared by the function. McConnell (*Code Complete*, '
      '2004) and Bloch (*Effective Java*, item 36) describe signatures '
      'that take two or more positional boolean flags as a readability '
      'antipattern: `foo(true, false, true)` at the call site forces '
      'every reader to jump to the declaration to recover what each '
      'flag means. Dart\'s named-parameter call site `foo(animated: '
      'true, immediate: false)` puts the intent on the spot, which '
      'dissolves the antipattern, so the metric ignores named bool '
      'parameters. Default warning threshold is 2 — the smallest '
      'positional-bool count where the call site loses self-'
      'documentation.';

  @override
  List<String> get refactorHints => const [
    'Split the function into separately named methods, one per bool — `setVisible(true)` becomes `show()` / `hide()`.',
    'Replace the bool flags with a typed enum or a small set of named factory constructors.',
    'Promote an "options" record or class so the call site reads as named fields instead of positional booleans.',
    'If only one bool is genuinely needed, make it a named parameter so the call site is `foo(force: true)` instead of `foo(true)`.',
  ];

  @override
  num compute(FunctionMetricInput input) {
    final params = input.parameters;
    if (params == null) return 0;
    var count = 0;
    for (final p in params.parameters) {
      // Named parameters carry their name at the call site
      // (`foo(animated: true)`), which dissolves the boolean-trap
      // antipattern — the reader sees the flag's purpose on the
      // spot. Only positional bool parameters are counted.
      if (p.isNamed) continue;
      if (_isBoolParameter(p)) count++;
    }
    return count;
  }

  /// `FormalParameter.type` is `null` for `this.foo` field parameters and
  /// `super.foo` parameters because their type lives on the field/super
  /// declaration; the signature itself is untyped, so a reader looking
  /// at the call site sees no `bool` here either. Function-typed
  /// parameters use a return-type annotation that is not the parameter's
  /// nominal type, so they fall through naturally.
  bool _isBoolParameter(FormalParameter p) {
    final type = p.type;
    if (type is! NamedType) return false;
    return type.name.lexeme == 'bool';
  }
}
