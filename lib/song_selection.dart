import 'package:flutter/foundation.dart';

import 'music_data.dart';

/// A selection belongs to one screen and follows that screen's song ordering.
class SongSelection extends ChangeNotifier {
  SongSelection({List<Song>? songs}) : _source = songs;

  List<Song>? _source;
  List<Song> _songs = [];
  final Set<String> _ids = {};
  bool active = false;
  bool busy = false;
  bool _disposed = false;
  bool get disposed => _disposed;

  List<Song> get selected =>
      _songs.where((song) => _ids.contains(song.id)).toList();
  bool contains(Song song) => _ids.contains(song.id);
  bool get allSelected => _songs.isNotEmpty && _ids.length == _songs.length;

  static List<Song> _unique(Iterable<Song> songs) =>
      {for (final song in songs) song.id: song}.values.toList();

  void toggle(Song song, List<Song> queue) {
    if (busy) return;
    if (!active) {
      _songs = _unique(_source ?? queue);
      active = true;
    }
    if (!_songs.any((track) => track.id == song.id)) {
      _songs = _unique([..._songs, ...queue, song]);
    }
    if (!_ids.add(song.id)) _ids.remove(song.id);
    notifyListeners();
  }

  void selectAll() {
    if (busy) return;
    if (allSelected) {
      _ids.clear();
    } else {
      _ids.addAll(_songs.map((song) => song.id));
    }
    notifyListeners();
  }

  void updateSongs(List<Song>? songs) {
    _source = songs;
    if (!active || songs == null) return;
    _songs = _unique(songs);
    _ids.retainAll(_songs.map((song) => song.id));
    if (_songs.isEmpty) active = false;
    notifyListeners();
  }

  void close() {
    active = false;
    _ids.clear();
    _songs = [];
    notifyListeners();
  }

  void setBusy(bool value) {
    busy = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
