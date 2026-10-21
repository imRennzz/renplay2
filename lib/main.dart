import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final player = AudioPlayer();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.renplay.audio',
    androidNotificationChannelName: 'Renplay',
    androidNotificationOngoing: true,
  );
  final lib = Lib();
  await lib.load();
  runApp(RenplayApp(lib));
}

class Track {
  final String id, path, title, artist;
  final String? art;
  Track(this.id, this.path, this.title, this.artist, this.art);
  Map<String, dynamic> toJson() => {'id': id, 'path': path, 'title': title, 'artist': artist, 'art': art};
  factory Track.fromJson(Map<String, dynamic> j) => Track(j['id'], j['path'], j['title'], j['artist'], j['art']);
}

class Lib extends ChangeNotifier {
  List<Track> tracks = [];
  Map<String, List<String>> lists = {};
  List<Track> queue = [];
  String cur = 'all';

  List<Track> get shown => cur == 'all'
      ? tracks
      : [for (final id in lists[cur] ?? <String>[]) ...tracks.where((t) => t.id == id)];

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    try {
      tracks = (jsonDecode(p.getString('tracks') ?? '[]') as List).map((e) => Track.fromJson(e)).toList();
      lists = (jsonDecode(p.getString('lists') ?? '{}') as Map).map((k, v) => MapEntry(k as String, List<String>.from(v)));
    } catch (_) {}
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('tracks', jsonEncode(tracks));
    await p.setString('lists', jsonEncode(lists));
    notifyListeners();
  }

  void setCur(String k) { cur = k; notifyListeners(); }

  Future<void> add() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: true);
    if (r == null) return;
    final dir = (await getApplicationDocumentsDirectory()).path;
    for (final f in r.files) {
      final src = f.path;
      if (src == null) continue;
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final dot = src.lastIndexOf('.');
      final dest = '$dir/$id${dot > 0 ? src.substring(dot) : '.mp3'}';
      await File(src).copy(dest);
      var title = f.name.replaceAll(RegExp(r'\.[^.]+$'), ''), artist = '';
      String? art;
      try {
        final m = readMetadata(File(dest), getImage: true);
        if ((m.title ?? '').isNotEmpty) title = m.title!;
        artist = m.artist ?? '';
        if (m.pictures.isNotEmpty) {
          art = '$dir/$id.img';
          await File(art).writeAsBytes(m.pictures.first.bytes);
        }
      } catch (_) {}
      tracks.add(Track(id, dest, title, artist, art));
    }
    await save();
  }

  Future<void> remove(Track t) async {
    tracks.remove(t);
    lists.forEach((_, v) => v.remove(t.id));
    try {
      await File(t.path).delete();
      if (t.art != null) await File(t.art!).delete();
    } catch (_) {}
    await save();
  }

  Future<void> play(List<Track> l, int i) async {
    queue = l;
    await player.setAudioSource(
      ConcatenatingAudioSource(children: [
        for (final t in l)
          AudioSource.file(t.path,
              tag: MediaItem(
                  id: t.id,
                  title: t.title,
                  artist: t.artist.isEmpty ? null : t.artist,
                  artUri: t.art == null ? null : Uri.file(t.art!)))
      ]),
      initialIndex: i,
    );
    player.play();
    notifyListeners();
  }
}

String fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

Widget artW(Track? t, double? size) => t?.art != null
    ? Image.file(File(t!.art!), width: size, height: size, fit: BoxFit.cover)
    : Container(width: size, height: size, color: Colors.black12, child: Icon(Icons.music_note, size: size == null ? 72 : 24));

class RenplayApp extends StatelessWidget {
  final Lib lib;
  const RenplayApp(this.lib, {super.key});
  @override
  Widget build(BuildContext context) {
    ThemeData th(Brightness b) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2A6F68), brightness: b));
    return MaterialApp(
      title: 'Renplay',
      debugShowCheckedModeBanner: false,
      theme: th(Brightness.light),
      darkTheme: th(Brightness.dark),
      home: Home(lib),
    );
  }
}

Future<void> newList(BuildContext context, Lib lib, Track? t) async {
  final c = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Nova playlist'),
      content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'Nome')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Criar')),
      ],
    ),
  );
  if (name == null || name.isEmpty || name == 'all') return;
  lib.lists.putIfAbsent(name, () => []);
  if (t != null && !lib.lists[name]!.contains(t.id)) lib.lists[name]!.add(t.id);
  if (t == null) lib.cur = name;
  await lib.save();
}

void trackMenu(BuildContext context, Lib lib, Track? t) {
  if (t == null) return;
  showModalBottomSheet(
    context: context,
    builder: (sheet) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        ListTile(title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: const Text('Opções')),
        for (final k in lib.lists.keys)
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: Text('Adicionar a $k'),
            onTap: () async {
              if (!lib.lists[k]!.contains(t.id)) lib.lists[k]!.add(t.id);
              await lib.save();
              if (sheet.mounted) Navigator.pop(sheet);
            },
          ),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('Nova playlist'),
          onTap: () async { Navigator.pop(sheet); await newList(context, lib, t); },
        ),
        if (lib.cur != 'all')
          ListTile(
            leading: const Icon(Icons.remove_circle_outline),
            title: const Text('Remover desta playlist'),
            onTap: () async { lib.lists[lib.cur]!.remove(t.id); await lib.save(); if (sheet.mounted) Navigator.pop(sheet); },
          ),
        ListTile(
          leading: const Icon(Icons.delete_outline),
          title: const Text('Excluir da biblioteca'),
          onTap: () async { Navigator.pop(sheet); await lib.remove(t); },
        ),
      ]),
    ),
  );
}

class Home extends StatelessWidget {
  final Lib lib;
  const Home(this.lib, {super.key});

  void openPlayer(BuildContext context) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerPage(lib)));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: lib,
        builder: (context, _) {
          final l = lib.shown;
          return Scaffold(
            appBar: AppBar(
              title: const Text('Renplay', style: TextStyle(fontWeight: FontWeight.w700)),
              actions: [TextButton.icon(onPressed: lib.add, icon: const Icon(Icons.add), label: const Text('Adicionar'))],
            ),
            body: Column(children: [
              SizedBox(
                height: 48,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                  for (final k in ['all', ...lib.lists.keys])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: Text(k == 'all' ? 'Todas' : k), selected: lib.cur == k, onSelected: (_) => lib.setCur(k)),
                    ),
                  ActionChip(label: const Text('+ Playlist'), onPressed: () => newList(context, lib, null)),
                ]),
              ),
              if (lib.cur != 'all')
                TextButton(
                  onPressed: () { lib.lists.remove(lib.cur); lib.cur = 'all'; lib.save(); },
                  child: const Text('Excluir esta playlist'),
                ),
              Expanded(
                child: l.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('Nenhuma música aqui.\nToque em Adicionar e escolha seus arquivos de áudio.', textAlign: TextAlign.center),
                        ),
                      )
                    : ListView.builder(
                        itemCount: l.length,
                        itemBuilder: (_, i) {
                          final t = l[i];
                          return ListTile(
                            leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: artW(t, 46)),
                            title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(t.artist.isEmpty ? 'Artista desconhecido' : t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () async {
                              await lib.play(l, i);
                              if (context.mounted) openPlayer(context);
                            },
                            trailing: IconButton(icon: const Icon(Icons.more_horiz), onPressed: () => trackMenu(context, lib, t)),
                          );
                        },
                      ),
              ),
            ]),
            bottomNavigationBar: lib.queue.isEmpty
                ? null
                : StreamBuilder<int?>(
                    stream: player.currentIndexStream,
                    builder: (c, s) {
                      final i = s.data ?? 0;
                      final t = i < lib.queue.length ? lib.queue[i] : null;
                      return SafeArea(
                        child: ListTile(
                          onTap: () => openPlayer(context),
                          leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: artW(t, 40)),
                          title: Text(t?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: StreamBuilder<PlayerState>(
                            stream: player.playerStateStream,
                            builder: (c, s) {
                              final playing = s.data?.playing ?? false;
                              return IconButton(
                                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                                onPressed: () => playing ? player.pause() : player.play(),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
          );
        },
      );
}

class PlayerPage extends StatelessWidget {
  final Lib lib;
  const PlayerPage(this.lib, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.keyboard_arrow_down, size: 32), onPressed: () => Navigator.pop(context)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
          child: StreamBuilder<int?>(
            stream: player.currentIndexStream,
            builder: (c, s) {
              final i = s.data ?? 0;
              final t = i < lib.queue.length ? lib.queue[i] : null;
              return Column(children: [
                const Spacer(),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: AspectRatio(aspectRatio: 1, child: ClipRRect(borderRadius: BorderRadius.circular(16), child: artW(t, null))),
                ),
                const SizedBox(height: 28),
                Text(t?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                Text(t?.artist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 16),
                StreamBuilder<Duration>(
                  stream: player.positionStream,
                  builder: (c, s) {
                    final pos = s.data ?? Duration.zero;
                    final dur = player.duration ?? Duration.zero;
                    final mx = max(dur.inMilliseconds, 1).toDouble();
                    return Column(children: [
                      Slider(
                        value: min(pos.inMilliseconds.toDouble(), mx),
                        max: mx,
                        onChanged: (v) => player.seek(Duration(milliseconds: v.round())),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(fmt(pos)), Text(fmt(dur))]),
                      ),
                    ]);
                  },
                ),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(iconSize: 40, icon: const Icon(Icons.skip_previous), onPressed: player.seekToPrevious),
                  const SizedBox(width: 12),
                  StreamBuilder<PlayerState>(
                    stream: player.playerStateStream,
                    builder: (c, s) {
                      final playing = s.data?.playing ?? false;
                      return IconButton.filled(
                        iconSize: 40,
                        padding: const EdgeInsets.all(16),
                        icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                        onPressed: () => playing ? player.pause() : player.play(),
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  IconButton(iconSize: 40, icon: const Icon(Icons.skip_next), onPressed: player.seekToNext),
                ]),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  StreamBuilder<bool>(
                    stream: player.shuffleModeEnabledStream,
                    builder: (c, s) {
                      final on = s.data ?? false;
                      return IconButton(
                        tooltip: 'Aleatório',
                        icon: Icon(Icons.shuffle, color: on ? cs.primary : null),
                        onPressed: () => player.setShuffleModeEnabled(!on),
                      );
                    },
                  ),
                  StreamBuilder<LoopMode>(
                    stream: player.loopModeStream,
                    builder: (c, s) {
                      final m = s.data ?? LoopMode.off;
                      return IconButton(
                        tooltip: 'Repetir',
                        icon: Icon(m == LoopMode.one ? Icons.repeat_one : Icons.repeat, color: m == LoopMode.off ? null : cs.primary),
                        onPressed: () => player.setLoopMode(LoopMode.values[(m.index + 1) % 3]),
                      );
                    },
                  ),
                  IconButton(tooltip: 'Playlist', icon: const Icon(Icons.playlist_add), onPressed: () => trackMenu(context, lib, t)),
                ]),
                const Spacer(),
              ]);
            },
          ),
        ),
      ),
    );
  }
}
