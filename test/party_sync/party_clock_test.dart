import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/party_sync/party_clock_service.dart';

void main() {
  group('PartyClockService', () {
    late PartyClockService clock;

    setUp(() {
      clock = PartyClockService();
    });

    test('initial state is un-synced', () {
      expect(clock.isSynced, isFalse);
      expect(clock.offsetMs, 0);
      expect(clock.rttMs, 0);
    });

    test('calculates offset correctly with symmetric network latency', () {
      // Simulate client send at 1000ms, host receives at 2005ms, replies at 2005ms, client receives at 1010ms.
      // One-way delay = 5ms.
      // Host clock is ahead of client by 1000ms.
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

      // Now introduce a huge 200ms Wi-Fi lag spike with corrupted offset
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
      // Offset = 0ms
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
  });
}

