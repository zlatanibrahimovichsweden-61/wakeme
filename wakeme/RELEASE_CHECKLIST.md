# WakeMe — Google Play Release Checklist

Owner key:  🤖 = I can do it in the code/repo   ·   👤 = needs you (Console, account, decisions, assets)
Status key: `[ ]` todo · `[~]` in progress · `[x]` done

---

## Phase 0 — Decisions to make first (👤)

- [ ] **Keep or drop background location?** (biggest factor for approval speed)
      - Drop `ACCESS_BACKGROUND_LOCATION` → skip Google's background-location
        review (no demo video). Requires testing the locked-screen alarm still
        fires via the foreground service. **Recommended.**
      - Keep it → must record a demo video + write justification for review.
- [ ] **Support email** for the store listing + privacy policy.
- [ ] **Where to host the privacy policy** (GitHub Pages / Google Sites / etc.).
- [ ] **Release track:** internal testing first (recommended) → closed → production.

---

## Phase 1 — Code & config (🤖, with 👤 input where noted)

- [x] `targetSdk = 35` (was 34 — rejection blocker). ✅
- [x] **Dropped `ACCESS_BACKGROUND_LOCATION`** + the "Allow all the time"
      prompt; **locked-screen alarm tested working** via the foreground
      service. → skips Google's background-location review. ✅
- [x] Pruned `RECEIVE_BOOT_COMPLETED` (service has `autoStartOnBoot = false`). ✅
- [x] Fixed `pubspec.yaml` asset warning (removed nonexistent `assets/icons/`). ✅
- [x] Bumped `version:` to `1.0.0+1`. ✅
- [ ] **(LAST, before release build)** Turn off test harness: `kTestMode = false`,
      remove the 🧪 panel hooks, strip all `WAKEYDBG`/`print` logging, delete
      `testEnsureArmed` / test prefs paths. *Kept ON for now to allow testing.*
- [ ] Add an in-app **Privacy Policy** link (needs the hosted URL + your email).
- [ ] 👤+🤖 **Release signing**: create an upload keystore, wire a real
      `signingConfig` (replace the debug-key release config), enroll in Play
      App Signing. *(Needs a few decisions from you — I'll walk you through it.)*
- [ ] Build the **App Bundle**: `flutter build appbundle --release` (`.aab`,
      not `.apk`).

## Phase 2 — Security (🤖 guide / 👤 act)

- [ ] **Restrict** the Maps API key (Cloud Console): Android app restriction
      (package `com.wakeme.wakeme` + release SHA-1) + API restriction (Maps SDK,
      Places, Directions, Geocoding).
- [ ] **Rotate** the Maps key (it was shared in chat).
- [ ] Confirm no secrets in git (`.env` is gitignored ✓).

## Phase 3 — Store listing assets (👤 create / 🤖 can draft text)

- [ ] App icon — ✅ already have (`assets/icon/wakey_icon.png`).
- [ ] **Feature graphic** 1024×500 px.
- [ ] **Phone screenshots** (2–8; you have some in `screenshots/`).
- [ ] App **title** (≤30 chars), **short description** (≤80), **full
      description** (≤4000). 🤖 I can draft all three.

## Phase 4 — Play Console setup (👤, 🤖 provides exact answers)

- [ ] Developer account ($25 one-time) + identity/payment verification.
- [ ] Create app → set as **Free**, select countries.
- [ ] **Privacy policy URL** (from Phase 0).
- [ ] **Data safety form** — answers below ↓.
- [ ] **App access**: no login required (all features open).
- [ ] **Ads**: none.
- [ ] **Content rating** questionnaire (everyone; utility app).
- [ ] **Target audience**: 13+ (not for children).
- [ ] **Foreground service** declaration: justify `location` type.
- [ ] (If keeping) **Background location** declaration + demo video.
- [ ] **News / Health / Government / Financial**: all **No**.

### Data safety form — ready answers
- Data collected: **Location → Approximate + Precise location**.
  - Collected: **Yes**. Shared: **No** (sent to Google as a service provider for
    maps/search/routing, not shared with the developer or third parties).
  - Purpose: **App functionality**. Not for ads/analytics.
  - Processed ephemerally / not stored on a server you control.
  - User can request deletion: data is local-only; cleared on uninstall.
- Account/personal info: **None**. Financial: **None**. Messages/contacts: **None**.
- Data encrypted in transit: **Yes** (HTTPS to Google). 
- App uses a data-deletion mechanism: clearing app storage / uninstall.

## Phase 5 — Pre-launch testing (🤖 build / 👤 verify)

- [ ] Upload `.aab` to **Internal testing** track.
- [ ] Review the **Pre-launch report** (Google's automated device tests) for
      crashes/ANRs/permission flags.
- [ ] Manually verify on your phone from the release build:
      - [ ] Arrival alarm: app open / another app / locked.
      - [ ] Dismiss + 60s auto-dismiss.
      - [ ] **Edge cases:** location denied, GPS off, offline, no custom sound.

## Phase 6 — Submit & maintain (👤)

- [ ] Promote internal → closed/production, submit for review.
- [ ] Respond to any policy email **within 48 h** (silence = removal).
- [ ] Keep the upload keystore backed up safely (losing it = can't update).

---

## Definition of "ready to submit"
All of Phase 1 + Phase 2 done · assets uploaded · all Console forms green ·
internal-track build installs and passes the manual + edge-case tests.
