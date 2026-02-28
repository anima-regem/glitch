<div align="center">
  <img src="logo.png" alt="Glitch logo" width="160" />

  <p>
    <a href="https://play.google.com/store/apps/details?id=in.karthav.glitch">
      <img src="https://img.shields.io/badge/Find%20it%20on-Google%20Play-414141?style=for-the-badge&logo=googleplay&logoColor=white" alt="Find on Google Play" />
    </a>
    <a href="https://buymeacoffee.com/vichukartha">
      <img src="https://img.shields.io/badge/Buy%20me%20a%20coffee-FFDD00?style=for-the-badge&logo=buymeacoffee&logoColor=000000" alt="Buy me a coffee" />
    </a>
  </p>

  <h1>Glitch</h1>
  <p>Local-first, single-focus day tracker for calm, consistent execution.</p>
</div>

## Status
- Version in source: `1.0.3+3`
- Platforms: Android, iOS
- Voice typing: Android only (model-first offline beta + native fallback)
- Offline model choices: `Standard`, `Ultra (int8)`, `Ultra Max (full)` with single active installed bundle
- Reliability patch status (February 28, 2026): cancel/remove works during `downloading` and `preparing`, extraction runs off UI isolate, adaptive RAM guardrails block unsupported ultra usage, and runtime overload auto-falls back to native recognizer

## Product Overview
Glitch is a local-first Flutter app for daily execution with minimal friction: pick one task, run focus sessions, and keep momentum across chores, habits, and project milestones.

## Core Experience
- **Focus**
  - Swipe through today's tasks (including due and overdue items).
  - Full-screen focus run mode with pause/resume and timer continuity.
  - One-tap complete/undo flow for habits and tasks.
  - Task metadata support: priority, effort, energy window, estimated minutes.
- **Lists**
  - **Chores:** due-date oriented active list with quick complete/edit/delete.
  - **Habits:** recurrence options (`Daily`, `Specific days`, `X days/week`) with streaks.
  - **Habit insights:** bottom-sheet analytics + 20-week habit heatmap.
  - **Projects:** create projects, track milestone progress %, manage milestone backlog.
- **Done**
  - 20-week day-completion heatmap based on planned vs completed items.
  - Weekly reflection summary with recovery-friendly messaging.
  - Completion history grouped by day with `Take back` undo actions.
- **Settings**
  - Appearance: dark mode, AMOLED/Black style, high contrast, text scaling.
  - Focus nudges: local reminder scheduling + test notification.
  - Voice typing controls: enable/disable + fallback speech toggle.
  - Offline Voice Model (Beta): optional on-device English model download (single active bundle, update/remove controls, Wi-Fi recommended with manual cellular override).
  - Data safety: backup vault folder, sync-now, passphrase rotation, encrypted export/import, local reset.
  - About/support links and release check shortcut.

## Data Model
- Task types: `Chore`, `Habit`, `Milestone`.
- Habit completion logs are stored separately from task definitions.
- Project milestones are linked by `projectId`; deleting a project removes its milestones.
- Day progress tracks only scheduled tasks + due habits (unscheduled chores do not affect completion ratio).

## Storage, Backup, and Recovery
- Local app state is stored on-device using Hive (`glitch_local_box`).
- Encrypted backup export/import uses passphrase-based crypto:
  - KDF: `PBKDF2-HMAC-SHA256` (`120000` iterations)
  - Cipher: `AES-256-CBC`
- Backup vault mode can auto-write debounced snapshots to a chosen folder (`glitch-vault-latest.json`).
- Vault passphrase is stored locally in secure storage on-device.
- Built-in migration recovery flow supports retry, raw encrypted backup export, and local reset.

## Screenshots
| Focus | Focus Run | Settings |
|---|---|---|
| <img src="screenshots/1000307679.png" alt="Focus task card" width="220" /> | <img src="screenshots/1000307680.png" alt="Focus run timer" width="220" /> | <img src="screenshots/1000307677.png" alt="Settings screen" width="220" /> |

## Install and Run
```bash
flutter pub get
flutter run
```

## Quality Checks
```bash
flutter analyze
flutter test
```

## Platform Notes
- Android permissions used: notifications, microphone, and external storage access for backup vault folders.
- Voice model beta uses download-on-demand storage under app support files; model artifacts are verified (SHA-256) before activation.
- Download flow exposes `downloading` and `preparing` phases; `Cancel` and `Cancel & remove` stay available while transfer/extraction is active.
- Adaptive guardrails block Ultra models on low-memory Android devices (`ultra_int8`: >=6 GB physical + >=1.2 GB available RAM, `ultra_full`: >=8 GB physical + >=1.8 GB available RAM, and not low-RAM flagged).
- iOS build is supported for core app usage; voice typing is currently Android-only in code.

## Data & Privacy
- Glitch is local-first and does not require cloud accounts for core use.
- Backups are encrypted and can be restored on other devices with the same passphrase.
- No server-side account or sync is required for core functionality.
- Voice typing defaults to local on-device/system recognition paths; any network-capable fallback remains explicit opt-in.
- If offline model runtime overruns device limits, Glitch automatically falls back to native system recognizer while preserving existing network-fallback consent rules.

## Support
- Buy me a coffee: [buymeacoffee.com/vichukartha](https://buymeacoffee.com/vichukartha)

<img src="assets/support/buymeacoffee_qr.png" alt="Buy me a coffee QR" width="220" />

## Project Links
- GitHub repository: [anima-regem/glitch](https://github.com/anima-regem/glitch)
- Latest releases: [GitHub Releases](https://github.com/anima-regem/glitch/releases/latest)
- Google Play listing: [Glitch on Google Play](https://play.google.com/store/apps/details?id=in.karthav.glitch)
- Privacy policy: [privacy-policy.html](privacy-policy.html)

## Release Process
- Release workflow guide: [RELEASE.md](RELEASE.md)
