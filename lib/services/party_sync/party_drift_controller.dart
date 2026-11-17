import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:musify/services/party_sync/party_clock_service.dart';

/// Type of correction action emitted by the PI controller.
enum DriftActionType {
  none,
  speedCorrection,
  reanchor,
  emergencyRestart,
}

/// Result of evaluating audio synchronization error against the PI controller.
class DriftCorrectionResult {
  const DriftCorrectionResult({
    required this.action,
    required this.recommendedSpeed,
    required this.targetSeekPositionMs,
    required this.filteredDriftMs,
    required this.rawDriftMs,
  });

  final DriftActionType action;
  final double recommendedSpeed;
  final int? targetSeekPositionMs;
  final double filteredDriftMs;
  final double rawDriftMs;
}

/// Pure PI (Proportional-Integral) controller implementing 4-zone adaptive
/// audio drift compensation with anti-windup, deadband, and zero-crossing reset.
class PartyPIController {
  PartyPIController({
    this.kp = 0.0004,
    this.ki = 0.00002,
    this.maxCorrection = 0.03, // ±3.0% maximum audio pitch-preserving rate nudge
    this.deadbandMs = 8.0,
    this.reanchorThresholdMs = 800.0,
    this.emergencyThresholdMs = 3000.0,
    this.smoothingAlpha = 0.35,
  });

  final double kp;
  final double ki;
  final double maxCorrection;
  final double deadbandMs;
  final double reanchorThresholdMs;
  final double emergencyThresholdMs;
  final double smoothingAlpha;

  double _integralAccumulator = 0;
  double _filteredDriftMs = 0;
  double _lastError = 0;
  bool _hasInitializedFilter = false;
  int _reanchorCount = 0;
  int _emergencyCount = 0;

  double get integralAccumulator => _integralAccumulator;
  double get filteredDriftMs => _filteredDriftMs;
  int get reanchorCount => _reanchorCount;
  int get emergencyCount => _emergencyCount;

  void reset() {
    _integralAccumulator = 0;
    _filteredDriftMs = 0;
    _lastError = 0;
    _hasInitializedFilter = false;
  }

  /// Evaluates the measured raw drift and expected playback position.
  ///
  /// - [rawDriftMs]: `currentPosition - expectedPosition`.
  ///   Positive means client audio output is ahead of host.
  ///   Negative means client audio output is behind host.
  DriftCorrectionResult evaluate({
    required double rawDriftMs,
    required int expectedPositionMs,
  }) {
    // 1. Exponential moving average smoothing to reject platform channel position polling jitter
    if (!_hasInitializedFilter) {
      _filteredDriftMs = rawDriftMs;
      _hasInitializedFilter = true;
    } else {
      _filteredDriftMs = (_filteredDriftMs * (1.0 - smoothingAlpha)) +
          (rawDriftMs * smoothingAlpha);
    }

    final drift = _filteredDriftMs;

    // 2. Zone 4: Emergency Disconnect / Rejoin (|drift| > emergencyThresholdMs)
    if (drift.abs() > emergencyThresholdMs) {
      _emergencyCount++;
      _integralAccumulator = 0;
      return DriftCorrectionResult(
        action: DriftActionType.emergencyRestart,
        recommendedSpeed: 1,
        targetSeekPositionMs: expectedPositionMs,
        filteredDriftMs: _filteredDriftMs,
        rawDriftMs: rawDriftMs,
      );
    }

    // 3. Zone 3: Re-anchor Hard Seek (reanchorThresholdMs < |drift| <= emergencyThresholdMs)
    if (drift.abs() > reanchorThresholdMs) {
      _reanchorCount++;
      _integralAccumulator = 0;
      return DriftCorrectionResult(
        action: DriftActionType.reanchor,
        recommendedSpeed: 1,
        targetSeekPositionMs: expectedPositionMs,
        filteredDriftMs: _filteredDriftMs,
        rawDriftMs: rawDriftMs,
      );
    }

    // 4. Zone 1: Deadband / Inaudible (|drift| <= deadbandMs)
    if (drift.abs() <= deadbandMs) {
      // Within deadband: keep speed at 1.0, clear integral accumulator
      _integralAccumulator = 0;
      return DriftCorrectionResult(
        action: DriftActionType.none,
        recommendedSpeed: 1,
        targetSeekPositionMs: null,
        filteredDriftMs: _filteredDriftMs,
        rawDriftMs: rawDriftMs,
      );
    }

    // 5. Zone 2: Continuous PI Micro-adjustment
    // Anti-windup: zero-crossing integral reset
    if ((_lastError > 0 && drift < 0) || (_lastError < 0 && drift > 0)) {
      _integralAccumulator = 0;
    }
    _lastError = drift;

    // If drift > 0 (client ahead), we need a negative correction (speed < 1.0)
    // If drift < 0 (client behind), we need a positive correction (speed > 1.0)
    final correctionError = -drift;

    _integralAccumulator += correctionError;
    final maxIntegral = maxCorrection / (ki > 0 ? ki : 1.0);
    _integralAccumulator =
        _integralAccumulator.clamp(-maxIntegral, maxIntegral);

    final pTerm = kp * correctionError;
    final iTerm = ki * _integralAccumulator;
    final totalCorrection = (pTerm + iTerm).clamp(-maxCorrection, maxCorrection);

    final recommendedSpeed = 1.0 + totalCorrection;

    return DriftCorrectionResult(
      action: DriftActionType.speedCorrection,
      recommendedSpeed: recommendedSpeed,
      targetSeekPositionMs: null,
      filteredDriftMs: _filteredDriftMs,
      rawDriftMs: rawDriftMs,
    );
  }
}

/// Active phase-locked loop drift controller that keeps local [AudioPlayer]
/// micro-aligned with the Party Host reference clock without stutter or breaking.
class PartyDriftController {
  PartyDriftController({
    required this.clock,
    required this.audioPlayer,
    PartyPIController? piController,
  }) : pi = piController ?? PartyPIController();

  final PartyClockService clock;
  final AudioPlayer audioPlayer;
  final PartyPIController pi;

  Timer? _monitorTimer;
  int _startPositionMs = 0;
  int _startedAtHostTimeMs = 0;
  bool _isPlaying = false;
  double _currentPlaybackRate = 1;

  /// User manual acoustic/latency offset slider in milliseconds.
  int manualCalibrationOffsetMs = 0;

  /// Latest measured smoothed drift from Host in milliseconds.
  int get lastMeasuredDriftMs => pi.filteredDriftMs.round();

  /// Current active playback rate applied to the player.
  double get currentPlaybackRate => _currentPlaybackRate;

  /// Count of hard re-anchoring seeks performed.
  int get reanchorCount => pi.reanchorCount;

  /// Whether active speed correction is currently engaged.
  bool get isCorrectingDrift => (_currentPlaybackRate - 1.0).abs() > 0.001;

  /// Informs the controller of a newly scheduled or ongoing playback session.
  void onPlaybackScheduled({
    required int startPositionMs,
    required int targetHostTimeMs,
  }) {
    _startPositionMs = startPositionMs;
    _startedAtHostTimeMs = targetHostTimeMs;
    _isPlaying = true;
    pi.reset();
    _startMonitoring();
  }

  /// Informs the controller that playback has paused.
  void onPlaybackPaused({required int positionMs}) {
    _isPlaying = false;
    _stopMonitoring();
    _startPositionMs = positionMs;
    pi.reset();
    _setSpeed(1);
  }

  /// Informs the controller that playback has stopped completely.
  void onPlaybackStopped() {
    _isPlaying = false;
    _stopMonitoring();
    _startPositionMs = 0;
    _startedAtHostTimeMs = 0;
    pi.reset();
    _setSpeed(1);
  }

  void _startMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(
      const Duration(milliseconds: 1200),
      (_) => _evaluateDrift(),
    );
  }

  void _stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  void _setSpeed(double speed) {
    _currentPlaybackRate = speed;
    if ((audioPlayer.speed - speed).abs() > 0.002) {
      unawaited(audioPlayer.setSpeed(speed));
    }
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

    final result = pi.evaluate(
      rawDriftMs: rawDriftMs,
      expectedPositionMs: expectedPositionMs,
    );

    switch (result.action) {
      case DriftActionType.none:
      case DriftActionType.speedCorrection:
        _setSpeed(result.recommendedSpeed);
        break;

      case DriftActionType.reanchor:
      case DriftActionType.emergencyRestart:
        final seekTarget = result.targetSeekPositionMs ?? expectedPositionMs;
        unawaited(
          audioPlayer.seek(
            Duration(milliseconds: seekTarget.clamp(0, 1000 * 3600 * 24)),
          ),
        );
        _setSpeed(1);
        break;
    }
  }

  void dispose() {
    _stopMonitoring();
    _setSpeed(1);
  }
}
