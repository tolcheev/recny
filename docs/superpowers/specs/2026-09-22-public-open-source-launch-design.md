# Recny Public Open-Source Launch Design

## Goal

Publish Recny as one public GitHub repository containing the macOS and Windows source code, a minimal GitHub Pages landing page, installation guides, and downloadable release artifacts.

The public repository will be `tolcheev/recny`. Its project site will be available at `https://tolcheev.github.io/recny/`.

## Public Repository

`tolcheev/recny` becomes the only active Recny repository. It will contain:

- `main`: current macOS and Windows source, tests, product documentation, build scripts, and GitHub Actions;
- `gh-pages`: static landing page and the update manifest;
- GitHub Releases: versioned macOS and Windows downloads;
- MIT license.

The current private Git history will not be published. Public `main` starts with one clean root commit based on the current working source. `AGENTS.md`, local assistant instructions, build output, local recordings, secrets, and machine-specific files are excluded. Commit metadata uses the GitHub noreply address so the existing personal email is absent from the public history.

After the new repository, Pages site, downloads, and application update URLs are verified, the obsolete public repositories `tolcheev/recny-download` and `tolcheev/recny-releases` are deleted. Existing old releases remain available in `tolcheev/recny` only when still useful; the new landing page points only to current Recny artifacts.

## Landing Page

The site is a dependency-free static page. It uses semantic HTML, one CSS file, and no analytics, cookies, external fonts, build system, or JavaScript requirement.

Visual direction: strict editorial minimalism. White background, near-black text, thin rules, compact typography, generous spacing, and one red recording indicator. The page avoids gradients, decorative cards, stock images, and simulated product screenshots.

Content order:

1. Recny name, one-sentence description, and source link.
2. macOS and Windows download buttons with exact stability labels.
3. Three product facts: automatic call detection, separate microphone/system tracks, local storage.
4. macOS installation guide.
5. Windows installation guide.
6. Privacy, platform limitations, license, and issue tracker links.

The macOS copy states that the build targets Apple Silicon and is ad-hoc signed rather than Apple-notarized. The Windows copy states that the build is an experimental x64 beta distributed as a ZIP without an installer. The page never implies feature parity or production support that the code does not provide.

## Releases

The launch publishes current platform builds from the same source snapshot:

- macOS `v0.1.8`: DMG and ZIP, plus SHA-256 files;
- Windows `v0.2.5-beta`: self-contained x64 ZIP, plus SHA-256 file.

The macOS artifact is built and tested locally on macOS. The Windows artifact is built and tested by GitHub Actions on `windows-latest`; it is not claimed as manually validated on Windows unless that validation occurs.

Application update manifests and code are changed to download from releases in `tolcheev/recny`. The Pages branch hosts `latest.json`, while every artifact URL points to the matching versioned GitHub Release asset.

## Installation Guides

macOS instructions cover DMG download, drag to Applications, first launch through Finder, Gatekeeper's Open Anyway flow, microphone permission, and Screen & System Audio Recording permission. They do not recommend disabling Gatekeeper globally.

Windows instructions cover ZIP download, extraction, launch of `Recny.exe`, SmartScreen's More info / Run anyway flow when shown, tray access, and local storage. They state that there is no installer and that the build is beta.

## Repository Documentation

The root README becomes public-facing. It explains the product, supported platforms, downloads, build commands, local-first storage, privacy model, contribution workflow, and license. Detailed engineering documents remain where they help contributors. Internal assistant instructions and obsolete private workflow notes are excluded from the clean public snapshot.

## Verification

Before making the repository public:

- scan the clean snapshot for credentials, private keys, local recordings, personal paths, and generated binaries;
- run macOS Swift tests and the packaging script;
- validate the Windows project through GitHub Actions;
- verify release checksums;
- verify landing-page links, responsive layout, keyboard focus, and accessible headings;
- verify `latest.json` URLs and update version comparisons;
- confirm `AGENTS.md` and prior Git history are absent from the public repository.

After publication:

- open the public repository and Pages URL without authentication;
- download every artifact and match its SHA-256 checksum;
- confirm GitHub Pages reports a successful build;
- confirm old repositories are deleted only after the replacement URLs work.

## Failure Handling

The existing private repository is preserved locally as a backup before the public history replacement. If Pages or release publication fails, the repository remains public only after source sanitization; old download repositories stay available until replacement downloads pass verification. Failed artifacts are removed from the release and rebuilt rather than advertised.
