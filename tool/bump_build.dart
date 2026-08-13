/// Bumps the +build number in pubspec.yaml by 1.
/// Usage: dart run tool/bump_build.dart
import 'dart:io';

void main() {
  final file = File('pubspec.yaml');
  if (!file.existsSync()) {
    stderr.writeln('pubspec.yaml not found (run from repo root)');
    exit(1);
  }
  final text = file.readAsStringSync();
  final re = RegExp(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$', multiLine: true);
  final m = re.firstMatch(text);
  if (m == null) {
    stderr.writeln('Could not parse version: line (expected x.y.z+build)');
    exit(1);
  }
  final name = m.group(1)!;
  final code = int.parse(m.group(2)!) + 1;
  final next = 'version: $name+$code';
  file.writeAsStringSync(text.replaceFirst(re, next));
  stdout.writeln('Bumped to $name+$code');
}
