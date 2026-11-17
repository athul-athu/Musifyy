import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/party_sync/party_protocol.dart';
import 'package:musify/services/party_sync/party_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Party Jukebox Collaborative Queue & Voting', () {
    final service = PartySyncService.instance;

    setUp(() async {
      await service.leaveParty();
      await service.startHosting(customRoomName: 'Jukebox Test Party');
    });

    tearDown(() async {
      await service.leaveParty();
    });

    test('allows guest to request song and adds initial requester vote in collaborative mode', () async {
      service.setJukeboxMode(PartyJukeboxMode.collaborative);

      await service.handleSongRequest(
        songData: {
          'ytid': 'track-1',
          'title': 'Blinding Lights',
          'artist': 'The Weeknd',
        },
        requestedBy: 'Guest Phone',
        requesterId: 'speaker-device-1',
      );

      expect(service.partyQueue.value.length, 1);
      final item = service.partyQueue.value.first;
      expect(item.ytid, 'track-1');
      expect(item.title, 'Blinding Lights');
      expect(item.requestedBy, 'Guest Phone');
      expect(item.voteCount, 1);
      expect(item.hasVoted('speaker-device-1'), isTrue);
    });

    test('reorders upcoming songs by vote count descending', () async {
      service.setJukeboxMode(PartyJukeboxMode.collaborative);

      // Track 0 is the current song playing
      await service.handleSongRequest(
        songData: {
          'ytid': 'track-0',
          'title': 'Track Zero (Playing)',
          'artist': 'Artist 0',
        },
        requestedBy: 'Host',
        requesterId: 'host',
      );

      // Add track 1
      await service.handleSongRequest(
        songData: {
          'ytid': 'track-1',
          'title': 'Track One',
          'artist': 'Artist A',
        },
        requestedBy: 'Guest 1',
        requesterId: 'device-1',
      );

      // Add track 2
      await service.handleSongRequest(
        songData: {
          'ytid': 'track-2',
          'title': 'Track Two',
          'artist': 'Artist B',
        },
        requestedBy: 'Guest 2',
        requesterId: 'device-2',
      );

      // Initially track 1 is index 1, track 2 is index 2
      expect(service.partyQueue.value[1].ytid, 'track-1');
      expect(service.partyQueue.value[2].ytid, 'track-2');

      // Upvote track 2 from host so track 2 has 2 votes vs track 1 having 1 vote
      service.toggleVote('track-2');
      
      expect(service.partyQueue.value.length, 3);
      expect(service.partyQueue.value[0].ytid, 'track-0');
      expect(service.partyQueue.value[1].ytid, 'track-2');
      expect(service.partyQueue.value[1].voteCount, 2);
      expect(service.partyQueue.value[2].ytid, 'track-1');
      expect(service.partyQueue.value[2].voteCount, 1);
    });

    test('toggles vote when the same voter votes again', () async {
      service.setJukeboxMode(PartyJukeboxMode.collaborative);

      await service.handleSongRequest(
        songData: {
          'ytid': 'track-3',
          'title': 'Track Three',
          'artist': 'Artist C',
        },
        requestedBy: 'Guest 3',
        requesterId: 'device-3',
      );

      expect(service.partyQueue.value.first.voteCount, 1);

      // Toggle vote off from device-3
      service.toggleVote('track-3'); // host vote adds
      expect(service.partyQueue.value.first.voteCount, 2);

      service.toggleVote('track-3'); // host vote removes
      expect(service.partyQueue.value.first.voteCount, 1);
    });

    test('ignores song requests when in djOnly mode', () async {
      service.setJukeboxMode(PartyJukeboxMode.djOnly);

      await service.handleSongRequest(
        songData: {
          'ytid': 'track-4',
          'title': 'Track Four',
          'artist': 'Artist D',
        },
        requestedBy: 'Guest 4',
        requesterId: 'device-4',
      );

      expect(service.partyQueue.value.isEmpty, isTrue);
    });
  });
}
