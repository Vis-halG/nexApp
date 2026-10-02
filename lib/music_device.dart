import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'music_data.dart';

class MusicDevice {
  static const channel = MethodChannel('com.thenex.nexmusic/features');
  static bool get android => !kIsWeb && Platform.isAndroid;
  static Future<List<Song>> scan() async {
    if (!android) throw UnsupportedError('Use Import files on this device.');
    final rows = await channel.invokeListMethod<Object?>('scanMusic') ?? [];
    return rows
        .whereType<Map>()
        .map(
          (r) => Song(
            id: 'local:${r['id']}',
            title: '${r['title']}',
            kind: 'audio',
            url: '${r['uri']}',
            artist: '${r['artist'] ?? ''}',
            album: '${r['album'] ?? ''}',
            albumId: '${r['albumId'] ?? ''}',
            artistId: '${r['artistId'] ?? ''}',
            localFolder: '${r['folder'] ?? ''}',
            sizeBytes: (r['size'] as num? ?? 0).toInt(),
            durationMs: (r['duration'] as num? ?? 0).toInt(),
          ),
        )
        .toList();
  }

  static Future<void> share(String text) =>
      channel.invokeMethod<void>('shareText', {'text': text});
  static Future<Map<String, dynamic>> equalizer(int session) async =>
      Map<String, dynamic>.from(
        await channel.invokeMapMethod<String, dynamic>('equalizer', {
              'session': session,
            }) ??
            {},
      );
  static Future<void> setEq(int band, double gain, bool enabled) =>
      channel.invokeMethod<void>('setEq', {
        'band': band,
        'gain': gain,
        'enabled': enabled,
      });
  static Future<void> setBass(int strength) =>
      channel.invokeMethod<void>('setBass', {'strength': strength});
  static Future<String> translate(String text, String target) async {
    if (!android) {
      throw UnsupportedError(
        'Offline lyric translation is available on Android.',
      );
    }
    return await channel.invokeMethod<String>('translate', {
          'text': text,
          'target': target,
        }) ??
        '';
  }

  static Future<void> openCast() => channel.invokeMethod<void>('openCast');
  static Future<bool> cast(
    Song song,
    String url, {
    Duration position = Duration.zero,
  }) async =>
      await channel.invokeMethod<bool>('castMedia', {
        'url': url,
        'title': song.title,
        'artist': song.artist,
        'art': song.artworkUrl,
        'video': song.isVideo,
        'positionMs': position.inMilliseconds,
      }) ??
      false;
  static Future<void> stopCast() => channel.invokeMethod<void>('stopCast');
  static Future<void> castControl(String action) =>
      channel.invokeMethod<void>('castControl', {'action': action});
}
