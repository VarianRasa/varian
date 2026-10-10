# Media Runtime Matrix — September 13, 2026

## Scope

The runtime probe exercises waveform decoding, 100 ms audio trimming to WAV,
and audio conversion to WAV for the checked-in MP3, OGG, M4A, and generated PCM
WAV fixtures. The probe uses the real platform plugin or Web Audio runtime; the
Flutter unit-test runner is not treated as runtime evidence.

## Results

| Runtime | MP3 | OGG | M4A | WAV | Evidence |
| --- | --- | --- | --- | --- | --- |
| Windows 10 | passed | expected unsupported | passed | passed | `tool/media_decoder_runtime_probe.dart` |
| Chrome | passed | passed | passed | not included in the browser probe | `tool/media_decoder_web_probe.dart` |
| Android 14 emulator, API 34 | passed | passed | passed | passed | `tool/media_decoder_runtime_probe.dart` |
| iOS | pending | pending | pending | pending | No iOS device or simulator is available on the Windows host |

Windows OGG is an explicit capability limitation of the Windows Media
Foundation backend. The application returns an unavailable/error state instead
of treating the source bytes as decoded audio.

## Reproduction

Windows:

```text
flutter run --no-pub -d windows --target tool/media_decoder_runtime_probe.dart
```

Expected Windows output is MP3, M4A, and WAV `passed`, with OGG reported as
`unsupported` and `expected: true`.

Chrome:

```text
flutter run --no-pub -d chrome --target tool/media_decoder_web_probe.dart
```

Read the `probe-output` text after the page changes from `running`. Web Audio
support is checked in a real Chrome page, not in `flutter test -d chrome`.

Android:

```text
flutter run --no-pub -d emulator-5554 --target tool/media_decoder_runtime_probe.dart
```

The Android probe also writes `files/media_decoder_runtime_probe.json` inside
the debug app. It can be retrieved with:

```text
adb shell run-as com.example.varian cat files/media_decoder_runtime_probe.json
```

## Test harness boundary

`test/features/media/media_decoder_runtime_matrix_test.dart` remains disabled
unless `VARIAN_MEDIA_RUNTIME=true` is supplied. On Web it is intentionally
skipped because the headless Flutter test harness does not provide reliable Web
Audio timing. The standalone Chrome probe is the authoritative Web check.

## Remaining capability gaps

- iOS requires an iOS simulator or device for the same runtime probe.
- Video proxy transcoding remains unavailable until a real codec encoder backend
  is integrated. The default backend reports `unsupported`; it never copies the
  original video and labels it as a proxy.
- Pure PCM concatenation runs in a Dart isolate. Native codec calls remain
  platform-bound until a cancellable native worker contract is available.
