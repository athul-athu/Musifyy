import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:musify/services/party_sync/party_clock_service.dart';

/// Active phase-locked loop controller that keeps local [AudioPlayer] playback
/// micro-aligned with the Host's reference clock and expected position.
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
  int _lastMeasuredDriftMs = 0;

  /// User manual acoustic/latency offset slider in milliseconds (-50ms to +50ms).
  int manualCalibrationOffsetMs = 0;

  /// Latest measured drift from Host in milliseconds.
  int get lastMeasuredDriftMs => _lastMeasuredDriftMs;

  /// Informs the controller of a newly scheduled or ongoing playback session.
  void onPlaybackScheduled({
    required int startPositionMs,
    required int targetHostTimeMs,
  }) {
    _startPositionMs = startPositionMs;
    _startedAtHostTimeMs = targetHostTimeMs;
    _isPlaying = true;
    _startMonitoring();
  }

  /// Informs the controller that playback has paused.
  void onPlaybackPaused({required int positionMs}) {
    _isPlaying = false;
    _stopMonitoring();
    _startPositionMs = positionMs;
    _lastMeasuredDriftMs = 0;
    unawaited(audioPlayer.setSpeed(1));
  }

  /// Informs the controller that playback has stopped completely.
  void onPlaybackStopped() {
    _isPlaying = false;
    _stopMonitoring();
    _startPositionMs = 0;
    _startedAtHostTimeMs = 0;
    _lastMeasuredDriftMs = 0;
    unawaited(audioPlayer.setSpeed(1));
  }

  void _startMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(
      const Duration(milliseconds: 1500),
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
    final driftMs = currentPositionMs - expectedPositionMs;
    _lastMeasuredDriftMs = driftMs;

    // 1. Zone: Inaudible / Perfect Phase (|drift| <= 20ms)
    if (driftMs.abs() <= 20) {
      if (audioPlayer.speed != 1) {
        unawaited(audioPlayer.setSpeed(1));
      }
      return;
    }

    // 2. Zone: Micro Drift (20ms < |drift| <= 120ms)
    // Smoothly nudge playback speed by +/- 2-3% without pitch change.
    if (driftMs > 20 && driftMs <= 120) {
      // Client is slightly ahead: slow down briefly
      if (audioPlayer.speed != 0.97) {
        unawaited(audioPlayer.setSpeed(0.97));
      }
      return;
    }

    if (driftMs < -20 && driftMs >= -120) {
      // Client is slightly behind: speed up briefly
      if (audioPlayer.speed != 1.03) {
        unawaited(audioPlayer.setSpeed(1.03));
      }
      return;
    }

    // 3. Zone: Severe Stall / Jump (|drift| > 120ms)
    // Direct seek to recover alignment immediately.
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

