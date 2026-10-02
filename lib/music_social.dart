import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'listening_models.dart';
import 'music_data.dart';

class MusicSocial extends ChangeNotifier {
  MusicSocial({required this.firestore, required this.uid}) {
    _broadcast = Timer.periodic(const Duration(seconds: 5), (_) {
      final state = playbackState?.call();
      if (isHost && state != null) {
        unawaited(
          publish(
            state.song,
            state.playing,
            state.position,
          ).catchError(_failed),
        );
      }
    });
  }
  final FirebaseFirestore firestore;
  final String uid;
  Map<String, dynamic>? room;
  String? roomId, error;
  List<Map<String, dynamic>> requests = [];
  List<Song> groupTaste = [];
  StreamSubscription<dynamic>? _roomSub, _requestsSub, _tastesSub;
  bool _disposed = false;
  Timer? _broadcast;
  ({Song? song, bool playing, Duration position}) Function()? playbackState;
  bool get isHost => room?['hostUid'] == uid;
  void Function(Map<String, dynamic> state)? onState;
  String get inviteCode => roomId ?? '';
  Future<String> createRoom(String name) async {
    await leave();
    final code = newMusicId().substring(0, 20);
    await firestore.collection('listeningRooms').doc(code).set({
      'name': name.trim().isEmpty
          ? 'Music room'
          : name.trim().substring(0, name.trim().length.clamp(0, 60)),
      'hostUid': uid,
      'members': [uid],
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
      'playing': false,
      'positionMs': 0,
      'current': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _listen(code);
    return code;
  }

  Future<void> join(String code) async {
    final value = code.trim();
    if (!RegExp(r'^[a-z0-9]{16,40}$').hasMatch(value)) {
      throw const FormatException(
        'Enter the room code or use an invitation link.',
      );
    }
    await leave();
    final reference = firestore.collection('listeningRooms').doc(value);
    await firestore.runTransaction((transaction) async {
      final document = await transaction.get(reference);
      final state = document.data();
      if (state == null || state['active'] != true) {
        throw StateError('This listening room has ended.');
      }
      final members = List<String>.from(state['members'] as List);
      if (members.length >= 25 && !members.contains(uid)) {
        throw StateError('This room is full.');
      }
      if (!members.contains(uid)) members.add(uid);
      transaction.update(reference, {'members': members});
    });
    _listen(value);
  }

  void _listen(String id) {
    roomId = id;
    _tastesSub = firestore
        .collection('listeningRooms')
        .doc(id)
        .collection('tastes')
        .snapshots()
        .listen((snapshot) {
          if (_disposed) return;
          groupTaste = {
            for (final document in snapshot.docs)
              for (final song in readSongs(document.data()['tracks']))
                song.id: song,
          }.values.toList();
          notifyListeners();
        }, onError: _failed);
    _roomSub = firestore
        .collection('listeningRooms')
        .doc(id)
        .snapshots()
        .listen((doc) {
          if (_disposed) return;
          room = doc.data();
          onState?.call(room ?? {});
          notifyListeners();
        }, onError: _failed);
    _requestsSub = firestore
        .collection('listeningRooms')
        .doc(id)
        .collection('requests')
        .snapshots()
        .listen((snapshot) {
          if (_disposed) return;
          requests =
              snapshot.docs.map((d) => {...d.data(), 'id': d.id}).toList()
                ..sort((a, b) {
                  int votes(Map r) => (r['votes'] as Map? ?? {}).values
                      .where((v) => v == true)
                      .length;
                  return votes(b).compareTo(votes(a));
                });
          notifyListeners();
        }, onError: _failed);
  }

  void _failed(Object e) {
    if (_disposed) return;
    error = 'The room connection was interrupted. Try rejoining.';
    debugPrint('Room: $e');
    notifyListeners();
  }

  Future<void> publish(Song? song, bool playing, Duration position) async {
    if (!isHost || roomId == null || _disposed) return;
    await firestore.collection('listeningRooms').doc(roomId).update({
      'current': song == null ? null : trackJson(song, cloud: true),
      'playing': playing,
      'positionMs': position.inMilliseconds,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> request(Song song) async {
    if (roomId == null) throw StateError('Join a room first.');
    await firestore
        .collection('listeningRooms')
        .doc(roomId)
        .collection('requests')
        .doc(newMusicId())
        .set({
          'song': trackJson(song, cloud: true),
          'requestedBy': uid,
          'votes': <String, bool>{},
          'createdAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> vote(String requestId, bool value) async => firestore
      .collection('listeningRooms')
      .doc(roomId)
      .collection('requests')
      .doc(requestId)
      .update({'votes.$uid': value});
  Future<void> removeRequest(String id) => firestore
      .collection('listeningRooms')
      .doc(roomId)
      .collection('requests')
      .doc(id)
      .delete();
  Future<void> leave() async {
    final id = roomId, host = isHost;
    roomId = null;
    room = null;
    requests = [];
    groupTaste = [];
    await _tastesSub?.cancel();
    _tastesSub = null;
    await _roomSub?.cancel();
    await _requestsSub?.cancel();
    _roomSub = null;
    _requestsSub = null;
    if (id != null) {
      try {
        await firestore
            .collection('listeningRooms')
            .doc(id)
            .update(
              host
                  ? {'active': false}
                  : {
                      'members': FieldValue.arrayRemove([uid]),
                    },
            );
      } catch (_) {}
    }
    if (!_disposed) notifyListeners();
  }

  Future<String> invitePlaylist(
    MusicPlaylist playlist, {
    bool editor = true,
  }) async {
    if (playlist.ownerUid != uid) {
      throw StateError('Only the owner can invite collaborators.');
    }
    final token = newMusicId();
    await firestore.collection('playlistInvites').doc(token).set({
      'playlistId': playlist.id,
      'ownerUid': uid,
      'editor': editor,
      'expiresAt': Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 7)),
      ),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return token;
  }

  Future<void> shareTaste(Iterable<Song> songs, {bool enabled = true}) async {
    if (roomId == null) return;
    await firestore
        .collection('listeningRooms')
        .doc(roomId)
        .collection('tastes')
        .doc(uid)
        .set({
          'tracks': enabled
              ? songs
                    .where((s) => !s.isLocal && !s.isPrivate && !s.isVideo)
                    .take(20)
                    .map((s) => trackJson(s, cloud: true))
                    .toList()
              : <Map<String, dynamic>>[],
        });
  }

  Future<void> setPlaylistMember(
    MusicPlaylist playlist,
    String member, {
    bool editor = false,
    bool remove = false,
  }) async {
    if (playlist.ownerUid != uid || member == uid) {
      throw StateError('Only the owner can manage other collaborators.');
    }
    await firestore.collection('playlists').doc(playlist.id).update({
      'members': remove
          ? FieldValue.arrayRemove([member])
          : FieldValue.arrayUnion([member]),
      'editors': editor && !remove
          ? FieldValue.arrayUnion([member])
          : FieldValue.arrayRemove([member]),
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<String> acceptPlaylistInvite(String token) async {
    final inviteRef = firestore.collection('playlistInvites').doc(token);
    String playlistId = '';
    await firestore.runTransaction((transaction) async {
      final invite = (await transaction.get(inviteRef)).data();
      if (invite == null ||
          (invite['expiresAt'] as Timestamp).toDate().isBefore(
            DateTime.now(),
          )) {
        throw StateError('This invitation has expired.');
      }
      playlistId = invite['playlistId'] as String;
      final reference = firestore.collection('playlists').doc(playlistId);
      transaction.set(
        firestore
            .collection('users')
            .doc(uid)
            .collection('playlistJoins')
            .doc(playlistId),
        {'inviteId': token, 'createdAt': FieldValue.serverTimestamp()},
      );
      transaction.update(reference, {
        'members': FieldValue.arrayUnion([uid]),
        if (invite['editor'] == true) 'editors': FieldValue.arrayUnion([uid]),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    });
    final playlist = await firestore
        .collection('playlists')
        .doc(playlistId)
        .get();
    if (!playlist.exists) throw StateError('This playlist is unavailable.');
    return playlistId;
  }

  Future<void> revokePlaylistInvites(MusicPlaylist playlist) async {
    if (playlist.ownerUid != uid) {
      throw StateError('Only the owner can revoke invitations.');
    }
    final invites = await firestore
        .collection('playlistInvites')
        .where('ownerUid', isEqualTo: uid)
        .get();
    final references = invites.docs
        .where((d) => d.data()['playlistId'] == playlist.id)
        .map((d) => d.reference)
        .toList();
    for (var start = 0; start < references.length; start += 400) {
      final batch = firestore.batch();
      for (final reference in references.skip(start).take(400)) {
        batch.delete(reference);
      }
      await batch.commit();
    }
  }

  Future<MusicPlaylist?> publicPlaylist(String id) async {
    final doc = await firestore.collection('playlists').doc(id).get();
    return doc.exists
        ? MusicPlaylist.fromJson({...doc.data()!, 'id': id})
        : null;
  }

  @override
  void dispose() {
    _disposed = true;
    _broadcast?.cancel();
    unawaited(_roomSub?.cancel());
    unawaited(_requestsSub?.cancel());
    unawaited(_tastesSub?.cancel());
    super.dispose();
  }
}
