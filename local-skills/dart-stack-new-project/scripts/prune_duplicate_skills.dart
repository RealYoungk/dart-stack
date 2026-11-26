// Removes project-level skill copies that the dart-stack plugin already ships.
//
// `serverpod create` and `dart run flutter_scene:init` copy package skills
// into the project. With dart-stack installed, those copies load twice.
//
// Usage: dart prune_duplicate_skills.dart <project-dir> [--apply]
//   Without --apply it only lists what it would remove.
//
// A copy is removed only when:
// - its folder name matches a skill in this plugin, and
// - no file in it is tracked by git.
// Removed folders go to the system trash when a trash command exists,
// otherwise to a folder in the system temp directory.
//
// It also removes the `dart` entry (`dart mcp-server`) from the project's
// .mcp.json, because this plugin already starts the Dart MCP server. Other
// entries, such as `serverpod`, stay.
import 'dart:convert';
import 'dart:io';

const skillHomes = ['.claude/skills', '.agents/skills'];

Future<void> main(List<String> args) async {
  final apply = args.contains('--apply');
  final rest = args.where((a) => !a.startsWith('--')).toList();
  if (rest.length != 1) {
    stderr.writeln(
      'Usage: dart prune_duplicate_skills.dart <project-dir> [--apply]',
    );
    exitCode = 64;
    return;
  }
  final project = Directory(rest.single).absolute;

  // <plugin>/skills/dart-stack-new-project/scripts/this.dart
  final bundled = File(Platform.script.toFilePath()).parent.parent.parent;
  final bundledNames = bundled
      .listSync()
      .whereType<Directory>()
      .where((d) => File('${d.path}/SKILL.md').existsSync())
      .map(_name)
      .toSet();

  final candidates = <Directory>[];
  for (final home in skillHomes) {
    final dir = Directory('${project.path}/$home');
    if (!dir.existsSync()) continue;
    for (final d in dir.listSync().whereType<Directory>()) {
      if (bundledNames.contains(_name(d))) candidates.add(d);
    }
  }

  final removable = <Directory>[];
  final kept = <String>[];
  for (final d in candidates) {
    if (await _isTracked(project, d)) {
      kept.add(_rel(project, d));
    } else {
      removable.add(d);
    }
  }

  if (removable.isEmpty) {
    stdout.writeln('No duplicate skill copies.');
  } else {
    stdout.writeln(
      '${apply ? 'Removing' : 'Would remove'} '
      '${removable.length} duplicate skill copies:',
    );
    for (final d in removable) {
      stdout.writeln('  ${_rel(project, d)}');
    }
  }
  if (kept.isNotEmpty) {
    stdout.writeln(
      'Kept ${kept.length} git-tracked copies: ${kept.join(', ')}',
    );
  }

  final mcp = File('${project.path}/.mcp.json');
  Map<String, dynamic>? mcpJson;
  if (mcp.existsSync()) {
    final json = jsonDecode(mcp.readAsStringSync()) as Map<String, dynamic>;
    final servers = json['mcpServers'] as Map<String, dynamic>?;
    final dart = servers?['dart'] as Map<String, dynamic>?;
    if (dart != null &&
        dart['command'] == 'dart' &&
        (dart['args'] as List?)?.join(' ') == 'mcp-server') {
      mcpJson = json;
      stdout.writeln(
        '${apply ? 'Removing' : 'Would remove'} the duplicate '
        '"dart" server from .mcp.json',
      );
    }
  }

  if (!apply) return;
  if (mcpJson != null) {
    (mcpJson['mcpServers'] as Map).remove('dart');
    mcp.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(mcpJson)}\n',
    );
  }
  if (removable.isEmpty) return;

  final trash = await _trashCommand();
  Directory? fallback;
  for (final d in removable) {
    if (trash != null) {
      final r = await Process.run(trash.first, [...trash.skip(1), d.path]);
      if (r.exitCode == 0) continue;
    }
    fallback ??= await Directory.systemTemp.createTemp('dart-stack-pruned-');
    await d.rename('${fallback.path}/${_name(d.parent.parent)}-${_name(d)}');
  }
  if (fallback != null) stdout.writeln('Moved to ${fallback.path}');
  for (final home in skillHomes) {
    final dir = Directory('${project.path}/$home');
    if (dir.existsSync() && dir.listSync().isEmpty) dir.deleteSync();
  }
}

String _name(FileSystemEntity e) =>
    e.uri.pathSegments.where((s) => s.isNotEmpty).last;

String _rel(Directory root, FileSystemEntity e) =>
    e.path.substring(root.path.length + 1);

Future<bool> _isTracked(Directory project, Directory d) async {
  final r = await Process.run('git', [
    'ls-files',
    '--',
    d.path,
  ], workingDirectory: project.path);
  return r.exitCode == 0 && (r.stdout as String).trim().isNotEmpty;
}

Future<List<String>?> _trashCommand() async {
  for (final c in [
    ['trash'],
    ['gio', 'trash'],
  ]) {
    final which = await Process.run('which', [c.first]);
    if (which.exitCode == 0) return c;
  }
  return null;
}
