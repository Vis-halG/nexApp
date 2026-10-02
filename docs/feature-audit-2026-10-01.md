# nexApp music feature audit and roadmap

Audit date: 1 October 2026 (Asia/Calcutta). App: `NexMusic`, branded `nexApp`, version `0.3.3+8021`.

**Recommendation:** pehle offline-library visibility aur account isolation improve karo; phir personal playlists, editable queue, sleep timer, account sync aur lyrics add karo. Uske baad discovery aur social listening expand karo.

## Scope and verification

- Flutter UI, controller, music providers, media-library persistence, Android integration, Firestore rules, README and existing tests inspect kiye.
- Competitor comparison official Spotify, YouTube Music and Apple Music pages par based hai, checked on the audit date. Availability plan, device, region aur track ke hisaab se vary kar sakti hai.
- `flutter analyze --no-pub`: no issues found.
- `flutter test --no-pub --reporter expanded`: 53 tests passed.
- `flutter test --no-pub tool/discovery_live_test.dart --reporter expanded`: 1 live test passed. Combined discovery/search, both music providers' radio, stream resolution, two byte ranges and video search checked.
- Physical-device UX, battery usage, airplane-mode restart, notifications delivery, production Firebase rules aur Cloudinary configuration ka end-to-end audit nahi hua. Passing checks poore product ki certification nahi hain.
- App behavior change nahi kiya; yeh audit aur proposed backlog hai.

## Already present

| Capability | Current implementation / limit |
| --- | --- |
| Account | Google sign-in through Firebase; app content requires sign-in. |
| Navigation | Home, Stream, Library and Profile. |
| Online discovery | JioSaavn and YouTube Music results mixed with duplicate filtering; separate YouTube video mode. |
| Recommendations | Quick Picks from the last three stream tracks; similar-to-last-played and song radio. Cold start uses featured music. |
| Audio player | Seek, previous/next, shuffle, repeat-one, mini player and full player. |
| Background audio | Audio service, notification and lock-screen controls. |
| Video | Dedicated video player and a Watch Music Video action. Switching currently starts another player. |
| Shared catalogue | Categories plus song/video uploads; batch progress, retry, pause/resume and cancellation. |
| Import | Android share-sheet, file selection, in-app browser downloads and link saving. |
| Editing | Title/category editing and Android audio trimming before upload. |
| Offline | Individual public/provider song downloads and private-media downloads; downloaded files preferred for playback. |
| Personal activity | Likes, recents, most played, never played and recently watched; stored on the device. |
| Private library | Account-owned folders and media metadata in Firestore; private files use Firebase Storage. |
| Preferences / maintenance | Light/dark mode, activity notification setting, in-app APK update check. |

Home-screen widgets are **not currently implemented**: README lists them, but `NexPhone.kt:76` has an empty `updateWidgets` branch with `Home screen widgets removed`, and the Android manifest does not register widget providers.

## Findings to address before feature expansion

These are source-based findings, except the separately listed tests above. Device reproduction remains a useful next validation step.

| Priority | Finding and impact | Evidence / suggested correction |
| --- | --- | --- |
| P0 | Downloaded online tracks can be missing from Downloads. | `music_controller.dart:791`: `downloadedSongs` filters only the shared `songs` catalogue, while `downloadSong` accepts provider tracks. Persist an offline track index containing metadata and file state for all sources; use it for Downloads. Verify after restart and without network. |
| P0 | Likes/history are device-global, not account-specific. Account switching can retain the previous listener's activity. | Controller loads generic preference keys; `MediaLibrary` uses `media_library_v1`; `signOut()` does not clear or switch likes/history. Introduce UID-scoped storage, a safe legacy-data migration and account-scoped recommendation state. |
| P1 | “Playlists & Categories” is a label over shared categories, not a personal playlist system. | `music_ui.dart:2780`, `music_data.dart:6`: only category creation/listing; songs have one category ID. Add an independent ordered playlist model with references to multiple sources. |
| P1 | Search behavior differs between screens. | Stream uses combined discovery. `music_ui.dart:2596` calls `searchProvider` using the first provider; controller searches that one provider. Reuse combined discovery for Search and invalidate stale results when clearing input. |
| P1 | Shuffle can replay recently heard songs, and Previous does not retrace shuffle history. Repeat is only off/one. | `music_controller.dart:1154-1195`: random next excluding just the current item; Previous follows list order; next wraps at the list end. Add a shuffled traversal/history and explicit off/all/one modes, with a separate autoplay setting. |
| P1 | Audio-mode YouTube playback uses an MP4 containing video as well as audio. | `music_provider.dart:396-407`, `:865-930`: selects the highest-bitrate muxed format. This can increase network/download size. Add source-aware quality options and size estimates; do not describe this as an audio-only stream. Available formats depend on provider access. |
| P1 | Audio/video switching does not preserve playback position. | `_openSongVideo` pauses audio and opens a new player; `VideoScreen._start` initializes and plays without seeking to the audio position. Preserve position when the recording matches, with a clear fallback for different versions. |
| P2 | “Liked Songs” can include videos; recents differ between Home and Profile. | `media_library.dart:132` uses the same predicate for all liked and liked songs; Profile uses `recentSongIds`, while Home uses the mixed activity library. Apply consistent collection rules and labels. |
| P2 | Play counts measure playback starts rather than meaningful listening time. | `recordSongPlay` runs after source loading and increments `plays`. Keep this definition explicit; add listened-duration/completion events before making listening-minute or annual recap claims. |
| P2 | README advertises removed widgets. | Native `updateWidgets` is a no-op. Align documentation with the product; reintroduce music widgets only as an intentional feature. |

The shared-catalogue policy intentionally permits any signed-in listener to rename, move or soft-delete uploads (`firestore.rules`, songs update rule). If the target expands beyond a trusted group, add owner/admin roles, reporting, restore and moderation. Changing this policy is a product decision, not a presumed bug fix.

README also says the unsigned Cloudinary preset lacks format/size restrictions and that deleting catalogue entries leaves media in Cloudinary. Before public growth, verify the live preset, add server-enforced upload limits and a media-cleanup process. Live backend settings were not inspected.

## Competitor comparison and proposed features

Effort is relative: S = small bounded change; M = several screens/model changes; L = substantial playback/backend/platform work. These are planning estimates, not delivery commitments.

| Feature | Verified competitor reference | nexApp gap | Proposed scope | Priority / effort |
| --- | --- | --- | --- | --- |
| Personal playlists | [YouTube Music library and playlists](https://support.google.com/youtubemusic/answer/6313542?hl=en), [Apple Music playlist editing](https://support.apple.com/en-us/118494) | Shared categories and liked collections exist; custom personal playlists absent. | Create, rename, cover, add/remove/reorder tracks, duplicate and multi-source references. | P1 / M |
| Editable playback queue | [Spotify Play Queue](https://support.spotify.com/us/article/play-queue/) | Internal queue exists; no queue editor. | Play next, add to queue, remove, reorder, clear and restore queue after restart. | P1 / M |
| Time-synced lyrics | [Spotify lyrics](https://support.spotify.com/us/article/lyrics/), [Apple lyrics](https://support.apple.com/en-bh/105076) | No lyrics service or screen. | Scrolling lyrics, tap-to-seek, manual LRC import for owned tracks, cached lyrics when permitted. Translation later. | P1 / M; external data access required |
| Download intelligence | [YouTube Music Smart Downloads](https://support.google.com/youtubemusic/answer/6313535?hl=en-GB) | Individual download/progress exists; no bulk playlist download or Wi-Fi/storage policy. | Playlist download, queue, cancel/retry, Wi-Fi-only, storage budget, downloaded-only mode; opt-in smart downloads later. | P1-P2 / M-L |
| Quality settings | [Spotify quality/download settings](https://support.spotify.com/us/article/your-premium-benefits/) | Fixed provider selection; no user-facing quality controls. | Wi-Fi/mobile/download quality, data saver, approximate file sizes and actual format indicators. | P2 / M; provider-dependent |
| Smooth transitions | [Apple AutoMix and Crossfade](https://support.apple.com/en-la/105067) | New URL is loaded for each track; no scheduled transitions. | Preloading and gapless playback first, adjustable crossfade next. AutoMix requires separate audio analysis work. | P2 / L |
| Collaborative playlists | [Apple Music collaboration](https://support.apple.com/en-us/118494) | Everyone shares the global catalogue; no invited collaborators on a playlist. | Private/public playlists, invite link, owner/editor/viewer roles and collaborator approval. | P3 / L |
| Listening rooms | [Spotify Jam](https://support.spotify.com/us/article/jam/) | No listening session model or shared queue. | QR/link room, one host device, song requests/votes and host controls; synchronized remote audio as a later stage. | P3 / L |
| Friends' taste mix | [Spotify Blend](https://support.spotify.com/us/article/social-recommendations-in-playlists/) | Recommendations use one device's recent tracks. | Opt-in group mix using participants' likes, shared artists and listening events. | P3 / L |
| Short discovery previews | [YouTube Music Samples](https://support.google.com/youtubemusic/answer/6313542?hl=en) | Feed cards and full playback exist; no preview discovery experience. | Swipeable short previews with like/play/playlist actions, using permitted preview media. | P3 / M-L |
| Seamless audio/video switch | [Spotify music-video switching](https://support.spotify.com/us/article/your-premium-benefits/) | Watch Video action exists; position transfer is absent. | Carry timestamp between matching recordings and restore audio when closing video. | P2 / M |
| Prompt-based playlists | [Spotify prompted playlists](https://support.spotify.com/us/article/your-premium-benefits/) | No text-prompt playlist flow. | “Rainy evening ke Hindi songs” → constrained catalogue search and saved playlist; start with mood/language rules, then evaluate AI. | P3 / L |

Do not assume lossless is absent from competitors: Spotify's current Premium documentation lists lossless streaming. For nexApp, FLAC upload acceptance does not itself establish a lossless streaming catalogue. Lossless and spatial audio depend on real source media and platform support; a settings toggle cannot create them.

## Additional features suitable for this app

| Feature | User value / scope | Priority / effort |
| --- | --- | --- |
| Sleep timer | 15/30/45/60 minutes, end-of-track, optional fade-out; should behave correctly during background playback. | P1 / S-M |
| Cloud activity sync | Account-scoped likes, playlists and recents across phones; local offline cache plus batched sync and conflict rules. Private-media metadata already has account storage. | P1 / M-L |
| Local device music library | On-device scan with permission, artist/album/folder views, metadata/artwork and playback without mandatory upload; optional guest mode for local/offline use. | P2 / M-L |
| Better recommendation controls | Language onboarding, mood/activity filters, hide song/artist, fewer repeats, completed/skip-aware scoring and “why recommended”. Radio already exists and can supply candidates. | P2 / M |
| Artist/album pages | Current `Song` stores artist text, but no structured album/artist identifiers or detail-page operations. Add metadata and provider capabilities first. | P2 / M-L |
| Share links | Outgoing track/playlist link, Android app links and browser fallback. Inbound share import already exists. | P2 / M |
| Equalizer and sound controls | Android EQ presets, bass and saved preferences where supported; platform fallback. Reliable volume normalization also needs loudness metadata/analysis. | P2 / M-L |
| Listening stats | Weekly most played, artists, listened minutes and shareable recap; collect meaningful playback duration rather than infer minutes from starts. | P2 / M |
| Playlist portability | JSON/CSV export/import and metadata-based matching; show unmatched/ambiguous tracks for review. External account imports require supported integrations. | P2 / M |
| Music widgets | Now playing, liked music and quick play. Native widgets need to be reintroduced; existing Flutter calls alone are insufficient. | P2 / M |
| Chromecast / Android Auto | Device picker/casting and browsable car library. A background media service alone does not verify car integration. | P3 / L |
| Identify a song / hum search | Useful discovery entry point, but requires recognition service, permissions, matching and cost evaluation. | P3 / L |
| Karaoke | Lyrics-only sing-along can follow lyrics work. Independent vocal control needs suitable audio stems or vocal separation, with compute and media-access requirements. | P3 / L |
| Podcasts / audiobooks | Separate content sources, progress, resume, speed and long-form navigation; broadens the product considerably. | P3 / L |

Lyrics, recognition, casting, content previews and provider catalogue integration have their own service/data-access requirements. Source recovery should use supported access. A playback failure should offer retry or a verified matching available source, rather than silently substituting a remix or live recording.

## Recommended release sequence

1. **Foundation:** fix provider download indexing, UID-scoped activity, inconsistent search/collections and README widget claims. Add restart/offline/account-switch checks for these flows.
2. **Daily listening:** personal playlists, editable/restorable queue, repeat off/all/one, shuffle history and sleep timer. These give immediate value without depending on a new catalogue service.
3. **Personal library:** cloud sync, lyrics, download manager, quality/data saver and artist/album browsing. Start sync with account-owned playlist/activity metadata; keep binaries local.
4. **Discovery polish:** language/mood controls, hide/skip feedback, meaningful listening stats, timestamp-preserving video switch, gapless/crossfade and local music scanning.
5. **Social differentiation:** invited collaborative playlists and a single-host listening room, followed by friends' mixes, remote sync and prompt-based discovery when the foundations are reliable.

## Best differentiation opportunities

- **One personal playlist across uploaded music, private imports and supported online sources.** Existing multi-provider discovery is a useful foundation. Playlist entries should preserve source IDs and optional recording/version metadata; expiring playback URLs should be resolved at play time.
- **Offline-first music for weak networks.** A complete offline index, explicit downloaded-only view, local files, Wi-Fi policy and storage budget matter more than adding another discovery carousel.
- **Music for a trusted group.** Invite-only collaborative playlists, song requests and a QR listening room build on the existing shared-upload behaviour without requiring every user to edit the global catalogue.
- **Indian-language discovery.** User-selected language/mood and Hindi/Punjabi/Bhojpuri/Tamil/etc. preferences can improve relevance; providers must expose suitable metadata or the app must maintain reliable tags.

## Suggested implementation boundaries

`music_ui.dart` is roughly 7,900 lines and `music_controller.dart` roughly 2,900 lines. New features should use dedicated playlist, queue, download, activity/sync and lyrics modules rather than keep growing these files. Split boundaries as each feature is added; a complete rewrite is not required for this roadmap.

For playlists, store stable track references and metadata separately from ephemeral stream URLs. For offline items, persist metadata, local file path, source and state together. For sync, isolate every user's local and cloud state and migrate legacy keys deliberately. These choices make later collaboration, portability and playback recovery easier.
