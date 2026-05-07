import '../config/config.dart';
import 'dismissal.dart';

/// Result of running a parsed [Dismissal] through the project's
/// [DismissalConfig] gates.
sealed class DismissalCheck {
  const DismissalCheck();
}

/// The dismissal passed every gate and should be applied to the
/// matching violation.
class DismissalAccepted extends DismissalCheck {
  const DismissalAccepted(this.dismissal);
  final Dismissal dismissal;
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
  return DismissalAccepted(d);
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
