# nexMusic 0.4.1 release verification

Verified 2 October 2026 (Asia/Calcutta). Package `com.thenex.nex_music`, version `0.4.1`, build `8023`.

## Changes

- Socket/DNS failures, timeouts and temporary service errors pause the transfer queue and retry with backoff or on connectivity changes. Manual pause/cancel remains respected. Wi-Fi-only downloads explain how to allow mobile data.
- Downloads resolve fresh provider URLs, refresh an expired link once, discard incomplete files and only index complete downloads.
- Upload retries retain completed Cloudinary transfers and reuse the catalogue ID. A Firestore transaction recognizes a previously committed upload without rewriting it or creating a duplicate.
- Stream opens audio results without a Songs/Videos selector or the four discovery shortcuts. Available music videos remain accessible from the player.
- Artist categories support individual collaboration credits, unknown tags, search and manual tags. New Android uploads read embedded artist metadata when available; supplemental tags are stored per account on the device.
- Random Play is available on Home, Stream and Library. Home mixes sources, Stream uses online music and Library uses uploaded/saved/local/playlist music. Library random playback does not append online radio recommendations; the scope survives queue restoration.

## Local artifact

- APK: `build/app/outputs/flutter-apk/nexMusic-0.4.1-arm64.apk`.
- Native release build passed: Android arm64, min SDK 24, target SDK 36.
- Size: 20,426,476 bytes.
- SHA-256: `ea3531dcbdad1d922d4b28e1f3ed5c4a490e224840fc8e1f89fc1eb09fd4e222`.
- Signature verification passed. Public release certificate SHA-256: `fdb7dd5ee63c5b6668debc4739c0f71261fb7f9ca7547b12a95f3409329e54ab`.

## Checks

| Check | Result |
| --- | --- |
| Flutter analysis: lib, test and opt-in transfer check | No issues |
| Flutter suite | 86 passed |
| Stream/Library UI regression after final test assertion | Passed |
| Live discovery integration | Passed: combined discovery and both radio providers |
| Live complete downloads | Passed: JioSaavn, YouTube Music and the public Cloudinary sample; complete files, matching byte counts and no partial files |
| Android packaged version and signature | Passed |
| Android emulator upgrade and UI | Passed: 0.4.1 installed over the test app, existing two-track playlist and offline song retained; Stream selectors/shortcuts absent, Random Play visible on both added tabs, Artists list opens |
| Git whitespace validation | Passed |

The transfer suite exercises queue-wide DNS recovery, a 100-song upload batch, interrupted downloads, Wi-Fi policy, manual pause, permanent errors, expired links, catalogue failures and a committed upload whose acknowledgement was lost. Random scope tests verify queue membership, restoration and Library queue-end behavior.

Screenshots and local logs are in `build/qa/` and ignored build outputs. GitHub's release workflow builds and publishes the phone APK variants separately; their hashes may differ from this local artifact.

## Validation limits

Live download checks use reachable providers and Cloudinary's public demo file. They do not authenticate to the user's Firebase account or upload files into their Cloudinary library. Recovery keeps transfers queued while the app is open; an unreachable server or broken phone DNS still requires connectivity to recover. No production backend deployment or credential changes were made. Artist tags added to public uploads on this device do not change the existing Firestore schema or sync to other devices.
