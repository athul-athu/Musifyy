import 'dart:math';

/// A single time synchronization sample.
class _ClockSample {
  const _ClockSample({
    required this.rttMicros,
    required this.offsetMicros,
  });

  final int rttMicros;
  final int offsetMicros;
}

/// High-precision clock synchronization engine implementing Cristian's algorithm
/// with jitter outlier filtering and running median calculation.
class PartyClockService {
  PartyClockService() {
    _stopwatch.start();
  }

  final Stopwatch _stopwatch = Stopwatch();
  final List<_ClockSample> _samples = [];
  static const int _maxSamples = 15;

  int _medianOffsetMicros = 0;
  int _latestRttMicros = 0;
  bool _isSynced = false;

  /// Local monotonic clock in microseconds.
  int get localNowMicros => _stopwatch.elapsedMicroseconds;

  /// Local monotonic clock in milliseconds.
  int get localNowMs => localNowMicros ~/ 1000;

  /// Current estimated clock offset from Host (in microseconds).
  ///
  /// hostTime = localTime + offset
  int get offsetMicros => _medianOffsetMicros;

  /// Current estimated clock offset in milliseconds.
  int get offsetMs => _medianOffsetMicros ~/ 1000;

  /// Round-trip latency to Host in milliseconds.
  int get rttMs => _latestRttMicros ~/ 1000;

  /// Whether sufficient samples have been gathered to consider the clocks aligned.
  bool get isSynced => _isSynced;

  /// Calculates the current time in the Host's reference frame (in milliseconds).
  int get hostNowMs => (localNowMicros + _medianOffsetMicros) ~/ 1000;

  /// Calculates the current time in the Host's reference frame (in microseconds).
  int get hostNowMicros => localNowMicros + _medianOffsetMicros;

  /// Computes the duration until a specified Host timestamp arrives.
  /// Returns [Duration.zero] if the timestamp has already passed.
  Duration delayUntilHostTime(int targetHostTimeMs) {
    final now = hostNowMs;
    final diff = targetHostTimeMs - now;
    if (diff <= 0) return Duration.zero;
    return Duration(milliseconds: diff);
  }

  /// Records a ping-pong round trip with the Host.
  ///
  /// - [t0]: Client send timestamp (localNowMicros)
  /// - [t1]: Host receive timestamp
  /// - [t2]: Host reply timestamp
  /// - [t3]: Client receive timestamp (localNowMicros)
  void recordSample({
    required int t0,
    required int t1,
    required int t2,
    required int t3,
  }) {
    final rtt = (t3 - t0) - (t2 - t1);
    if (rtt < 0) return; // Discard invalid clock anomaly

    final offset = ((t1 - t0) + (t2 - t3)) ~/ 2;
    _latestRttMicros = rtt;

    _samples.add(_ClockSample(rttMicros: rtt, offsetMicros: offset));
    if (_samples.length > _maxSamples) {
      _samples.removeAt(0);
    }

    _recalculateMedian();
  }

  void _recalculateMedian() {
    if (_samples.isEmpty) return;

    // Find the minimum RTT among gathered samples.
    var minRtt = _samples.first.rttMicros;
    for (final s in _samples) {
      if (s.rttMicros < minRtt) minRtt = s.rttMicros;
    }

    // Filter out jitter spikes where RTT is > 1.8x minimum RTT (if we have >= 4 samples).
    final validSamples = _samples.length >= 4
        ? _samples
            .where((s) => s.rttMicros <= max(minRtt * 1.8, minRtt + 15000))
            .toList()
        : _samples;

    if (validSamples.isEmpty) return;

    final sortedOffsets = validSamples.map((s) => s.offsetMicros).toList()
      ..sort();
    _medianOffsetMicros = sortedOffsets[sortedOffsets.length ~/ 2];

    if (_samples.length >= 3) {
      _isSynced = true;
    }
  }

  /// Resets clock synchronization history.
  void reset() {
    _samples.clear();
    _medianOffsetMicros = 0;
    _latestRttMicros = 0;
    _isSynced = false;
  }
}

