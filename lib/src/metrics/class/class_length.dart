import 'class_metric.dart';

/// Class Length (LOC) — total source lines spanned by the class declaration,
/// including its body braces, member definitions, blank lines, and comments.
class ClassLength extends ClassMetric {
  const ClassLength();

  @override
  String get id => 'class-length';

  @override
  String get rationale =>
      'Class length is the total number of source lines spanned by the '
      'class declaration, including its body braces, member '
      'definitions, blanks, and comments. It pairs with NOM and WMC '
      'to flag classes that are too large to read at a glance. Beck '
      '(*Smalltalk Best Practice Patterns*, 1996) and Fowler (*'
      'Refactoring*, 1999) both list "large class" as a primary code '
      'smell.';

  @override
  List<String> get refactorHints => const [
    'Extract the class\'s second responsibility into a collaborator ("Extract Class").',
    'Split state-only and behaviour-only sections of the class along their natural seam.',
    'Hoist mature subsections into a value object the class composes.',
  ];

  @override
  num compute(ClassMetricInput input) {
    final start = input.lineInfo
        .getLocation(input.declaration.offset)
        .lineNumber;
    final end = input.lineInfo.getLocation(input.declaration.end).lineNumber;
    return end - start + 1;
  }
}
