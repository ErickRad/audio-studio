import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/audio_formats.dart';
import '../models/clip.dart';
import '../models/library_item.dart';
import '../models/timeline_track.dart';
import '../services/audio_engine.dart';
import '../services/ffmpeg_runner.dart';
import '../services/preview_service.dart';
import '../services/storage_service.dart';

class ProjectController extends ChangeNotifier {
  static const int minClipMs = 100;
  static const int maxTracks = 6;
  static const List<String> importExtensions = [
    'mp3', 'wav', 'flac', 'm4a', 'aac', 'ogg', 'opus', 'wma',
    'mp4', 'mkv', 'mov', 'webm', 'avi', '3gp',
  ];

  final List<LibraryItem> library = [];
  final List<TimelineTrack> tracks = [];
  final Map<String, List<double>> peaks = {};
  final AudioPlayer player = AudioPlayer();
  final List<List<TimelineTrack>> undoStack = [];
  final List<List<TimelineTrack>> redoStack = [];

  String? selectedId;
  int activeTrack = 0;
  final ValueNotifier<int> playhead = ValueNotifier<int>(0);
  double pxPerSecond = 60;
  bool playing = false;
  bool dirty = true;
  bool rendering = false;
  bool exporting = false;
  String? renderedPath;
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
    await loadProject();
    player
        .createPositionStream(
          steps: 800,
          minPeriod: const Duration(milliseconds: 30),
          maxPeriod: const Duration(milliseconds: 60),
        )
        .listen((pos) {
      if (!player.playing || dirty) return;
      playheadMs = pos.inMilliseconds.clamp(0, projectEndMs).toInt();
    });
    player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        player.pause();
        playheadMs = projectEndMs;
      }
      playing = state.playing && state.processingState != ProcessingState.completed;
      notifyListeners();
    });
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
    await file.writeAsString(jsonEncode(library.map((i) => i.toJson()).toList()));
  }

  Future<void> loadProject() async {
    final file = await StorageService.projectFile();
    if (await file.exists()) {
      try {
        final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
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
      tracks.add(TimelineTrack(id: newId(), name: 'Faixa 2'));
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
    await file.writeAsString(jsonEncode({'tracks': tracks.map((t) => t.toJson()).toList()}));
  }

  Future<LibraryItem> addToLibrary({
    required String title,
    required String artist,
    required String path,
  }) async {
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
      final dest = p.join(folder.path, '${DateTime.now().millisecondsSinceEpoch}_${p.basename(src)}');
      await File(src).copy(dest);
      await addToLibrary(title: p.basenameWithoutExtension(src), artist: 'Local', path: dest);
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
    if (player.playing) player.pause();
    dirty = true;
    final end = projectEndMs;
    if (playheadMs > end) playheadMs = end;
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
    if (clip.startMs < 0 || clip.inMs < 0 || clip.outMs > clip.sourceMs) return false;
    if (clip.lengthMs < minClipMs) return false;
    for (final o in tracks[trackIndex].clips) {
      if (o.id == clip.id) continue;
      if (clip.startMs < o.endMs - 1 && clip.endMs > o.startMs + 1) return false;
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
    final next = c.reversed ? c.copyWith(inMs: c.inMs - src) : c.copyWith(outMs: c.outMs + src);
    if (replaceClip(id, next)) afterEdit();
  }

  void updateClip(String id, AudioClip Function(AudioClip) change) {
    final loc = findClip(id);
    if (loc == null) return;
    final next = change(tracks[loc.track].clips[loc.index]);
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
        second = c.copyWith(id: newId(), inMs: cut, startMs: playheadMs, fadeInMs: 0);
      } else {
        final cut = c.outMs - srcOffset;
        first = c.copyWith(inMs: cut, fadeOutMs: 0);
        second = c.copyWith(id: newId(), outMs: cut, startMs: playheadMs, fadeInMs: 0);
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
          list[i] = list[i].copyWith(startMs: list[i].startMs - removed.durationMs);
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
      final end = tracks[loc.track].clips.fold<int>(0, (m, c) => max(m, c.endMs));
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
    playheadMs = ms.clamp(0, projectEndMs).toInt();
    if (!dirty && renderedPath != null) {
      await player.seek(Duration(milliseconds: playheadMs));
    }
  }

  Future<bool> renderPreview() async {
    final end = projectEndMs;
    final dir = await getTemporaryDirectory();
    final out = p.join(dir.path, 'preview_${DateTime.now().millisecondsSinceEpoch}.wav');
    final args = AudioEngine.buildMixArgs(tracks, end, out, null);
    if (args == null) return false;
    rendering = true;
    notifyListeners();
    try {
      final ok = await FfmpegRunner.run(args);
      if (!ok) {
        lastError = FfmpegRunner.lastLog;
        return false;
      }
      final previous = renderedPath;
      await player.setFilePath(out);
      renderedPath = out;
      dirty = false;
      if (previous != null) {
        try {
          await File(previous).delete();
        } catch (_) {}
      }
      return true;
    } finally {
      rendering = false;
      notifyListeners();
    }
  }

  Future<void> togglePlay() async {
    if (player.playing) {
      await player.pause();
      return;
    }
    if (projectEndMs == 0 || rendering) return;
    await PreviewService.instance.stop();
    if (playheadMs >= projectEndMs - 30) playheadMs = 0;
    if (dirty || renderedPath == null) {
      final ok = await renderPreview();
      if (!ok) return;
    }
    await player.seek(Duration(milliseconds: playheadMs));
    player.play();
  }

  Future<void> stop() async {
    await player.pause();
    await seek(0);
  }

  Future<String?> exportProject(ExportOptions options, String outPath) async {
    if (projectEndMs == 0 || exporting) return null;
    exporting = true;
    notifyListeners();
    try {
      if (player.playing) await player.pause();
      final args = AudioEngine.buildMixArgs(tracks, projectEndMs, outPath, options);
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
    playhead.dispose();
    player.dispose();
    super.dispose();
  }
}
