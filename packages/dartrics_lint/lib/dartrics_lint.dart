/// Public entry of the `dartrics_lint` analyzer plugin.
///
/// Two integration paths are exposed:
///
/// 1. **As a programmatic library.** Call [diagnose] with a parsed/resolved
///    [CompilationUnit] + [LineInfo] + [DartricsLintConfig] to obtain a flat
///    list of [DartricsDiagnostic] records. This is what the CLI and the
///    plugin entrypoint share.
/// 2. **As a Dart analyzer plugin.** The plugin host invokes the package
///    through `tool/analyzer_plugin/`; the plugin defers to [diagnose] for
///    every analyzed file.
library;

export 'src/config.dart';
export 'src/diagnostic.dart';
export 'src/runner.dart';
