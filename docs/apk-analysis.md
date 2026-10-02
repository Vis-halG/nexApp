# Music reference APK and nexMusic integration

Inspected locally on 2026-09-25 using Android `aapt`, ZIP inventory, manifest,
bundled JSON configuration and DEX inspection. Reference APKs and extracted
third-party assets are excluded from Git; the reference app was not repackaged.

| File | Verified identity | Finding |
| --- | --- | --- |
| `base.apk` | `com.novexa.spicetify`, version `1.0.0` (1), 14,430,877 bytes | Flutter base package with assets and Android glue; no `libapp.so`, kernel snapshot or provider bundle. The architecture split containing compiled Dart code was not supplied. Its exact provider implementation and recommendation algorithm cannot be recovered from this file alone. |

SHA-256:

```text
base.apk  C283FFB5E846ACA01CF5D6613390C38739F99C38E8C573A7A727B33C79DA25C3
```

## Implementation

- Stream interleaves JioSaavn and YouTube Music results. Same-source IDs and
  matching title/artist recordings are de-duplicated; video versions remain
  separate. Original provider IDs are retained for playback and offline files.
- Quick Picks uses recent listening and both providers' song radios. Similar
  recommendations map the seed into each catalogue before requesting radio.
  Cold start uses both providers' featured tracks. Requests have independent
  failure handling, bounded caching and stale-response protection.
- JioSaavn radio uses `webradio.createEntityStation` and `webradio.getSong` with
  `ctx=android`. YouTube uses Music `next` radio and genuine continuation tokens;
  exhausted searches no longer append invented `part N` queries.

Public references checked:

- [JioSaavn radio request schema](https://github.com/saavn-labs/sdk/blob/main/src/saavn/operations/web-radio/schema.ops.ts).

## Verification

```powershell
flutter analyze lib/
flutter test
flutter test tool/discovery_live_test.dart
flutter build apk --release --target-platform android-arm64
```

Live checks validated both music catalogues, searches, song radios, music stream
URL resolution and audio byte reads at the beginning and past 1.5 MB, plus
YouTube video discovery.
