# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Antigravity, etc.) when working with code in this repository.

## Project

Recess (课表) — a minimal Android college course-schedule app built with Flutter + Riverpod + go_router + drift. UI strings and most doc comments are in Chinese. iOS is intentionally unsupported.

## Commands

```bash
flutter pub get                                              # install deps
flutter create . --platforms=android --org io.github.jiangkaiqi2005         # regenerate Android platform dir (see below)
dart run build_runner build --delete-conflicting-outputs      # codegen: drift + go_router (after changing tables/routes)
dart run flutter_launcher_icons                              # regenerate app icons (after changing assets/icon/icon.png)
dart run flutter_native_splash:create                        # regenerate splash screen
flutter test                                                 # run all tests
flutter test test/week_calculator_test.dart                  # run a single test file
flutter analyze --fatal-infos --fatal-warnings               # lint — CI gate, must be clean
flutter build apk --release                                  # Android APK
flutter build appbundle --release                            # Android AAB
```

### Platform directories are gitignored

`android/` is gitignored and regenerated via `flutter create . --platforms=android` after a fresh clone. Do not commit generated platform directories. Android widget integration code lives in `native_templates/android/` and is documented in `WIDGET_SETUP.md`.

### Generated files

`lib/data/app_database.g.dart` is drift-generated (the `part` of `app_database.dart`). Never hand-edit; rerun `build_runner` after touching anything under `lib/data/tables/` or the `@DriftDatabase` annotation. `analysis_options.yaml` excludes `*.g.dart` from analysis.

## Architecture

Feature-first layering under `lib/`:

- `core/` — persistence-free domain: `models/` (`Course`, `Semester`), `constants/`, `theme/`, `widgets/` (shared state views), pure `utils/` (`week_calculator.dart`).
- `data/` — drift persistence: `tables/` (drift `Table` defs), `repositories/` (domain-typed data access), `mappers.dart`, `providers/`, and `app_database.dart`.
- `features/` — feature modules, each with `application/` (Riverpod providers) + `presentation/` (screens) + optionally `data/`/`domain/`: `schedule`, `course`, `semester`, `import`, `settings`, `widget`.
- `app/router.dart` — go_router route table (7 routes).

### Riverpod provider chain

`data/providers/database_providers.dart` is the root: `appDatabaseProvider` (process-singleton `AppDatabase`, drift opened on a background isolate) → `courseRepositoryProvider` / `semesterRepositoryProvider` / `coursePlatformRepositoryProvider`. Feature providers in `features/*/application/` build on these. The schedule screen consumes `scheduleCoursesProvider` (a `StreamProvider` over `CourseRepository.watchCourses`) plus `activeSemesterProvider` (`FutureProvider`). State that survives rebuilds lives in `StateNotifier`s (e.g. `SelectedWeekNotifier`, `courseFormProvider`). `ProviderScope` is set at the root in `main.dart`.

### Domain vs. persistence split (important naming collision)

drift generates data classes also named `Course` / `Semester`, identical to the domain models in `core/models/`. The convention (see `mappers.dart`) is to import `app_database.dart` with an `as db` prefix: `db.Course` = drift entity, bare `Course` = domain model. Mappers are extension methods (`toDomain()` / `toCompanion()`) that convert between the two. Repositories expose only domain models to the rest of the app.

### Database specifics

`schemaVersion = 2`; the 1→2 migration only creates the `CoursePlatforms` table, whose rows belong to a semester + course name rather than to a single course row (see `docs/adr/0001-course-platforms-keyed-by-name.md`). The `weeks` list on a course is stored as a CSV string (`"1,2,3,16"`) in the `Courses` table — not a join table — and split/joined in `mappers.dart`. On first launch `AppDatabase.seedDefaultSemester()` writes one default active semester (most recent Monday, 18 weeks) so the app never opens to an empty state; the seed is idempotent and serialized.

### Import pipeline

`features/import/` supports three sources: WebView教务-system import, ICS file, JSON file. `ImportCourse` (`domain/import_course.dart`) is the intermediate, persistence-free representation used for the preview/select UI before writing to the DB; `Course.id` is generated at write time. `coursesConflict(a, b)` checks day + section overlap + week intersection. Adding a new school's教务 system = implement `SchoolAdapter` (`loginUrl`, `isSchedulePage`, `extractJs`) in `features/import/data/`, then register it in the `schoolAdapters` list in `school_adapter.dart`. `extractJs` must emit JSON that `previewWebviewCourses` (`domain/webview_course_parser.dart`) can parse and validate.

### Routing conventions

go_router, declared once in `app/router.dart`. Screens `context.push` existing routes rather than adding new ones. `/course/edit` reads the optional existing course id from `state.extra` (a `String`); a null/missing `extra` means "create new".

### Desktop widget bridge

`features/widget/application/widget_service.dart` serializes every occurrence from today through the end of the semester to native via `home_widget`, together with a per-date teaching-week map (`semester_days`) and a `widget_loaded` marker (no App Group is configured on Android; widget provider `CourseWidgetProvider`, package `io.github.jiangkaiqi2005.recess`). Native `WidgetSelector` picks what to show from the current local time; `WidgetRefreshScheduler` re-renders at the next class boundary or midnight with an inexact alarm. Failures are swallowed — the widget is a nice-to-have and must not affect the main app. `widgetServiceProvider` is a global singleton; refreshes are triggered centrally by `_AppEffects` in `main.dart` (data-change listeners, midnight timer, app resume), not by individual screens.

## Conventions

- `dayOfWeek`: 1=Mon … 7=Sun, matching `DateTime.weekday`.
- Weeks are 1-based; `computeCurrentWeek(startDate, today)` returns 0 if before start. `currentWeekOverride` on `Semester` takes precedence over the computed week (for调课/假期).
- Default course color is `0xFF5B8DEF` (the app's primary blue); 10-color palette in the editor.
- Pure logic (week math, parsers, conflict detection) goes in `core/utils/` or `features/*/domain/` and is unit-tested. Existing tests include: `week_calculator`, `ics_parser`, `json_importer`, `import_course`, `schedule_helpers`, `course_platform_repository`, `backup_repository`, `app_database_migration`.

## CI

`.github/workflows/ci.yml` runs on push/PR to main: `pub get` → `build_runner` → `flutter analyze --fatal-infos --fatal-warnings` → `flutter test`. Pushing a `v*` tag triggers `.github/workflows/release.yml` to build Android APK/AAB. Both run on a clean checkout, so generated code is rebuilt in CI — local `*.g.dart` changes won't be committed.

## Branch Strategy

Default branch: `develop` (active development). `main` = production-ready releases only.

| Branch | Purpose | Lifecycle |
|--------|---------|-----------|
| `main` | Stable release code | Permanent, direct push after local verification |
| `develop` | Daily integration | Permanent, direct push after local verification |
| `feature/xxx` | New feature | Temporary, delete after merge |
| `fix/xxx` | Bug fix | Temporary, delete after merge |
| `release/vX.Y.Z` | Release preparation | Temporary |
| `hotfix/xxx` | Production emergency fix | Temporary |

### Branch naming

```
feature/week-view-month-date
feature/cqu-import-robustness
fix/findday-monday-shift
release/v1.0.7
hotfix/crash-on-semester-delete
```

### Commit message format

```
<type>(<scope>): <short description>
```

Types: `feat` · `fix` · `docs` · `chore` · `refactor` · `test`

### Workflow

This is a personal project. Do not open PRs unless the user explicitly asks for one or
GitHub branch protection makes a direct push impossible.

1. Work directly on `develop` for ordinary features and fixes, or use a temporary branch when isolation is useful.
2. Run code generation, strict analysis, and the full test suite before committing.
3. Commit and push directly to `develop`.
4. To release: prepare and verify the release, update `main` and `develop` directly, then tag `vX.Y.Z` and publish the GitHub Release.
5. Hotfixes start from `main`, are verified locally, then are pushed directly to both `main` and `develop`.

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues on `jiangkaiqi2005/Recess`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical triage roles use the default label strings (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` at the repo root plus `docs/adr/`. See `docs/agents/domain.md`.
