---
name: dart-stack-new-project
description: Set up a new Dart/Flutter project with the official CLIs, in the layout Serverpod recommends - a Serverpod backend with a Flutter app, a Flutter-only app, or a Jaspr website - and add shad, Flutter Scene, A2UI, or Patrol to it for the first time. Use when the user asks to create, start, scaffold, bootstrap, or initialize a project or app, or to add one of these packages to a project that does not use it yet. Not for work inside a project that is already set up.
---

# New project setup

Scaffolding comes from the official CLIs, never from hand-written files. This skill decides which CLI to run, in what order, and what to clean up after. Once a package is added, its own skill owns the details: read it before writing code.

## 1. Decide the shape

Ask only what you cannot infer from the request.

| The user needs | Start with |
|---|---|
| A backend (accounts, data, real-time) and an app | Serverpod, `fullstack` template |
| A backend only | Serverpod, `server` template |
| An app with no backend of its own | `flutter create` |
| A website or docs site | Jaspr (inside the Serverpod workspace if there is one) |
| Code reused across several Serverpod projects | Serverpod, `module` template |

Default to Serverpod when a backend is needed at all. Do not add Melos: a pub workspace already links the packages, and the Serverpod CLI runs generation, the server, and migrations.

## 2. Create the workspace

### Serverpod

```bash
serverpod create <name> --no-interactive --ide claude
```

- `--no-interactive` is required for an agent. Without `--ide`, non-interactive mode configures Claude, Cursor, and VS Code; `--ide claude` keeps only Claude.
- `--template server` or `--template module` changes the template. `--[no-]database`, `--[no-]redis`, `--[no-]auth`, `--[no-]webapp`, `--[no-]website` toggle features.
- The result is one pub workspace: `<name>_server`, `<name>_client` (generated, never edit), `<name>_flutter`. The root `pubspec.yaml` lists them under `workspace:`, each package has `resolution: workspace`, and one `dart pub get` at the root resolves all of them.
- It also writes `.mcp.json` with the `serverpod` MCP server (keep it), `AGENTS.md` (keep it, and follow it), and copies package skills into `.claude/skills` (remove the duplicates in step 4).
- Then read `serverpod-overview` before touching the server.

### Flutter only

```bash
flutter create --org <reverse.domain> <name>
```

### Jaspr website

Inside a Serverpod workspace, create it at the workspace root and name it `<name>_web`, following Serverpod's `<name>_<role>` convention:

```bash
jaspr create <name>_web --mode static --routing multi-page --no-pub-get
```

- `--mode`: `static` (pre-rendered), `server` (server-rendered), or `client`. Read `jaspr-pre-rendering-and-hydration` to choose. `--flutter embedded` embeds a Flutter app.
- Join it to the workspace: add `resolution: workspace` under `environment:` in its `pubspec.yaml`, add `- <name>_web` to the root `workspace:` list, then run `dart pub get` at the root.
- Known break (checked 2026-11-26): Jaspr 0.23.x templates fail version solving on Dart 3.14 (`jaspr_builder` pins `analyzer ^12`, `build_web_compilers >=4.8.11` needs `analyzer >=13.3`). The fix is the 0.24 prerelease line for all four: `jaspr: ^0.24.0-beta.2`, `jaspr_builder: ^0.24.0-beta.2`, `jaspr_router: ^0.10.0-beta.2`, `build_web_compilers: ^4.8.11`. If version solving fails some other way, check pub.dev for the newest prerelease of each package before downgrading anything.
- Verify with `dart run build_runner build` and `dart analyze` in the package.

For a few plain pages served by the Serverpod server itself, `serverpod create --website` and the `serverpod-webserver` skill are lighter than a Jaspr package.

## 3. Add packages to the Flutter app

Run these in `<name>_flutter` (or the Flutter app's folder).

| Package | Commands | Then read |
|---|---|---|
| shad (UI components) | `flutter pub add shad` | `shad-overview`, its installation guide (`ShadApp`) |
| Flutter Scene (3D) | `flutter pub add flutter_scene` then `dart run flutter_scene:init --no-skills` | `flutter_scene-idioms` |
| A2UI (agent-generated UI) | `flutter pub add a2ui_flutter a2ui_core` | `a2ui` |
| Patrol (end-to-end tests) | follow the skill | `patrol-setup` |

- `flutter_scene:init` is required, not optional. `--no-skills` stops it from copying its skills into the project; this plugin ships them. Run the app with `flutter run --enable-flutter-gpu` (native). Flutter Scene needs Flutter 3.47 stable or newer.
- Never add `genui`, `flutter_genui`, or `genui_a2ui`: they are discontinued in favor of `a2ui_flutter`, `a2ui_core`, and `a2ui_agent`.
- Pick one UI component library. shad is the default here; do not add a second one alongside it.

## 4. Remove duplicate skills

The CLIs copy package skills into the project, so they would load twice next to this plugin. List them, then remove them:

```bash
dart <this skill's directory>/scripts/prune_duplicate_skills.dart <workspace root>
dart <this skill's directory>/scripts/prune_duplicate_skills.dart <workspace root> --apply
```

It removes only folders whose names match a skill this plugin ships and that git does not track, moves them to the trash, and drops the duplicate `dart` server from `.mcp.json`. Skills from other packages (for example `petitparser-*`, `synchronized-lock`) stay. Run it again after any later `serverpod create` or `flutter_scene:init`.

## 5. Verify

1. `dart pub get` at the workspace root succeeds.
2. `dart analyze` at the root reports no errors. Infos from templates are fine.
3. Serverpod: start the stack the way `AGENTS.md` says (`serverpod runner start` in `<name>_server`), confirm it with `serverpod runner status`, then leave it running for the user.
4. Tell the user what was created, which choices you made for them, and how to run it.

Traps seen in testing (Serverpod 4.1.2, macOS, 2026-11-26):

- The runner is a background process that can keep the agent's shell waiting when its output is piped (`| tail`). Run runner commands with `</dev/null >runner.out 2>&1` and read the file, or run them in the background.
- A very long project path makes the server's build hook fail with `install_name_tool: ... larger updated load commands do not fit`. Move the project to a shorter path; it is not a code problem.
- When another Serverpod runner on the machine holds the default ports, the new one binds random ports. `serverpod runner status` prints the real ones.
