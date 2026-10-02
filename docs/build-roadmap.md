# Music expansion implementation tracker

Implementation: nexApp `0.4.0+8022`. Checked items describe code and native adapters; production activation and physical-device validation are listed below.

Requested scope: build the complete feature roadmap from the 1 October 2026 audit, using the existing Firebase / Cloudflare backend.

- [x] Account-scoped activity, offline index, consistent collections/search
- [x] Personal playlists, covers, ordering, import/export, sharing
- [x] Queue editor/restore, shuffle history, repeat modes, autoplay
- [x] Sleep timer, preloading/gapless, crossfade, EQ, quality/data saver
- [x] Cloud activity and playlist sync
- [x] Lyrics, LRC import, seek, offline cache, translation, karaoke view
- [x] Download manager, bulk downloads, Wi-Fi/storage policy, smart downloads
- [x] Local music library and guest access
- [x] Mood/language/feedback discovery, artist/album pages, prompt playlists, previews
- [x] Meaningful listening stats and shareable recap
- [x] Collaborative playlists, rooms/requests/votes, shared playback, taste mix
- [x] Android music widgets, sharing/deep links, Cast and Android Auto
- [x] Song recognition adapter and backend route
- [x] Podcasts/audiobooks: import, RSS, resume/speed
- [x] Rules/backend validation, regression tests, release APK

External services must be wired to real adapters and tested where configured. Device-only integrations must be built and identified separately from physical-device validation. Credentials are not embedded in the app.

## Activation still pending

- [ ] Deploy the reviewed Firestore rules and Cloudflare Worker to the existing backend. Until then, new cloud/social and recognition routes are not live.
- [ ] Configure real recognition/humming provider credentials; none were found in the existing config.
- [ ] Validate Cast receivers, Android Auto, translation model downloads, device audio effects and background transitions on physical devices.
- [ ] Provision suitable media/integrations for lossless/spatial playback, beat-aware AutoMix, loudness normalization, vocal separation and competitor account imports if those extensions are desired. They are not implemented in this build.

## Checks

- Flutter analysis: clean.
- Flutter suite: 71 tests passed.
- Live combined music discovery, search, radio and stream byte ranges: passed.
- Worker route tests: 5 passed.
- Firestore emulator authorization tests: 5 passed.
- Native arm64 release compilation and isolated Android emulator smoke checks: see the release verification report.
