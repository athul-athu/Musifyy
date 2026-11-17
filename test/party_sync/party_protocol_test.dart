import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/party_sync/party_protocol.dart';

void main() {
  group('PartyProtocol serialization', () {
    test('serializes and deserializes PartyMessage correctly with versioning', () {
      final msg = PartyMessage.create(
        type: PartyMessageType.play,
        payload: {
          'positionMs': 1234,
          'targetHostTimeMs': 56789,
        },
        revision: 42,
        sessionId: 'session-xyz',
        clockEpochId: 'epoch-1',
      );

      final raw = msg.serialize();
      final decoded = PartyMessage.tryDeserialize(raw);

      expect(decoded, isNotNull);
      expect(decoded!.type, PartyMessageType.play);
      expect(decoded.payload['positionMs'], 1234);
      expect(decoded.payload['targetHostTimeMs'], 56789);
      expect(decoded.protocolVersion, kPartyProtocolVersion);
      expect(decoded.revision, 42);
      expect(decoded.sessionId, 'session-xyz');
      expect(decoded.clockEpochId, 'epoch-1');
      expect(decoded.messageId.isNotEmpty, isTrue);
      expect(decoded.isValid, isTrue);
    });

    test('backward compatibility: handles v1 message without new fields', () {
      final v1Json = {
        'type': 'play',
        'payload': {'positionMs': 500},
      };

      final msg = PartyMessage.fromJson(v1Json);
      expect(msg.type, PartyMessageType.play);
      expect(msg.payload['positionMs'], 500);
      expect(msg.revision, 0);
      expect(msg.sessionId, '');
      expect(msg.messageId, '');
      expect(msg.protocolVersion, kPartyProtocolVersion);
    });

    test('validates all PartyMessageType enum values serialize and parse', () {
      for (final type in PartyMessageType.values) {
        final msg = PartyMessage.create(type: type, payload: {'test': 1});
        final raw = msg.serialize();
        final decoded = PartyMessage.tryDeserialize(raw);
        expect(decoded?.type, type);
      }
    });

    test('gracefully handles malformed json', () {
      expect(PartyMessage.tryDeserialize('{invalid json}'), isNull);
      expect(PartyMessage.tryDeserialize(''), isNull);
    });

    test('PartyRoomInfo roundtrip with new fields', () {
      const room = PartyRoomInfo(
        id: '1234',
        name: "Athul's Party",
        hostName: 'Musify (Android)',
        ip: '192.168.1.15',
        port: 54321,
        speakersCount: 3,
        currentSongTitle: 'Believer',
        sessionId: 'sess-abc',
        maxParticipants: 8,
      );

      final json = room.toJson();
      final decoded = PartyRoomInfo.fromJson(json);

      expect(decoded.id, '1234');
      expect(decoded.name, "Athul's Party");
      expect(decoded.hostName, 'Musify (Android)');
      expect(decoded.ip, '192.168.1.15');
      expect(decoded.port, 54321);
      expect(decoded.speakersCount, 3);
      expect(decoded.currentSongTitle, 'Believer');
      expect(decoded.protocolVersion, 2);
      expect(decoded.sessionId, 'sess-abc');
      expect(decoded.maxParticipants, 8);
    });

    test('ConnectedSpeaker serialization with enhanced telemetry fields', () {
      final speaker = ConnectedSpeaker(
        id: 'speaker-1',
        name: 'iPhone 13',
        platform: 'iOS',
        ip: '192.168.1.20',
        rttMs: 4,
        offsetMs: 12,
        driftMs: 2,
        clockUncertaintyMs: 1,
        bufferDurationMs: 450,
        reanchorCount: 1,
        audioRoute: 'bluetooth',
        lastHeartbeatMs: 1000,
        isReady: true,
        status: 'playing',
        playbackState: 'playing',
        volume: 0.8,
        calibrationOffsetMs: -15,
      );

      final json = speaker.toJson();
      final decoded = ConnectedSpeaker.fromJson(json);

      expect(decoded.id, 'speaker-1');
      expect(decoded.name, 'iPhone 13');
      expect(decoded.rttMs, 4);
      expect(decoded.offsetMs, 12);
      expect(decoded.driftMs, 2);
      expect(decoded.clockUncertaintyMs, 1);
      expect(decoded.bufferDurationMs, 450);
      expect(decoded.underrunCount, 0);
      expect(decoded.reanchorCount, 1);
      expect(decoded.audioRoute, 'bluetooth');
      expect(decoded.isReady, true);
      expect(decoded.status, 'playing');
      expect(decoded.playbackState, 'playing');
      expect(decoded.volume, 0.8);
      expect(decoded.calibrationOffsetMs, -15);
    });

    test('message ID generation is non-empty and unique', () {
      final id1 = PartyMessage.generateId();
      final id2 = PartyMessage.generateId();
      expect(id1, isNotEmpty);
      expect(id2, isNotEmpty);
      expect(id1 != id2, isTrue);
    });
  });
}
