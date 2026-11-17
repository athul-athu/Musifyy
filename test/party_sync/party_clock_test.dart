import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/party_sync/party_clock_service.dart';

void main() {
  group('PartyClockService', () {
    late PartyClockService clock;

    setUp(() {
      clock = PartyClockService(clockEpochId: 'epoch-init');
    });

    test('initial state is un-synced', () {
      expect(clock.isSynced, isFalse);
      expect(clock.offsetMs, 0);
      expect(clock.rttMs, 0);
      expect(clock.sampleCount, 0);
      expect(clock.quality, SyncQuality.unsyncable);
      expect(clock.clockEpochId, 'epoch-init');
    });

    test('calculates offset correctly with symmetric network latency', () {
      // Client send at 1000ms, host receives at 2005ms, replies at 2005ms, client receives at 1010ms.
      // One-way delay = 5ms. Offset = 1000ms.
      const t0 = 1000 * 1000;
      const t1 = 2005 * 1000;
      const t2 = 2005 * 1000;
      const t3 = 1010 * 1000;

      for (var i = 0; i < 4; i++) {
        clock.recordSample(t0: t0, t1: t1, t2: t2, t3: t3);
      }

      expect(clock.isSynced, isTrue);
      expect(clock.rttMs, 10);
      expect(clock.offsetMs, 1000);
      expect(clock.sampleCount, 4);
    });

    test('rejects network jitter spike outliers', () {
      // 4 clean samples with 4ms RTT and 500ms offset
      for (var i = 0; i < 4; i++) {
        clock.recordSample(
          t0: 1000000,
          t1: 1502000,
          t2: 1502000,
          t3: 1004000,
        );
      }
      expect(clock.offsetMs, 500);

      // Huge 200ms Wi-Fi lag spike with corrupted offset
      clock.recordSample(
        t0: 1000000,
        t1: 1700000,
        t2: 1700000,
        t3: 1200000,
      );

      // The spike should be rejected from the median calculation!
      expect(clock.offsetMs, 500);
    });

    test('computes delay until future host timestamp correctly', () {
      clock
        ..recordSample(
          t0: 1000000,
          t1: 1002000,
          t2: 1002000,
          t3: 1004000,
        )
        ..recordSample(
          t0: 1000000,
          t1: 1002000,
          t2: 1002000,
          t3: 1004000,
        )
        ..recordSample(
          t0: 1000000,
          t1: 1002000,
          t2: 1002000,
          t3: 1004000,
        );

      final hostNow = clock.hostNowMs;
      final futureTime = hostNow + 800;
      final delay = clock.delayUntilHostTime(futureTime);

      expect(delay.inMilliseconds, inInclusiveRange(750, 850));

      final pastTime = hostNow - 500;
      expect(clock.delayUntilHostTime(pastTime), Duration.zero);
    });

    test('linear regression estimates clock drift rate in ppm', () {
      // Simulate drift: Host clock runs 50 microseconds faster every 1 second (50 ppm)
      // 6 samples separated by 500ms
      const baseOffset = 200000; // 200ms
      const intervalMicros = 500000; // 500ms
      const driftPerInterval = 25; // 25us per 500ms = 50 ppm

      for (var i = 0; i < 6; i++) {
        final t0 = i * intervalMicros;
        final t3 = t0 + 4000; // RTT = 4ms
        final offset = baseOffset + (i * driftPerInterval);
        final t1 = t0 + 2000 + offset;
        final t2 = t1;

        clock.recordSample(t0: t0, t1: t1, t2: t2, t3: t3);
      }

      expect(clock.driftRatePpm, closeTo(50.0, 5.0));
      expect(clock.uncertaintyMs, lessThanOrEqualTo(5));
    });

    test('clock epoch reset clears sample history on coordinator restart', () {
      for (var i = 0; i < 5; i++) {
        clock.recordSample(
          t0: 1000000,
          t1: 1502000,
          t2: 1502000,
          t3: 1004000,
        );
      }
      expect(clock.isSynced, isTrue);
      expect(clock.sampleCount, 5);

      // Coordinator restarts with a new epoch
      clock.setClockEpoch('epoch-new');
      expect(clock.clockEpochId, 'epoch-new');
      expect(clock.isSynced, isFalse);
      expect(clock.sampleCount, 0);
      expect(clock.offsetMs, 0);
    });

    test('sync quality transitions as samples accumulate', () {
      expect(clock.quality, SyncQuality.unsyncable);

      // 3 clean samples -> low
      for (var i = 0; i < 3; i++) {
        clock.recordSample(
          t0: 1000000,
          t1: 1002000,
          t2: 1002000,
          t3: 1004000,
        );
      }
      expect(clock.quality, isNot(SyncQuality.unsyncable));

      // 5 clean samples -> medium or high
      for (var i = 0; i < 2; i++) {
        clock.recordSample(
          t0: 1000000,
          t1: 1002000,
          t2: 1002000,
          t3: 1004000,
        );
      }
      expect(
        clock.quality == SyncQuality.medium || clock.quality == SyncQuality.high,
        isTrue,
      );
    });
  });
}
