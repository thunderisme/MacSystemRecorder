# Contributing

Thanks for helping improve MacSystemRecorder.

## Local Development

Build the app:

```sh
swift build
```

Build a release app bundle:

```sh
swift build -c release
./Scripts/make-app.sh
```

## Pull Requests

- Keep changes focused.
- Include the macOS version you tested on.
- Run `swift build -c release` before submitting.
- Avoid committing generated build outputs from `.build/`.

## Notes

This app uses Apple's ScreenCaptureKit APIs. Contributors may need to grant Screen Recording permission before testing capture flows.
