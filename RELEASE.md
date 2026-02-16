# Release Process

This document describes the CI/CD pipeline and release process for Glitch.

## Overview

The project uses GitHub Actions for continuous integration and deployment. There are two main workflows:

1. **Dev Build** - Runs on every push to feature branches
2. **Release Build** - Triggered by version tags for production releases

## Version Control File

The `version.json` file at the root of the repository controls the release process:

```json
{
  "version": "1.0.0",
  "build_number": 1,
  "release_notes": "Initial release",
  "is_release": false
}
```

### Fields:
- `version`: Semantic version number (e.g., "1.0.0")
- `build_number`: Incrementing integer for each build
- `release_notes`: Description of changes in this release
- `is_release`: Must be `true` to create a production release

## Dev Build Workflow

**Trigger:** Push to any branch (except main) or pull request

**Actions:**
1. Checkout code
2. Setup Java and Flutter
3. Install dependencies (`flutter pub get`)
4. Analyze code (`flutter analyze`)
5. Run tests (`flutter test`)
6. Build debug APK
7. Upload debug APK as artifact (retained for 7 days)

Debug APKs can be downloaded from the Actions tab in GitHub for testing.

## Release Build Workflow

**Trigger:** Push a version tag (format: `v*.*.*`)

**Actions:**
1. **Validate Release:**
   - Check that `version.json` exists
   - Verify `is_release` is set to `true`
   - Confirm tag version matches `version.json` version
2. **Build:**
   - Run tests
   - Build release APK with version from `version.json`
   - Rename APK to `glitch-v{version}.apk`
3. **Create GitHub Release:**
   - Create a GitHub release with the tag
   - Attach the APK file
   - Include release notes from `version.json`

## Creating a Release

Follow these steps to create a production release:

### 1. Update Version Control File

Edit `version.json`:
```json
{
  "version": "1.1.0",
  "build_number": 2,
  "release_notes": "- Added new feature\n- Fixed bug in X\n- Improved performance",
  "is_release": true
}
```

**Important:** Set `is_release` to `true`

### 2. Commit Changes

```bash
git add version.json
git commit -m "Prepare release v1.1.0"
git push
```

### 3. Create and Push Tag

```bash
git tag v1.1.0
git push origin v1.1.0
```

The tag push will trigger the release workflow automatically.

### 4. Post-Release Cleanup

After the release is published, update `version.json` to prepare for the next development cycle:

```json
{
  "version": "1.1.0",
  "build_number": 2,
  "release_notes": "",
  "is_release": false
}
```

Commit and push this change:
```bash
git add version.json
git commit -m "Reset release flag for development"
git push
```

## Version Numbering

Follow [Semantic Versioning](https://semver.org/):

- **MAJOR version** (1.0.0 → 2.0.0): Incompatible changes
- **MINOR version** (1.0.0 → 1.1.0): New features, backwards compatible
- **PATCH version** (1.0.0 → 1.0.1): Bug fixes, backwards compatible

Increment `build_number` with each release regardless of version changes.

## Troubleshooting

### Release workflow fails with "is_release must be set to true"
Make sure you've set `"is_release": true` in `version.json` before tagging.

### Release workflow fails with "version does not match"
The version in `version.json` must exactly match the tag (without the 'v' prefix).
For example, tag `v1.2.3` requires `"version": "1.2.3"` in `version.json`.

### Can't find the APK
After a successful release build:
1. Go to the repository's Releases page
2. Find your release (e.g., v1.1.0)
3. Download the attached APK file

For dev builds:
1. Go to the Actions tab
2. Select the workflow run
3. Download the debug-apk artifact
