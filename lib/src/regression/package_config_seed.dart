import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Seeds `<targetRoot>/.dart_tool/package_config.json` from the one
/// under [sourceRoot], so analysis inside a freshly mounted worktree
/// resolves `package:` imports. `git worktree add` checks out tracked
/// files only and `.dart_tool/` is untracked, so without this step the
/// historical side of a regression diff has no package resolution and
/// the resolution-dependent metrics (CBO, RFC, the Martin lenses)
/// silently drift against the working-tree side even on identical code.
///
/// The config is rewritten through [rewritePackageConfig] on the way:
/// relative `rootUri` entries that resolve inside [repoTop] stay
/// relative (the worktree checks out the whole repository, and the
/// analysis root maps to the same repo-relative sub-directory, so the
/// same relative URI points at the matching historical source); ones
/// escaping the repository are anchored at their original absolute
/// location.
///
/// Best-effort by design: a missing source config is skipped (the
/// project may simply not have run `dart pub get` — analysis then
/// degrades symmetrically on both sides, the pre-existing behaviour),
/// and if the compared refs disagree about dependencies the seeded
/// resolution reflects the working tree's `pub get` state.
void seedWorktreePackageConfig({
  required String sourceRoot,
  required String targetRoot,
  required String repoTop,
}) {
  final sourceFile = File(
    p.join(sourceRoot, '.dart_tool', 'package_config.json'),
  );
  if (!sourceFile.existsSync()) return;
  final rewritten = rewritePackageConfig(
    sourceFile.readAsStringSync(),
    sourceDir: sourceFile.parent.path,
    repoTop: repoTop,
  );
  File(p.join(targetRoot, '.dart_tool', 'package_config.json'))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(rewritten);
}

/// Pure rewrite core of [seedWorktreePackageConfig]. [sourceDir] is the
/// directory the original `package_config.json` lives in — the base
/// every relative `rootUri` is defined against per the package-config
/// v2 spec.
///
/// Entries pass through untouched except relative `rootUri`s that
/// resolve outside [repoTop] (path dependencies living next to the
/// repository, not inside it): those would silently dangle from the
/// worktree's location, so they are rewritten to absolute `file:` URIs.
/// Content that is not the expected JSON shape is returned verbatim —
/// a config dartrics cannot read is still better copied than dropped.
String rewritePackageConfig(
  String raw, {
  required String sourceDir,
  required String repoTop,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return raw;
  }
  if (decoded is! Map<String, Object?>) return raw;
  final packages = decoded['packages'];
  if (packages is! List) return raw;
  for (final entry in packages) {
    if (entry is Map<String, Object?>) {
      _rewriteEntry(entry, sourceDir: sourceDir, repoTop: repoTop);
    }
  }
  return jsonEncode(decoded);
}

/// Rewrites a single package entry's `rootUri` in place when — and only
/// when — it is a relative URI resolving outside [repoTop]. Everything
/// else (absolute URIs, unparsable or missing `rootUri`s, repo-internal
/// paths) is left exactly as found.
void _rewriteEntry(
  Map<String, Object?> entry, {
  required String sourceDir,
  required String repoTop,
}) {
  final rootUri = entry['rootUri'];
  if (rootUri is! String) return;
  final uri = Uri.tryParse(rootUri);
  if (uri == null || uri.hasScheme) return;
  final resolved = p.normalize(p.join(sourceDir, p.fromUri(uri)));
  if (p.equals(resolved, repoTop) || p.isWithin(repoTop, resolved)) return;
  entry['rootUri'] = p.toUri(resolved).toString();
}
