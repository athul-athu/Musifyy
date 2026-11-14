import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/party_sync/party_protocol.dart';

void main() {
  group('PartyProtocol serialization', () {
    test('serializes and deserializes PartyMessage correctly', () {
      const msg = PartyMessage(
        type: PartyMessageType.play,
        payload: {
          'positionMs': 1234,
          'targetHostTimeMs': 56789,
        },
      );

      final raw = msg.serialize();
      final decoded = PartyMessage.tryDeserialize(raw);

      expect(decoded, isNotNull);
      expect(decoded!.type, PartyMessageType.play);
      expect(decoded.payload['positionMs'], 1234);
      expect(decoded.payload['targetHostTimeMs'], 56789);
    });

    test('gracefully handles malformed json', () {
      expect(PartyMessage.tryDeserialize('{invalid json}'), isNull);
      expect(PartyMessage.tryDeserialize(''), isNull);
    });

    test('PartyRoomInfo roundtrip', () {
      const room = PartyRoomInfo(
        id: '1234',
        name: "Athul's Party",
        hostName: 'Musify (Android)',
        ip: '192.168.1.15',
        port: 54321,
        speakersCount: 3,
        currentSongTitle: 'Believer',
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
    });

    test('ConnectedSpeaker serialization', () {
      final speaker = ConnectedSpeaker(
        id: 'speaker-1',
        name: 'iPhone 13',
        platform: 'iOS',
        ip: '192.168.1.20',
        rttMs: 4,
        driftMs: 2,
        isReady: true,
        status: 'playing',
      );

      final json = speaker.toJson();
      expect(json['id'], 'speaker-1');
      expect(json['name'], 'iPhone 13');
      expect(json['rttMs'], 4);
      expect(json['driftMs'], 2);
      expect(json['isReady'], true);
    });
  });
}

