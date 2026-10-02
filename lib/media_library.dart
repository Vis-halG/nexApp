import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'music_data.dart';

enum MediaCollection {
  recent('Recently played & watched'),
  watched('Recently watched'),
  liked('All liked'),
  likedSongs('Liked songs'),
  mostPlayed('Most played'),
  neverPlayed('Never played');

  const MediaCollection(this.label);
  final String label;
}

class LibraryMedia {
  LibraryMedia.song(this.song);

  Song song;
  bool liked = false, playedBefore = false;
  int plays = 0, lastPlayed = 0;
  String get key => 'song:${song.id}';
  String get title => song.title;
  String get artwork => song.artworkUrl;
  bool get isVideo => song.isVideo;
  bool get wasPlayed => plays > 0 || playedBefore;
  String get kind => song.isVideo ? 'Video' : 'Song';

  Map<String, dynamic> toJson() => {
    'song': song.toJson(),
    'liked': liked,
    'playedBefore': playedBefore,
    'plays': plays,
    'lastPlayed': lastPlayed,
  };
}

/// Local activity stores metadata as well as IDs, so online likes survive a
/// restart even when their tracks are absent from the current discovery feed.
class MediaLibrary extends ChangeNotifier {
  MediaLibrary(this._prefs, {this.namespace = ''}) {
    _legacyLikes.addAll(_prefs.getStringList(key('likedSongIds')) ?? []);
    _legacyRecent.addAll(_prefs.getStringList(key('recentSongIds')) ?? []);
    for (final raw
        in _prefs.getStringList(key('recent_stream_history')) ?? <String>[]) {
      try {
        final song = Song.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (song != null) {
          _legacyRecent.add(song.id);
          rememberSongs([song]);
        }
      } catch (_) {
        /* An invalid old entry must not hide the rest. */
      }
    }
    try {
      final rows = jsonDecode(_prefs.getString(key(_storageKey)) ?? '[]');
      if (rows is List) {
        for (final raw in rows.whereType<Map>()) {
          try {
            LibraryMedia? item;
            if (raw['song'] is Map) {
              final song = Song.fromJson(
                Map<String, dynamic>.from(raw['song']),
              );
              if (song != null && !song.isPrivate) {
                item = LibraryMedia.song(song);
              }
            }
            if (item == null) continue;
            item
              ..liked = raw['liked'] == true
              ..playedBefore = raw['playedBefore'] == true
              ..plays = (raw['plays'] as num? ?? 0).toInt().clamp(0, 1000000000)
              ..lastPlayed = (raw['lastPlayed'] as num? ?? 0).toInt();
            _items[item.key] = item;
          } catch (_) {
            /* Keep valid saved activity when one row is damaged. */
          }
        }
      }
    } catch (_) {
      /* Start with the legacy history if stored JSON is damaged. */
    }
  }

  static const _storageKey = 'media_library_v1';
  final String namespace;
  String key(String name) => namespace.isEmpty ? name : '$namespace:$name';
  List<LibraryMedia> get entries => List.unmodifiable(_items.values);
  final SharedPreferences _prefs;
  final _items = <String, LibraryMedia>{};
  final _legacyLikes = <String>{}, _legacyRecent = <String>{};
  Future<void> _saved = Future.value();
  Future<void> get saved => _saved;

  void rememberSongs(Iterable<Song> songs) {
    for (final song in songs) {
      if (song.isPrivate) continue;
      final item = _items.putIfAbsent(
        'song:${song.id}',
        () => LibraryMedia.song(song)
          ..liked = _legacyLikes.contains(song.id)
          ..playedBefore = _legacyRecent.contains(song.id),
      );
      item.song = song;
    }
    _trimDiscovery();
  }

  void _trimDiscovery() {
    // Only discovered, untouched cards are disposable; likes/history stay.
    final unseen = _items.values
        .where((e) => !e.liked && !e.wasPlayed)
        .toList();
    for (final item in unseen.take(
      (unseen.length - 500).clamp(0, unseen.length),
    )) {
      _items.remove(item.key);
    }
  }

  List<LibraryMedia> collection(MediaCollection collection) {
    final result = _items.values
        .where(
          (item) => switch (collection) {
            MediaCollection.recent => item.wasPlayed,
            MediaCollection.watched => item.wasPlayed && item.isVideo,
            MediaCollection.liked => item.liked,
            MediaCollection.likedSongs => item.liked && !item.isVideo,
            MediaCollection.mostPlayed => item.plays > 0,
            MediaCollection.neverPlayed => !item.wasPlayed,
          },
        )
        .toList();
    if (collection == MediaCollection.recent ||
        collection == MediaCollection.watched) {
      result.sort((a, b) => b.lastPlayed.compareTo(a.lastPlayed));
    } else if (collection == MediaCollection.mostPlayed) {
      result.sort((a, b) {
        final count = b.plays.compareTo(a.plays);
        return count != 0 ? count : b.lastPlayed.compareTo(a.lastPlayed);
      });
    }
    return result;
  }

  void setSongLiked(Song song, bool liked) {
    setSongsLiked([song], liked);
  }

  void setSongsLiked(Iterable<Song> songs, bool liked) {
    for (final song in songs.where((s) => !s.isPrivate)) {
      final item = _items.putIfAbsent(
        'song:${song.id}',
        () =>
            LibraryMedia.song(song)
              ..playedBefore = _legacyRecent.contains(song.id),
      );
      item.song = song;
      item.liked = liked;
      if (liked) {
        _legacyLikes.add(song.id);
      } else {
        _legacyLikes.remove(song.id);
      }
    }
    _trimDiscovery();
    _changed();
  }

  void recordSongPlay(Song song) {
    if (song.isPrivate) return;
    rememberSongs([song]);
    _record(_items['song:${song.id}']!);
  }

  void applyCloudLike(Song song, bool liked) {
    if (song.isPrivate) return;
    rememberSongs([song]);
    _items['song:${song.id}']!.liked = liked;
    if (liked) {
      _legacyLikes.add(song.id);
    } else {
      _legacyLikes.remove(song.id);
    }
    _changed();
  }

  void applyCloudPlay(Song song, int lastPlayed) {
    if (song.isPrivate || lastPlayed <= 0) return;
    rememberSongs([song]);
    final item = _items['song:${song.id}']!;
    if (lastPlayed > item.lastPlayed) {
      item.lastPlayed = lastPlayed;
      item.playedBefore = true;
      _changed();
    }
  }

  void _record(LibraryMedia item) {
    item.plays++;
    item.lastPlayed = DateTime.now().millisecondsSinceEpoch;
    _changed();
  }

  void removeSongs(Set<String> ids) {
    _items.removeWhere((_, item) => ids.contains(item.song.id));
    _legacyLikes.removeAll(ids);
    _legacyRecent.removeAll(ids);
    _changed();
  }

  void _changed() {
    final json = jsonEncode(
      _items.values
          .where((e) => e.liked || e.wasPlayed)
          .map((e) => e.toJson())
          .toList(),
    );
    _saved = _saved.catchError((Object _) {}).then((_) async {
      await _prefs.setString(key(_storageKey), json);
    });
    unawaited(
      _saved.catchError((Object error) {
        debugPrint('Could not save media history: $error');
      }),
    );
    notifyListeners();
  }
}
