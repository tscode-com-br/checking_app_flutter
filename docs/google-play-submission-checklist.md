# Google Play Submission Checklist

Use this checklist to submit version 1.0.0 to Google Play with less risk.

## 1) Release artifact (.aab)

- [ ] `android/keystore.properties` exists with real values (no `change-me`)
- [ ] Upload keystore file exists at `android/keys/checking-upload-keystore.jks`
- [ ] `flutter analyze` passes
- [ ] `flutter test` passes
- [ ] Signed AAB generated at `build/app/outputs/bundle/release/app-release.aab`
- [ ] Matching R8 mapping archived at `build/release-artifacts/<buildName>+<buildNumber>/r8-mapping/mapping.txt`

Suggested command:

```powershell
pwsh ./scripts/play-release-preflight.ps1 -BuildName 1.0.0 -BuildNumber 1
```

Crash analysis note:

- Keep the archived `mapping.txt` for every uploaded AAB.
- If a residual crash appears obfuscated in Play Console or Android logs, use the mapping from the same uploaded build to deobfuscate the stack before investigating root cause.

## 2) App identity and release notes

- [ ] Package name confirmed: `com.br.checking`
- [ ] Version confirmed in `pubspec.yaml`: `1.0.0+1`
- [ ] Release notes prepared (pt-BR and optional en-US)

Minimal release note template:

```text
Versao inicial do app Checking para registro de Check-In e Check-Out.
Inclui envio manual, sincronizacao de historico, agendamento e geolocalizacao.
```

## 3) Store listing assets

- [ ] App icon (512x512)
- [ ] Feature graphic (1024x500)
- [ ] Phone screenshots (at least 2)
- [ ] Short description (up to 80 chars)
- [ ] Full description (up to 4000 chars)
- [ ] Contact email and website/support URL

## 4) Privacy and policy documents

- [ ] Public privacy policy URL published and tested
- [ ] Terms/support URL added (recommended)

Because this app requests location and notifications, policy text must explicitly explain:

1. Why location is needed for operation
2. If/when background location is used
3. What data is sent to backend APIs
4. How users can disable location features

## 5) Data Safety form (Play Console)

Prepare answers based on actual app behavior:

- [ ] Personal data categories used by the app are mapped
- [ ] Data collection vs data sharing answered correctly
- [ ] Data encryption in transit declared (HTTPS)
- [ ] Data deletion/support channel documented

Current technical hints from app configuration:

1. Uses network access (`INTERNET`, `ACCESS_NETWORK_STATE`)
2. Uses location (`COARSE`, `FINE`, `BACKGROUND`)
3. Uses notifications (`POST_NOTIFICATIONS`)
4. Restores schedule logic after boot (`RECEIVE_BOOT_COMPLETED`)

## 6) Sensitive permission declarations

- [ ] Background location declaration completed in Play Console
- [ ] Clear product justification added (operational automation requirement)
- [ ] Test instructions added for reviewer (how to reproduce feature)

## 7) Device validation before upload

- [ ] Tested in Android 13 device (notifications + location permissions)
- [ ] Tested in Android 14 device
- [ ] Fresh install + login/key flow validated
- [ ] Background scenario validated (app closed / reboot / boot receiver)

## 8) Play Console release flow

1. Create release in Internal testing track
2. Upload `app-release.aab`
3. Add release notes
4. Resolve pre-launch warnings (if any)
5. Roll out to internal testers
6. Validate crash-free behavior and critical flows
7. Promote to production when approved

## 9) Known blocker in current workspace

Release build currently fails if the keystore file is missing:

`Configured storeFile does not exist: .../android/keys/checking-upload-keystore.jks`

Action required: generate/import the real upload keystore and update `android/keystore.properties`.
