import '../config/config.dart';
import 'dismissal.dart';

/// Result of running a parsed [Dismissal] through the project's
/// [DismissalConfig] gates.
sealed class DismissalCheck {
  const DismissalCheck();
}

/// The dismissal passed every gate and should be applied to the
/// matching violation. The dismissal payload itself isn't carried —
/// callers already have the original [Dismissal] in hand from
/// [validateDismissal]'s first argument.
class DismissalAccepted extends DismissalCheck {
  const DismissalAccepted();
}

/// The dismissal matched a violation but failed validation. The
/// violation stays live; the AI report carries [reason] in
/// [MetricViolation.dismissalRejected] so loops can amend the entry.
class DismissalRejected extends DismissalCheck {
  const DismissalRejected(this.dismissal, this.reason);
  final Dismissal dismissal;
  final String reason;
}

/// Pure-function validator: runs a single [Dismissal] through the
/// configured gates and returns either [DismissalAccepted] or
/// [DismissalRejected]. Does not mutate state, so it is trivially
/// composable from both the comment scanner and the YAML loader.
DismissalCheck validateDismissal(Dismissal d, DismissalConfig cfg) {
  final reasonRejection = _checkReason(d, cfg);
  if (reasonRejection != null) return reasonRejection;
  if (d.source == DismissalSource.yaml) {
    final yamlRejection = _checkYamlMetadata(d, cfg);
    if (yamlRejection != null) return yamlRejection;
  }
  return const DismissalAccepted();
}

DismissalRejected? _checkReason(Dismissal d, DismissalConfig cfg) {
  if (!cfg.requireReason) return null;
  final trimmed = d.reason.trim();
  if (trimmed.isEmpty) return DismissalRejected(d, 'reason missing');
  if (trimmed.length < cfg.minReasonLength) {
    return DismissalRejected(
      d,
      'reason too short (need >= ${cfg.minReasonLength})',
    );
  }
  return null;
}

/// `by:` / `at:` only exist on YAML entries — `config_loader` already
/// refuses to enable [DismissalConfig.requireAuthor] /
/// [DismissalConfig.requireTimestamp] without `sources.yaml: true`, so
/// this helper can assume the dismissal is already YAML-sourced.
DismissalRejected? _checkYamlMetadata(Dismissal d, DismissalConfig cfg) {
  if (cfg.requireAuthor && (d.by == null || d.by!.trim().isEmpty)) {
    return DismissalRejected(d, 'missing required `by:` field');
  }
  if (cfg.requireTimestamp && d.at == null) {
    return DismissalRejected(d, 'missing required `at:` field');
  }
  return null;
}

/// Rejects a dismissal whose `metric` names something outside the
/// metric catalogue.
///
/// The dismiss channel is keyed on `(file, scope, metricId)`, so an id
/// that no metric emits can never match a violation. Accepting it
/// records a suppression that does nothing and reports nothing — the
/// silent no-op the channel exists to prevent. [knownIds] comes from
/// `collectRuleDescriptions()`; the caller owns that dependency so this
/// layer stays free of the metrics layer.
DismissalRejected? checkDismissalMetricId(Dismissal d, Set<String> knownIds) {
  if (knownIds.contains(d.metricId)) return null;
  return DismissalRejected(d, unknownMetricIdReason(d.metricId));
}

/// The reachability verdict's id. It reads like a metric id but isn't
/// one — `dartrics rules` doesn't list it and no violation carries it —
/// and the fix is a different config key, so it gets a targeted message
/// instead of the generic "not in the catalogue" one.
const String unusedVerdictId = 'unused';

/// Rejection text for [checkDismissalMetricId].
String unknownMetricIdReason(String id) => id == unusedVerdictId
    ? 'unknown metric id "$id" — `unused` is a reachability verdict, '
          'not a thresholded metric, and is not dismissable. Keep the '
          'declaration alive with `unused: { roots: ["<path>::<scope>"] }`, '
          '`unused: { entry-points: [...] }`, or a keep-alive annotation '
          'listed in `unused: { ignore-annotations: [...] }` instead.'
    : 'unknown metric id "$id" — not in the catalogue '
          '(run `dartrics rules` for the full list)';
