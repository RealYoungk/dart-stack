# dart-stack

An **unofficial** Claude Code plugin that bundles the **official** agent skills of the Dart ecosystem into one install:

| Upstream | Source | Skills | License |
|---|---|---|---|
| Flutter and Dart | [flutter/agent-plugins](https://github.com/flutter/agent-plugins) (`main`) | 25 | BSD-3-Clause |
| Serverpod | [`serverpod`](https://pub.dev/packages/serverpod) on pub.dev | 21 | SSPL-1.0 |
| Jaspr | [`jaspr`](https://pub.dev/packages/jaspr) on pub.dev | 5 | MIT |
| Flutter Scene | [`flutter_scene`](https://pub.dev/packages/flutter_scene) on pub.dev | 6 | MIT |

It also starts the Dart MCP server (`dart mcp-server`), the same way the official Flutter plugin does.

Exact upstream versions and the skills each one provides are in [`sources.lock.json`](sources.lock.json).

## Install

```bash
claude plugin marketplace add RealYoungk/dart-stack
claude plugin install dart-stack@dart-stack
```

If you also have the official `dart-flutter` plugin, disable it. Both define the same Flutter and Dart skills and the same MCP server.

```bash
claude plugin disable dart-flutter@dart-flutter
```

To receive updates automatically, turn on auto-update for the `dart-stack` marketplace in the `/plugin` menu.

## How updates work

1. A GitHub Actions workflow runs `dart tool/sync.dart` every day at 18:00 UTC.
2. The script reads the latest stable version of each pub.dev package and the latest `main` commit of `flutter/agent-plugins`.
3. If any upstream changed, it replaces `skills/` and `licenses/`, writes `sources.lock.json`, and bumps the plugin patch version.
4. The workflow commits the result. Claude Code picks up the new version on its next marketplace update.

Run it locally:

```bash
dart tool/sync.dart          # update
dart tool/sync.dart --check  # report only, exit 1 if outdated
```

## Licensing

Every file under `skills/` is copied **verbatim** from its upstream and remains under that upstream's license. The full license texts are in [`licenses/`](licenses). This repository does not modify, relicense, or claim authorship of those skills. All credit belongs to the Flutter, Dart, Serverpod, Jaspr, and Flutter Scene authors.

The sync script, manifests, and workflow in this repository are MIT licensed.

This project is not affiliated with or endorsed by Google, the Flutter team, Serverpod, Jaspr, or Flutter Scene.
