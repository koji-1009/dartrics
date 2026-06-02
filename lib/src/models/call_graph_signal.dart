import 'analysis_report.dart';

/// Per-declaration call-graph numbers derived from the element-resolved
/// reachability pass. Signals carry no threshold and no severity — they
/// are *reference information*, not violations. The AI reporter surfaces
/// them in a dedicated `signals:` block so downstream agents read them as
/// "compare against your own intent" rather than "fix this".
///
/// The signal is emitted per project-local declaration the resolved
/// reachability pass already tracked (top-level + class / mixin /
/// extension / extension-type members + enum values + top-level
/// variables). Off-project references (SDK, dependency package) are
/// excluded both as sources and as targets — the same scoping rule the
/// reachability BFS already uses.
class CallGraphSignal {
  const CallGraphSignal({
    required this.file,
    required this.scope,
    required this.fanInCallers,
    required this.fanInCalls,
    required this.fanOutCallees,
    required this.fanOutCalls,
  });

  /// Project-relative path of the file declaring the scope.
  final String file;

  /// The declaration the signal is anchored to.
  final ScopeRef scope;

  /// Number of distinct declarations that reference this one. Useful
  /// as a refactoring blast-radius measure: "renaming this changes
  /// fan-in-callers files / scopes."
  final int fanInCallers;

  /// Total invocation-edge count pointing at this declaration —
  /// `A → this` counted once per textual reference in `A`'s body.
  /// Useful as a churn / hot-path measure.
  final int fanInCalls;

  /// Number of distinct project-local declarations this scope
  /// references. Counts dependencies, not call sites.
  final int fanOutCallees;

  /// Total invocation-edge count originating from this scope.
  /// Calling `foo()` three times yields `fanOutCalls += 3`.
  final int fanOutCalls;

  Map<String, Object?> toJson() => {
    'file': file,
    'scope': scope.toJson(),
    'fanInCallers': fanInCallers,
    'fanInCalls': fanInCalls,
    'fanOutCallees': fanOutCallees,
    'fanOutCalls': fanOutCalls,
  };

  /// Ranks the most-connected declarations first: fan-in callers
  /// descending, then fan-out callees as the tiebreak. Shared by every
  /// reporter that emits a signals block so the ordering stays identical
  /// across formats.
  static int byConnectivity(CallGraphSignal a, CallGraphSignal b) {
    final byFanIn = b.fanInCallers.compareTo(a.fanInCallers);
    if (byFanIn != 0) return byFanIn;
    return b.fanOutCallees.compareTo(a.fanOutCallees);
  }
}
