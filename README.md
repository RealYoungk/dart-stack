# dart-stack

An **unofficial** Claude Code plugin that bundles the **official** agent skills of the Dart ecosystem into one install:

| Upstream | Source | Skills | License |
|---|---|---|---|
| Flutter and Dart | [flutter/agent-plugins](https://github.com/flutter/agent-plugins) (`main`) | 25 | BSD-3-Clause |
| Serverpod | [`serverpod`](https://pub.dev/packages/serverpod) on pub.dev | 21 | SSPL-1.0 |
| Relic | [`relic`](https://pub.dev/packages/relic) on pub.dev | 7 | BSD-3-Clause |
| shad | [`shad`](https://pub.dev/packages/shad) on pub.dev | 1 | MIT |
| Jaspr | [`jaspr`](https://pub.dev/packages/jaspr) on pub.dev (newest prerelease, see below) | 8 | MIT |
| Flutter Scene | [`flutter_scene`](https://pub.dev/packages/flutter_scene) on pub.dev | 6 | MIT |
| Patrol | [`patrol`](https://pub.dev/packages/patrol) on pub.dev | 4 | Apache-2.0 |
| A2UI | [a2ui-project/a2ui](https://github.com/a2ui-project/a2ui) (`main`): `skills/a2ui`, `.agents/skills/a2ui-migration` | 2 | Apache-2.0 |

It also starts the Dart MCP server (`dart mcp-server`), the same way the official Flutter plugin does.

### The one skill written here

No upstream covers starting a project, so this repository adds one skill of its own, kept in [`local-skills/`](local-skills):

- **`dart-stack-new-project`**: sets up a new project with the official CLIs in the layout Serverpod recommends (one pub workspace), sets up the Flutter app with go_router and the MVVM layout from the official Flutter architecture skill (plain `ChangeNotifier`, no state management package), adds shad, Flutter Scene, A2UI, or Patrol, adds release monitoring with one free tool per area (GA4, Clarity, Crashlytics, Firebase Performance, Serverpod logs), and removes the skill copies that `serverpod create` and `flutter_scene:init` put in the project, since this plugin already ships them. It holds commands and order only; every package detail is left to that package's own skill.

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
2. The script reads the latest stable version of each pub.dev package and the latest `main` commit of each GitHub source. Jaspr is the exception: it takes the newest version, prerelease included, because the stable 0.23.x line does not resolve on Dart 3.14 and projects use the 0.24 prerelease. When a stable release passes the prerelease, the script takes that stable release.
3. If any upstream or `local-skills/` changed, it rebuilds `skills/` and `licenses/`, writes `sources.lock.json`, and bumps the plugin patch version.
4. The workflow commits the result. Claude Code picks up the new version on its next marketplace update.

Run it locally:

```bash
dart tool/sync.dart          # update
dart tool/sync.dart --check  # report only, exit 1 if outdated
```

## Licensing

Except `skills/dart-stack-new-project/` (built from `local-skills/`), every file under `skills/` is copied **verbatim** from its upstream and remains under that upstream's license. The full license texts are in [`licenses/`](licenses). This repository does not modify, relicense, or claim authorship of those skills. All credit belongs to the Flutter, Dart, Serverpod, Relic, shad, Jaspr, Flutter Scene, Patrol, and A2UI authors.

The sync script, manifests, workflow, and `local-skills/` in this repository are MIT licensed.

This project is not affiliated with or endorsed by Google, the Flutter team, Serverpod, Relic, shad, Jaspr, Flutter Scene, Patrol, or A2UI.
