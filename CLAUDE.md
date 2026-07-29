# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Antigravity, etc.) when working with code in this repository.

## Project

Hormone (课表) — a minimal college course-schedule app for iOS/Android, built with Flutter + Riverpod + go_router + drift. UI strings and most doc comments are in Chinese.

## Commands

```bash
flutter pub get                                              # install deps
flutter create . --platforms=android,ios                     # regenerate platform dirs (see below)
dart run build_runner build --delete-conflicting-outputs      # codegen: drift + go_router (after changing tables/routes)
dart run flutter_launcher_icons                              # regenerate app icons (after changing assets/icon/icon.png)
dart run flutter_native_splash:create                        # regenerate splash screen
flutter test                                                 # run all tests
flutter test test/week_calculator_test.dart                  # run a single test file
flutter analyze --fatal-infos --fatal-warnings               # lint — CI gate, must be clean
flutter build apk --release                                  # Android APK
flutter build appbundle --release                            # Android AAB
flutter build ios --release --no-codesign                    # iOS (no signing)
```

### Platform directories are gitignored

`android/`, `ios/`, `macos/`, `windows/`, `linux/`, `web/` are all in `.gitignore`. They are regenerated from the templates in `native_templates/` via `flutter create . --platforms=android,ios` after a fresh clone. Do not commit platform directories. Native widget integration code lives in `native_templates/` and is documented in `WIDGET_SETUP.md`.

### Generated files

`lib/data/app_database.g.dart` is drift-generated (the `part` of `app_database.dart`). Never hand-edit; rerun `build_runner` after touching anything under `lib/data/tables/` or the `@DriftDatabase` annotation. `analysis_options.yaml` excludes `*.g.dart` from analysis.

## Architecture

Feature-first layering under `lib/`:

- `core/` — persistence-free domain: `models/` (`Course`, `Semester`), `constants/`, `theme/`, pure `utils/` (`week_calculator.dart`).
- `data/` — drift persistence: `tables/` (drift `Table` defs), `repositories/` (domain-typed data access), `mappers.dart`, `providers/`, and `app_database.dart`.
- `features/` — feature modules, each with `application/` (Riverpod providers) + `presentation/` (screens) + optionally `data/`/`domain/`: `schedule`, `course`, `semester`, `import`, `settings`, `widget`.
- `app/router.dart` — go_router route table (6 routes).

### Riverpod provider chain

`data/providers/database_providers.dart` is the root: `appDatabaseProvider` (process-singleton `AppDatabase`, drift opened on a background isolate) → `courseRepositoryProvider` / `semesterRepositoryProvider`. Feature providers in `features/*/application/` build on these. The schedule screen consumes `scheduleCoursesProvider` (a `StreamProvider` over `CourseRepository.watchCourses`) plus `activeSemesterProvider` (`FutureProvider`). State that survives rebuilds lives in `StateNotifier`s (e.g. `SelectedWeekNotifier`, `courseFormProvider`). `ProviderScope` is set at the root in `main.dart`.

### Domain vs. persistence split (important naming collision)

drift generates data classes also named `Course` / `Semester`, identical to the domain models in `core/models/`. The convention (see `mappers.dart`) is to import `app_database.dart` with an `as db` prefix: `db.Course` = drift entity, bare `Course` = domain model. Mappers are extension methods (`toDomain()` / `toCompanion()`) that convert between the two. Repositories expose only domain models to the rest of the app.

### Database specifics

`schemaVersion = 1`. The `weeks` list on a course is stored as a CSV string (`"1,2,3,16"`) in the `Courses` table — not a join table — and split/joined in `mappers.dart`. On first launch `AppDatabase.seedDefaultSemester()` writes one default active semester (most recent Monday, 18 weeks) so the app never opens to an empty state; the seed is idempotent and serialized.

### Import pipeline

`features/import/` supports three sources: WebView教务-system import, ICS file, JSON file. `ImportCourse` (`domain/import_course.dart`) is the intermediate, persistence-free representation used for the preview/select UI before writing to the DB; `Course.id` is generated at write time. `coursesConflict(a, b)` checks day + section overlap + week intersection. Adding a new school's教务 system = implement `SchoolAdapter` (`loginUrl`, `scheduleUrl`, `isSchedulePage`, `extractJs`) in `features/import/data/`, then register it in the `schoolAdapters` list in `school_adapter.dart`. `extractJs` must emit JSON parseable by `ExtractedCourse.fromJson`.

### Routing conventions

go_router, declared once in `app/router.dart`. Screens `context.push` existing routes rather than adding new ones. `/course/edit` reads the optional existing course id from `state.extra` (a `String`); a null/missing `extra` means "create new".

### Desktop widget bridge

`features/widget/application/widget_service.dart` serializes today's courses to native via `home_widget` (App Group `group.hormone`, widget name `CourseWidget` / `CourseWidgetProvider`). Failures are swallowed — the widget is a nice-to-have and must not affect the main app. `widgetServiceProvider` is a global singleton invoked after imports/edits to refresh.

## Conventions

- `dayOfWeek`: 1=Mon … 7=Sun, matching `DateTime.weekday`.
- Weeks are 1-based; `computeCurrentWeek(startDate, today)` returns 0 if before start. `currentWeekOverride` on `Semester` takes precedence over the computed week (for调课/假期).
- Default course color is `0xFF5B8DEF` (the app's primary blue); 10-color palette in the editor.
- Pure logic (week math, parsers, conflict detection) goes in `core/utils/` or `features/*/domain/` and is unit-tested. Existing tests: `week_calculator`, `ics_parser`, `json_importer`, `import_course`.

## CI

`.github/workflows/ci.yml` runs on push/PR to main: `pub get` → `build_runner` → `flutter analyze --fatal-infos --fatal-warnings` → `flutter test`. Pushing a `v*` tag triggers `.github/workflows/release.yml` (Android APK/AAB + unsigned iOS). Both run on a clean checkout, so generated code is rebuilt in CI — local `*.g.dart` changes won't be committed.
