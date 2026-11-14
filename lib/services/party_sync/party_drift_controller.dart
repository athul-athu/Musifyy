import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:musify/services/party_sync/party_clock_service.dart';

/// Active phase-locked loop controller that keeps local [AudioPlayer] playback
/// micro-aligned with the Host's reference clock without audio dropouts or breaking.
class PartyDriftController {
  PartyDriftController({
    required this.clock,
    required this.audioPlayer,
  });

  final PartyClockService clock;
  final AudioPlayer audioPlayer;

  Timer? _monitorTimer;
  int _startPositionMs = 0;
  int _startedAtHostTimeMs = 0;
  bool _isPlaying = false;
  double _smoothedDriftMs = 0;

  /// User manual acoustic/latency offset slider in milliseconds (-50ms to +50ms).
  int manualCalibrationOffsetMs = 0;

  /// Latest measured drift from Host in milliseconds.
  int get lastMeasuredDriftMs => _smoothedDriftMs.round();

  /// Informs the controller of a newly scheduled or ongoing playback session.
  void onPlaybackScheduled({
    required int startPositionMs,
    required int targetHostTimeMs,
  }) {
    _startPositionMs = startPositionMs;
    _startedAtHostTimeMs = targetHostTimeMs;
    _isPlaying = true;
    _smoothedDriftMs = 0;
    _startMonitoring();
  }

  /// Informs the controller that playback has paused.
  void onPlaybackPaused({required int positionMs}) {
    _isPlaying = false;
    _stopMonitoring();
    _startPositionMs = positionMs;
    _smoothedDriftMs = 0;
    unawaited(audioPlayer.setSpeed(1));
  }

  /// Informs the controller that playback has stopped completely.
  void onPlaybackStopped() {
    _isPlaying = false;
    _stopMonitoring();
    _startPositionMs = 0;
    _startedAtHostTimeMs = 0;
    _smoothedDriftMs = 0;
    unawaited(audioPlayer.setSpeed(1));
  }

  void _startMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(
      const Duration(milliseconds: 2200),
      (_) => _evaluateDrift(),
    );
  }

  void _stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  void _evaluateDrift() {
    if (!_isPlaying || !clock.isSynced) return;

    final hostNow = clock.hostNowMs;
    if (hostNow < _startedAtHostTimeMs) {
      // Still waiting for scheduled start time
      return;
    }

    final elapsedSinceStartMs = hostNow - _startedAtHostTimeMs;
    final expectedPositionMs =
        _startPositionMs + elapsedSinceStartMs + manualCalibrationOffsetMs;

    final currentPositionMs = audioPlayer.position.inMilliseconds;
    final rawDriftMs = (currentPositionMs - expectedPositionMs).toDouble();

    // Exponential smoothing filter to reject platform channel position polling jitter
    if (_smoothedDriftMs == 0) {
      _smoothedDriftMs = rawDriftMs;
    } else {
      _smoothedDriftMs = (_smoothedDriftMs * 0.65) + (rawDriftMs * 0.35);
    }

    final drift = _smoothedDriftMs;

    // 1. Zone: Inaudible / Perfect Phase (|drift| <= 35ms)
    // Within 35ms, the phase difference is inaudible in room acoustics.
    if (drift.abs() <= 35) {
      if (audioPlayer.speed != 1) {
        unawaited(audioPlayer.setSpeed(1));
      }
      return;
    }

    // 2. Zone: Micro Drift (35ms < |drift| <= 1500ms)
    // Gently nudge playback speed by +/- 1.5% without pitch change or buffer flush.
    // This smoothly closes the phase gap without causing any audio breaking or stutter.
    if (drift > 35 && drift <= 1500) {
      // Client is ahead: gently slow down
      if (audioPlayer.speed != 0.985) {
        unawaited(audioPlayer.setSpeed(0.985));
      }
      return;
    }

    if (drift < -35 && drift >= -1500) {
      // Client is behind: gently speed up
      if (audioPlayer.speed != 1.015) {
        unawaited(audioPlayer.setSpeed(1.015));
      }
      return;
    }

    // 3. Zone: Massive Desync / Scrub (|drift| > 1500ms)
    // Only perform a hard seek if the player is more than 1.5 seconds out of sync.
    unawaited(
      audioPlayer.seek(
        Duration(
          milliseconds: expectedPositionMs.clamp(0, 1000 * 3600 * 24),
        ),
      ),
    );
    if (audioPlayer.speed != 1) {
      unawaited(audioPlayer.setSpeed(1));
    }
  }

  void dispose() {
    _stopMonitoring();
    unawaited(audioPlayer.setSpeed(1));
  }
}
