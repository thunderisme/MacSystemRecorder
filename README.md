# MacSystemRecorder

A small open-source native macOS app that records a display with system audio to an MP4 file.

MacSystemRecorder is intentionally simple: choose a display, choose where to save, press record, and get an MP4 with system audio.

## Features

- Record a full display with system audio
- Add a 3, 5, or 10 second start delay
- Crop recording to a selected area
- Hide MacSystemRecorder's own audio from the capture
- Auto-save completed recordings as MP4 files

## Requirements

- macOS 13 or later
- Xcode command line tools
- Screen Recording permission when macOS asks for it
- Swift Package Manager, included with Xcode

## Build

```sh
swift build -c release
./Scripts/make-app.sh
```

The packaged app is created at:

```text
dist/release/MacSystemRecorder.app
```

By default, `make-app.sh` creates an ad-hoc signed local build that launches on Apple Silicon Macs. For public distribution, use a real signing identity:

```sh
SIGNING_MODE=identity CODESIGN_IDENTITY="Developer ID Application: Your Name" ./Scripts/make-app.sh
```

## Run

Open the packaged app:

```sh
open dist/release/MacSystemRecorder.app
```

Pick a display, choose where to save the file, set an optional start delay or crop area, then press **Start Recording**. Press **Stop Recording** to finish the MP4.

If macOS prompts for Screen Recording permission, allow it in **System Settings > Privacy & Security > Screen & System Audio Recording**, then quit and reopen the app. If Settings already shows access is enabled but the app still cannot read displays, use **Quit & Reopen** in the permission panel.

## Sharing a Build

For quick testing, zip the packaged app:

```sh
ditto -c -k --keepParent dist/release/MacSystemRecorder.app dist/release/MacSystemRecorder.zip
```

Ad-hoc or unsigned builds may require right-clicking the app and choosing **Open** the first time. For public downloads, use Developer ID signing and Apple notarization; otherwise Gatekeeper behavior varies by macOS version and browser.

## Installer Package

Create a macOS installer package that installs the app into `/Applications`:

```sh
swift build -c release
./Scripts/make-app.sh
./Scripts/make-pkg.sh
```

The installer is created at:

```text
dist/release/MacSystemRecorder.pkg
```

Unsigned installer packages may show Gatekeeper warnings. For public binary releases, sign the app and installer, then notarize the package with Apple.

```sh
INSTALLER_SIGN_IDENTITY="Developer ID Installer: Your Name" ./Scripts/make-pkg.sh
```

For public binary releases, sign and notarize the app with an Apple Developer ID before uploading release artifacts.

## Disk Image

Create a drag-to-Applications DMG:

```sh
swift build -c release
./Scripts/make-app.sh
./Scripts/make-dmg.sh
```

The disk image is created at:

```text
dist/release/MacSystemRecorder.dmg
```

Open the DMG, drag `MacSystemRecorder.app` onto the `Applications` shortcut, then open it from `/Applications`.

## Troubleshooting Downloads

If your browser removes the zip as unsafe, download the DMG or PKG instead. The app is open source but not notarized yet, so macOS may still warn that it cannot verify the developer.

If the installer says it succeeded but you cannot find the app, check:

```sh
open /Applications/MacSystemRecorder.app
```

The app bundle is named `MacSystemRecorder.app`; Finder may display it as `Mac System Recorder`.

If macOS privacy permissions get stuck, quit MacSystemRecorder, remove any old entry from **System Settings > Privacy & Security > Screen & System Audio Recording**, reopen the app, and use **Ask macOS** from the permission panel.

## Publishing Source

Initialize and push the repository:

```sh
git init
git add .
git commit -m "Initial open source release"
git branch -M main
git remote add origin git@github.com:YOUR_USERNAME/MacSystemRecorder.git
git push -u origin main
```

## License

MIT. See [LICENSE](LICENSE).
