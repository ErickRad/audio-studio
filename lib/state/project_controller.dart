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
import '../services/audio_engine.dart';
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
  int activeTrack = 0;
  final ValueNotifier<int> playhead = ValueNotifier<int>(0);
  double pxPerSecond = 60;
  bool playing = false;
  bool get rendering => false;
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
    if (selectedClip == null) selectedId = null;
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

  void select(String id) {
    selectedId = id;
    notifyListeners();
  }

  void clearSelection() {
    selectedId = null;
    notifyListeners();
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
    if (selectedClip == null) selectedId = null;
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

  void splitAtPlayhead() {
    bool inside(AudioClip c) =>
        playheadMs > c.startMs + minClipMs && playheadMs < c.endMs - minClipMs;
    final targets = <String>[];
    final sel = selectedClip;
    if (sel != null && inside(sel)) {
      targets.add(sel.id);
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
    afterEdit();
  }

  void deleteSelected({bool ripple = false}) {
    final id = selectedId;
    if (id == null) return;
    final loc = findClip(id);
    if (loc == null) return;
    pushHistory();
    final list = tracks[loc.track].clips;
    final removed = list.removeAt(loc.index);
    if (ripple) {
      for (var i = 0; i < list.length; i++) {
        if (list[i].startMs >= removed.endMs - 1) {
          list[i] =
              list[i].copyWith(startMs: list[i].startMs - removed.durationMs);
        }
      }
    }
    selectedId = null;
    afterEdit();
  }

  void duplicateSelected() {
    final id = selectedId;
    if (id == null) return;
    final loc = findClip(id);
    if (loc == null) return;
    final clip = tracks[loc.track].clips[loc.index];
    pushHistory();
    var copy = clip.copyWith(id: newId(), startMs: clip.endMs);
    if (!isValid(loc.track, copy)) {
      final end =
          tracks[loc.track].clips.fold<int>(0, (m, c) => max(m, c.endMs));
      copy = copy.copyWith(startMs: end);
    }
    tracks[loc.track].clips.add(copy);
    selectedId = copy.id;
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
