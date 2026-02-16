# CI/CD Quick Start Guide

## Dev Workflow (Daily Development)

1. **Create a feature branch:**
   ```bash
   git checkout -b feature/my-new-feature
   ```

2. **Make your changes and push:**
   ```bash
   git add .
   git commit -m "Add new feature"
   git push origin feature/my-new-feature
   ```

3. **CI automatically runs:**
   - ✅ Analyzes code (`flutter analyze`)
   - ✅ Runs tests (`flutter test`)
   - ✅ Builds debug APK
   - ✅ Uploads APK as artifact

4. **Download debug APK (optional):**
   - Go to Actions tab in GitHub
   - Click on your workflow run
   - Download "debug-apk" artifact

## Release Workflow (Publishing)

### Step 1: Update version.json

```bash
# Edit version.json
{
  "version": "1.1.0",
  "build_number": 2,
  "release_notes": "New feature added\nBug fixes\nPerformance improvements",
  "is_release": true
}
```

### Step 2: Commit and push

```bash
git add version.json
git commit -m "Prepare release v1.1.0"
git push origin main
```

### Step 3: Create and push tag

```bash
git tag v1.1.0
git push origin v1.1.0
```

### Step 4: Wait for release

- CI validates version.json
- Builds release APK
- Creates GitHub Release
- Attaches APK to release

### Step 5: Post-release cleanup

```bash
# Reset release flag
# Edit version.json:
{
  "version": "1.1.0",
  "build_number": 2,
  "release_notes": "",
  "is_release": false
}

git add version.json
git commit -m "Reset release flag"
git push origin main
```

## Common Issues

### ❌ "is_release must be set to true"
**Fix:** Set `"is_release": true` in version.json before tagging

### ❌ "version does not match"
**Fix:** Ensure version.json version matches your tag (without 'v'):
- Tag: `v1.2.3` → version.json: `"version": "1.2.3"`

### ❌ Can't find my debug APK
**Location:** GitHub → Actions → Click workflow run → Artifacts section

### ❌ Tests failing in CI
**Local check:** Run `flutter test` locally before pushing

## Version Numbering Guide

- **1.0.0 → 2.0.0**: Breaking changes (MAJOR)
- **1.0.0 → 1.1.0**: New features (MINOR)
- **1.0.0 → 1.0.1**: Bug fixes (PATCH)

Always increment `build_number` for each release.

## See Also

- [RELEASE.md](RELEASE.md) - Detailed release documentation
- [README.md](README.md) - Project overview
