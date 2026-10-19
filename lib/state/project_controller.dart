import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import '../models/audio_formats.dart';
import '../models/clip.dart';
import '../models/library_folder.dart';
import '../models/library_item.dart';
import '../models/timeline_track.dart';
import '../services/audio_analyzer.dart';
import '../services/audio_engine.dart';
import '../services/smart_join.dart';
import '../services/cover_service.dart';
import '../services/ffmpeg_runner.dart';
import '../services/live_engine.dart';
import '../services/preview_service.dart';
import '../services/storage_service.dart';

class ProjectController extends ChangeNotifier {
  static const int minClipMs = 100;
  static const int maxTracks = 6;
  static const List<String> importExtensions = [
    'mp3',
    'wav',
    'flac',
    'm4a',
    'aac',
    'ogg',
    'opus',
    'wma',
    'mp4',
    'mkv',
    'mov',
    'webm',
    'avi',
    '3gp',
  ];

  final List<LibraryItem> library = [];
  final List<LibraryFolder> folders = [];
  String activeFolderId = '';
  final List<TimelineTrack> tracks = [];
  final Map<String, List<double>> peaks = {};
  late final LiveEngine engine = LiveEngine(
    playhead: playhead,
    tracks: tracks,
    onStateChanged: onEngineState,
  );
  final List<List<TimelineTrack>> undoStack = [];
  final List<List<TimelineTrack>> redoStack = [];

  String? selectedId;
  final Set<String> selectedIds = <String>{};
  int activeTrack = 0;
  final ValueNotifier<int> playhead = ValueNotifier<int>(0);
  double pxPerSecond = 60;
  bool playing = false;
  bool get rendering => false;
  bool smartBusy = false;
  String smartStatus = '';
  bool exporting = false;
  String lastError = '';
  int idCounter = 0;
  Timer? saveTimer;

  int get playheadMs => playhead.value;
  set playheadMs(int value) => playhead.value = value;

  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;

  int get projectEndMs {
    var end = 0;
    for (final t in tracks) {
      for (final c in t.clips) {
        if (c.endMs > end) end = c.endMs;
      }
    }
    return end;
  }

  Set<String> get selection => Set.unmodifiable(selectedIds);

  List<AudioClip> get selectedClips {
    if (selectedIds.isEmpty) {
      final clip = selectedClip;
      return clip == null ? <AudioClip>[] : <AudioClip>[clip];
    }
    return [
      for (final track in tracks)
        for (final clip in track.clips)
          if (selectedIds.contains(clip.id)) clip,
    ];
  }

  AudioClip? get selectedClip {
    for (final t in tracks) {
      for (final c in t.clips) {
        if (c.id == selectedId) return c;
      }
    }
    return null;
  }

  String newId() => '${DateTime.now().microsecondsSinceEpoch}_${idCounter++}';

  ({int track, int index})? findClip(String id) {
    for (var ti = 0; ti < tracks.length; ti++) {
      final clips = tracks[ti].clips;
      for (var ci = 0; ci < clips.length; ci++) {
        if (clips[ci].id == id) return (track: ti, index: ci);
      }
    }
    return null;
  }

  Future<void> init() async {
    await loadLibrary();
    await loadFolders();
    await loadProject();
    engine.sync();
  }

  void onEngineState() {
    playing = engine.playing;
    notifyListeners();
  }

  Future<void> loadLibrary() async {
    final file = await StorageService.libraryFile();
    if (!await file.exists()) return;
    try {
      final data = jsonDecode(await file.readAsString()) as List;
      library
        ..clear()
        ..addAll(data
            .cast<Map<String, dynamic>>()
            .map(LibraryItem.fromJson)
            .where((i) => File(i.path).existsSync()));
    } catch (_) {}
    notifyListeners();
  }

  Future<void> saveLibrary() async {
    final file = await StorageService.libraryFile();
    await file
        .writeAsString(jsonEncode(library.map((i) => i.toJson()).toList()));
  }

  Future<void> loadProject() async {
    final file = await StorageService.projectFile();
    if (await file.exists()) {
      try {
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final list = (data['tracks'] as List).cast<Map<String, dynamic>>();
        tracks
          ..clear()
          ..addAll(list.map(TimelineTrack.fromJson));
        for (final t in tracks) {
          t.clips.removeWhere((c) => !File(c.path).existsSync());
        }
      } catch (_) {
        tracks.clear();
      }
    }
    if (tracks.isEmpty) {
      tracks.add(TimelineTrack(id: newId(), name: 'Faixa 1'));
    }
    for (final t in tracks) {
      for (final c in t.clips) {
        loadPeaks(c.path);
      }
    }
    notifyListeners();
  }

  void scheduleSave() {
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 800), saveProject);
  }

  Future<void> saveProject() async {
    final file = await StorageService.projectFile();
    await file.writeAsString(
        jsonEncode({'tracks': tracks.map((t) => t.toJson()).toList()}));
  }

  Future<void> loadFolders() async {
    final file = await StorageService.foldersFile();
    if (!await file.exists()) return;
    try {
      final data = jsonDecode(await file.readAsString()) as List;
      folders
        ..clear()
        ..addAll(data.cast<Map<String, dynamic>>().map(LibraryFolder.fromJson));
    } catch (_) {}
    notifyListeners();
  }

  Future<void> saveFolders() async {
    final file = await StorageService.foldersFile();
    await file
        .writeAsString(jsonEncode(folders.map((f) => f.toJson()).toList()));
  }

  Future<String?> createFolder(String name, {bool activate = true}) async {
    final clean = name.trim();
    if (clean.isEmpty) return null;
    final folder = LibraryFolder(id: newId(), name: clean);
    folders.add(folder);
    if (activate) activeFolderId = folder.id;
    await saveFolders();
    notifyListeners();
    return folder.id;
  }

  Future<void> renameFolder(String id, String name) async {
    final clean = name.trim();
    final index = folders.indexWhere((f) => f.id == id);
    if (clean.isEmpty || index < 0) return;
    folders[index] = folders[index].copyWith(name: clean);
    await saveFolders();
    notifyListeners();
  }

  Future<void> deleteFolder(String id) async {
    folders.removeWhere((f) => f.id == id);
    for (var i = 0; i < library.length; i++) {
      if (library[i].folderId == id) {
        library[i] = library[i].copyWith(folderId: '');
      }
    }
    if (activeFolderId == id) activeFolderId = '';
    await saveFolders();
    await saveLibrary();
    notifyListeners();
  }

  Future<void> moveItem(String itemId, String folderId) async {
    final index = library.indexWhere((i) => i.id == itemId);
    if (index < 0) return;
    library[index] = library[index].copyWith(folderId: folderId);
    await saveLibrary();
    notifyListeners();
  }

  Future<void> moveItems(Iterable<String> itemIds, String folderId) async {
    final ids = itemIds.toSet();
    for (var i = 0; i < library.length; i++) {
      if (ids.contains(library[i].id)) {
        library[i] = library[i].copyWith(folderId: folderId);
      }
    }
    await saveLibrary();
    notifyListeners();
  }

  void setActiveFolder(String id) {
    activeFolderId = id;
    notifyListeners();
  }

  Future<LibraryItem> addToLibrary({
    required String title,
    required String artist,
    required String path,
    String coverPath = '',
    String? folderId,
  }) async {
    var cover = coverPath;
    if (cover.isEmpty) {
      cover = await CoverService.extractEmbedded(path) ?? '';
    }
    var ms = await FfmpegRunner.probeDurationMs(path);
    if (ms <= 0) {
      final tmp = AudioPlayer();
      try {
        final d = await tmp.setFilePath(path);
        ms = d?.inMilliseconds ?? 0;
      } catch (_) {}
      await tmp.dispose();
    }
    library.removeWhere((i) => i.path == path);
    final item = LibraryItem(
      id: newId(),
      title: title,
      artist: artist,
      path: path,
      durationMs: ms,
      coverPath: cover,
      folderId: folderId ?? activeFolderId,
    );
    library.insert(0, item);
    await saveLibrary();
    notifyListeners();
    return item;
  }

  Future<void> toggleFavorite(String id) async {
    final i = library.indexWhere((x) => x.id == id);
    if (i < 0) return;
    library[i] = library[i].copyWith(favorite: !library[i].favorite);
    await saveLibrary();
    notifyListeners();
  }

  Future<void> updateItemInfo(String id, String title, String artist) async {
    final i = library.indexWhere((x) => x.id == id);
    if (i < 0) return;
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) return;
    library[i] = library[i].copyWith(title: cleanTitle, artist: artist.trim());
    await saveLibrary();
    notifyListeners();
  }

  Future<int> importFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: importExtensions,
      allowMultiple: true,
    );
    if (result == null) return 0;
    final folder = await StorageService.musicDir();
    var count = 0;
    for (final f in result.files) {
      final src = f.path;
      if (src == null) continue;
      final dest = p.join(folder.path,
          '${DateTime.now().millisecondsSinceEpoch}_${p.basename(src)}');
      await File(src).copy(dest);
      await addToLibrary(
          title: p.basenameWithoutExtension(src), artist: 'Local', path: dest);
      count++;
    }
    return count;
  }

  Future<void> removeFromLibrary(LibraryItem item) async {
    pushHistory();
    library.removeWhere((i) => i.id == item.id);
    for (final t in tracks) {
      t.clips.removeWhere((c) => c.path == item.path);
    }
    peaks.remove(item.path);
    try {
      await File(item.path).delete();
    } catch (_) {}
    final cover = item.coverPath;
    if (cover.isNotEmpty && !library.any((i) => i.coverPath == cover)) {
      try {
        await File(cover).delete();
      } catch (_) {}
    }
    await saveLibrary();
    afterEdit();
  }

  Future<void> loadPeaks(String path) async {
    if (peaks.containsKey(path)) return;
    peaks[path] = const [];
    peaks[path] = await AudioEngine.computePeaks(path);
    notifyListeners();
  }

  List<TimelineTrack> snapshot() => tracks.map((t) => t.copy()).toList();

  void pushHistory() {
    undoStack.add(snapshot());
    if (undoStack.length > 60) undoStack.removeAt(0);
    redoStack.clear();
  }

  void beginEdit() => pushHistory();

  void restore(List<TimelineTrack> state) {
    tracks
      ..clear()
      ..addAll(state);
    activeTrack = activeTrack.clamp(0, tracks.length - 1).toInt();
    selectedIds.removeWhere((id) => findClip(id) == null);
    if (selectedId != null && findClip(selectedId!) == null) {
      selectedId = selectedIds.isEmpty ? null : selectedIds.last;
    }
    afterEdit();
  }

  void undo() {
    if (undoStack.isEmpty) return;
    redoStack.add(snapshot());
    restore(undoStack.removeLast());
  }

  void redo() {
    if (redoStack.isEmpty) return;
    undoStack.add(snapshot());
    restore(redoStack.removeLast());
  }

  void afterEdit() {
    final end = projectEndMs;
    if (!engine.playing && playheadMs > end) playheadMs = end;
    engine.sync();
    scheduleSave();
    notifyListeners();
  }

  void select(String id, {bool toggle = false, bool additive = false}) {
    if (toggle) {
      if (selectedIds.contains(id)) {
        selectedIds.remove(id);
        if (selectedId == id) {
          selectedId = selectedIds.isEmpty ? null : selectedIds.last;
        }
      } else {
        selectedIds.add(id);
        selectedId = id;
      }
    } else if (additive) {
      selectedIds.add(id);
      selectedId = id;
    } else {
      selectedIds
        ..clear()
        ..add(id);
      selectedId = id;
    }
    notifyListeners();
  }

  void selectAllClips() {
    selectedIds
      ..clear()
      ..addAll(tracks.expand((t) => t.clips.map((c) => c.id)));
    selectedId = selectedIds.isEmpty ? null : selectedIds.last;
    notifyListeners();
  }

  void clearSelection() {
    selectedId = null;
    selectedIds.clear();
    notifyListeners();
  }

  void finishInteractiveEdit() {
    engine.sync();
    scheduleSave();
    notifyListeners();
  }

  // Atualiza apenas o modelo durante o arraste. Sincronização do motor e
  // persistência são adiadas até o gesto terminar para evitar trabalho por frame.
  void previewMoveClip(String id, int startMs, int trackIndex, int snapMs) {
    final loc = findClip(id);
    if (loc == null) return;
    final clip = tracks[loc.track].clips[loc.index];
    var start = max(0, startMs);
    final targets = <int>[0, playheadMs];
    for (final t in tracks) {
      for (final other in t.clips) {
        if (other.id == id) continue;
        targets
          ..add(other.startMs)
          ..add(other.endMs);
      }
    }
    var bestDiff = snapMs + 1;
    var bestStart = start;
    for (final target in targets) {
      final ds = (start - target).abs();
      if (ds < bestDiff) {
        bestDiff = ds;
        bestStart = target;
      }
      final de = (start + clip.durationMs - target).abs();
      if (de < bestDiff) {
        bestDiff = de;
        bestStart = target - clip.durationMs;
      }
    }
    if (bestDiff <= snapMs) start = max(0, bestStart);
    final ti = trackIndex.clamp(0, tracks.length - 1).toInt();
    final next = clip.copyWith(startMs: start);
    if (!isValid(ti, next)) return;
    if (ti == loc.track) {
      tracks[ti].clips[loc.index] = next;
    } else {
      tracks[loc.track].clips.removeAt(loc.index);
      tracks[ti].clips.add(next);
    }
    activeTrack = ti;
    notifyListeners();
  }

  void previewTrimLeft(String id, int deltaMs) {
    final loc = findClip(id);
    if (loc == null || deltaMs == 0) return;
    final clip = tracks[loc.track].clips[loc.index];
    final src = (deltaMs * clip.speed).round();
    final next = clip.reversed
        ? clip.copyWith(
            outMs: clip.outMs - src, startMs: clip.startMs + deltaMs)
        : clip.copyWith(inMs: clip.inMs + src, startMs: clip.startMs + deltaMs);
    if (isValid(loc.track, next)) {
      tracks[loc.track].clips[loc.index] = next;
      notifyListeners();
    }
  }

  void previewTrimRight(String id, int deltaMs) {
    final loc = findClip(id);
    if (loc == null || deltaMs == 0) return;
    final clip = tracks[loc.track].clips[loc.index];
    final src = (deltaMs * clip.speed).round();
    final next = clip.reversed
        ? clip.copyWith(inMs: clip.inMs - src)
        : clip.copyWith(outMs: clip.outMs + src);
    if (isValid(loc.track, next)) {
      tracks[loc.track].clips[loc.index] = next;
      notifyListeners();
    }
  }

  void setActiveTrack(int index) {
    activeTrack = index.clamp(0, tracks.length - 1).toInt();
    notifyListeners();
  }

  void addTrack() {
    if (tracks.length >= maxTracks) return;
    pushHistory();
    tracks.add(TimelineTrack(id: newId(), name: 'Faixa ${tracks.length + 1}'));
    activeTrack = tracks.length - 1;
    afterEdit();
  }

  void removeActiveTrack() {
    if (tracks.length <= 1) return;
    pushHistory();
    tracks.removeAt(activeTrack);
    activeTrack = activeTrack.clamp(0, tracks.length - 1).toInt();
    selectedIds.removeWhere((id) => findClip(id) == null);
    if (selectedId != null && findClip(selectedId!) == null) {
      selectedId = selectedIds.isEmpty ? null : selectedIds.last;
    }
    afterEdit();
  }

  void toggleTrackMute(int index) {
    pushHistory();
    tracks[index].muted = !tracks[index].muted;
    afterEdit();
  }

  void setTrackVolume(int index, double value) {
    tracks[index].volume = value;
    afterEdit();
  }

  void renameTrack(int index, String name) {
    if (name.isEmpty || index < 0 || index >= tracks.length) return;
    pushHistory();
    tracks[index].name = name;
    afterEdit();
  }

  bool isValid(int trackIndex, AudioClip clip) {
    if (trackIndex < 0 || trackIndex >= tracks.length) return false;
    if (clip.startMs < 0 || clip.inMs < 0 || clip.outMs > clip.sourceMs)
      return false;
    if (clip.lengthMs < minClipMs) return false;
    for (final o in tracks[trackIndex].clips) {
      if (o.id == clip.id) continue;
      if (clip.startMs < o.endMs - 1 && clip.endMs > o.startMs + 1)
        return false;
    }
    return true;
  }

  bool replaceClip(String id, AudioClip next, {int? toTrack}) {
    final loc = findClip(id);
    if (loc == null) return false;
    final target = toTrack ?? loc.track;
    if (!isValid(target, next)) return false;
    if (target == loc.track) {
      tracks[target].clips[loc.index] = next;
    } else {
      tracks[loc.track].clips.removeAt(loc.index);
      tracks[target].clips.add(next);
    }
    return true;
  }

  void addClip(LibraryItem item) {
    if (item.durationMs <= 0) return;
    pushHistory();
    final ti = activeTrack.clamp(0, tracks.length - 1).toInt();
    final start = tracks[ti].clips.fold<int>(0, (m, c) => max(m, c.endMs));
    final clip = AudioClip(
      id: newId(),
      label: item.title,
      path: item.path,
      sourceMs: item.durationMs,
      coverPath: item.coverPath,
      inMs: 0,
      outMs: item.durationMs,
      startMs: start,
    );
    tracks[ti].clips.add(clip);
    selectedId = clip.id;
    selectedIds
      ..clear()
      ..add(clip.id);
    loadPeaks(item.path);
    afterEdit();
  }

  void moveClip(String id, int startMs, int trackIndex, int snapMs) {
    final loc = findClip(id);
    if (loc == null) return;
    final clip = tracks[loc.track].clips[loc.index];
    var start = max(0, startMs);
    final targets = <int>[0, playheadMs];
    for (final t in tracks) {
      for (final o in t.clips) {
        if (o.id == id) continue;
        targets.add(o.startMs);
        targets.add(o.endMs);
      }
    }
    var bestDiff = snapMs + 1;
    var bestStart = start;
    for (final t in targets) {
      final dStart = (start - t).abs();
      if (dStart < bestDiff) {
        bestDiff = dStart;
        bestStart = t;
      }
      final dEnd = (start + clip.durationMs - t).abs();
      if (dEnd < bestDiff) {
        bestDiff = dEnd;
        bestStart = t - clip.durationMs;
      }
    }
    if (bestDiff <= snapMs) start = max(0, bestStart);
    final ti = trackIndex.clamp(0, tracks.length - 1).toInt();
    if (replaceClip(id, clip.copyWith(startMs: start), toTrack: ti)) {
      activeTrack = ti;
      afterEdit();
    }
  }

  void trimLeft(String id, int deltaMs) {
    final loc = findClip(id);
    if (loc == null) return;
    final c = tracks[loc.track].clips[loc.index];
    final src = (deltaMs * c.speed).round();
    final next = c.reversed
        ? c.copyWith(outMs: c.outMs - src, startMs: c.startMs + deltaMs)
        : c.copyWith(inMs: c.inMs + src, startMs: c.startMs + deltaMs);
    if (replaceClip(id, next)) afterEdit();
  }

  void trimRight(String id, int deltaMs) {
    final loc = findClip(id);
    if (loc == null) return;
    final c = tracks[loc.track].clips[loc.index];
    final src = (deltaMs * c.speed).round();
    final next = c.reversed
        ? c.copyWith(inMs: c.inMs - src)
        : c.copyWith(outMs: c.outMs + src);
    if (replaceClip(id, next)) afterEdit();
  }

  void updateClip(String id, AudioClip Function(AudioClip) change) {
    final loc = findClip(id);
    if (loc == null) return;
    final previous = tracks[loc.track].clips[loc.index];
    var next = change(previous);
    if (engine.playing &&
        next.speed != previous.speed &&
        playheadMs >= previous.startMs &&
        playheadMs < previous.endMs) {
      final consumed = (playheadMs - previous.startMs) * previous.speed;
      final newStart = max(0, (playheadMs - consumed / next.speed).round());
      final adjusted = next.copyWith(startMs: newStart);
      if (isValid(loc.track, adjusted)) next = adjusted;
    }
    if (replaceClip(id, next)) afterEdit();
  }

  int laneFor(AudioClip clip, int prefer, int avoid) {
    final order = <int>[prefer];
    for (var i = 0; i < tracks.length; i++) {
      if (i != prefer) order.add(i);
    }
    for (final i in order) {
      if (i == avoid || i >= tracks.length) continue;
      if (isValid(i, clip)) return i;
    }
    if (tracks.length < maxTracks) {
      tracks
          .add(TimelineTrack(id: newId(), name: 'Faixa ${tracks.length + 1}'));
      return tracks.length - 1;
    }
    return -1;
  }

  Future<List<AudioAnalysis?>> analyzeAll(List<AudioClip> clips) {
    return Future.wait(clips.map((c) async {
      try {
        return await AudioAnalyzer.analyze(c.path);
      } catch (_) {
        return null;
      }
    }));
  }

  Future<List<AudioClip>?> chainPlace(
    List<AudioClip> clips,
    List<AudioAnalysis?> analyses,
    SmartJoinOptions o,
    int prefer,
  ) async {
    var current = o.trimSilence
        ? SmartJoin.trimEdges(clips.first, analyses.first)
        : clips.first;
    var lane = laneFor(current, prefer, -1);
    if (lane < 0) return null;
    tracks[lane].clips.add(current);
    final placed = <AudioClip>[current];
    var overlapSum = 0;
    for (var i = 1; i < clips.length; i++) {
      var b = clips[i];
      if (o.trimSilence) b = SmartJoin.trimEdges(b, analyses[i]);
      final result =
          SmartJoin.join(current, analyses[i - 1], b, analyses[i], o);
      final li = tracks[lane].clips.indexWhere((x) => x.id == current.id);
      tracks[lane].clips[li] = result.first;
      placed[placed.length - 1] = result.first;
      final nextLane = laneFor(result.second, prefer, lane);
      if (nextLane < 0) return null;
      tracks[nextLane].clips.add(result.second);
      placed.add(result.second);
      overlapSum += result.overlapMs;
      current = result.second;
      lane = nextLane;
    }
    smartStatus = '${clips.length} trechos unidos, sobreposição média de '
        '${(overlapSum / max(1, clips.length - 1) / 1000).toStringAsFixed(1)} s';
    return placed;
  }

  Future<String> smartJoinTrack(int trackIndex, SmartJoinOptions o) async {
    if (smartBusy) return 'Já existe uma união em andamento.';
    if (trackIndex < 0 || trackIndex >= tracks.length) return 'Faixa inválida.';
    final source = [...tracks[trackIndex].clips]
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    if (source.length < 2) return 'A faixa precisa de pelo menos 2 trechos.';
    return runChain(source, o, trackIndex, null);
  }

  Future<String> smartJoinPair(String clipId, SmartJoinOptions o) async {
    if (smartBusy) return 'Já existe uma união em andamento.';
    final loc = findClip(clipId);
    if (loc == null) return 'Selecione um trecho.';
    final list = [...tracks[loc.track].clips]
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    final index = list.indexWhere((x) => x.id == clipId);
    if (index < 0 || index >= list.length - 1) {
      return 'Não há um trecho seguinte nesta faixa.';
    }
    return runChain(
        [list[index], list[index + 1]], o, loc.track, list.sublist(index + 2));
  }

  Future<String> runChain(
    List<AudioClip> clips,
    SmartJoinOptions o,
    int prefer,
    List<AudioClip>? trailing,
  ) async {
    smartBusy = true;
    smartStatus = 'Analisando áudio…';
    notifyListeners();
    try {
      final analyses = await analyzeAll(clips);
      var ordered = clips;
      var ordA = analyses;
      if (o.sortByBpm && clips.length > 2) {
        final idx = List<int>.generate(clips.length, (i) => i)
          ..sort((x, y) {
            final bx =
                analyses[x]?.reliable == true ? analyses[x]!.bpm : 9999.0;
            final by =
                analyses[y]?.reliable == true ? analyses[y]!.bpm : 9999.0;
            return bx.compareTo(by);
          });
        ordered = [for (final i in idx) clips[i]];
        ordA = [for (final i in idx) analyses[i]];
        final base = clips.first.startMs;
        ordered[0] = ordered[0].copyWith(startMs: base);
      }
      final before = snapshot();
      pushHistory();
      final ids = clips.map((c) => c.id).toSet();
      var oldEnd = 0;
      for (final c in clips) {
        oldEnd = max(oldEnd, c.endMs);
      }
      for (final t in tracks) {
        t.clips.removeWhere((x) => ids.contains(x.id));
      }
      final placed = await chainPlace(ordered, ordA, o, prefer);
      if (placed == null) {
        undoStack.removeLast();
        restore(before);
        return 'Não há faixas livres suficientes para a transição.';
      }
      if (trailing != null && trailing.isNotEmpty) {
        var newEnd = 0;
        for (final c in placed) {
          newEnd = max(newEnd, c.endMs);
        }
        final delta = newEnd - oldEnd;
        for (final t in trailing) {
          final moved = t.copyWith(startMs: max(0, t.startMs + delta));
          final loc = findClip(t.id);
          if (loc == null) continue;
          if (!replaceClip(t.id, moved)) {
            undoStack.removeLast();
            restore(before);
            return 'Os trechos seguintes não couberam depois da união.';
          }
        }
      }
      selectedId = placed.last.id;
      afterEdit();
      return smartStatus;
    } catch (e) {
      return 'Falha na união: $e';
    } finally {
      smartBusy = false;
      notifyListeners();
    }
  }

  Future<String> smartMix(List<LibraryItem> items, SmartJoinOptions o) async {
    if (smartBusy) return 'Já existe uma união em andamento.';
    final valid = items.where((i) => i.durationMs > 0).toList();
    if (valid.length < 2) return 'Selecione pelo menos 2 músicas.';
    final base = projectEndMs;
    final clips = <AudioClip>[
      for (final item in valid)
        AudioClip(
          id: newId(),
          label: item.title,
          path: item.path,
          coverPath: item.coverPath,
          sourceMs: item.durationMs,
          inMs: 0,
          outMs: item.durationMs,
          startMs: base,
        ),
    ];
    for (final item in valid) {
      loadPeaks(item.path);
    }
    return runChain(
        clips, o, activeTrack.clamp(0, tracks.length - 1).toInt(), null);
  }

  Future<bool> trimClipSilence(String clipId) async {
    final loc = findClip(clipId);
    if (loc == null) return false;
    final clip = tracks[loc.track].clips[loc.index];
    final analysis = await AudioAnalyzer.analyze(clip.path);
    if (analysis == null) return false;
    final trimmed = SmartJoin.trimEdges(clip, analysis);
    if (trimmed.inMs == clip.inMs && trimmed.outMs == clip.outMs) return false;
    pushHistory();
    if (!replaceClip(clipId, trimmed)) {
      undoStack.removeLast();
      return false;
    }
    afterEdit();
    return true;
  }

  void splitAtPlayhead() {
    bool inside(AudioClip c) =>
        playheadMs > c.startMs + minClipMs && playheadMs < c.endMs - minClipMs;
    final targets = <String>[];
    final selected = selectedClips;
    if (selected.isNotEmpty) {
      for (final clip in selected) {
        if (inside(clip)) targets.add(clip.id);
      }
    } else {
      for (final t in tracks) {
        for (final c in t.clips) {
          if (inside(c)) targets.add(c.id);
        }
      }
    }
    if (targets.isEmpty) return;
    pushHistory();
    String? lastRight;
    for (final id in targets) {
      final loc = findClip(id);
      if (loc == null) continue;
      final c = tracks[loc.track].clips[loc.index];
      final srcOffset = ((playheadMs - c.startMs) * c.speed).round();
      AudioClip first;
      AudioClip second;
      if (!c.reversed) {
        final cut = c.inMs + srcOffset;
        first = c.copyWith(outMs: cut, fadeOutMs: 0);
        second = c.copyWith(
            id: newId(), inMs: cut, startMs: playheadMs, fadeInMs: 0);
      } else {
        final cut = c.outMs - srcOffset;
        first = c.copyWith(inMs: cut, fadeOutMs: 0);
        second = c.copyWith(
            id: newId(), outMs: cut, startMs: playheadMs, fadeInMs: 0);
      }
      tracks[loc.track].clips[loc.index] = first;
      tracks[loc.track].clips.add(second);
      lastRight = second.id;
    }
    selectedId = lastRight;
    selectedIds..clear();
    if (lastRight != null) selectedIds.add(lastRight);
    afterEdit();
  }

  void deleteSelected({bool ripple = false}) {
    final ids = selectedIds.isNotEmpty
        ? Set<String>.from(selectedIds)
        : (selectedId == null ? <String>{} : <String>{selectedId!});
    if (ids.isEmpty) return;
    final existing = <String>{
      for (final t in tracks)
        for (final c in t.clips)
          if (ids.contains(c.id)) c.id,
    };
    if (existing.isEmpty) {
      clearSelection();
      return;
    }
    pushHistory();
    for (final track in tracks) {
      final removed = track.clips.where((c) => existing.contains(c.id)).toList()
        ..sort((a, b) => a.startMs.compareTo(b.startMs));
      if (removed.isEmpty) continue;
      track.clips.removeWhere((c) => existing.contains(c.id));
      if (ripple) {
        for (var i = 0; i < track.clips.length; i++) {
          final clip = track.clips[i];
          final shift = removed
              .where((r) => r.endMs <= clip.startMs + 1)
              .fold<int>(0, (sum, r) => sum + r.durationMs);
          if (shift > 0) {
            track.clips[i] =
                clip.copyWith(startMs: max(0, clip.startMs - shift));
          }
        }
      }
    }
    clearSelection();
    afterEdit();
  }

  void duplicateSelected() {
    final originals = selectedClips;
    if (originals.isEmpty) return;
    pushHistory();
    final copies = <AudioClip>[];
    for (final clip in originals) {
      final loc = findClip(clip.id);
      if (loc == null) continue;
      var copy = clip.copyWith(id: newId(), startMs: clip.endMs);
      if (!isValid(loc.track, copy)) {
        final end =
            tracks[loc.track].clips.fold<int>(0, (m, c) => max(m, c.endMs));
        copy = copy.copyWith(startMs: end);
      }
      if (isValid(loc.track, copy)) {
        tracks[loc.track].clips.add(copy);
        copies.add(copy);
      }
    }
    selectedIds
      ..clear()
      ..addAll(copies.map((c) => c.id));
    selectedId = copies.isEmpty ? null : copies.last.id;
    afterEdit();
  }

  void zoom(double factor) => setZoom(pxPerSecond * factor);

  void setZoom(double value) {
    pxPerSecond = value.clamp(8, 400).toDouble();
    notifyListeners();
  }

  Future<void> seek(int ms) async {
    final target = ms.clamp(0, projectEndMs).toInt();
    playheadMs = target;
    await engine.seek(target);
  }

  Future<void> togglePlay() async {
    if (engine.playing) {
      await engine.pause();
      return;
    }
    if (projectEndMs == 0) return;
    await PreviewService.instance.stop();
    await engine.play(playheadMs);
  }

  Future<void> stop() async {
    await engine.pause();
    await seek(0);
  }

  Future<String?> exportProject(ExportOptions options, String outPath) async {
    if (projectEndMs == 0 || exporting) return null;
    exporting = true;
    notifyListeners();
    try {
      if (engine.playing) await engine.pause();
      final args =
          AudioEngine.buildMixArgs(tracks, projectEndMs, outPath, options);
      if (args == null) return null;
      final ok = await FfmpegRunner.run(args);
      if (!ok) lastError = FfmpegRunner.lastLog;
      return ok ? outPath : null;
    } finally {
      exporting = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    saveTimer?.cancel();
    engine.dispose();
    playhead.dispose();
    super.dispose();
  }
}
