# Glitch

Glitch is a local-first focus tracker built in Flutter.

It is designed around single-task momentum: less dashboard noise, faster execution, and simple daily recovery when mistakes happen.

## Core Product

- One-task-at-a-time `Today` flow with swipe navigation
- Dedicated `Chores` list for editing/completing chores in bulk
- Habits with flexible recurrence:
  - Daily
  - Specific weekdays
  - X days per week
- Project + milestone tracking with progress
- `Done` screen with:
  - take-back/undo actions (recover accidental completions)
  - day-based completion heatmap
- Local encrypted backup/restore (JSON export/import)
- Dark-first custom UI with selectable dark style:
  - AMOLED
  - Black

## UX Highlights

- Single-focus task card and timer on `Today`
- “Perfect day” reward state when all planned items are completed
- Heatmap-driven completion feedback across days
- Bottom navigation workflow: Today, Chores, Habits, Projects, Done, Settings

## Tech Stack

- Flutter (stable)
- Riverpod for state management
- Hive for local persistence
- AES-encrypted backup with device key (secure storage)

## Project Structure

```text
lib/
  core/
  features/
    chores/
    habits/
    projects/
    completed/
    backup/
    settings/
    tasks/
  shared/
  main.dart
```

## Run Locally

1. Install Flutter 3.38+ (Dart 3.10+).
2. Install dependencies:

```bash
flutter pub get
```

3. Run the app:

```bash
flutter run
```

## Quality Checks

```bash
flutter analyze
flutter test
```

## CI/CD Pipeline

This repository includes automated CI/CD workflows:

- **Dev builds**: Automatically run tests and build debug APKs on every push
- **Release builds**: Create production releases with versioned APKs

See [RELEASE.md](RELEASE.md) for detailed information on the release process.

## Notes

- Data is local-first. There is no account system and no cloud sync in this version.
- Backups are encrypted and intended for manual export/import workflows.
