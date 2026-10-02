part of 'music_ui.dart';

Future<void> _castSong(BuildContext context, Song? song) async {
  if (song == null) return;
  _push(context, MusicCastScreen(song: song));
}

class MusicCastScreen extends StatefulWidget {
  const MusicCastScreen({super.key, required this.song});
  final Song song;
  @override
  State<MusicCastScreen> createState() => _MusicCastScreenState();
}

class _MusicCastScreenState extends State<MusicCastScreen> {
  bool casting = false, busy = false;
  String? status;
  Future<void> start() async {
    final music = context.read<MusicController>();
    setState(() => busy = true);
    try {
      final url = await music.resolvedPlayableUrl(widget.song);
      if (!url.startsWith('https:')) {
        throw StateError('Choose an online track to play on a receiver.');
      }
      final started = await MusicDevice.cast(
        widget.song,
        url,
        position: music.position,
      );
      if (!started) {
        throw StateError(
          'Connect a receiver first, then tap Play on receiver.',
        );
      }
      await music.pauseAudio();
      if (mounted) {
        setState(() {
          casting = true;
          status = 'Playing on your receiver';
        });
      }
    } catch (e) {
      if (mounted) setState(() => status = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cast music')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.cast, size: 72, color: NexApp.violet),
        const SizedBox(height: 20),
        Text(
          widget.song.title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: MusicDevice.android
              ? () => _featureTask(context, MusicDevice.openCast)
              : null,
          child: const Text('Choose receiver'),
        ),
        OutlinedButton(
          onPressed: busy ? null : start,
          child: Text(busy ? 'Connecting…' : 'Play on receiver'),
        ),
        if (casting)
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              IconButton(
                tooltip: 'Play on receiver',
                icon: const Icon(Icons.play_arrow),
                onPressed: () => MusicDevice.castControl('play'),
              ),
              IconButton(
                tooltip: 'Pause on receiver',
                icon: const Icon(Icons.pause),
                onPressed: () => MusicDevice.castControl('pause'),
              ),
              TextButton(
                onPressed: () => _featureTask(context, () async {
                  await MusicDevice.stopCast();
                  if (mounted) {
                    setState(() {
                      casting = false;
                      status = 'Disconnected';
                    });
                  }
                }),
                child: const Text('Disconnect'),
              ),
            ],
          ),
        if (status != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(status!, textAlign: TextAlign.center),
          ),
      ],
    ),
  );
}

Future<void> _openMusicLink(BuildContext context, String link) =>
    _featureTask(context, () async {
      final uri = Uri.tryParse(link);
      if (uri == null ||
          !((uri.scheme == 'https' &&
                  uri.host == Uri.parse(pushWorkerUrl).host) ||
              (uri.scheme == 'nexmusic' && uri.host == 'share'))) {
        throw const FormatException('This music link is invalid.');
      }
      final path = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (path.firstOrNull == 'share') path.removeAt(0);
      final music = context.read<MusicController>();
      if (path.firstOrNull == 'track') {
        final data = uri.queryParameters['data'];
        if (data == null || data.length > 16000) {
          throw const FormatException('This song link is invalid.');
        }
        final row = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(data))),
        );
        final song = row is Map
            ? Song.fromJson(Map<String, dynamic>.from(row))
            : null;
        if (song == null || song.isLocal || song.isPrivate) {
          throw const FormatException('This track cannot be shared.');
        }
        music.library.rememberSongs([song]);
        if (context.mounted) await _openSong(context, song, queue: [song]);
        return;
      }
      if (path.length != 2 || music.social == null) {
        throw StateError('Sign in to open this invitation.');
      }
      switch (path[0]) {
        case 'room':
          await music.social!.join(path[1]);
          if (context.mounted) _push(context, const SocialMusicScreen());
        case 'invite':
          final id = await music.social!.acceptPlaylistInvite(path[1]);
          if (context.mounted) _push(context, PlaylistScreen(id: id));
        case 'playlist':
          final p = await music.social!.publicPlaylist(path[1]);
          if (p == null || !p.public) {
            throw StateError('This playlist is unavailable.');
          }
          music.personal.rememberSharedPlaylist(p);
          if (context.mounted) _push(context, PlaylistScreen(id: p.id));
        default:
          throw const FormatException('This music link is invalid.');
      }
    });
