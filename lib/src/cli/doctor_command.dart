import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/io.dart';

import '../config/config.dart';
import '../config/config_loader.dart';
import '../metrics/metric_catalogue.dart';
import '../unused/keep_alive_presets.dart';

/// `dartrics doctor` — validates the `dartrics:` block in
/// `analysis_options.yaml` for typos, ordering issues, and references
/// to ids dartrics doesn't ship.
///
/// Surfaces two outcomes:
/// - **error** (exit 78): `ConfigException` from the loader — malformed
///   YAML or schema-level violation. The user can't continue.
/// - **warning** (exit 1): the file parses, but contains references the
///   tool cannot honour (unknown metric id, unknown preset, threshold
///   ordering inconsistent with the metric's polarity). The run would
///   silently misbehave; doctor surfaces it.
///
/// Doctor is read-only: it never edits the config. The fix is the
/// user's, and the goal is to make typos visible before they cause
/// silent under-reporting on a CI run.
class DoctorCommand extends Command<int> {
  DoctorCommand() {
    argParser.addOption(
      'config',
      help: 'Path to analysis_options.yaml.',
      defaultsTo: 'analysis_options.yaml',
    );
  }

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Validate the `dartrics:` block in analysis_options.yaml.';

  @override
  Future<int> run() async {
    final path = argResults!['config'] as String;
    final Config config;
    try {
      config = await loadConfig(path);
    } on ConfigException catch (e) {
      stderr.writeln('dartrics doctor: ${e.message}');
      return ExitCode.config.code;
    }
    final issues = diagnose(config);
    for (final issue in issues) {
      stdout.writeln('  [WARN] ${issue.message}');
      if (issue.hint != null) {
        stdout.writeln('         hint: ${issue.hint}');
      }
    }
    if (issues.isEmpty) {
      stdout.writeln('dartrics doctor: $path — clean.');
      return ExitCode.success.code;
    }
    stdout.writeln(
      'dartrics doctor: $path — ${issues.length} issue${issues.length == 1 ? '' : 's'}.',
    );
    return 1;
  }
}

/// One flagged item in the doctor report. Doctor only emits warnings
/// today; the type stays open for future severities (e.g. `info`)
/// without forcing every call site to plumb a tier through right now.
class DoctorIssue {
  const DoctorIssue({required this.message, this.hint});

  final String message;
  final String? hint;
}

/// Pure-data diagnosis of a parsed [Config]. Exposed so callers (the
/// CLI command, future `lib/dartrics.dart` exports) can reuse the same
/// rules without having to re-load the YAML.
List<DoctorIssue> diagnose(Config config) {
  final issues = <DoctorIssue>[];
  final knownMetrics = collectRuleDescriptions();
  final knownIds = knownMetrics.map((r) => r.id).toSet();
  final polarityById = {for (final r in knownMetrics) r.id: r.polarity};

  for (final entry in config.metricThresholds.entries) {
    final id = entry.key;
    final t = entry.value;
    if (!knownIds.contains(id)) {
      final hint = _didYouMean(id, knownIds);
      issues.add(
        DoctorIssue(
          message: 'unknown metric id "$id"',
          hint: hint == null ? null : 'did you mean "$hint"?',
        ),
      );
      continue;
    }
    final orderingIssue = checkThresholdOrdering(id, t, polarityById[id]!);
    if (orderingIssue != null) issues.add(orderingIssue);
  }

  for (final preset in config.unused.presets) {
    if (!keepAlivePresets.containsKey(preset)) {
      final hint = _didYouMean(preset, keepAlivePresets.keys.toSet());
      issues.add(
        DoctorIssue(
          message: 'unknown unused preset "$preset"',
          hint: hint == null ? null : 'did you mean "$hint"?',
        ),
      );
    }
  }

  return issues;
}

/// For polarity=down (lower-is-better) metrics, error must be ≥ warning.
/// For polarity=up (higher-is-better) metrics, error must be ≤ warning.
/// neutral metrics skip the ordering check — there is no universally
/// healthier direction.
///
/// The up-polarity branch is currently dormant for built-in metrics
/// (the maintainability index was the only `up` metric and was retired
/// in 0.1.0 because it adds no signal over CC + Halstead Volume + LOC).
/// The path stays live because custom embedder metrics can register
/// with up polarity. Exposed as a public top-level so tests can verify
/// the up branch via a synthetic polarity string without depending on
/// a built-in metric.
DoctorIssue? checkThresholdOrdering(
  String id,
  MetricThresholds t,
  String polarity,
) {
  final w = t.warning;
  final e = t.error;
  if (w == null || e == null) return null;
  switch (polarity) {
    case 'down':
      if (e < w) {
        return DoctorIssue(
          message:
              '"$id" has error=$e below warning=$w, '
              'but the metric is "down" (lower is better) — '
              'every error case is also a warning case, so error '
              'should be ≥ warning.',
        );
      }
    case 'up':
      if (e > w) {
        return DoctorIssue(
          message:
              '"$id" has error=$e above warning=$w, '
              'but the metric is "up" (higher is better) — '
              'error should be ≤ warning so that the more permissive '
              'level (warning) is reached first as the metric drops.',
        );
      }
    case 'neutral':
      // No universally healthier direction; ordering is user-defined.
      return null;
  }
  return null;
}

/// Levenshtein-distance "did you mean" lookup. Returns the closest
/// candidate when the distance is ≤ 2, otherwise null. The 2-edit cap
/// keeps suggestions tight enough that "foo" doesn't match "bar".
String? _didYouMean(String input, Set<String> candidates) {
  String? best;
  var bestDistance = 3; // strictly less than this to qualify
  for (final c in candidates) {
    final d = _levenshtein(input, c);
    if (d < bestDistance) {
      bestDistance = d;
      best = c;
    }
  }
  return best;
}

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  final m = a.length;
  final n = b.length;
  var prev = List<int>.generate(n + 1, (i) => i);
  var curr = List<int>.filled(n + 1, 0);
  for (var i = 1; i <= m; i++) {
    curr[0] = i;
    for (var j = 1; j <= n; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      curr[j] = [
        curr[j - 1] + 1, // insertion
        prev[j] + 1, // deletion
        prev[j - 1] + cost, // substitution
      ].reduce((x, y) => x < y ? x : y);
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[n];
}
