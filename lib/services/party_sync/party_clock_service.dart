import 'dart:math';

/// Sync quality rating based on clock uncertainty and sample stability.
enum SyncQuality {
  unsyncable,
  low,
  medium,
  high,
}

/// A single timestamped round-trip measurement between speaker and host.
class ClockSample {
  const ClockSample({
    required this.t0,
    required this.t1,
    required this.t2,
    required this.t3,
    required this.rttMicros,
    required this.offsetMicros,
    required this.localMidpointMicros,
  });

  final int t0;
  final int t1;
  final int t2;
  final int t3;
  final int rttMicros;
  final int offsetMicros;
  final int localMidpointMicros;
}

/// High-precision clock synchronization engine implementing Cristian's algorithm
/// with ordinary least squares (OLS) linear regression for drift estimation,
/// jitter rejection, uncertainty tracking, and clock epoch management.
class PartyClockService {
  PartyClockService({this._clockEpochId = ''}) {
    _stopwatch.start();
  }

  final Stopwatch _stopwatch = Stopwatch();
  final List<ClockSample> _samples = [];
  static const int _maxSamples = 20;

  String _clockEpochId;
  int _latestRttMicros = 0;
  int _latestOffsetMicros = 0;
  int _medianOffsetMicros = 0;
  double _regressionSlope = 0; // microsecond offset change per microsecond of elapsed time
  double _regressionIntercept = 0;
  int _regressionBaseTimeMicros = 0;
  int _uncertaintyMicros = 0;
  bool _isSynced = false;

  /// Local monotonic clock in microseconds.
  int get localNowMicros => _stopwatch.elapsedMicroseconds;

  /// Local monotonic clock in milliseconds.
  int get localNowMs => localNowMicros ~/ 1000;

  /// Active clock epoch identifier. Changes whenever the party coordinator restarts.
  String get clockEpochId => _clockEpochId;

  /// Sets the active clock epoch. If changed, resets clock synchronization history.
  void setClockEpoch(String epochId) {
    if (epochId != _clockEpochId) {
      _clockEpochId = epochId;
      reset();
    }
  }

  /// Current estimated clock offset from Host in microseconds (drift-compensated).
  ///
  /// hostTime = localTime + offset
  int get offsetMicros {
    if (_samples.length >= 4 && _regressionSlope != 0) {
      final elapsed = localNowMicros - _regressionBaseTimeMicros;
      return (_regressionIntercept + (_regressionSlope * elapsed)).round();
    }
    return _medianOffsetMicros;
  }

  /// Current estimated clock offset in milliseconds.
  int get offsetMs => offsetMicros ~/ 1000;

  /// Round-trip latency to Host in milliseconds.
  int get rttMs => _latestRttMicros ~/ 1000;

  /// Latest raw RTT in microseconds.
  int get latestRttMicros => _latestRttMicros;

  /// Latest raw clock offset in microseconds.
  int get latestOffsetMicros => _latestOffsetMicros;

  /// Estimated clock drift rate in parts per million (ppm).
  /// Positive means the host clock runs faster than local clock.
  double get driftRatePpm => _regressionSlope * 1000000;

  /// Current clock offset uncertainty estimate in microseconds (± bound).
  int get uncertaintyMicros => _uncertaintyMicros;

  /// Current clock offset uncertainty estimate in milliseconds.
  int get uncertaintyMs => _uncertaintyMicros ~/ 1000;

  /// Whether sufficient samples have been gathered to consider clocks aligned.
  bool get isSynced => _isSynced;

  /// Number of valid samples gathered in current epoch.
  int get sampleCount => _samples.length;

  /// Categorical synchronization quality rating.
  SyncQuality get quality {
    if (!_isSynced || _samples.length < 3) {
      return SyncQuality.unsyncable;
    }
    final uncertMs = uncertaintyMs;
    if (_samples.length >= 8 && uncertMs <= 5) {
      return SyncQuality.high;
    }
    if (_samples.length >= 5 && uncertMs <= 15) {
      return SyncQuality.medium;
    }
    return SyncQuality.low;
  }

  /// Calculates the current time in the Host's reference frame (in milliseconds).
  int get hostNowMs => (localNowMicros + offsetMicros) ~/ 1000;

  /// Calculates the current time in the Host's reference frame (in microseconds).
  int get hostNowMicros => localNowMicros + offsetMicros;

  /// Computes the duration until a specified Host timestamp arrives.
  /// Returns [Duration.zero] if the timestamp has already passed.
  Duration delayUntilHostTime(int targetHostTimeMs) {
    final now = hostNowMs;
    final diff = targetHostTimeMs - now;
    if (diff <= 0) return Duration.zero;
    return Duration(milliseconds: diff);
  }

  /// Records a 4-timestamp exchange with the Host:
  ///
  /// - [t0]: Client send timestamp (localNowMicros)
  /// - [t1]: Host receive timestamp (Host monotonic micros)
  /// - [t2]: Host reply timestamp (Host monotonic micros)
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
    final midpoint = (t0 + t3) ~/ 2;
    _latestRttMicros = rtt;
    _latestOffsetMicros = offset;

    _samples.add(
      ClockSample(
        t0: t0,
        t1: t1,
        t2: t2,
        t3: t3,
        rttMicros: rtt,
        offsetMicros: offset,
        localMidpointMicros: midpoint,
      ),
    );

    if (_samples.length > _maxSamples) {
      _samples.removeAt(0);
    }

    _recalculateParameters();
  }

  void _recalculateParameters() {
    if (_samples.isEmpty) return;

    // 1. Find minimum RTT among gathered samples.
    var minRtt = _samples.first.rttMicros;
    for (final s in _samples) {
      if (s.rttMicros < minRtt) minRtt = s.rttMicros;
    }

    // 2. Filter out network jitter spikes where RTT is > 1.8x min RTT.
    final rttFiltered = _samples.length >= 4
        ? _samples
            .where((s) => s.rttMicros <= max(minRtt * 1.8, minRtt + 15000))
            .toList()
        : List<ClockSample>.from(_samples);

    if (rttFiltered.isEmpty) return;

    // 3. Compute baseline median offset
    final sortedOffsets = rttFiltered.map((s) => s.offsetMicros).toList()
      ..sort();
    _medianOffsetMicros = sortedOffsets[sortedOffsets.length ~/ 2];

    if (_samples.length >= 3) {
      _isSynced = true;
    }

    // 4. Ordinary Least Squares (OLS) Linear Regression for drift rate:
    // offset(t) = intercept + slope * (t - baseTime)
    if (rttFiltered.length >= 4) {
      final baseTime = rttFiltered.first.localMidpointMicros;
      _regressionBaseTimeMicros = baseTime;

      var sumX = 0.0;
      var sumY = 0.0;
      final n = rttFiltered.length;

      for (final s in rttFiltered) {
        sumX += (s.localMidpointMicros - baseTime).toDouble();
        sumY += s.offsetMicros.toDouble();
      }

      final meanX = sumX / n;
      final meanY = sumY / n;

      var num = 0.0;
      var den = 0.0;

      for (final s in rttFiltered) {
        final dx = (s.localMidpointMicros - baseTime).toDouble() - meanX;
        final dy = s.offsetMicros.toDouble() - meanY;
        num += dx * dy;
        den += dx * dx;
      }

      final timeSpanMicros =
          rttFiltered.last.localMidpointMicros - rttFiltered.first.localMidpointMicros;

      // Only apply slope if time span is at least 300ms to avoid numerical instability
      if (den > 0 && timeSpanMicros >= 300000) {
        _regressionSlope = num / den;
        _regressionIntercept = meanY - (_regressionSlope * meanX);
      } else {
        _regressionSlope = 0;
        _regressionIntercept = _medianOffsetMicros.toDouble();
      }

      // 5. Calculate residual standard deviation & uncertainty bound
      var sumResidualSq = 0.0;
      for (final s in rttFiltered) {
        final predicted = _regressionIntercept +
            (_regressionSlope * (s.localMidpointMicros - baseTime).toDouble());
        final residual = s.offsetMicros.toDouble() - predicted;
        sumResidualSq += residual * residual;
      }

      final residualStdDev =
          sqrt(sumResidualSq / (n > 2 ? n - 2 : 1));

      // Total uncertainty = one-way network latency uncertainty + residual variance
      _uncertaintyMicros = ((minRtt / 2) + residualStdDev).round();
    } else {
      _regressionSlope = 0;
      _regressionIntercept = _medianOffsetMicros.toDouble();
      _uncertaintyMicros = (minRtt ~/ 2) + 10000; // conservative 10ms jitter prior
    }
  }

  /// Resets clock synchronization history.
  void reset() {
    _samples.clear();
    _medianOffsetMicros = 0;
    _latestRttMicros = 0;
    _latestOffsetMicros = 0;
    _regressionSlope = 0;
    _regressionIntercept = 0;
    _regressionBaseTimeMicros = 0;
    _uncertaintyMicros = 0;
    _isSynced = false;
  }
}
