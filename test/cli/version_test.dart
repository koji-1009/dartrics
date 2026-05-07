import 'dart:io';

import 'package:dartrics/dartrics.dart';
import 'package:dartrics/src/cli/runner.dart';
import 'package:dartrics/src/entry_point.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('dartricsVersion is exported and matches pubspec.yaml', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    final match = RegExp(
      r'^version:\s*(.+)$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull);
    expect(dartricsVersion.trim(), match!.group(1)!.trim());
  });

  test('runner registers the rules subcommand', () {
    final runner = buildCommandRunner();
    expect(runner.commands.containsKey('rules'), isTrue);
  });

  group('isVersionRequest', () {
    test('--version at top level is detected', () {
      expect(isVersionRequest(['--version']), isTrue);
      expect(isVersionRequest(['--verbose', '--version']), isTrue);
    });

    test('subcommand args are not hijacked', () {
      expect(isVersionRequest([]), isFalse);
      expect(isVersionRequest(['analyze', '--version']), isFalse);
      expect(isVersionRequest(['--', '--version']), isFalse);
      expect(isVersionRequest(['--reporter', 'ai']), isFalse);
    });
  });

  test('runApp short-circuits on --version and sets exitCode 0', () async {
    final code = await runAppQuietly(['--version']);
    expect(code, 0);
  });
}
