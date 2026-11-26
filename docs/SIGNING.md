# Signing, notarizing and distributing Graphist

`make app` produces an **ad-hoc signed** app. It runs on the Mac that built it, but
on other Macs Gatekeeper blocks it. To distribute it, pick one of these routes:

| Route | Use when | Certificate |
|---|---|---|
| **Developer ID + notarization** (recommended) | You distribute the app yourself: website, GitHub releases, colleagues | *Developer ID Application* |
| Mac App Store / TestFlight | You want App Store distribution | *Apple Distribution* + *Mac Installer Distribution*, provisioning profile, App Sandbox |

The scripts in this repo automate the **Developer ID** route.

---

## Developer ID: one-time setup

### 1. Pick a bundle identifier

Replace the placeholder `com.example.graphist`, either permanently in
`Packaging/Info.plist` or for each build with `BUNDLE_ID=com.yourcompany.graphist`.
Developer ID signing does not require registering an App ID, but it is still good
practice to register one under *Certificates, Identifiers & Profiles*.

### 2. Create a Developer ID Application certificate

Only the Account Holder of the team, or an Admin with permission, can create it.

- **With Xcode:** Settings ▸ Accounts ▸ select your team ▸ *Manage Certificates…* ▸
  **+** ▸ *Developer ID Application*.
- **Or on the web:** developer.apple.com ▸ Certificates ▸ **+** ▸
  *Developer ID Application*. Upload a CSR made with Keychain Access, then
  double-click the downloaded `.cer` to install it.

Check that the certificate is installed and copy its exact name:

```bash
security find-identity -v -p codesigning
#  1) ABC123... "Developer ID Application: Your Name (TEAMID)"
```

### 3. Store notarization credentials in the keychain

Use either an app-specific password (create one at account.apple.com ▸ Sign-In
and Security ▸ App-Specific Passwords):

```bash
xcrun notarytool store-credentials graphist-notary \
  --apple-id "you@example.com" --team-id TEAMID --password "abcd-efgh-ijkl-mnop"
```

or an App Store Connect API key (better for CI). Create it under App Store Connect ▸
Users and Access ▸ Integrations ▸ Keys:

```bash
xcrun notarytool store-credentials graphist-notary \
  --key ~/keys/AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer <issuer-uuid>
```

`graphist-notary` is the default profile name that `scripts/sign-and-notarize.sh`
looks for. Override it with `NOTARY_PROFILE=...`.

## Developer ID: each release

```bash
export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
BUNDLE_ID=com.yourcompany.graphist VERSION=1.0.0 make release
```

`make release` runs:

1. `UNIVERSAL=1 scripts/build-app.sh`, a universal (arm64 + x86_64) build.
   Some Intel Macs run Tahoe, so this covers them too.
2. `scripts/sign-and-notarize.sh`, which:
   - `codesign --options runtime --timestamp --entitlements Packaging/Graphist.entitlements`
     (hardened runtime and secure timestamp are both required for notarization)
   - `xcrun notarytool submit … --wait`
   - `xcrun stapler staple`, so the ticket travels with the app and works offline
   - `spctl --assess`, the same check Gatekeeper runs
   - writes `build/Graphist-<version>.zip` for you to distribute

Useful variations:

```bash
make sign                                       # sign only, no notarization
xcrun notarytool history --keychain-profile graphist-notary
xcrun notarytool log <submission-id> --keychain-profile graphist-notary   # why a submission failed
```

**A DMG instead of a zip (optional):**

```bash
hdiutil create -volname Graphist -srcfolder build/Graphist.app -ov -format UDZO build/Graphist.dmg
codesign --timestamp --sign "$DEVELOPER_ID" build/Graphist.dmg
xcrun notarytool submit build/Graphist.dmg --keychain-profile graphist-notary --wait
xcrun stapler staple build/Graphist.dmg
```

### Notes

- `Packaging/Graphist.entitlements` is intentionally empty. Graphist needs no
  special entitlements under the hardened runtime, and that includes Metal's runtime
  shader compilation.
- Don't use `codesign --deep`. Sign nested code (frameworks, helpers) individually,
  inside-out, if you ever add any.
- Bump `VERSION` (CFBundleShortVersionString) for each release. `CFBundleVersion`
  defaults to the git commit count.

---

## Mac App Store (if you need it later)

The App Store needs a few more things, all doable from the CLI:

1. Turn on the **App Sandbox** in `Packaging/Graphist.entitlements`
   (`com.apple.security.app-sandbox` = true), plus
   `com.apple.application-identifier` and `com.apple.developer.team-identifier`.
2. Register the App ID, create an App Store **provisioning profile**, and copy it to
   `Graphist.app/Contents/embedded.provisionprofile`.
3. Sign with your **Apple Distribution** certificate (no `--options runtime` needed),
   then package with
   `productbuild --component build/Graphist.app /Applications --sign "3rd Party Mac Developer Installer: …" Graphist.pkg`.
4. Add an app icon (Icon Composer `.icon` / asset catalog) and the
   `LSApplicationCategoryType` key, which is already set.
5. Upload with Transporter or `xcrun altool --upload-package`.

If you go this route, the simplest option is often to generate an Xcode project
(Xcode can manage profiles and capabilities) while keeping the same `Sources/` and
`Shaders/`.
