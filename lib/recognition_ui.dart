part of 'music_ui.dart';

class RecognitionScreen extends StatefulWidget {
  const RecognitionScreen({super.key});
  @override
  State<RecognitionScreen> createState() => _RecognitionScreenState();
}

class _RecognitionScreenState extends State<RecognitionScreen> {
  final recorder = AudioRecorder();
  bool busy = false, recording = false, humming = false;
  String? message;
  List<Song> matches = [];
  Timer? timer;
  Future<void> identify() async {
    final music = context.read<MusicController>();
    setState(() {
      busy = true;
      message = 'Checking recognition service…';
    });
    try {
      if (!music.signedIn) throw StateError('Sign in to identify songs.');
      final capability = await fetchMusicJson(
        Uri.parse('$pushWorkerUrl/capabilities'),
      );
      if (capability is! Map ||
          capability[humming ? 'humming' : 'recognition'] != true) {
        throw StateError(
          humming
              ? 'Humming recognition is not configured for this account yet.'
              : 'Song recognition service is not configured yet.',
        );
      }
      if (!await recorder.hasPermission()) {
        throw StateError('Microphone permission is needed to listen.');
      }
      final folder = await getTemporaryDirectory();
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: '${folder.path}/nex-identify-${newMusicId()}.wav',
      );
      if (!mounted) {
        await recorder.stop();
        return;
      }
      setState(() {
        recording = true;
        message = humming ? 'Hum for 10 seconds…' : 'Listening for 10 seconds…';
      });
      timer = Timer(const Duration(seconds: 10), finish);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          recording = false;
          message = '$e';
        });
      }
    }
  }

  Future<void> finish() async {
    timer?.cancel();
    timer = null;
    if (!recording) return;
    setState(() {
      recording = false;
      message = 'Finding this song…';
    });
    String? path;
    try {
      path = await recorder.stop();
      if (path == null) throw StateError('No recording was captured.');
      if (!mounted) return;
      final music = context.read<MusicController>();
      final result = await music.identifyRecording(path, humming: humming);
      final query = '${result['title'] ?? ''} ${result['artist'] ?? ''}'.trim();
      if (query.isEmpty) {
        throw StateError('No match found. Try again near the music.');
      }
      final found = await music.discovery.browse(query: query);
      if (mounted) {
        setState(() {
          matches = found.songs;
          message = 'Found: $query';
          busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          message = '$e';
          busy = false;
        });
      }
    } finally {
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    unawaited(recorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Identify a song')),
    body: ListView(
      children: [
        const SizedBox(height: 36),
        const Icon(Icons.music_note, size: 80, color: NexApp.violet),
        SwitchListTile(
          title: const Text('Hum a melody'),
          value: humming,
          onChanged: busy ? null : (v) => setState(() => humming = v),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: FilledButton.icon(
            onPressed: recording
                ? finish
                : busy
                ? null
                : identify,
            icon: Icon(recording ? Icons.stop : Icons.mic),
            label: Text(
              recording
                  ? 'Identify now'
                  : busy
                  ? 'Finding…'
                  : 'Start listening',
            ),
          ),
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(message!, textAlign: TextAlign.center),
          ),
        for (final song in matches) _discoveryTile(context, song, matches),
      ],
    ),
  );
}
