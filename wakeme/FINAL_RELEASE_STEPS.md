# WakeMe — Final Release Steps

Everything below is the LAST phase, after you've finished testing. The repo is
already prepped: release signing falls back to the debug key until you create
`key.properties`, and all `WAKEYDBG` logging is now tied to `kTestMode`, so a
single flag flip silences every debug print.

Do these in order.

---

## 1. Turn off the test harness  (code — ask me, or do it yourself)
- Set `kTestMode = false` in `lib/core/testing/test_mode.dart`.
  → the 🧪 panel, its hooks, and ALL `WAKEYDBG` logs disappear automatically.
- (Optional clean removal) delete `test_mode.dart`, the two
  `if (kTestMode) const TestFab()` lines in `home_screen.dart` /
  `armed_screen.dart`, and the `// TEST-ONLY` blocks in
  `background_alarm_service.dart`.

## 2. Create your upload keystore  (you — once, then back it up)
Run this in a folder OUTSIDE the repo (e.g. `C:\Users\Fo2sh\keys\`). It needs
Java's `keytool` (bundled with Android Studio's JDK):

```bash
keytool -genkeypair -v -keystore upload-keystore.jks -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

It asks for a password (twice) and some name/org fields (any values are fine).
🔑 **Back up `upload-keystore.jks` + the passwords somewhere safe. Losing them
means you can never update the app.**

## 3. Wire the keystore  (you — create android/key.properties)
Create `wakeme/android/key.properties` (already gitignored — never commit it):

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=C:/Users/Fo2sh/keys/upload-keystore.jks
```

Use forward slashes in `storeFile`. Once this file exists, release builds sign
with your real key automatically (no Gradle edits needed).

## 4. Add the in-app Privacy Policy link  (ask me — I need your URL + email)
Once you've hosted `PRIVACY_POLICY.md` and have a support email, tell me both
and I'll wire a "Privacy Policy" link into the app.

## 5. Build the App Bundle  (you)
```bash
flutter clean
flutter build appbundle --release
```
Output: `build/app/outputs/bundle/release/app-release.aab` (upload this, NOT an apk).

## 6. Maps API key — Cloud Console  (you — do anytime)
- **Rotate** the key (it was pasted in chat once) → put the new value in `.env`.
- **Restrict** it: Application restriction → Android apps → add package
  `com.wakeme.wakeme` + your release SHA-1 (get it from Play Console → App
  signing, or `keytool -list -v -keystore upload-keystore.jks -alias upload`).
  API restriction → Maps SDK for Android, Places, Directions, Geocoding.

## 7. Play Console  (you — answers are in RELEASE_CHECKLIST.md Phase 4)
Upload the `.aab` to Internal testing first, review the Pre-launch report,
fill the Data safety form (ready answers in the checklist), then promote.

---

### Quick "am I done?" check
- [ ] `kTestMode = false`
- [ ] `android/key.properties` exists and points at your `.jks`
- [ ] Privacy policy hosted + linked in-app
- [ ] `.aab` built and signed with the upload key (not debug)
- [ ] Maps key rotated + restricted
