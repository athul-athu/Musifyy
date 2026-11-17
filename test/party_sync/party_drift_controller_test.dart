import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/party_sync/party_drift_controller.dart';

void main() {
  group('PartyPIController', () {
    late PartyPIController pi;

    setUp(() {
      pi = PartyPIController(
        smoothingAlpha: 0.5,
      );
    });

    test('deadband: small drift within threshold produces no correction', () {
      final result = pi.evaluate(rawDriftMs: 5, expectedPositionMs: 10000);
      expect(result.action, DriftActionType.none);
      expect(result.recommendedSpeed, 1.0);
    });

    test('speed correction: client ahead slows down (< 1.0)', () {
      // 50ms ahead (positive drift)
      final result = pi.evaluate(rawDriftMs: 50, expectedPositionMs: 10000);
      expect(result.action, DriftActionType.speedCorrection);
      expect(result.recommendedSpeed, lessThan(1.0));
      expect(result.recommendedSpeed, greaterThanOrEqualTo(0.97));
    });

    test('speed correction: client behind speeds up (> 1.0)', () {
      // 50ms behind (negative drift)
      final result = pi.evaluate(rawDriftMs: -50, expectedPositionMs: 10000);
      expect(result.action, DriftActionType.speedCorrection);
      expect(result.recommendedSpeed, greaterThan(1.0));
      expect(result.recommendedSpeed, lessThanOrEqualTo(1.03));
    });

    test('max correction clamp: extreme sub-reanchor drift does not exceed limit', () {
      // 700ms drift is just below 800ms reanchor threshold
      final result = pi.evaluate(rawDriftMs: -700, expectedPositionMs: 10000);
      expect(result.action, DriftActionType.speedCorrection);
      expect(result.recommendedSpeed, closeTo(1.03, 0.001));
    });

    test('anti-windup: integral accumulator is clamped and resets on zero-crossing', () {
      // Accumulate integral with negative drift
      for (var i = 0; i < 20; i++) {
        pi.evaluate(rawDriftMs: -100, expectedPositionMs: 10000);
      }
      expect(pi.integralAccumulator, greaterThan(0));

      // Error crosses zero (positive drift)
      pi.evaluate(rawDriftMs: 100, expectedPositionMs: 10000);
      // Integral should be reset on zero-crossing
      expect(pi.integralAccumulator, lessThanOrEqualTo(100.0));
    });

    test('reanchor threshold: hard seek triggered between 800ms and 3000ms', () {
      final result = pi.evaluate(rawDriftMs: 1200, expectedPositionMs: 25000);
      expect(result.action, DriftActionType.reanchor);
      expect(result.targetSeekPositionMs, 25000);
      expect(pi.reanchorCount, 1);
    });

    test('emergency threshold: triggered above 3000ms', () {
      final result = pi.evaluate(rawDriftMs: 4500, expectedPositionMs: 25000);
      expect(result.action, DriftActionType.emergencyRestart);
      expect(result.targetSeekPositionMs, 25000);
      expect(pi.emergencyCount, 1);
    });

    test('smoothing rejects instantaneous spikes', () {
      // Steady at 0ms
      pi.evaluate(rawDriftMs: 0, expectedPositionMs: 10000);

      // Sudden 40ms spike
      final result = pi.evaluate(rawDriftMs: 40, expectedPositionMs: 10000);
      // With smoothingAlpha = 0.5, filtered drift is 20ms
      expect(result.filteredDriftMs, closeTo(20.0, 1.0));
    });
  });
}
