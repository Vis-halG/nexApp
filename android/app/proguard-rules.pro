# ExoPlayer's streaming modules are excluded in build.gradle.kts. just_audio
# and video_player only use them for .mpd, .m3u8 and rtsp:// sources, which
# nexApp refuses before playback.
-dontwarn androidx.media3.exoplayer.dash.**
-dontwarn androidx.media3.exoplayer.hls.**
-dontwarn androidx.media3.exoplayer.rtsp.**
-dontwarn androidx.media3.exoplayer.smoothstreaming.**

# Preserve audio_service and Android media session classes
-keep class com.ryanheise.audioservice.** { *; }
-keep class androidx.media.** { *; }
-keep class androidx.media3.** { *; }

# Size optimizations for R8
-repackageclasses ''
-allowaccessmodification
-keep class com.thenex.nex_music.NexCastOptions { *; }
