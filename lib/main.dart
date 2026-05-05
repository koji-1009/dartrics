/// Top-level analyzer-plugin entrypoint required by `analysis_server_plugin`.
///
/// The Dart analysis server discovers this file and references the
/// [plugin] top-level variable when a project's `analysis_options.yaml`
/// enables `plugins: dartrics`.
library;

import 'src/lint/dartrics_plugin.dart';

final plugin = DartricsPlugin();
