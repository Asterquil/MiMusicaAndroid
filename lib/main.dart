import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MusicApp());

class Song {
  final String id, path, title, artist, album;
  const Song({required this.id, required this.path, required this.title, required this.artist, required this.album});
  Map<String, dynamic> toJson() => {'id': id, 'path': path, 'title': title, 'artist': artist, 'album': album};
  factory Song.fromJson(Map<String, dynamic> m) => Song(id: m['id'] as String, path: m['path'] as String, title: m['title'] as String, artist: m['artist'] as String, album: m['album'] as String);
}

class MusicApp extends StatelessWidget {
  const MusicApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mi Música', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark, colorSchemeSeed: const Color(0xFF32D583), scaffoldBackgroundColor: const Color(0xFF101114)),
    home: const MusicHome(),
  );
}

class MusicHome extends StatefulWidget {
  const MusicHome({super.key});
  @override
  State<MusicHome> createState() => _MusicHomeState();
}

class _MusicHomeState extends State<MusicHome> {
  final AudioPlayer player = AudioPlayer();
  final TextEditingController search = TextEditingController();
  List<Song> songs = [];
  Map<String, List<String>> playlists = {};
  String? selectedPlaylist;
  String? currentId;
  bool shuffle = false, loading = false;
  LoopMode loopMode = LoopMode.off;
  double volume = 0.8;
  Duration position = Duration.zero, duration = Duration.zero;
  bool playing = false;
  final Random random = Random();
  final List<String> history = [];
  int historyCursor = -1;

  Song? get current {
    for (final s in songs) { if (s.id == currentId) return s; }
    return null;
  }

  List<Song> get visibleSongs {
    final ids = selectedPlaylist == null ? null : playlists[selectedPlaylist]?.toSet();
    final q = search.text.trim().toLowerCase();
    return songs.where((s) => (ids == null || ids.contains(s.id)) && ('${s.title} ${s.artist} ${s.album}'.toLowerCase().contains(q))).toList();
  }

  @override
  void initState() {
    super.initState();
    _restore();
    player.positionStream.listen((p) { if (mounted) setState(() => position = p); });
    player.durationStream.listen((d) { if (mounted) setState(() => duration = d ?? Duration.zero); });
    player.playerStateStream.listen((s) { if (mounted) setState(() => playing = s.playing); });
    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && mounted) _onCompleted();
    });
    player.setVolume(volume);
    search.addListener(_refresh);
  }

  void _refresh() { if (mounted) setState(() {}); }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final saved = (jsonDecode(prefs.getString('songs') ?? '[]') as List).cast<Map<String, dynamic>>();
      final restored = saved.map(Song.fromJson).where((s) => File(s.path).existsSync()).toList();
      final raw = (jsonDecode(prefs.getString('playlists') ?? '{}') as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        songs = restored;
        playlists = raw.map((k, v) => MapEntry(k, (v as List).cast<String>().where((id) => restored.any((s) => s.id == id)).toList()));
        volume = prefs.getDouble('volume') ?? 0.8;
        shuffle = prefs.getBool('shuffle') ?? false;
        loopMode = LoopMode.values[(prefs.getInt('loop') ?? 0).clamp(0, LoopMode.values.length - 1)];
      });
      await player.setVolume(volume);
    } catch (e) { _message('No se pudo restaurar la biblioteca: $e'); }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('songs', jsonEncode(songs.map((s) => s.toJson()).toList()));
    await prefs.setString('playlists', jsonEncode(playlists));
    await prefs.setDouble('volume', volume);
    await prefs.setBool('shuffle', shuffle);
    await prefs.setInt('loop', loopMode.index);
  }

  void _message(String msg) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg))); }

  Future<void> _import() async {
    if (loading) return;
    setState(() => loading = true);
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['mp3', 'wav', 'ogg', 'm4a', 'flac'], allowMultiple: true, withData: false);
      if (result == null) return;
      final root = await getApplicationDocumentsDirectory();
      final dir = Directory('${root.path}/audio');
      await dir.create(recursive: true);
      var added = 0;
      for (final file in result.files) {
        if (file.path == null) continue;
        final source = File(file.path!);
        if (!await source.exists()) continue;
        final id = '${DateTime.now().microsecondsSinceEpoch}_${random.nextInt(1 << 32)}';
        final ext = file.extension?.toLowerCase() ?? 'mp3';
        final target = await source.copy('${dir.path}/$id.$ext');
        String title = file.name.replaceFirst(RegExp(r'\.[^.]+$'), ''), artist = 'Artista desconocido', album = 'Álbum desconocido';
        try {
          final metadata = await MetadataRetriever.fromFile(target);
          if (metadata.trackName?.trim().isNotEmpty == true) title = metadata.trackName!.trim();
          if (metadata.trackArtistNames?.isNotEmpty == true) artist = metadata.trackArtistNames!.join(', ');
          if (metadata.albumName?.trim().isNotEmpty == true) album = metadata.albumName!.trim();
        } catch (_) { /* Un archivo sin etiquetas sigue siendo reproducible. */ }
        songs.add(Song(id: id, path: target.path, title: title, artist: artist, album: album));
        added++;
      }
      if (mounted) setState(() {});
      await _save();
      _message('$added canciones importadas');
    } catch (e) { _message('Error al importar: $e'); }
    finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> _play(Song song, {bool recordHistory = true}) async {
    try {
      if (recordHistory) {
        if (historyCursor < history.length - 1) history.removeRange(historyCursor + 1, history.length);
        history.add(song.id);
        historyCursor = history.length - 1;
      }
      setState(() { currentId = song.id; position = Duration.zero; duration = Duration.zero; });
      await player.stop();
      await player.setFilePath(song.path);
      await player.play();
    } catch (e) { _message('No se pudo reproducir ${song.title}: $e'); }
  }

  Future<void> _togglePlay() async {
    if (current == null) { if (visibleSongs.isNotEmpty) await _play(visibleSongs.first); return; }
    try {
      if (player.processingState == ProcessingState.completed) await player.seek(Duration.zero);
      if (player.playing) { await player.pause(); } else { await player.play(); }
    } catch (e) { _message('Error de reproducción: $e'); }
  }

  List<Song> get _queue {
    final ids = selectedPlaylist == null ? null : playlists[selectedPlaylist]?.toSet();
    final queue = songs.where((s) => ids == null || ids.contains(s.id)).toList();
    if (current != null && !queue.any((s) => s.id == currentId)) return songs;
    return queue;
  }

  Future<void> _next({bool automatic = false}) async {
    if (automatic && loopMode == LoopMode.one && current != null) {
      await player.seek(Duration.zero); await player.play(); return;
    }
    final queue = _queue;
    if (queue.isEmpty) return;
    final i = queue.indexWhere((s) => s.id == currentId);
    if (automatic && !shuffle && i == queue.length - 1 && loopMode == LoopMode.off) {
      await player.stop(); await player.seek(Duration.zero); return;
    }
    Song next;
    if (shuffle && queue.length > 1) {
      final choices = queue.where((s) => s.id != currentId).toList();
      next = choices[random.nextInt(choices.length)];
    } else { next = queue[(i + 1) % queue.length]; }
    await _play(next);
  }

  Future<void> _previous() async {
    if (position.inSeconds > 3) { await player.seek(Duration.zero); return; }
    if (historyCursor > 0) {
      historyCursor--;
      final id = history[historyCursor];
      final matches = songs.where((s) => s.id == id);
      if (matches.isNotEmpty) { await _play(matches.first, recordHistory: false); return; }
    }
    final queue = _queue;
    if (queue.isEmpty) return;
    final i = queue.indexWhere((s) => s.id == currentId);
    await _play(queue[(i <= 0 ? queue.length : i) - 1]);
  }

  Future<void> _onCompleted() async {
    // El motor permanece en estado completed hasta cargar otra pista.
    await _next(automatic: true);
  }

  Future<void> _createPlaylist() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Nueva lista de reproducción'),
      content: TextField(controller: controller, autofocus: true, maxLength: 50, decoration: const InputDecoration(hintText: 'Nombre de la lista')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Crear'))],
    ));
    controller.dispose();
    if (name == null || name.isEmpty) return;
    if (playlists.containsKey(name)) { _message('Ya existe una lista con ese nombre'); return; }
    setState(() { playlists[name] = []; selectedPlaylist = name; });
    await _save();
  }

  Future<void> _addToPlaylist(Song song) async {
    if (playlists.isEmpty) { _message('Crea una lista primero'); return; }
    final name = await showModalBottomSheet<String>(context: context, builder: (ctx) => SafeArea(child: ListView(
      shrinkWrap: true, children: playlists.keys.map((n) => ListTile(title: Text(n), onTap: () => Navigator.pop(ctx, n))).toList(),
    )));
    if (name == null) return;
    setState(() { if (!playlists[name]!.contains(song.id)) playlists[name]!.add(song.id); });
    await _save();
    _message('Añadida a $name');
  }

  Future<void> _removeFromPlaylist(Song song) async {
    final name = selectedPlaylist;
    if (name == null) return;
    setState(() => playlists[name]!.remove(song.id));
    await _save();
  }

  Future<void> _deletePlaylist() async {
    final name = selectedPlaylist;
    if (name == null) return;
    setState(() { playlists.remove(name); selectedPlaylist = null; });
    await _save();
  }

  String _time(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Widget _cover(Song song, {double size = 52}) => FutureBuilder<Metadata?>(
    future: _metadata(song.path),
    builder: (ctx, snapshot) {
      final bytes = snapshot.data?.albumArt;
      return ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: size, height: size,
        child: bytes != null && bytes.isNotEmpty
          ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
          : Container(color: const Color(0xFF30363B), child: const Icon(Icons.music_note, color: Color(0xFF32D583)))));
    },
  );

  final Map<String, Future<Metadata?>> _artCache = {};
  Future<Metadata?> _metadata(String path) => _artCache.putIfAbsent(path, () async {
    try { return await MetadataRetriever.fromFile(File(path)); } catch (_) { return null; }
  });

  @override
  Widget build(BuildContext context) {
    final song = current;
    return Scaffold(
      appBar: AppBar(title: const Text('🎵 Mi Música'), actions: [
        if (loading) const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
        IconButton(tooltip: 'Importar canciones', onPressed: loading ? null : _import, icon: const Icon(Icons.library_music)),
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: _import, icon: const Icon(Icons.add), label: const Text('Importar')),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: TextField(controller: search,
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Buscar canción, artista o álbum', border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))))),
        SizedBox(height: 52, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          Padding(padding: const EdgeInsets.all(4), child: ChoiceChip(label: const Text('Todas'), selected: selectedPlaylist == null, onSelected: (_) => setState(() => selectedPlaylist = null))),
          ...playlists.keys.map((name) => Padding(padding: const EdgeInsets.all(4), child: ChoiceChip(label: Text(name), selected: selectedPlaylist == name, onSelected: (_) => setState(() => selectedPlaylist = name)))),
          IconButton(tooltip: 'Crear lista', onPressed: _createPlaylist, icon: const Icon(Icons.playlist_add)),
          if (selectedPlaylist != null) IconButton(tooltip: 'Eliminar lista', onPressed: _deletePlaylist, icon: const Icon(Icons.delete_outline)),
        ])),
        Expanded(child: visibleSongs.isEmpty
          ? Center(child: Text(songs.isEmpty ? 'Importa canciones para comenzar' : 'No hay canciones en esta vista', style: const TextStyle(color: Colors.white60)))
          : ListView.builder(itemCount: visibleSongs.length, itemBuilder: (ctx, i) {
              final s = visibleSongs[i];
              return ListTile(leading: _cover(s), selected: currentId == s.id,
                title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${s.artist} · ${s.album}', maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => _play(s),
                trailing: PopupMenuButton<String>(onSelected: (action) => action == 'add' ? _addToPlaylist(s) : _removeFromPlaylist(s),
                  itemBuilder: (_) => [const PopupMenuItem(value: 'add', child: Text('Añadir a lista')),
                    if (selectedPlaylist != null) const PopupMenuItem(value: 'remove', child: Text('Quitar de esta lista'))]),
              );
            })),
        Container(padding: const EdgeInsets.fromLTRB(14, 10, 14, 12), decoration: const BoxDecoration(color: Color(0xFF202329), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (song != null) Row(children: [_cover(song, size: 46), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60)),
            ]))]) else const Text('Selecciona una canción'),
            Slider(value: position.inMilliseconds.clamp(0, max(duration.inMilliseconds, 1)).toDouble(), max: max(duration.inMilliseconds, 1).toDouble(),
              onChanged: song == null || duration == Duration.zero ? null : (v) => player.seek(Duration(milliseconds: v.round()))),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(_time(position)), Text(_time(duration))]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              IconButton(tooltip: 'Aleatorio', color: shuffle ? const Color(0xFF32D583) : null, onPressed: () { setState(() => shuffle = !shuffle); _save(); }, icon: const Icon(Icons.shuffle)),
              IconButton(tooltip: 'Anterior', onPressed: _previous, icon: const Icon(Icons.skip_previous), iconSize: 34),
              IconButton.filled(tooltip: playing ? 'Pausar' : 'Reproducir', onPressed: _togglePlay, icon: Icon(playing ? Icons.pause : Icons.play_arrow), iconSize: 36),
              IconButton(tooltip: 'Siguiente', onPressed: _next, icon: const Icon(Icons.skip_next), iconSize: 34),
              IconButton(tooltip: 'Repetir', color: loopMode != LoopMode.off ? const Color(0xFF32D583) : null,
                onPressed: () { setState(() => loopMode = LoopMode.values[(loopMode.index + 1) % LoopMode.values.length]); _save(); },
                icon: Icon(loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat)),
            ]),
            Row(children: [const Icon(Icons.volume_down), Expanded(child: Slider(value: volume, onChanged: (v) { setState(() => volume = v); player.setVolume(v); }, onChangeEnd: (_) => _save())), const Icon(Icons.volume_up)]),
          ])),
      ])),
    );
  }

  @override
  void dispose() {
    search.removeListener(_refresh);
    search.dispose();
    player.dispose();
    super.dispose();
  }
}
