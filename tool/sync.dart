// Pulls the official agent skills from each upstream into skills/.
//
// Sources:
// - pub.dev packages (latest stable): serverpod, relic, shad, jaspr,
//   flutter_scene, patrol
// - GitHub flutter/agent-plugins (main): Flutter and Dart skills
//
// Skills are copied verbatim. Each upstream LICENSE goes to licenses/.
// When any upstream version changes, the plugin patch version is bumped.
//
// Usage: dart tool/sync.dart [--check]
//   --check  report what would change, write nothing, exit 1 if outdated.
import 'dart:convert';
import 'dart:io';

const pubPackages = [
  'serverpod',
  'relic',
  'shad',
  'jaspr',
  'flutter_scene',
  'patrol',
];
const githubRepo = 'flutter/agent-plugins';
const githubBranch = 'main';

final root = File(Platform.script.toFilePath()).parent.parent;
final skillsDir = Directory('${root.path}/skills');
final licensesDir = Directory('${root.path}/licenses');
final lockFile = File('${root.path}/sources.lock.json');
final pluginFile = File('${root.path}/.claude-plugin/plugin.json');

final http = HttpClient()..userAgent = 'dart-stack-sync';

Future<void> main(List<String> args) async {
  final checkOnly = args.contains('--check');
  final tmp = await Directory.systemTemp.createTemp('dart-stack-');
  try {
    // 1. Resolve upstream versions.
    final lock = <String, Map<String, String>>{};
    for (final name in pubPackages) {
      final info = await _getJson('https://pub.dev/api/packages/$name');
      final latest = info['latest'] as Map<String, dynamic>;
      lock[name] = {
        'source': 'pub.dev',
        'version': latest['version'] as String,
        'archive': latest['archive_url'] as String,
      };
    }
    final commit = await _getJson(
        'https://api.github.com/repos/$githubRepo/commits/$githubBranch',
        github: true);
    lock['flutter-agent-plugins'] = {
      'source': 'github',
      'repo': githubRepo,
      'commit': commit['sha'] as String,
      'archive': 'https://codeload.github.com/$githubRepo/tar.gz/${commit['sha']}',
    };

    final oldLock = lockFile.existsSync()
        ? (jsonDecode(lockFile.readAsStringSync()) as Map<String, dynamic>)
        : <String, dynamic>{};
    final changed = _versionsOf(oldLock) != _versionsOf(lock);

    for (final e in lock.entries) {
      final v = e.value['version'] ?? e.value['commit']!.substring(0, 12);
      stdout.writeln('${e.key.padRight(24)} $v');
    }
    if (!changed) {
      stdout.writeln('Up to date.');
      _setOutput('changed', 'false');
      return;
    }
    if (checkOnly) {
      stdout.writeln('Update available.');
      exitCode = 1;
      return;
    }

    // 2. Download and extract each upstream.
    final staged = Directory('${tmp.path}/skills')..createSync();
    final stagedLicenses = Directory('${tmp.path}/licenses')..createSync();
    final owner = <String, String>{}; // skill name -> source
    for (final e in lock.entries) {
      final dir = Directory('${tmp.path}/src-${e.key}')..createSync();
      final archive = File('${tmp.path}/${e.key}.tar.gz');
      await _download(e.value['archive']!, archive);
      final r = await Process.run('tar', ['xzf', archive.path, '-C', dir.path]);
      if (r.exitCode != 0) throw 'tar failed for ${e.key}: ${r.stderr}';
      // GitHub tarballs wrap everything in one top-level folder.
      final base = e.value['source'] == 'github'
          ? dir.listSync().whereType<Directory>().single
          : dir;
      final src = Directory('${base.path}/skills');
      if (!src.existsSync()) throw '${e.key} has no skills/ folder';
      for (final s in src.listSync().whereType<Directory>()) {
        final name = s.uri.pathSegments.where((p) => p.isNotEmpty).last;
        if (!File('${s.path}/SKILL.md').existsSync()) continue;
        if (owner.containsKey(name)) {
          throw 'Skill name clash: $name in ${owner[name]} and ${e.key}';
        }
        owner[name] = e.key;
        await _copyDir(s, Directory('${staged.path}/$name'));
      }
      final license = File('${base.path}/LICENSE');
      if (!license.existsSync()) throw '${e.key} has no LICENSE';
      license.copySync('${stagedLicenses.path}/${e.key}.LICENSE');
    }

    // 3. Replace skills/ and licenses/ in one step.
    for (final d in [skillsDir, licensesDir]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    await _copyDir(staged, skillsDir);
    await _copyDir(stagedLicenses, licensesDir);

    final lockOut = {
      for (final e in lock.entries)
        e.key: {
          ...e.value,
          'skills': (owner.entries
                  .where((o) => o.value == e.key)
                  .map((o) => o.key)
                  .toList()
                ..sort())
              .join(','),
        }
    };
    lockFile.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(lockOut)}\n');

    final version = _bumpPluginVersion();
    stdout.writeln('Synced ${owner.length} skills. Plugin version $version.');
    _setOutput('changed', 'true');
    _setOutput('version', version);
  } finally {
    http.close();
    tmp.deleteSync(recursive: true);
  }
}

String _versionsOf(Map<String, dynamic> lock) {
  final keys = lock.keys.toList()..sort();
  return keys.map((k) {
    final v = lock[k] as Map;
    return '$k=${v['version'] ?? v['commit']}';
  }).join(';');
}

String _bumpPluginVersion() {
  final json = jsonDecode(pluginFile.readAsStringSync()) as Map<String, dynamic>;
  final parts = (json['version'] as String).split('.').map(int.parse).toList();
  parts[2]++;
  final version = parts.join('.');
  json['version'] = version;
  pluginFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(json)}\n');
  return version;
}

void _setOutput(String key, String value) {
  final path = Platform.environment['GITHUB_OUTPUT'];
  if (path != null) File(path).writeAsStringSync('$key=$value\n', mode: FileMode.append);
}

Future<HttpClientResponse> _get(String url, {bool github = false}) async {
  final req = await http.getUrl(Uri.parse(url));
  final token = Platform.environment['GITHUB_TOKEN'];
  if (github && token != null) req.headers.set('Authorization', 'Bearer $token');
  final res = await req.close();
  if (res.statusCode != 200) throw 'GET $url -> ${res.statusCode}';
  return res;
}

Future<Map<String, dynamic>> _getJson(String url, {bool github = false}) async {
  final res = await _get(url, github: github);
  return jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
}

Future<void> _download(String url, File to) async {
  final res = await _get(url);
  await res.pipe(to.openWrite());
}

Future<void> _copyDir(Directory from, Directory to) async {
  to.createSync(recursive: true);
  await for (final e in from.list(recursive: true, followLinks: false)) {
    final rel = e.path.substring(from.path.length + 1);
    if (e is Directory) {
      Directory('${to.path}/$rel').createSync(recursive: true);
    } else if (e is File) {
      File('${to.path}/$rel').parent.createSync(recursive: true);
      e.copySync('${to.path}/$rel');
    }
  }
}
