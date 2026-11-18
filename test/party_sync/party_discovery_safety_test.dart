import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/party_sync/party_protocol.dart';
import 'package:musify/services/party_sync/party_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ValueListenableBuilder for discoveredRooms does not throw during layout/build',
      (tester) async {
    final service = PartySyncService.instance;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              return ValueListenableBuilder<List<PartyRoomInfo>>(
                valueListenable: service.discoveredRooms,
                builder: (context, rooms, _) {
                  return Text('Rooms: ${rooms.length}');
                },
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Rooms: 0'), findsOneWidget);

    // Call startDiscovery and pump
    await service.startDiscovery();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // Stop discovery and verify clean state
    service.stopDiscovery();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
