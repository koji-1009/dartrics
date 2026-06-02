/// Renders [value] as a YAML inline (flow) scalar that round-trips through
/// a YAML re-parser such as `dapper`'s `formatYaml`.
///
/// Plain values that can't be misread are emitted bare so the common case
/// stays terse and readable. Anything that would change meaning — a leading
/// indicator character, an embedded `:` / `#`, leading/trailing whitespace,
/// a newline or tab, or a token a parser would coerce to null / bool /
/// number — is double-quoted with `\` and `"` escaped. Without this a
/// free-text field (e.g. a user-authored dismiss reason like `- pending`
/// or `[WIP]`) would either abort the re-parse or silently lose its value.
String yamlInlineScalar(String value) {
  if (!_needsYamlQuoting(value)) return value;
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\t', r'\t');
  return '"$escaped"';
}

/// YAML indicator characters that change a scalar's meaning when they are
/// the first character of a plain (unquoted) scalar.
const _leadingIndicators = {
  '!',
  '&',
  '*',
  '[',
  ']',
  '{',
  '}',
  ',',
  '|',
  '>',
  '@',
  '`',
  '"',
  "'",
  '%',
  '-',
  '?',
};

/// Plain scalars a YAML parser would read as something other than a string.
const _reservedScalars = {
  'null',
  'Null',
  'NULL',
  '~',
  'true',
  'True',
  'TRUE',
  'false',
  'False',
  'FALSE',
  'yes',
  'Yes',
  'no',
  'No',
  'on',
  'On',
  'off',
  'Off',
};

/// Characters that force quoting wherever they appear: `:` and `#` start a
/// mapping / comment, and a newline or tab would break an inline scalar.
final _quoteTrigger = RegExp(r'[:#\n\t]');

bool _needsYamlQuoting(String value) {
  if (value.isEmpty) return true;
  if (value.startsWith(' ') || value.endsWith(' ')) return true;
  if (value.contains(_quoteTrigger)) return true;
  if (_leadingIndicators.contains(value[0])) return true;
  if (_reservedScalars.contains(value)) return true;
  return num.tryParse(value) != null;
}
