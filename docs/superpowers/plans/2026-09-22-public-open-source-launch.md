# Recny Public Open-Source Launch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish Recny source, website, macOS release, and Windows beta release in one clean public `tolcheev/recny` repository.

**Architecture:** Repoint both clients and the update manifest to `tolcheev/recny`, add a dependency-free static site deployed by GitHub Actions, then create a clean repository from the current tracked snapshot without the private Git history or `AGENTS.md`. Build platform artifacts from that snapshot, publish them as versioned GitHub Releases, verify the public paths, and delete the three obsolete GitHub repositories only after replacement downloads work.

**Tech Stack:** Swift 6 and SwiftUI, .NET 8 WinForms, Bash, Python 3, static HTML/CSS, GitHub Actions, GitHub Pages, GitHub Releases, GitHub CLI.

---

## File Map

- `apps/macos/Sources/RecnyCore/AppUpdate.swift`: macOS manifest and issue URLs.
- `apps/macos/Tests/RecnyCoreTests/AppUpdateTests.swift`: macOS support-link assertions.
- `apps/windows/Recny.Windows.Core/Updates/AppUpdate.cs`: Windows manifest and issue URLs.
- `apps/windows/Recny.Windows.Tests/Program.cs`: Windows support-link assertions and manifest fixtures.
- `scripts/package_macos.sh`: current public macOS package version.
- `scripts/write_update_manifest.py`: independent macOS and Windows release tags in one repository.
- `docs/UPDATE_MANIFEST.md`: public update endpoint and release procedure.
- `README.md`: public product, installation, build, privacy, and contribution guide.
- `LICENSE`: MIT license grant.
- `CONTRIBUTING.md`: build, test, issue, and pull-request workflow.
- `SECURITY.md`: private vulnerability-reporting guidance without promising unsupported SLAs.
- `.github/ISSUE_TEMPLATE/bug_report.yml`: URL target already used by both apps.
- `.github/workflows/pages.yml`: deploy `site/` to GitHub Pages.
- `.github/workflows/windows-build.yml`: build and retain the Windows beta artifact.
- `site/index.html`: minimal public landing page and installation instructions.
- `site/styles.css`: responsive editorial styling and accessible interaction states.
- `site/.nojekyll`: serve static files without Jekyll processing.
- `site/latest.json`: update manifest deployed at `https://tolcheev.github.io/recny/latest.json`.

### Task 1: Move Application Support URLs into the Unified Repository

**Files:**
- Modify: `apps/macos/Sources/RecnyCore/AppUpdate.swift`
- Modify: `apps/macos/Tests/RecnyCoreTests/AppUpdateTests.swift`
- Modify: `apps/windows/Recny.Windows.Core/Updates/AppUpdate.cs`
- Modify: `apps/windows/Recny.Windows.Tests/Program.cs`

- [ ] **Step 1: Change macOS tests to require unified URLs**

Update the support-link assertion to require `github.com/tolcheev/recny/issues/new`. Add an assertion that `AppUpdateChecker.defaultManifestURL.absoluteString` equals `https://tolcheev.github.io/recny/latest.json`.

- [ ] **Step 2: Run the focused macOS tests and verify failure**

Run:

```bash
swift test --package-path apps/macos --filter AppUpdateTests
```

Expected: URL assertions fail because the production constants still use `recny-releases`.

- [ ] **Step 3: Change the macOS constants**

Set:

```swift
public static let bugReportBaseURL = URL(
    string: "https://github.com/tolcheev/recny/issues/new"
)!

public static let defaultManifestURL = URL(
    string: "https://tolcheev.github.io/recny/latest.json"
)!
```

- [ ] **Step 4: Run the focused macOS tests and verify success**

Run the Step 2 command. Expected: all `AppUpdateTests` pass.

- [ ] **Step 5: Change Windows tests to require unified URLs**

Change the support-link assertion to require `github.com/tolcheev/recny/issues/new`. Add an assertion that `AppUpdateChecker.DefaultManifestUrl` equals `https://tolcheev.github.io/recny/latest.json`.

- [ ] **Step 6: Change the Windows constants**

Set:

```csharp
public const string DefaultManifestUrl = "https://tolcheev.github.io/recny/latest.json";
public const string BugReportBaseUrl = "https://github.com/tolcheev/recny/issues/new";
```

- [ ] **Step 7: Run Windows tests when a Windows runner is available**

Run:

```powershell
dotnet run --project apps/windows/Recny.Windows.Tests/Recny.Windows.Tests.csproj -c Release
```

Expected: process exits `0` and prints the existing passing test summary.

- [ ] **Step 8: Commit endpoint migration**

```bash
git add apps/macos/Sources/RecnyCore/AppUpdate.swift apps/macos/Tests/RecnyCoreTests/AppUpdateTests.swift apps/windows/Recny.Windows.Core/Updates/AppUpdate.cs apps/windows/Recny.Windows.Tests/Program.cs
git commit -m "build: move support links to Recny repository"
```

### Task 2: Produce Versioned Unified Update Metadata

**Files:**
- Modify: `scripts/package_macos.sh`
- Modify: `scripts/write_update_manifest.py`
- Modify: `docs/UPDATE_MANIFEST.md`
- Modify: `README.md`

- [ ] **Step 1: Make package version consistent with the built application**

Change the default in `scripts/package_macos.sh` to:

```bash
PACKAGE_VERSION="${PACKAGE_VERSION:-v0.1.8}"
```

- [ ] **Step 2: Give each platform an independent release tag**

Replace the shared release variables in `scripts/write_update_manifest.py` with:

```python
repository = "https://github.com/tolcheev/recny"
mac_tag = env("RECNY_MACOS_RELEASE_TAG", "v0.1.8")
windows_tag = env("RECNY_WINDOWS_RELEASE_TAG", "v0.2.5-windows-beta")
mac_release_base = f"{repository}/releases/download/{mac_tag}"
windows_release_base = f"{repository}/releases/download/{windows_tag}"
mac_release_page = f"{repository}/releases/tag/{mac_tag}"
windows_release_page = f"{repository}/releases/tag/{windows_tag}"
```

Use the macOS values in the `macos` object and Windows values in the `windows` object. Keep filenames `Recny-v0.1.8-macOS.dmg` and `Recny-Windows-v0.2.5-beta.zip`.

- [ ] **Step 3: Generate and validate a manifest fixture**

Run:

```bash
RECNY_UPDATE_MANIFEST_PATH=/tmp/recny-latest.json scripts/write_update_manifest.py
python3 -m json.tool /tmp/recny-latest.json >/dev/null
rg -n 'tolcheev/recny/releases/(tag|download)' /tmp/recny-latest.json
```

Expected: valid JSON and four matching unified release URLs; no `recny-releases` text.

- [ ] **Step 4: Update documentation**

Document `https://tolcheev.github.io/recny/latest.json`, the two release tags, and the exact asset filenames in `docs/UPDATE_MANIFEST.md` and the update section of `README.md`.

- [ ] **Step 5: Commit release metadata changes**

```bash
git add scripts/package_macos.sh scripts/write_update_manifest.py docs/UPDATE_MANIFEST.md README.md
git commit -m "build: unify Recny release metadata"
```

### Task 3: Add Public Repository Policy Files

**Files:**
- Create: `LICENSE`
- Create: `CONTRIBUTING.md`
- Create: `SECURITY.md`
- Create: `.github/ISSUE_TEMPLATE/bug_report.yml`
- Modify: `README.md`

- [ ] **Step 1: Add the MIT license**

Use the standard MIT text with copyright line:

```text
Copyright (c) 2026 Vladislav Tolcheev
```

- [ ] **Step 2: Add contribution instructions**

Cover macOS and Windows prerequisites, exact build/test commands, local-only test-data rules, small pull requests, and the requirement to update docs for behavior changes.

- [ ] **Step 3: Add security reporting instructions**

Ask reporters not to open public issues for vulnerabilities and to use GitHub's private vulnerability reporting when available. State supported versions as current releases only and avoid response-time promises.

- [ ] **Step 4: Add the bug issue form**

Create fields for platform, Recny version, OS version, call app, actual result, expected result, reproduction steps, and sanitized diagnostics. Warn users not to attach recordings or private call content.

- [ ] **Step 5: Rewrite the root README for public users**

Lead with Recny's local automatic recording purpose. Include platform status, download link to `https://tolcheev.github.io/recny/`, installation summaries, local storage paths, privacy boundaries, source layout, build/test commands, contribution links, and MIT license. Describe Windows as beta and macOS as ad-hoc signed.

- [ ] **Step 6: Check public wording and links**

Run:

```bash
rg -n 'recny-releases|recny-download|ToRec|TOrbitRecorder download' README.md CONTRIBUTING.md SECURITY.md .github/ISSUE_TEMPLATE
```

Expected: no obsolete product or repository links, except the intentional historical storage-folder name explanation.

- [ ] **Step 7: Commit public repository files**

```bash
git add LICENSE CONTRIBUTING.md SECURITY.md README.md .github/ISSUE_TEMPLATE/bug_report.yml
git commit -m "docs: prepare Recny for open source"
```

### Task 4: Build the Minimal Landing Page

**Files:**
- Create: `site/index.html`
- Create: `site/styles.css`
- Create: `site/.nojekyll`
- Create: `.github/workflows/pages.yml`

- [ ] **Step 1: Write semantic landing-page HTML**

Use a single `main` with `header`, download section, feature list, two installation sections, limitations section, and footer. Link downloads to:

```text
https://github.com/tolcheev/recny/releases/download/v0.1.8/Recny-v0.1.8-macOS.dmg
https://github.com/tolcheev/recny/releases/download/v0.2.5-windows-beta/Recny-Windows-v0.2.5-beta.zip
```

Use Russian public copy. State Apple Silicon, ad-hoc signing, Windows x64 beta, no Windows installer, local storage, and MIT source availability.

- [ ] **Step 2: Implement strict minimalist CSS**

Use CSS custom properties for near-black, white, muted gray, rule gray, and recording red. Use the native font stack to avoid third-party requests. Keep content at `72rem`, set responsive download actions, visible `:focus-visible` outlines, reduced-motion handling, and print-safe colors.

- [ ] **Step 3: Add GitHub Pages workflow**

Create a workflow using `actions/checkout@v4`, `actions/configure-pages@v5`, `actions/upload-pages-artifact@v3` with `path: site`, and `actions/deploy-pages@v4`. Grant `contents: read`, `pages: write`, and `id-token: write`; serialize deployments with the `pages` concurrency group.

- [ ] **Step 4: Validate static files without launching an external browser**

Run:

```bash
test -f site/index.html
test -f site/styles.css
test -f site/.nojekyll
rg -n '<h1|<h2|aria-|focus-visible|prefers-reduced-motion' site/index.html site/styles.css
rg -n 'recny-download|recny-releases|ToRec' site || true
```

Expected: required semantic/accessibility markers exist and obsolete names do not.

- [ ] **Step 5: Commit the site**

```bash
git add site .github/workflows/pages.yml
git commit -m "feat: add minimal Recny landing page"
```

### Task 5: Verify Source and Build macOS Release Artifacts

**Files:**
- Generated only: `dist/Recny-v0.1.8-macOS.dmg`
- Generated only: `dist/Recny-v0.1.8-macOS.zip`
- Generated only: `dist/*.sha256`
- Generated only: `dist/latest.json`

- [ ] **Step 1: Run all macOS tests**

```bash
swift test --package-path apps/macos
```

Expected: all tests pass.

- [ ] **Step 2: Package the public macOS build**

```bash
PACKAGE_VERSION=v0.1.8 RECNY_MACOS_RELEASE_TAG=v0.1.8 RECNY_WINDOWS_RELEASE_TAG=v0.2.5-windows-beta scripts/package_macos.sh
```

Expected: DMG, ZIP, two checksum files, and `dist/latest.json` exist.

- [ ] **Step 3: Verify package identity and checksums**

```bash
codesign --verify --deep --strict dist/Recny.app
shasum -a 256 -c dist/Recny-v0.1.8-macOS.dmg.sha256
shasum -a 256 -c dist/Recny-v0.1.8-macOS.zip.sha256
python3 -m json.tool dist/latest.json >/dev/null
```

Expected: code-sign verification succeeds, both checksums report `OK`, and JSON parses.

- [ ] **Step 4: Copy the verified manifest into the site**

```bash
cp dist/latest.json site/latest.json
git add site/latest.json
git commit -m "build: publish Recny update manifest"
```

### Task 6: Create a Sanitized Public Repository

**Files:**
- Exclude from public snapshot: `AGENTS.md`
- Preserve locally: complete existing repository and a Git bundle backup.

- [ ] **Step 1: Record current state and create a local Git bundle**

```bash
git status --short --branch
git bundle create /tmp/recny-private-history.bundle --all
git bundle verify /tmp/recny-private-history.bundle
```

Expected: clean tracked working tree and a verified bundle containing every current ref.

- [ ] **Step 2: Export the tracked snapshot into a temporary directory**

```bash
RECNY_PUBLIC_DIR="$(mktemp -d /tmp/recny-public.XXXXXX)"
git archive HEAD | tar -x -C "$RECNY_PUBLIC_DIR"
rm "$RECNY_PUBLIC_DIR/AGENTS.md"
```

The removal is limited to the validated temporary directory. Do not alter the local private repository copy.

- [ ] **Step 3: Scan the exported snapshot**

Check filenames for credentials, recordings, databases, signing identities, generated binaries, and local configuration. Search contents for private-key markers, GitHub tokens, API secrets, `/Users/`, and the obsolete repositories. Expected: no secrets or personal filesystem paths; only intentional migration references in the launch spec/plan may name old repositories.

- [ ] **Step 4: Initialize one clean public commit**

```bash
git -C "$RECNY_PUBLIC_DIR" init -b main
git -C "$RECNY_PUBLIC_DIR" config user.name "Vladislav Tolcheev"
git -C "$RECNY_PUBLIC_DIR" config user.email "25820467+tolcheev@users.noreply.github.com"
git -C "$RECNY_PUBLIC_DIR" add .
git -C "$RECNY_PUBLIC_DIR" commit -m "Initial open-source release"
```

Expected: exactly one commit and no `AGENTS.md`.

- [ ] **Step 5: Replace the private GitHub repository without exposing its pull-request history**

Rename `tolcheev/recny` to `tolcheev/recny-private-backup`, create a new public `tolcheev/recny`, and push sanitized `main` from the temporary directory. Do not change visibility on the old repository because its pull requests and unreachable objects contain private history.

- [ ] **Step 6: Verify public repository state**

Expected: public visibility, one `main` commit, MIT detected, no pull requests inherited, `AGENTS.md` returns HTTP 404, and repository description/homepage point to Recny and `https://tolcheev.github.io/recny/`.

### Task 7: Publish macOS and Windows Releases

**Files:**
- Modify if required: `.github/workflows/windows-build.yml`
- Release assets: generated outside Git.

- [ ] **Step 1: Publish macOS v0.1.8**

Create GitHub Release `v0.1.8` titled `Recny v0.1.8 for macOS`, marked as a prerelease because it is not notarized, with DMG, ZIP, and both SHA-256 files. Release notes must describe Apple Silicon, ad-hoc signing, permissions, local storage, and the main changes.

- [ ] **Step 2: Run the Windows workflow on public main**

Dispatch `.github/workflows/windows-build.yml` on `main`, wait for completion, and download artifact `Recny-Windows-v0.2.5-beta`.

- [ ] **Step 3: Verify Windows build output**

Confirm the artifact contains `Recny-Windows-v0.2.5-beta.zip`, calculate `Recny-Windows-v0.2.5-beta.zip.sha256`, and confirm workflow build and tests succeeded.

- [ ] **Step 4: Publish Windows v0.2.5 beta**

Create GitHub prerelease `v0.2.5-windows-beta` titled `Recny v0.2.5 beta for Windows`, attach the ZIP and SHA-256 file, and state x64, self-contained ZIP, no installer, Windows runner tests passed, and no manual Windows audio validation was performed during this launch.

### Task 8: Deploy and Verify GitHub Pages

**Files:**
- No source changes unless verification finds a defect.

- [ ] **Step 1: Enable Pages with GitHub Actions**

Configure the new repository's Pages build type as `workflow`, run or rerun the Pages workflow on `main`, and wait for a successful deployment.

- [ ] **Step 2: Verify unauthenticated public endpoints**

Use built-in web fetching or `curl` to confirm HTTP 200 for the repository, site, stylesheet, manifest, both release pages, both download assets, and checksum assets.

- [ ] **Step 3: Verify downloaded checksums**

Download assets from the public URLs into a temporary directory and run `shasum -a 256 -c` against the published checksum files. Expected: every artifact reports `OK`.

- [ ] **Step 4: Verify responsive and accessible presentation**

Inspect the site only with the shared Codex in-app browser. Check desktop and narrow widths, visible keyboard focus, heading order, button labels, guide readability, and the absence of horizontal overflow.

- [ ] **Step 5: Verify app update metadata**

Fetch `https://tolcheev.github.io/recny/latest.json`; confirm versions, tags, asset names, release URLs, and SHA-256 URLs all resolve.

### Task 9: Remove Obsolete GitHub Repositories

**Files:**
- No local source changes.

- [ ] **Step 1: Confirm replacement readiness**

Do not delete anything until Tasks 6-8 pass. Record the final repository, Pages, macOS release, Windows release, and manifest URLs.

- [ ] **Step 2: Delete obsolete repositories**

Delete:

```text
tolcheev/recny-download
tolcheev/recny-releases
tolcheev/recny-private-backup
```

GitHub requires a token with `delete_repo`. If the current credential lacks it, stop only this deletion step, leave the repositories unchanged, and report the exact missing scope. Never weaken authentication or open an external browser to work around the scope.

- [ ] **Step 3: Final verification**

Confirm `tolcheev/recny` remains public and functional, all three obsolete repository URLs return 404, the Pages site still works, releases still download, and local private history remains recoverable from the local repository and `/tmp/recny-private-history.bundle` for the duration of this task.
