# Local AI release and website implementation plan

> Use subagent-driven-development for the website implementation and independent reviews. User authorized production publication on 2026-11-01.

**Goal:** Ship macOS v0.1.9 (build 12) with optional local transcripts/notes and publish installation and usage documentation on the existing GitHub Pages site.

**Architecture:** Continue the public main history and current static HTML/CSS site. Integrate the two reviewed local-AI commits without merging the older unrelated history. Keep Windows v0.2.5 beta downloads unchanged. Publish a new immutable macOS Release and update Pages only after assets are public and verified. No application launch, repository deletion, history rewrite or private recordings publication.

**Design:** Retain the existing editorial layout, recording-red accent and local assets. The home page explains recording and optional local notes, links to exact v0.1.9 downloads and a separate guide.html. The guide covers installation, macOS permissions, first recording, local-model preparation, transcripts, notes, editing/export, updates and troubleshooting. Distinguish macOS-only AI from Windows beta. State ad-hoc signing and measured model limits.

## 1. Integrate release code

- Branch from origin/main; cherry-pick b8d4e90 and c946982.
- Preserve the public update and support endpoints. Restore LOCAL_AI.md, LOCAL_AI_VALIDATION.md and RELEASE_NOTES_LOCAL_AI.md from 2c55e09.
- Set build_macos.sh defaults to v0.1.9 / 0.1.9 / 12, package_macos.sh default to v0.1.9 and manifest build default to 12. Update write_update_manifest.py macOS defaults and notes; preserve Windows release URLs.

## 2. Website and guide

- Update site/index.html and site/styles.css; add site/guide.html. Update site/sitemap.xml and README links. Keep canonical URL https://tolcheev.github.io/recny/.
- Use exact release asset names Recny-v0.1.9-macOS.dmg and Recny-v0.1.9-macOS.zip. No unsupported product screenshots, analytics or external fonts.
- Read and apply Russian publication style skills and the full anti-slop gate. Verify source code matches setup commands and labels.
- Check local links, anchors, headings, metadata and responsive layout using the shared in-app browser only.

## 3. Verify and package

```sh
swift test --package-path apps/macos
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -p test_local_notes.py
./scripts/package_macos.sh
DRY_RUN=1 ./scripts/install_macos.sh
```

- Inspect release Info.plist, arm64 executable, embedded helper and dependency command. Verify ad-hoc signature, DMG integrity, ZIP extraction and both SHA-256 checksums.
- Run a fresh offline synthetic helper smoke check against the packaged helper. Use earlier measured long-fixture results with their actual date; do not present them as fresh November measurements.
- Review scope and correctness separately before publication.

## 4. Publish and verify

- Commit source and website changes; push a release branch and open/attach a PR. The user authorized merge/deploy.
- Prepare draft Release v0.1.9 with verified DMG, ZIP and checksums. Publish only the verified assets; retain prior release. Merge reviewed PR through the existing workflow and follow Pages deployment to success.
- Verify public release asset sizes/digests, website and guide links, latest.json and the deployed source SHA. No private fixture content enters Git or release assets.
- Report public site, guide and release URLs and exact remaining limitations.
