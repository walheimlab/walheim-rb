# Release Process

This guide is for maintainers releasing new versions of Walheim to RubyGems.

## Prerequisites

- RubyGems.org account with access to the `walheim` gem
- RubyGems API key configured in GitHub Secrets as `RUBYGEMS_API_KEY`
- Write access to the GitHub repository

## Semantic Versioning

Walheim follows [Semantic Versioning](https://semver.org/):

- **MAJOR** (x.0.0): Breaking changes
- **MINOR** (0.x.0): New features (backward compatible)
- **PATCH** (0.0.x): Bug fixes (backward compatible)

Examples:
- `0.1.0` → `0.2.0`: New feature added
- `0.2.0` → `0.2.1`: Bug fix
- `0.9.0` → `1.0.0`: Breaking changes (stable release)

## Release Steps

### 1. Update Version

Edit `lib/walheim/version.rb` with the new version:

```ruby
module Walheim
  VERSION = "0.2.0"  # Update version here
end
```

### 2. Update CHANGELOG

Edit `CHANGELOG.md` to document changes:

```markdown
## [0.2.0] - 2024-01-15

### Added
- New feature X

### Changed
- Updated behavior Y

### Fixed
- Bug Z
```

**CHANGELOG Guidelines:**
- Move items from `[Unreleased]` to the new version section
- Add release date
- Categorize changes: Added, Changed, Deprecated, Removed, Fixed, Security
- Update comparison links at the bottom

### 3. Commit Version Bump

```bash
# Stage changes
git add lib/walheim/version.rb CHANGELOG.md

# Commit with conventional commit message
git commit -m "chore: bump version to 0.2.0"

# Push to main branch
git push origin main
```

### 4. Create Git Tag

```bash
# Create annotated tag (must match version exactly)
git tag v0.2.0

# Or with a message
git tag -a v0.2.0 -m "Release version 0.2.0"

# Push the tag to trigger automated release
git push origin v0.2.0
```

**Important:** The tag must be in format `vX.Y.Z` (e.g., `v0.2.0`) and must exactly match the version in `lib/walheim/version.rb`.

### 5. Automated Publishing

Once the tag is pushed, the GitHub workflow (`.github/workflows/publish.yml`) automatically:

1. ✅ **Validates** tag matches `lib/walheim/version.rb`
2. ✅ **Verifies** semantic versioning format
3. 🔨 **Builds** the gem
4. 📦 **Publishes** to RubyGems.org
5. 🎉 **Creates** GitHub Release with auto-generated notes

Monitor the workflow: https://github.com/walheimlab/walheim-rb/actions

### 6. Verify Release

After the workflow completes:

```bash
# Check RubyGems.org
open https://rubygems.org/gems/walheim

# Check GitHub Releases
open https://github.com/walheimlab/walheim-rb/releases

# Test installation
gem install walheim
whctl --version
```

## First-Time Setup

### Getting RubyGems API Key

1. Create account at https://rubygems.org
2. Go to https://rubygems.org/settings/edit
3. Create API key with `push_rubygem` scope
4. Copy the API key

### Configuring GitHub Secret

1. Go to repository settings: https://github.com/walheimlab/walheim-rb/settings/secrets/actions
2. Click "New repository secret"
3. Name: `RUBYGEMS_API_KEY`
4. Value: Paste your RubyGems API key
5. Click "Add secret"

### Claiming Gem Name (First Release Only)

If this is the very first release:

1. Verify the gem name is available: https://rubygems.org/gems/walheim
2. The first successful push will claim the gem name
3. Future releases will require authentication with the same account

## Troubleshooting

### Version Mismatch Error

```
❌ Version mismatch!
Git tag version: 0.2.0
Gem version: 0.1.0
```

**Solution:** Ensure the tag version matches `lib/walheim/version.rb` exactly.

```bash
# Delete incorrect tag
git tag -d v0.2.0
git push origin :refs/tags/v0.2.0

# Fix version.rb and recreate tag
vim lib/walheim/version.rb
git add lib/walheim/version.rb
git commit -m "fix: correct version number"
git tag v0.2.0
git push origin main
git push origin v0.2.0
```

### Invalid Semantic Version

```
❌ Version does not follow semantic versioning format: 0.1
```

**Solution:** Use proper semantic versioning format (MAJOR.MINOR.PATCH):

```ruby
VERSION = "0.1.0"  # ✅ Correct
VERSION = "0.1"    # ❌ Wrong
VERSION = "1"      # ❌ Wrong
```

### RubyGems Authentication Failed

```
❌ Error publishing to RubyGems
```

**Solution:** Verify the `RUBYGEMS_API_KEY` secret is correctly configured in GitHub.

### Build Fails Locally

```bash
# Test gem build locally before tagging
gem build walheim.gemspec

# Check for warnings and errors
# Fix any issues before proceeding with release
```

## Pre-Release Versions

For beta/alpha releases, use pre-release identifiers:

```ruby
VERSION = "1.0.0-beta.1"
VERSION = "1.0.0-rc.1"
VERSION = "1.0.0-alpha.1"
```

Tag accordingly:
```bash
git tag v1.0.0-beta.1
```

Pre-release versions will be published to RubyGems but won't be installed by default with `gem install walheim` (users must specify the exact version).

## Yanking a Release

If you need to remove a broken release:

```bash
# Yank from RubyGems (makes it unavailable but keeps record)
gem yank walheim -v 0.2.0

# Delete GitHub release
# Go to releases page and delete manually
```

**Note:** Yanking should be rare and only for critical issues. Consider releasing a patch version instead.

## Release Checklist

Use this checklist for each release:

- [ ] All tests pass locally
- [ ] CHANGELOG.md updated with all changes
- [ ] Version bumped in `lib/walheim/version.rb`
- [ ] Version follows semantic versioning
- [ ] Changes committed to main branch
- [ ] Git tag created matching version
- [ ] Tag pushed to GitHub
- [ ] GitHub workflow completed successfully
- [ ] Gem appears on RubyGems.org
- [ ] GitHub Release created
- [ ] Installation verified: `gem install walheim`
- [ ] Version command works: `whctl --version`

## Communication

After a successful release:

1. Update any relevant documentation
2. Announce the release (if significant):
   - GitHub Discussions
   - Twitter/social media
   - Email to contributors
3. Monitor for issues and user feedback
