import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/party_sync/party_protocol.dart';
import 'package:musify/services/party_sync/party_sync_service.dart';

void main() {
  group('PartySyncService Integration', () {
    late PartySyncService service;

    setUp(() {
      service = PartySyncService.instance;
    });

    tearDown(() async {
      await service.leaveParty();
    });

    test('starts hosting and accepts client connection over WebSocket', () async {
      final hosted = await service.startHosting(customRoomName: 'Test Room');
      expect(hosted, isTrue);
      expect(service.isHost, isTrue);
      expect(service.currentRoom.value, isNotNull);
      expect(service.currentRoom.value!.name, 'Test Room');

      final port = service.currentRoom.value!.port;
      expect(port, greaterThan(0));

      // Connect a mock speaker client
      final clientSocket = await WebSocket.connect('ws://127.0.0.1:$port/party/ws');
      final receivedMessages = <PartyMessage>[];
      final welcomeCompleter = Completer<PartyMessage>();

      clientSocket.listen((data) {
        final msg = PartyMessage.tryDeserialize(data.toString());
        if (msg != null) {
          receivedMessages.add(msg);
          if (msg.type == PartyMessageType.welcome && !welcomeCompleter.isCompleted) {
            welcomeCompleter.complete(msg);
          }
        }
      });

      // Send join
      const join = PartyMessage(
        type: PartyMessageType.join,
        payload: {
          'id': 'mock-speaker',
          'name': 'Mock iPhone',
          'platform': 'iOS',
          'ip': '127.0.0.1',
        },
      );
      clientSocket.add(join.serialize());

      // Wait for welcome
      final welcome = await welcomeCompleter.future.timeout(const Duration(seconds: 5));
      expect(welcome.type, PartyMessageType.welcome);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(service.connectedSpeakers.value, isNotEmpty);
      expect(service.connectedSpeakers.value.first.name, 'Mock iPhone');

      // Test Host Play broadcast
      service.coordinateHostPlay(positionMs: 500, leadTimeMs: 1000);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(receivedMessages.any((m) => m.type == PartyMessageType.play), isTrue);

      // Clean up client
      await clientSocket.close();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(service.connectedSpeakers.value, isEmpty);
    });
  });
}

