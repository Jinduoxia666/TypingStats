# Repository Guidelines

## Project Structure & Module Organization

TypingStats is a Swift 5.9 macOS menu bar application packaged with SwiftPM. App code lives under `Sources/TypingStats`:

- `App/` application entry point and shared state.
- `MenuBar/` and `UI/` SwiftUI views.
- `Monitoring/`, `Permissions/`, `Stats/`, `Storage/`, `Sync/`, and `Export/` hold domain services.
- `Resources/` contains `Info.plist`, app entitlements, and `AppIcon.icns`.
- `Tests/TypingStatsTests` contains unit tests.
- `tools/` contains development utilities such as icon generation.

Keep new files close to the feature they serve. Avoid shared helpers until multiple modules need them.

## Build, Test, and Development Commands

- `make build` builds the release executable with `swift build -c release`.
- `make app` creates `.build/TypingStats.app`, copies resources, and signs it.
- `make run` rebuilds the app bundle, stops any running `TypingStats`, and opens the app.
- `make test` runs the Swift test suite via `swift test`.
- `make dmg` builds a drag-to-install DMG in `.build/TypingStats.dmg`.
- `make reset-perm` resets the Accessibility grant for `com.jinduoxia.TypingStats`.
- `swift test` runs tests directly without Make.

The project also includes `project.yml` for XcodeGen-style Xcode project generation; keep it aligned with `Package.swift` when targets, resources, or bundle settings change.

## Coding Style & Naming Conventions

Use idiomatic Swift with 4-space indentation. Follow existing names: types in `UpperCamelCase`, methods and properties in `lowerCamelCase`, and test methods as `testBehaviorOrCase`. Keep SwiftUI views small and feature-specific. Prefer names like `StatsService` or `DatabaseManager` over generic utility types.

Do not introduce formatting or linting tools unless the repository adopts them explicitly.

## Testing Guidelines

Tests currently use XCTest in `Tests/TypingStatsTests`. Add tests for deterministic domain logic, date handling, storage behavior, and export/sync transformations. Name test files after the unit under test, for example `StatsServiceTests.swift`, and run `make test` before submitting changes.

## Commit & Pull Request Guidelines

Git history currently uses a concise subject with an optional scope-style description, for example `Initial commit: TypingStats - private local typing tracker`. Keep commit subjects specific to the changed behavior.

Pull requests should include a short summary, test results, and screenshots or recordings for visible UI changes. Mention changes to signing, entitlements, Accessibility permissions, schema, or local data storage.

## Security & Configuration Tips

This app handles local typing statistics and Accessibility permissions. Do not log raw keystrokes, commit private local data, or weaken `Resources/TypingStats.entitlements` without explaining why.
