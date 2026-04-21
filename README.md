# Mail Tracker Blocker

A macOS sample app for testing `MEContentBlocker` (MailKit) with AdGuard-style filter rules.

It verifies that:
- `MEContentBlocker` loads and is applied by Mail.app
- `if-domain`/`unless-domain` behaviour in the Mail rendering context
- `css-display-none` applicability in email rendering
- The rule conversion pipeline stays within the 150,000-rule budget

**Reference implementation:** [ameshkov/safari-blocker](https://github.com/ameshkov/safari-blocker)

---

## Requirements

- macOS 12.0 (Monterey) or later
- Xcode 15+
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

---

## Setup

### 1. Set placeholders

This repo is template-ready. Replace placeholders:
- `neshumov` → your reverse-domain prefix (example: `com.acme`)
- `YOUR_TEAM_ID` → your Apple Developer Team ID (example: `ABCDE12345`)

| File | Setting |
|---|---|
| `Shared/AppGroupConstants.swift` | `AppGroup.id`, `BundleIDs.*` |
| `project.yml` | `PRODUCT_BUNDLE_IDENTIFIER` (both targets), `APP_GROUP_ID` |
| `MailTrackerBlockerApp/MailTrackerBlockerApp.entitlements` | App Group string |
| `MailExtension/MailExtension.entitlements` | App Group string |

After replacement, values should look like this:
- App bundle id: `com.acme.mail-tracker-blocker`
- Extension bundle id: `com.acme.mail-tracker-blocker.MailExtension`
- App Group: `group.com.acme.mail-tracker-blocker`

### 2. Set your Development Team

In `project.yml` set `DEVELOPMENT_TEAM: YOUR_TEAM_ID` for both targets, or set Team in Xcode Signing & Capabilities.

### 3. Enable the App Group

In the Apple Developer portal, create an App Group with the same ID you set above, and add it to both App IDs.

### 4. Generate the Xcode project

```bash
make generate
# or
make open    # generates and opens in Xcode
```

If you changed placeholders after generating once, run `make generate` again.

---

## Usage

1. Build and run `MailTrackerBlockerApp`.
2. Click **Load filter.txt** to load `filters/filter.txt` (or any AdGuard-format filter).
3. Configure pipeline options:
   - **Strip $domain=** — removes `domain=` modifiers before conversion (tests `if-domain` handling).
   - **Include css-display-none rules** — passes cosmetic `##selector` rules through the pipeline.
4. Click **Run Pipeline**. The app converts the rules and saves the JSON to the shared App Group container.
5. Open Mail.app → Settings → Extensions → enable **Mail Tracker Blocker Extension**.
6. Restart Mail.app to pick up the new rules.

---

## Test Scenarios

### Scenario 1 — Basic blocking
Add tracking-pixel domains to `filters/filter.txt`, run the pipeline, open a test email containing those URLs in Mail.app, and verify the requests are blocked (use Proxyman or Charles).

### Scenario 2 — `if-domain` behaviour
Run with a `$domain=` rule first **without** Strip $domain=, then **with** it. Compare whether the rule fires in each case to determine how Mail.app assigns the document domain.

### Scenario 3 — `css-display-none`
Enable **Include css-display-none rules**, add a `##img[width="1"][height="1"]` rule, and check in Accessibility Inspector whether the element is hidden after opening the email.

### Scenario 4 — Rule count budget
Load a large filter list. The pipeline stats panel shows `finalJSONEntryCount / 150,000` and warns at 120,000.

### Scenario 5 — Reload after update
Edit `filter.txt`, click **Run Pipeline** again without restarting the app, and confirm Mail.app uses the updated rules.

---

## Project Structure

```
mail-tracker-blocker/
├── MailTrackerBlockerApp/   Container app (SwiftUI)
├── MailExtension/           MEContentBlocker extension
├── Shared/                  Code shared between both targets
├── filters/filter.txt       Sample test rules
├── project.yml              XcodeGen spec
└── Makefile
```

---

## Dependencies

| Library | Source | Purpose |
|---|---|---|
| SafariConverterLib | https://github.com/AdguardTeam/SafariConverterLib | Converts AdGuard filter rules to WebKit content blocker JSON |

Added automatically via Swift Package Manager when you open the generated project.
