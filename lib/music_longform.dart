import 'package:xml/xml.dart';
import 'music_data.dart';
import 'music_lyrics.dart';
import 'listening_models.dart';

class PodcastFeed {
  const PodcastFeed(this.title, this.episodes);
  final String title;
  final List<Song> episodes;
}

PodcastFeed parsePodcastFeed(String content, Uri feedUrl) {
  final document = XmlDocument.parse(content);
  final channel =
      document.findAllElements('channel').firstOrNull ?? document.rootElement;
  String text(XmlElement node, String name) =>
      node.childElements
          .where((e) => e.name.local == name)
          .firstOrNull
          ?.innerText
          .trim() ??
      '';
  final title = text(channel, 'title');
  final feedArt = channel.childElements
      .where((e) => e.name.local == 'image')
      .firstOrNull;
  final art =
      feedArt?.getAttribute('href') ??
      (feedArt == null ? '' : text(feedArt, 'url'));
  final episodes = <Song>[];
  for (final item in channel.childElements.where(
    (e) => e.name.local == 'item' || e.name.local == 'entry',
  )) {
    final enclosure = item.childElements
        .where(
          (e) =>
              e.name.local == 'enclosure' ||
              (e.name.local == 'link' && e.getAttribute('rel') == 'enclosure'),
        )
        .firstOrNull;
    final url =
        enclosure?.getAttribute('url') ?? enclosure?.getAttribute('href') ?? '';
    if (Uri.tryParse(url)?.scheme != 'https') continue;
    final guid = text(item, 'guid');
    final episodeTitle = text(item, 'title');
    if (episodeTitle.isEmpty) continue;
    final duration = text(item, 'duration').split(':');
    var seconds = 0;
    for (final part in duration) {
      seconds = seconds * 60 + (int.tryParse(part) ?? 0);
    }
    final episodeArt = item.childElements
        .where((e) => e.name.local == 'image')
        .firstOrNull
        ?.getAttribute('href');
    episodes.add(
      Song(
        id: 'podcast:${musicStorageId('${feedUrl.toString()}:${guid.isEmpty ? url : guid}')}',
        title: episodeTitle,
        artist: title,
        album: title,
        kind: 'audio',
        url: url,
        contentType: 'podcast',
        durationMs: seconds * 1000,
        artworkUrl: episodeArt ?? art,
      ),
    );
    if (episodes.length == 100) break;
  }
  if (episodes.isEmpty) {
    throw const FormatException(
      'No playable HTTPS audio episodes were found in this feed.',
    );
  }
  return PodcastFeed(title.isEmpty ? feedUrl.host : title, episodes);
}

Future<PodcastFeed> loadPodcastFeed(String url) async {
  final uri = Uri.parse(url.trim());
  return parsePodcastFeed(await fetchMusicText(uri), uri);
}
