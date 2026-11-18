import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

const libraryChannel = MethodChannel('mimusica/library');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.mimusica.music_player_local.audio',
    androidNotificationChannelName: 'Reproducción de música',
    androidNotificationOngoing: true,
  );
  runApp(const MusicApp());
}

class Song {
  final String id, uri, title, artist, album;
  final int albumId, duration;
  const Song({required this.id, required this.uri, required this.title,
    required this.artist, required this.album, required this.albumId, required this.duration});
  factory Song.fromMap(Map<dynamic, dynamic> map) => Song(
    id: '${map['id']}', uri: '${map['uri']}', title: '${map['title']}',
    artist: '${map['artist']}', album: '${map['album']}',
    albumId: (map['albumId'] as num).toInt(), duration: (map['duration'] as num).toInt(),
  );
}

class MusicApp extends StatelessWidget {
  const MusicApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false, title: 'Mi Música',
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xFF35D49A), scaffoldBackgroundColor: const Color(0xFF101114)),
    home: const MusicHome(),
  );
}

class MusicHome extends StatefulWidget {
  const MusicHome({super.key});
  @override
  State<MusicHome> createState() => _MusicHomeState();
}

class _MusicHomeState extends State<MusicHome> with WidgetsBindingObserver {
  final AudioPlayer player = AudioPlayer();
  final TextEditingController search = TextEditingController();
  final Random rng = Random();
  final Map<int, Future<Uint8List?>> covers = {};
  List<Song> songs = [];
  List<Song> queue = [];
  Map<String, List<String>> playlists = {};
  String? selectedPlaylist;
  bool scanning = false, permissionDenied = false, shuffle = false;
  double volume = .8;
  LoopMode repeat = LoopMode.off;
  Duration position = Duration.zero, duration = Duration.zero;
  bool playing = false;
  String? currentId;
  final List<StreamSubscription<dynamic>> subscriptions = [];

  Song? get current {
    for (final song in queue) { if (song.id == currentId) return song; }
    return null;
  }

  List<Song> get visible {
    final ids = selectedPlaylist == null ? null : playlists[selectedPlaylist]?.toSet();
    final query = search.text.trim().toLowerCase();
    return songs.where((s) => (ids == null || ids.contains(s.id)) &&
      '${s.title} ${s.artist} ${s.album}'.toLowerCase().contains(query)).toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    search.addListener(_refresh);
    subscriptions.add(player.positionStream.listen((value) {
      if (mounted) setState(() => position = value);
    }));
    subscriptions.add(player.durationStream.listen((value) {
      if (mounted) setState(() => duration = value ?? Duration.zero);
    }));
    subscriptions.add(player.playerStateStream.listen((value) {
      if (mounted) setState(() => playing = value.playing);
    }));
    subscriptions.add(player.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < queue.length && mounted) {
        setState(() => currentId = queue[index].id);
      }
    }));
    _initialize();
  }

  void _refresh() { if (mounted) setState(() {}); }

  Future<void> _initialize() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = jsonDecode(prefs.getString('playlists') ?? '{}') as Map<String, dynamic>;
      playlists = raw.map((k, v) => MapEntry(k, (v as List).map((e) => '$e').toList()));
    } catch (_) { playlists = {}; }
    volume = prefs.getDouble('volume') ?? .8;
    shuffle = prefs.getBool('shuffle') ?? false;
    repeat = LoopMode.values[(prefs.getInt('repeat') ?? 0).clamp(0, LoopMode.values.length - 1)];
    await player.setVolume(volume);
    await player.setLoopMode(repeat);
    await player.setShuffleModeEnabled(shuffle);
    await _scan();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('playlists', jsonEncode(playlists));
    await prefs.setDouble('volume', volume);
    await prefs.setBool('shuffle', shuffle);
    await prefs.setInt('repeat', repeat.index);
  }

  Future<void> _scan() async {
    if (scanning) return;
    setState(() { scanning = true; permissionDenied = false; });
    try {
      final allowed = await libraryChannel.invokeMethod<bool>('permission') ?? false;
      if (!allowed) {
        if (mounted) setState(() => permissionDenied = true);
        return;
      }
      final raw = await libraryChannel.invokeListMethod<dynamic>('songs') ?? [];
      final scanned = raw.map((e) => Song.fromMap(e as Map)).toList();
      if (mounted) setState(() { songs = scanned; covers.clear(); });
    } catch (e) { _message('No se pudo leer la biblioteca: $e'); }
    finally { if (mounted) setState(() => scanning = false); }
  }

  Future<Uint8List?> _coverBytes(int albumId) => covers.putIfAbsent(albumId, () async {
    if (albumId <= 0) return null;
    try { return await libraryChannel.invokeMethod<Uint8List>('art', {'albumId': albumId}); }
    catch (_) { return null; }
  });

  Widget _cover(Song song, {double size = 50}) => SizedBox(width: size, height: size,
    child: ClipRRect(borderRadius: BorderRadius.circular(10),
      child: FutureBuilder<Uint8List?>(future: _coverBytes(song.albumId), builder: (context, snapshot) {
        final data = snapshot.data;
        return data == null || data.isEmpty
          ? Container(color: const Color(0xFF30343A), child: const Icon(Icons.music_note, color: Color(0xFF35D49A)))
          : Image.memory(data, fit: BoxFit.cover, gaplessPlayback: true);
      })));

  Future<void> _play(Song selected) async {
    final list = visible.isNotEmpty && visible.any((s) => s.id == selected.id) ? visible : songs;
    final index = list.indexWhere((s) => s.id == selected.id);
    if (index < 0) return;
    try {
      await player.stop();
      queue = List.of(list);
      final source = ConcatenatingAudioSource(children: queue.map((s) => AudioSource.uri(
        Uri.parse(s.uri), tag: MediaItem(id: s.uri, title: s.title,
          artist: s.artist.isEmpty ? 'Artista desconocido' : s.artist,
          album: s.album, duration: Duration(milliseconds: s.duration),
          artUri: s.albumId > 0 ? Uri.parse('content://media/external/audio/albumart/${s.albumId}') : null,
        ))).toList());
      await player.setAudioSource(source, initialIndex: index);
      await player.setShuffleModeEnabled(shuffle);
      await player.setLoopMode(repeat);
      if (mounted) setState(() => currentId = selected.id);
      await player.play();
    } catch (e) { _message('Error al reproducir: $e'); }
  }

  Future<void> _toggle() async {
    if (current == null) { if (visible.isNotEmpty) await _play(visible.first); return; }
    if (player.playing) { await player.pause(); }
    else {
      if (player.processingState == ProcessingState.completed) await player.seek(Duration.zero);
      await player.play();
    }
  }

  Future<void> _next() async {
    if (player.hasNext) { await player.seekToNext(); }
    else if (queue.isNotEmpty) { await player.seek(Duration.zero, index: 0); }
    if (!player.playing) await player.play();
  }

  Future<void> _previous() async {
    if (position.inSeconds > 3) { await player.seek(Duration.zero); return; }
    if (player.hasPrevious) { await player.seekToPrevious(); }
    else if (queue.isNotEmpty) { await player.seek(Duration.zero, index: queue.length - 1); }
    if (!player.playing) await player.play();
  }

  Future<void> _toggleShuffle() async {
    shuffle = !shuffle;
    await player.setShuffleModeEnabled(shuffle);
    await _save(); _refresh();
  }

  Future<void> _toggleRepeat() async {
    repeat = repeat == LoopMode.off ? LoopMode.all : repeat == LoopMode.all ? LoopMode.one : LoopMode.off;
    await player.setLoopMode(repeat);
    await _save(); _refresh();
  }

  Future<void> _newPlaylist() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Nueva playlist'),
      content: TextField(controller: controller, autofocus: true, maxLength: 50,
        decoration: const InputDecoration(hintText: 'Nombre')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Crear'))],
    ));
    controller.dispose();
    if (name == null || name.isEmpty) return;
    if (playlists.containsKey(name)) { _message('Esa playlist ya existe'); return; }
    setState(() { playlists[name] = []; selectedPlaylist = name; });
    await _save();
  }

  Future<void> _addToPlaylist(Song song) async {
    if (playlists.isEmpty) { _message('Primero crea una playlist'); return; }
    final name = await showModalBottomSheet<String>(context: context,
      builder: (ctx) => SafeArea(child: ListView(shrinkWrap: true,
        children: playlists.keys.map((name) => ListTile(title: Text(name),
          onTap: () => Navigator.pop(ctx, name))).toList())));
    if (name == null) return;
    setState(() { if (!playlists[name]!.contains(song.id)) playlists[name]!.add(song.id); });
    await _save();
    _message('Agregada a $name');
  }

  Future<void> _removeFromPlaylist(Song song) async {
    final name = selectedPlaylist;
    if (name == null) return;
    setState(() => playlists[name]!.remove(song.id));
    await _save();
  }

  Future<void> _deletePlaylist() async {
    if (selectedPlaylist == null) return;
    setState(() { playlists.remove(selectedPlaylist); selectedPlaylist = null; });
    await _save();
  }

  void _message(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _clock(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _scan();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final s in subscriptions) { s.cancel(); }
    search.removeListener(_refresh);
    search.dispose();
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final song = current;
    return Scaffold(
      appBar: AppBar(title: const Text('🎵 Mi Música'), actions: [
        if (scanning) const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20,
          child: CircularProgressIndicator(strokeWidth: 2))),
        IconButton(tooltip: 'Actualizar biblioteca', onPressed: scanning ? null : _scan,
          icon: const Icon(Icons.refresh)),
      ]),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: TextField(
          controller: search, decoration: InputDecoration(prefixIcon: const Icon(Icons.search),
            hintText: 'Buscar música', border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))))),
        SizedBox(height: 50, child: ListView(scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            Padding(padding: const EdgeInsets.all(4), child: ChoiceChip(label: Text('Todas (${songs.length})'),
              selected: selectedPlaylist == null, onSelected: (_) => setState(() => selectedPlaylist = null))),
            ...playlists.keys.map((name) => Padding(padding: const EdgeInsets.all(4),
              child: ChoiceChip(label: Text(name), selected: selectedPlaylist == name,
                onSelected: (_) => setState(() => selectedPlaylist = name)))),
            IconButton(tooltip: 'Crear playlist', onPressed: _newPlaylist, icon: const Icon(Icons.playlist_add)),
            if (selectedPlaylist != null) IconButton(tooltip: 'Eliminar playlist',
              onPressed: _deletePlaylist, icon: const Icon(Icons.delete_outline)),
          ])),
        Expanded(child: visible.isEmpty ? Center(child: Padding(padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(permissionDenied ? 'Autoriza el acceso a música para detectar tus canciones' :
              scanning ? 'Buscando música...' : 'No se encontraron canciones musicales', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: _scan, icon: const Icon(Icons.refresh),
              label: const Text('Buscar música')),
          ]))) : ListView.builder(itemCount: visible.length, itemBuilder: (ctx, i) {
          final s = visible[i];
          return ListTile(leading: _cover(s), selected: currentId == s.id,
            title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(s.artist.isEmpty ? 'Artista desconocido' : s.artist,
              maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => _play(s),
            trailing: PopupMenuButton<String>(onSelected: (value) {
              if (value == 'add') { _addToPlaylist(s); }
              else { _removeFromPlaylist(s); }
            }, itemBuilder: (_) => [const PopupMenuItem(value: 'add', child: Text('Agregar a playlist')),
              if (selectedPlaylist != null) const PopupMenuItem(value: 'remove', child: Text('Quitar de playlist'))]),
          );
        })),
        Container(padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          decoration: const BoxDecoration(color: Color(0xFF202329),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (song != null) Row(children: [_cover(song, size: 46), const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60)),
              ]))]) else const Text('Selecciona una canción'),
            Slider(value: position.inMilliseconds.toDouble().clamp(0,
              max(1, duration.inMilliseconds).toDouble()).toDouble(),
              max: max(1, duration.inMilliseconds).toDouble(),
              onChanged: song == null ? null : (value) => player.seek(Duration(milliseconds: value.toInt()))),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(_clock(position)), Text(_clock(duration)),
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              IconButton(tooltip: 'Aleatorio', onPressed: _toggleShuffle,
                color: shuffle ? const Color(0xFF35D49A) : null, icon: const Icon(Icons.shuffle)),
              IconButton(tooltip: 'Anterior', onPressed: _previous, icon: const Icon(Icons.skip_previous), iconSize: 32),
              IconButton.filled(tooltip: playing ? 'Pausar' : 'Reproducir', onPressed: _toggle,
                icon: Icon(playing ? Icons.pause : Icons.play_arrow), iconSize: 32),
              IconButton(tooltip: 'Siguiente', onPressed: _next, icon: const Icon(Icons.skip_next), iconSize: 32),
              IconButton(tooltip: 'Repetir', onPressed: _toggleRepeat,
                color: repeat == LoopMode.off ? null : const Color(0xFF35D49A),
                icon: Icon(repeat == LoopMode.one ? Icons.repeat_one : Icons.repeat)),
            ]),
            Row(children: [const Icon(Icons.volume_down, size: 20),
              Expanded(child: Slider(value: volume, onChanged: (v) {
                setState(() => volume = v); player.setVolume(v);
              }, onChangeEnd: (_) => _save())), const Icon(Icons.volume_up, size: 20)]),
          ])),
      ])),
    );
  }
}
