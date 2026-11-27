---
name: dart-stack-new-project
description: Set up a new Dart/Flutter project with the official CLIs, in the layout Serverpod recommends - a Serverpod backend with a Flutter app, a Flutter-only app, or a Jaspr website - with go_router and ChangeNotifier-based MVVM, or a Flame game, and add shad, Flutter Scene, A2UI, or Patrol to it for the first time. Use when the user asks to create, start, scaffold, bootstrap, or initialize a project or app, or to add one of these packages to a project that does not use it yet. Also use when preparing a release or adding analytics, crash reporting, session replay, or monitoring (GA4, Crashlytics, Clarity, Firebase Performance). Not for other work inside a project that is already set up.
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
| A 2D game | `flame create` (Flame). With a backend, Serverpod first, then Flame in `<name>_flutter` |
| A 3D app or game | Flutter Scene, added in step 3 |
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

### Flame game

Install the CLI once with `dart pub global activate flame_cli`, then:

```bash
flame create <name> --org <reverse.domain> --template basics --platforms <list>
```

- Templates: `simple`, `basics` (default), `example`. `--packages flame_audio,flame_tiled` adds bridge packages. See `flame-cli` for the rest, and read `flame-best-practices` before writing game code.
- In a Serverpod workspace, do not run `flame create`. In `<name>_flutter` run `flutter pub add flame dev:flame_test dev:flame_lint`, and point `analysis_options.yaml` at `flame_lint` as `flame-best-practices` says.
- Version gap (checked 2026-11-27): the Flame skills come from Flame's `main` branch and are written for Flame 2 (`2.0.0-dev`). The released `flame_cli` 0.1.0 creates Flame 1.38.2 projects and has no `flame wait` or `flame status`. When a skill rule does not match the installed version, follow the installed package's API and tell the user.
- Verify with `flutter analyze` and `flutter test` (checked: the `basics` template passes both).

### Jaspr website

Inside a Serverpod workspace, create it at the workspace root and name it `<name>_web`, following Serverpod's `<name>_<role>` convention:

```bash
jaspr create <name>_web --mode static --routing multi-page --no-pub-get
```

- `--mode`: `static` (pre-rendered), `server` (server-rendered), or `client`. Read `jaspr-pre-rendering-and-hydration` to choose. `--flutter embedded` embeds a Flutter app.
- Join it to the workspace: add `resolution: workspace` under `environment:` in its `pubspec.yaml`, add `- <name>_web` to the root `workspace:` list, then run `dart pub get` at the root.
- Known break (checked 2026-11-26): Jaspr 0.23.x templates fail version solving on Dart 3.14 (`jaspr_builder` pins `analyzer ^12`, `build_web_compilers >=4.8.11` needs `analyzer >=13.3`). The fix is the 0.24 prerelease line for all four: `jaspr: ^0.24.0-beta.2`, `jaspr_builder: ^0.24.0-beta.2`, `jaspr_router: ^0.10.0-beta.2`, `build_web_compilers: ^4.8.11`. If version solving fails some other way, check pub.dev for the newest prerelease of each package before downgrading anything.
- Verify with `dart run build_runner build` and `dart analyze` in the package.
- This plugin ships the Jaspr skills of the newest prerelease, so they match the 0.24 line. Read `jaspr-fundamentals` first; `jaspr-content` covers docs and blog sites.

For a few plain pages served by the Serverpod server itself, `serverpod create --website` and the `serverpod-webserver` skill are lighter than a Jaspr package.

## 3. Set up the Flutter app

Run these in `<name>_flutter` (or the Flutter app's folder).

### Base (always)

1. `flutter pub add go_router`, then set it up as `flutter-setup-declarative-routing` says. With shad, use `ShadApp.router(routerConfig: ...)`. Routing rules:
   - Keep the whole route tree in one `lib/routing/router.dart`. Declare navigator keys there as top-level finals, never inside `build`.
   - Guard sign-in in the top-level `redirect`, never in screens. With Serverpod auth, pass `refreshListenable: client.auth.authInfoListenable`, read `client.auth.isAuthenticated` in `redirect`, and return `null` when the user is already on the target route, or it loops.
   - Tabs whose scroll position or input must survive a switch use `StatefulShellRoute.indexedStack`. Sign-in, onboarding, and full-screen viewers sit outside the shell on the root navigator.
   - `context.go` for tab and top-level moves, `context.push` only when the user must come back to the same screen.
2. Lay out `lib/` as `flutter-apply-architecture-best-practices` says: `data/repositories/`, and `ui/features/<feature>/view_models/` and `views/`.
3. Manage state with Flutter only: ViewModels extend `ChangeNotifier`, views listen with `ListenableBuilder`, and Repositories go into ViewModels through the constructor. Create them once near `main()` and pass them down.

Do not add these unless the user asks:

- A state management package (Riverpod, bloc, provider, GetX).
- `freezed`, `json_serializable`, `http`, or `dio` in a Serverpod app. The generated client is the Service layer and `.spy.yaml` models are already immutable with `copyWith` and JSON support; Repositories wrap `client.<endpoint>.<method>()` calls. In a Flutter-only app, follow `flutter-use-http-package` and `flutter-implement-json-serialization`.
- Localization. Add it with `flutter-setup-localization` only when the app needs more than one language.

### Optional packages

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

## 6. Before release: monitoring

Not part of a new project. Do this when the user prepares a release or asks for analytics, crash reports, or monitoring. Each tool covers one area, so they do not overlap; do not add a second tool for an area that is already covered (for example PostHog next to GA4 and Clarity, or Sentry next to Crashlytics on mobile).

| Area | Tool | Cost |
|---|---|---|
| App usage analytics | GA4 (`firebase_analytics`) | Free |
| App session replay, heatmaps | Microsoft Clarity (`clarity_flutter`, Android and iOS only) | Free |
| App crashes and errors | Firebase Crashlytics (`firebase_crashlytics`, no web) | Free |
| App performance | Firebase Performance (`firebase_performance`) | Free |
| Web app errors (Flutter web, Jaspr) | Sentry (`sentry_flutter`), only when a web app ships | Free plan: 1 user, 5,000 errors per month |
| Server logs, failed and slow calls | Serverpod logging and Insights (`serverpod-logging`) | Built in |
| Server uptime | Serverpod `/readyz` (`serverpod-health-checks`) and one external uptime monitor | Built in |
| Server APM (traces, metrics) | Skip until needed; then `otel_serverpod` (third party) with Grafana Cloud | Free tier |

The user must do these, because they need the user's own accounts:

- Create the Firebase project and run `firebase login`.
- Create the Clarity project and give you its project ID (Clarity dashboard, Settings).
- Update the app's privacy policy and the store privacy forms (App Store privacy labels, Google Play data safety) for the data these tools collect.

Then, in the Flutter app:

1. `flutter pub add firebase_core firebase_analytics firebase_crashlytics firebase_performance clarity_flutter`. Add the packages before step 2, so that FlutterFire adds the Crashlytics and Performance Gradle plugins.
2. `dart pub global activate flutterfire_cli`, then `flutterfire configure` in the app folder. It writes `lib/firebase_options.dart`.
3. In `main()`: call `WidgetsFlutterBinding.ensureInitialized()`, then `await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`.
4. Send errors to Crashlytics: `FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;` and `PlatformDispatcher.instance.onError = (e, s) { FirebaseCrashlytics.instance.recordError(e, s, fatal: true); return true; };`. Skip both on web.
5. Track screens: add `FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance)` to `GoRouter(observers: [...])`. Shell branches need the observer on their own `StatefulShellBranch(observers: [...])` too.
6. Wrap the app: `runApp(ClarityWidget(app: MyApp(), clarityConfig: ClarityConfig(projectId: '<id>')))` on Android and iOS only (skip it when `kIsWeb`). Wrap sensitive widgets (passwords, payment, personal data) in `ClarityMask`.
7. After sign-in, log the user to all of them with the same opaque ID (the Serverpod user ID, never an email): `FirebaseAnalytics.instance.setUserId`, `FirebaseCrashlytics.instance.setUserIdentifier`, `Clarity.setCustomUserId`.
8. Verify on a release build: force a test crash, open a few screens, and check each dashboard. Data can take minutes to appear.
