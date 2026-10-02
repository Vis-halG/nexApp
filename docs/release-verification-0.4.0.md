# nexApp 0.4.0 release verification

Verified 2 October 2026 (Asia/Calcutta). Package `com.thenex.nex_music`, version `0.4.0`, build `8022`.

## Artifact

- APK: `build/app/outputs/flutter-apk/nexApp-0.4.0-arm64.apk`.
- Native release build: passed; Android arm64, min SDK 24, target SDK 36.
- Size: 21,154,592 bytes (20.2 MiB).
- SHA-256: `07b294b08d794ccb997d89702e81583ac249e37aae20fd43de4f174f1c6c7c2d`.
- Signature verification: passed using the configured NexMusic release certificate.
- Public signing certificate SHA-256: `fdb7dd5ee63c5b6668debc4739c0f71261fb7f9ca7547b12a95f3409329e54ab`. This can be used in the Worker Android App Links configuration; it is not a private key.

## Automated checks

| Check | Result |
| --- | --- |
| Flutter analysis | No issues |
| Flutter suite | 71 passed |
| Live provider integration | Passed: combined discovery/search, JioSaavn and YouTube Music radio, stream resolution and byte ranges, video search |
| Cloudflare Worker routes | 5 passed |
| Firestore emulator authorization | 5 passed: account isolation, ownership, invites/roles, guest requests/votes and host controls, private invite proofs and revocation |
| Git whitespace validation | Passed |

The suite includes queue traversal/restore, stable offline indexing, UID-scoped migration, safe playlist export, persisted paused downloads, CSV quoting/matching, timed lyrics, non-Latin recording matching, podcast identities, cloud recents, playlist validation rollback, meaningful recap/ranking, and playback restart after completion. The ordinary update-check test now uses a deterministic HTTP fixture; the optional live GitHub release test remains in `tool/update_live_test.dart`.

## Android emulator smoke checks

A fresh API 35 Google Play x86_64 AVD with arm64 translation was used. The existing emulator installation had a different signing certificate, so validation used a separate AVD without uninstalling the old app.

- Latest APK installed and launched successfully; guest entry opened the app.
- Audio permission prompt and Android MediaStore scan discovered a generated test WAV.
- Device audio played through its native `content://` URI to the end (12.007 seconds). Runtime validation caught and fixed HTTP headers incorrectly proxying device URIs.
- Created a personal playlist, searched and added a JioSaavn track and the device WAV, and confirmed its two entries.
- Playlist download saved the provider track and ignored the already local file.
- Installed the final APK over the test installation and restarted: the playlist and offline track remained available.
- With Wi-Fi and mobile data disabled (`Active default network: none`), the restored provider download played through the Android media session. Flutter/Android fatal-error logs were empty for this final flow.
- Screenshots are in `build/qa/`; they are local QA artifacts, not tracked source files.

## Remaining activation and validation

Production rules and Worker routes have not been deployed. Cloud/social features require that activation. Recognition and humming credentials were absent in the existing backend/config; real adapters and capability-aware UI are built, but live matching remains unavailable until a provider is configured.

Cast receivers, Android Auto head units, translation-model downloads, microphone matching, device-specific EQ and background crossfade still require physical-device/service checks. Lossless/spatial media, beat-aware AutoMix, loudness normalization, vocal separation and competitor account imports are separate unsupported extensions, as explained in `music-expansion-setup.md`.
