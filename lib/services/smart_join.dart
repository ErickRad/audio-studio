import 'dart:math';

import '../models/clip.dart';
import 'audio_analyzer.dart';

class SmartJoinOptions {
  final bool alignBeats;
  final bool matchTempo;
  final bool matchLoudness;
  final bool trimSilence;
  final bool sortByBpm;
  final int overlapMs;
  final bool preferLowEnergy;
  final bool equalPowerCrossfade;
  final double maxTempoShift;
  final int searchWindowMs;

  const SmartJoinOptions({
    this.alignBeats = true,
    this.matchTempo = true,
    this.matchLoudness = true,
    this.trimSilence = true,
    this.sortByBpm = false,
    this.overlapMs = 0,
    this.preferLowEnergy = true,
    this.equalPowerCrossfade = true,
    this.maxTempoShift = 0.10,
    this.searchWindowMs = 2500,
  });

  SmartJoinOptions copyWith({
    bool? alignBeats,
    bool? matchTempo,
    bool? matchLoudness,
    bool? trimSilence,
    bool? sortByBpm,
    int? overlapMs,
    bool? preferLowEnergy,
    bool? equalPowerCrossfade,
    double? maxTempoShift,
    int? searchWindowMs,
  }) {
    return SmartJoinOptions(
      alignBeats: alignBeats ?? this.alignBeats,
      matchTempo: matchTempo ?? this.matchTempo,
      matchLoudness: matchLoudness ?? this.matchLoudness,
      trimSilence: trimSilence ?? this.trimSilence,
      sortByBpm: sortByBpm ?? this.sortByBpm,
      overlapMs: overlapMs ?? this.overlapMs,
      preferLowEnergy: preferLowEnergy ?? this.preferLowEnergy,
      equalPowerCrossfade: equalPowerCrossfade ?? this.equalPowerCrossfade,
      maxTempoShift: maxTempoShift ?? this.maxTempoShift,
      searchWindowMs: searchWindowMs ?? this.searchWindowMs,
    );
  }
}

class JoinResult {
  final AudioClip first;
  final AudioClip second;
  final int overlapMs;
  final bool beatAligned;
  final bool tempoMatched;
  final double transitionScore;
  final String strategy;

  const JoinResult({
    required this.first,
    required this.second,
    required this.overlapMs,
    required this.beatAligned,
    required this.tempoMatched,
    this.transitionScore = 0,
    this.strategy = 'crossfade',
  });
}

class SmartJoin {
  static const int minOverlapMs = 400;
  static const int maxOverlapMs = 12000;

  static AudioClip trimEdges(AudioClip c, AudioAnalysis? a) {
    if (a == null) return c;
    final newIn = max(c.inMs, a.firstSoundMs - 30);
    final newOut = min(c.outMs, a.lastSoundMs + 120);
    if (newOut - newIn < 1000) return c;
    final shift = ((newIn - c.inMs) / max(0.01, c.speed)).round();
    return c.copyWith(inMs: newIn, outMs: newOut, startMs: c.startMs + shift);
  }

  static double tempoRatio(AudioClip a, AudioAnalysis an, AudioAnalysis bn) {
    final targetBpm = an.bpm * a.speed;
    var ratio = targetBpm / bn.bpm;

    if (ratio > 1.5) ratio /= 2;
    if (ratio < 0.67) ratio *= 2;
    return ratio;
  }

  static double _clampDouble(double value, double low, double high) =>
      value.clamp(low, high).toDouble();

  static double _rmsDifference(AudioAnalysis a, AudioAnalysis b, int aFrom,
      int aTo, int bFrom, int bTo) {
        
    final dbA = a.rmsDb(aFrom, aTo);
    final dbB = b.rmsDb(bFrom, bTo);
    if (dbA <= -60 || dbB <= -60) return 0;
    return (dbA - dbB).abs();
  }

  /// Scores possible cut positions using RMS mismatch, silence, and beat distance.
  /// This is an analysis-based estimate; sample-accurate waveform phase matching
  /// requires reading aligned PCM windows at the final playback sample rate.
  static int _bestBoundary({
    required AudioAnalysis outgoing,
    required AudioAnalysis incoming,
    required int desiredOutMs,
    required int incomingInMs,
    required int overlapMs,
    required int searchWindowMs,
    required bool preferLowEnergy,
    required bool alignBeats,
  }) {
    final low = max(outgoing.firstSoundMs, desiredOutMs - searchWindowMs);
    final high = min(outgoing.lastSoundMs, desiredOutMs + searchWindowMs);
    if (high <= low) return desiredOutMs;
    var best = desiredOutMs;
    var bestScore = double.infinity;
    final step = max(20, AudioAnalysis.blockMs ~/ 2);
    for (var candidate = low; candidate <= high; candidate += step) {
      final outFrom = max(outgoing.firstSoundMs, candidate - overlapMs);
      final inTo = min(incoming.lastSoundMs, incomingInMs + overlapMs);
      final levelDiff = _rmsDifference(
        outgoing, incoming, outFrom, candidate, incomingInMs, inTo,
      );
      final outEnergy = outgoing.rmsDb(outFrom, candidate);
      final inEnergy = incoming.rmsDb(incomingInMs, inTo);
      var score = levelDiff;
      if (preferLowEnergy) {
        score += max(0, outEnergy + 35) * 0.10;
        score += max(0, inEnergy + 35) * 0.10;
      }
      if (alignBeats && outgoing.reliable) {
        final snapped = outgoing.snapNearest(candidate);
        score += (candidate - snapped).abs() * 0.004;
      }
      // Prefer a nearby boundary unless another candidate is clearly better.
      score += (candidate - desiredOutMs).abs() * 0.001;
      if (score < bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    return best;
  }

  static JoinResult join(
    AudioClip a,
    AudioAnalysis? an,
    AudioClip b,
    AudioAnalysis? bn,
    SmartJoinOptions o,
  ) {
    var firstClip = a;
    var next = b;
    var tempoMatched = false;
    final tempoReliable = an != null &&
        bn != null &&
        an.reliable &&
        bn.reliable &&
        an.confidence >= 0.18 &&
        bn.confidence >= 0.18;

    if (o.trimSilence) {
      firstClip = trimEdges(firstClip, an);
      next = trimEdges(next, bn);
    }

    if (o.matchTempo && tempoReliable) {
      final ratio = tempoRatio(firstClip, an, bn);
      if ((ratio - 1).abs() <= o.maxTempoShift &&
          (ratio - 1).abs() > 0.004) {
        next = next.copyWith(speed: _clampDouble(
          next.speed * ratio,
          next.speed * (1 - o.maxTempoShift),
          next.speed * (1 + o.maxTempoShift),
        ));
        tempoMatched = true;
      }
    }

    var beatAligned = false;
    if (o.alignBeats && bn != null && bn.reliable &&
        bn.beatConfidence >= 0.10) {
      final snapped = bn.snapForward(next.inMs);
      if (snapped >= next.inMs &&
          snapped < next.outMs - 2000) {
        next = next.copyWith(inMs: snapped);
        beatAligned = true;
      }
    }

    final capBase = min(firstClip.durationMs, next.durationMs);
    var overlap = o.overlapMs;
    if (overlap <= 0) {
      if (an != null && an.reliable && an.beatConfidence >= 0.1) {
        overlap = (an.periodMs / max(0.01, firstClip.speed) * 8).round();
      } else {
        overlap = 3000;
      }
      overlap = overlap.clamp(1500, 8000).toInt();
    }
    overlap = min(overlap, max(minOverlapMs, (capBase * 0.45).round()));
    overlap = overlap.clamp(minOverlapMs, maxOverlapMs).toInt();
    overlap = min(overlap, max(minOverlapMs, capBase ~/ 2));

    var start = firstClip.endMs - overlap;
    if (o.alignBeats && an != null && an.reliable &&
        an.beatConfidence >= 0.10) {
      final srcDesired = firstClip.inMs +
          ((start - firstClip.startMs) * firstClip.speed).round();
      final beatSrc = an.snapNearest(srcDesired)
          .clamp(firstClip.inMs, firstClip.outMs).toInt();
      final tBeat = firstClip.startMs +
          ((beatSrc - firstClip.inMs) / max(0.01, firstClip.speed)).round();
      if (tBeat > firstClip.startMs + minOverlapMs &&
          tBeat < firstClip.endMs - minOverlapMs) {
        start = tBeat;
        beatAligned = true;
      }
    }

    if (o.preferLowEnergy && an != null && bn != null) {
      final desiredSource = firstClip.inMs +
          ((start - firstClip.startMs) * firstClip.speed).round();
      final bestSource = _bestBoundary(
        outgoing: an,
        incoming: bn,
        desiredOutMs: desiredSource,
        incomingInMs: next.inMs,
        overlapMs: overlap,
        searchWindowMs: o.searchWindowMs,
        preferLowEnergy: true,
        alignBeats: o.alignBeats,
      );
      final timeline = firstClip.startMs +
          ((bestSource - firstClip.inMs) / max(0.01, firstClip.speed)).round();
      if (timeline > firstClip.startMs + minOverlapMs &&
          timeline < firstClip.endMs - minOverlapMs) {
        start = timeline;
      }
    }

    start = max(start, firstClip.startMs + minOverlapMs);
    overlap = max(minOverlapMs, firstClip.endMs - start);
    overlap = min(overlap, max(minOverlapMs, next.durationMs ~/ 2));

    var volume = next.volume;
    var transitionScore = 0.45;
    if (an != null && bn != null) {
      final srcFrom = firstClip.inMs +
          ((start - firstClip.startMs) * firstClip.speed).round();
      final srcTo = min(firstClip.outMs, srcFrom +
          (overlap * firstClip.speed).round());
      final inTo = min(next.outMs, next.inMs +
          (overlap * next.speed).round());
      final dbA = an.rmsDb(srcFrom, srcTo);
      final dbB = bn.rmsDb(next.inMs, inTo);
      final levelDiff = (dbA - dbB).abs();

      transitionScore = _clampDouble(1 - levelDiff / 24, 0, 1);

      if (o.matchLoudness && dbA > -60 && dbB > -60) {
        final gainA = max(firstClip.volume, 1e-6);
        final gainB = max(next.volume, 1e-6);
        final effectiveDbA = dbA + 20 * log(gainA) / ln10;
        final effectiveDbB = dbB + 20 * log(gainB) / ln10;
        final diff = effectiveDbA - effectiveDbB;

        volume = (next.volume * pow(10, diff / 20))
            .clamp(0.0, 1.0).toDouble();
      }
      if (an.beatConfidence > 0 && bn.beatConfidence > 0) {
        transitionScore = _clampDouble(
          transitionScore * 0.75 +
              ((an.beatConfidence + bn.beatConfidence) / 2) * 0.25,
          0,
          1,
        );
      }
    }

    final first = firstClip.copyWith(
      fadeOutMs: min(overlap, firstClip.durationMs),
      fadeShape: 1,
    );

    final second = next.copyWith(
      startMs: start,
      volume: volume,
      fadeInMs: overlap,
      fadeShape: 1,
    );

    return JoinResult(
      first: first,
      second: second,
      overlapMs: overlap,
      beatAligned: beatAligned,
      tempoMatched: tempoMatched,
      transitionScore: transitionScore,
      strategy: o.equalPowerCrossfade ? 'equal-power-requested' : 'linear-crossfade',
    );
  }
}
