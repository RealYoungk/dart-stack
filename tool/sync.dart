// Pulls the official agent skills from each upstream into skills/.
//
// Sources:
// - pub.dev packages (latest stable): serverpod, relic, shad, jaspr,
//   flutter_scene, patrol. Packages in [prereleasePackages] take the newest
//   version instead, prerelease included.
// - GitHub repositories (default branch head), see [githubSources]:
//   flutter/agent-plugins for Flutter and Dart, a2ui-project/a2ui for A2UI
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

/// Packages whose newest version, prerelease included, is taken instead of
/// the latest stable. Jaspr: the stable 0.23.x line does not resolve on
/// Dart 3.14, so projects use the 0.24 prerelease and need its skills.
const prereleasePackages = {'jaspr'};

/// GitHub sources. `paths` lists skill folders to take; null takes every
/// folder under `skills/`. Only user-facing skills are listed: repository
/// maintenance skills (PR hygiene, triage bots, releases) are left out.
const githubSources = [
  (
    key: 'flutter-agent-plugins',
    repo: 'flutter/agent-plugins',
    branch: 'main',
    paths: null,
  ),
  (
    key: 'a2ui',
    repo: 'a2ui-project/a2ui',
    branch: 'main',
    paths: ['skills/a2ui', '.agents/skills/a2ui-migration'],
  ),
];

final root = File(Platform.script.toFilePath()).parent.parent;

/// This repository's own skills. They are merged into skills/ on every sync
/// and are the only skills not copied from an upstream.
final localSkillsDir = Directory('${root.path}/local-skills');
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
      var latest = info['latest'] as Map<String, dynamic>;
      if (prereleasePackages.contains(name)) {
        // pub.dev lists versions in ascending order.
        latest = (info['versions'] as List)
            .cast<Map<String, dynamic>>()
            .lastWhere((v) => v['retracted'] != true);
      }
      lock[name] = {
        'source': 'pub.dev',
        'version': latest['version'] as String,
        'archive': latest['archive_url'] as String,
      };
    }
    for (final g in githubSources) {
      final commit = await _getJson(
        'https://api.github.com/repos/${g.repo}/commits/${g.branch}',
        github: true,
      );
      lock[g.key] = {
        'source': 'github',
        'repo': g.repo,
        'commit': commit['sha'] as String,
        'archive':
            'https://codeload.github.com/${g.repo}/tar.gz/${commit['sha']}',
        if (g.paths != null) 'paths': g.paths!.join(','),
      };
    }
    if (localSkillsDir.existsSync()) {
      lock['dart-stack'] = {
        'source': 'local',
        'version': await _hashDir(localSkillsDir),
      };
    }

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
      if (e.value['source'] == 'local') {
        for (final s in localSkillsDir.listSync().whereType<Directory>()) {
          final name = s.uri.pathSegments.where((p) => p.isNotEmpty).last;
          if (!File('${s.path}/SKILL.md').existsSync()) continue;
          if (owner.containsKey(name)) {
            throw 'Skill name clash: $name in ${owner[name]} and ${e.key}';
          }
          owner[name] = e.key;
          await _copyDir(s, Directory('${staged.path}/$name'));
        }
        continue; // Covered by this repository's own LICENSE.
      }
      final dir = Directory('${tmp.path}/src-${e.key}')..createSync();
      final archive = File('${tmp.path}/${e.key}.tar.gz');
      await _download(e.value['archive']!, archive);
      final r = await Process.run('tar', ['xzf', archive.path, '-C', dir.path]);
      if (r.exitCode != 0) throw 'tar failed for ${e.key}: ${r.stderr}';
      // GitHub tarballs wrap everything in one top-level folder.
      final base = e.value['source'] == 'github'
          ? dir.listSync().whereType<Directory>().single
          : dir;
      final List<Directory> picked;
      final paths = e.value['paths'];
      if (paths != null) {
        picked = [
          for (final p in paths.split(',')) Directory('${base.path}/$p'),
        ];
        for (final d in picked) {
          if (!File('${d.path}/SKILL.md').existsSync()) {
            throw '${e.key}: ${d.path.substring(base.path.length + 1)} has no SKILL.md';
          }
        }
      } else {
        final src = Directory('${base.path}/skills');
        if (!src.existsSync()) throw '${e.key} has no skills/ folder';
        picked = src.listSync().whereType<Directory>().toList();
      }
      for (final s in picked) {
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
          'skills':
              (owner.entries
                      .where((o) => o.value == e.key)
                      .map((o) => o.key)
                      .toList()
                    ..sort())
                  .join(','),
        },
    };
    lockFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(lockOut)}\n',
    );

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
  return keys
      .map((k) {
        final v = lock[k] as Map;
        return '$k=${v['version'] ?? v['commit']}:${v['paths'] ?? ''}';
      })
      .join(';');
}

/// FNV-1a over every file's relative path and bytes, in sorted order.
Future<String> _hashDir(Directory dir) async {
  final files =
      dir
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) => !f.path.endsWith('.DS_Store'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  var h = 0xcbf29ce484222325;
  void add(List<int> bytes) {
    for (final b in bytes) {
      h ^= b;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
  }

  for (final f in files) {
    add(utf8.encode(f.path.substring(dir.path.length)));
    add(await f.readAsBytes());
  }
  return BigInt.from(h).toUnsigned(64).toRadixString(16).padLeft(16, '0');
}

String _bumpPluginVersion() {
  final json =
      jsonDecode(pluginFile.readAsStringSync()) as Map<String, dynamic>;
  final parts = (json['version'] as String).split('.').map(int.parse).toList();
  parts[2]++;
  final version = parts.join('.');
  json['version'] = version;
  pluginFile.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(json)}\n',
  );
  return version;
}

void _setOutput(String key, String value) {
  final path = Platform.environment['GITHUB_OUTPUT'];
  if (path != null)
    File(path).writeAsStringSync('$key=$value\n', mode: FileMode.append);
}

Future<HttpClientResponse> _get(String url, {bool github = false}) async {
  final req = await http.getUrl(Uri.parse(url));
  final token = Platform.environment['GITHUB_TOKEN'];
  if (github && token != null)
    req.headers.set('Authorization', 'Bearer $token');
  final res = await req.close();
  if (res.statusCode != 200) throw 'GET $url -> ${res.statusCode}';
  return res;
}

Future<Map<String, dynamic>> _getJson(String url, {bool github = false}) async {
  final res = await _get(url, github: github);
  return jsonDecode(await res.transform(utf8.decoder).join())
      as Map<String, dynamic>;
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
