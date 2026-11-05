<div align="center">

# JobHunter

**A native macOS app that fetches open roles from 182 company career boards, scores each listing against your resume, and tracks every application from _New_ to _Offer_ on your Mac. No account, no server, no subscription.**

[![Release](https://img.shields.io/github/v/release/kodelint/jobhunter?sort=semver&color=7c6cf0)](https://github.com/kodelint/jobhunter/releases)
[![Build](https://github.com/kodelint/jobhunter/actions/workflows/release.yml/badge.svg)](https://github.com/kodelint/jobhunter/actions/workflows/release.yml)
[![CI](https://github.com/kodelint/jobhunter/actions/workflows/ci.yml/badge.svg)](https://github.com/kodelint/jobhunter/actions/workflows/ci.yml)
[![Downloads](https://img.shields.io/github/downloads/kodelint/jobhunter/total?color=44b884)](https://github.com/kodelint/jobhunter/releases)
[![License: MIT](https://img.shields.io/github/license/kodelint/jobhunter?color=blue)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey?logo=apple)](https://www.apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift&logoColor=white)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-2396f3?logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)](#tech)

![JobHunter dashboard](docs/dashboard.png)

</div>

## Overview

JobHunter pulls open roles straight from public applicant tracking system (ATS) APIs, ranks them against your resume, and tracks your pipeline (`New -> Applied -> Interviewing -> Offer / Rejected`) in one local macOS application. Your resume, API keys, and application history stay on your Mac in SQLite and the macOS Keychain.

## Highlights

- **182 verified boards built in.** Fetches live postings across Greenhouse (90), Ashby (67), Lever (16), and SmartRecruiters (9) in one scan.
- **URL paste and live board verification.** Add or edit any company from the **Sources** tab by pasting a career board URL or entering a slug. Click **Verify / Detect** to probe all four ATS platforms and check the live open role count before saving.
- **Live AI model discovery.** Queries your provider's `/v1/models` endpoint (`api.anthropic.com/v1/models`, `api.openai.com/v1/models`, `generativelanguage.googleapis.com/v1beta/models`, or your local server's `/v1/models` and `/api/tags`) with your API key so every available model appears in the picker automatically.
- **Two-stage fit scoring.** A fast local keyword pass scores every role against your resume profile, then optional AI evaluation scores the top matches (0-100) with a one-line verdict, match reasons, gaps, and five signal sub-scores.
- **Wrong-match feedback loop.** Flag a role as a wrong match with a reason, and future AI evaluations score similar off-profile roles lower.
- **Full application pipeline.** Track sourced and manually added applications through every stage, set follow-up dates, and optionally sync Gmail over IMAP to auto-advance stages from recruiter replies.

## Screenshots

| Dashboard | Matches + role detail |
| :---: | :---: |
| ![Dashboard](docs/dashboard.png) | ![Matches](docs/matches.png) |

## How a Scan Works

1. **Source:** Conditional `GET` requests (`ETag` / `If-Modified-Since`) fetch enabled career boards across Greenhouse, Ashby, Lever, and SmartRecruiters. Unchanged boards return HTTP `304` and skip parsing. Every posting gets a deterministic FNV-1a ID so rescans update existing records in place.
2. **Score:** An off-main-thread keyword pass ranks each posting against your resume profile (titles, seniority band, skills, location, and eligibility constraints).
3. **Evaluate (optional):** For the top `N` keyword matches that have not been scored yet, the selected AI model evaluates fit against your resume and returns a 0-100 score, verdict, reasons, gaps, and five sub-scores (`leadership`, `location`, `technical`, `domain`, `compensation`).
4. **Track:** Roles land in your pipeline tabs (`New`, `All`, `Low`, `Favorites`, `Applied`, `Ignored`, `Wrong matches`).

## Features

### Sourcing & Board Management
- **Built-in catalog:** 182 live-verified engineering and AI company boards across **Greenhouse** (90), **Ashby** (67), **Lever** (16), and **SmartRecruiters** (9).
- **Add or edit sources in app:** Paste any Greenhouse, Ashby, Lever, or SmartRecruiters board URL to auto-fill the ATS and token, or enter a company token and click **Verify / Detect** to auto-detect the ATS and preview the open job count.
- **Conditional caching:** Stores `ETag` and `Last-Modified` headers per board in SQLite to avoid redundant downloads.
- **SmartRecruiters detail backfill:** Paginates listings and fetches full job descriptions only for newly discovered postings (capped per scan).

### Resume Matching & Live AI Evaluation
- **Resume extraction:** Parses your resume into target titles, seniority level, atomic skills, and country.
- **Dynamic model catalog:** Fetches available models directly from Anthropic (`/v1/models`), OpenAI (`/v1/models`), Google Gemini (`/v1beta/models`), or a local Ollama / OpenAI-compatible server (`/v1/models` and `/api/tags`).
- **Cached AI scores:** Evaluates only the top `N` unscored roles per scan and reuses cached scores on future scans.
- **Wrong-match training:** Marking a role as a wrong match records your reason and passes it into future AI prompts as a negative signal.

### Eligibility & Constraints
- Extracts work authorization, compensation range, remote/hybrid/onsite policy, required years of experience, IC vs. management track, travel percentage, and security clearance from each posting.
- Filters roles against your configured work authorization status, minimum compensation floor, work style preferences, and country.

### Pipeline & Gmail Sync
- **Manual role entry:** Log applications submitted outside your configured boards (for example Workday or referrals) in the same pipeline.
- **Optional Gmail IMAP sync:** Connects over IMAP using a Gmail App Password stored in a `0600` netrc file, classifies recruiter replies into interview, offer, or rejection, and updates the matching application stage.

### Privacy & Storage
- All application state, jobs, resume data, and HTTP cache headers live in `~/Library/Application Support/JobHunter/jobhunter.sqlite`.
- API keys are stored in the macOS **Keychain** or read from environment variables (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY` / `GOOGLE_API_KEY`).
- Outbound network requests go only to the enabled public ATS board APIs, your selected AI provider (when enabled), and Gmail IMAP (when configured).

## Install

Download the latest `JobHunter-vX.Y.Z.dmg` from [**Releases**](https://github.com/kodelint/jobhunter/releases), open it, and drag `JobHunter.app` to `/Applications`.

Ad-hoc signed builds require **right-click -> Open** (or _System Settings -> Privacy & Security -> Open Anyway_) on first launch.

**Requirements:** macOS 14 (Sonoma) or later. Universal binary (`arm64` + `x86_64`).

## Build from Source

JobHunter compiles directly with `swiftc` and links only system frameworks (`SwiftUI`, `AppKit`, `Security`, `sqlite3`).

```bash
git clone https://github.com/kodelint/jobhunter.git
cd jobhunter
./scripts/build-dmg.sh
cp -R build/JobHunter.app /Applications/JobHunter.app
open -a /Applications/JobHunter.app
```

| Script | Purpose |
| --- | --- |
| `scripts/build-dmg.sh` | Compile universal binary (`arm64` + `x86_64`), inject git tag version (`CFBundleShortVersionString`) and commit count (`CFBundleVersion`) into `Info.plist`, sign, and package `dist/JobHunter-vX.Y.Z.dmg`. |
| `scripts/compile-check.sh` | Fast `arm64` type-check of `Sources/*.swift`. |
| `scripts/run-selfcheck.sh` | Compile and run deterministic self-checks (`selfcheck OK`). |

Set `DEVELOPER_ID` (and optional `NOTARY_PROFILE` or `AC_APPLE_ID` / `AC_TEAM_ID` / `AC_PASSWORD`) before running `scripts/build-dmg.sh` to produce a Developer ID signed and notarized DMG.

## Releases & Versioning

- App version (`CFBundleShortVersionString`) comes from the latest `vX.Y.Z` git tag (or the `VERSION` environment variable), and build number (`CFBundleVersion`) comes from `git rev-list --count HEAD`.
- The active version and build number appear in the sidebar header, menu bar popover, and **AI & Settings -> About** panel.
- Pushing a `vX.Y.Z` tag triggers `.github/workflows/release.yml`, which runs `scripts/run-selfcheck.sh`, builds the universal DMG, and publishes a GitHub Release.
- Pushing or opening a pull request to `main` triggers `.github/workflows/ci.yml`.

## License

[MIT](LICENSE) © kodelint
