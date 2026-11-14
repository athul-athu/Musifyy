import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_multicast_lock/flutter_multicast_lock.dart';
import 'package:just_audio/just_audio.dart';
import 'package:musify/main.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/party_sync/party_clock_service.dart';
import 'package:musify/services/party_sync/party_drift_controller.dart';
import 'package:musify/services/party_sync/party_protocol.dart';
import 'package:musify/utilities/platform_utils.dart';

enum PartyRole {
  none,
  host,
  speaker,
}

enum PartyState {
  idle,
  hosting,
  discovering,
  connecting,
  connectedSpeaker,
}

class PartySyncService {
  PartySyncService._();
  static final PartySyncService instance = PartySyncService._();

  static const int discoveryPort = 41589;
  static const String discoveryProtocol = 'musify_party_v1';

  final ValueNotifier<PartyRole> role = ValueNotifier(PartyRole.none);
  final ValueNotifier<PartyState> state = ValueNotifier(PartyState.idle);
  final ValueNotifier<List<PartyRoomInfo>> discoveredRooms = ValueNotifier([]);
  final ValueNotifier<List<ConnectedSpeaker>> connectedSpeakers =
      ValueNotifier([]);
  final ValueNotifier<PartyRoomInfo?> currentRoom = ValueNotifier(null);

  final PartyClockService clock = PartyClockService();
  PartyDriftController? _driftController;

  final FlutterMulticastLock _multicastLock = FlutterMulticastLock();

  // Host properties
  HttpServer? _hostServer;
  RawDatagramSocket? _hostBroadcastSocket;
  Timer? _hostBroadcastTimer;
  Timer? _hostPlayScheduleTimer;
  Timer? _hostPrepareTimeoutTimer;
  final Map<WebSocket, ConnectedSpeaker> _clientSockets = {};
  Map? _currentHostSong;
  bool _isHostPlaying = false;
  int _lastKnownHostPositionMs = 0;

  // Speaker / Client properties
  WebSocket? _speakerSocket;
  RawDatagramSocket? _discoverySocket;
  Timer? _clockSyncTimer;
  Timer? _speakerStatusTimer;

  bool get isHost => role.value == PartyRole.host;
  bool get isSpeaker => role.value == PartyRole.speaker;
  bool get isInParty => role.value != PartyRole.none;

  int get calibrationOffsetMs =>
      _driftController?.manualCalibrationOffsetMs ?? 0;
  set calibrationOffsetMs(int value) {
    _driftController?.manualCalibrationOffsetMs = value;
  }

  int get lastMeasuredDriftMs => _driftController?.lastMeasuredDriftMs ?? 0;

  String get deviceName {
    if (kIsWeb) return 'Musify (Web)';
    if (isAndroidPlatform) return 'Musify (Android)';
    if (isIosPlatform) return 'Musify (iOS)';
    return 'Musify (${Platform.localHostname})';
  }

  String? get _currentSongTitle {
    try {
      return audioHandler.mediaItem.value?.title;
    } catch (_) {
      return null;
    }
  }

  int get _currentPositionMs {
    try {
      return audioHandler.audioPlayer.position.inMilliseconds;
    } catch (_) {
      return 0;
    }
  }

  // ===========================================================================
  // HOST IMPLEMENTATION
  // ===========================================================================

  /// Starts hosting a Party Room on the local network.
  Future<bool> startHosting({String? customRoomName}) async {
    await leaveParty();

    try {
      if (isAndroidPlatform) {
        try {
          await _multicastLock.acquireMulticastLock();
        } catch (_) {}
      }

      final hostIp = await _findLocalIp() ?? '127.0.0.1';
      _hostServer = await HttpServer.bind(InternetAddress.anyIPv4, 0);

      final roomCode = (1000 + Random().nextInt(9000)).toString();
      final roomName = customRoomName ?? '$deviceName Party';

      final room = PartyRoomInfo(
        id: roomCode,
        name: roomName,
        hostName: deviceName,
        ip: hostIp,
        port: _hostServer!.port,
        currentSongTitle: _currentSongTitle,
      );

      currentRoom.value = room;
      role.value = PartyRole.host;
      state.value = PartyState.hosting;
      connectedSpeakers.value = [];

      _hostServer!.listen(_handleHostHttpRequest);

      // Start UDP Room Discovery Broadcast
      await _startHostBroadcast(room);

      logger.log(
        'Party Host started on $hostIp:${_hostServer!.port} (Room Code: $roomCode)',
      );
      return true;
    } catch (e, st) {
      logger.log('Failed to start Party Host: $e', error: e, stackTrace: st);
      await leaveParty();
      return false;
    }
  }

  Future<void> _startHostBroadcast(PartyRoomInfo room) async {
    try {
      _hostBroadcastSocket =
          await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0)
            ..broadcastEnabled = true;

      _hostBroadcastTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _sendHostBroadcast(room),
      );
      _sendHostBroadcast(room);
    } catch (e) {
      logger.log('Could not initialize Party broadcast socket: $e');
    }
  }

  void _sendHostBroadcast(PartyRoomInfo room) {
    final socket = _hostBroadcastSocket;
    if (socket == null) return;

    final updatedRoom = PartyRoomInfo(
      id: room.id,
      name: room.name,
      hostName: room.hostName,
      ip: room.ip,
      port: room.port,
      speakersCount: _clientSockets.length,
      currentSongTitle: _currentSongTitle,
    );

    final payload = utf8.encode(
      jsonEncode({
        'protocol': discoveryProtocol,
        'room': updatedRoom.toJson(),
      }),
    );

    for (final broadcastAddress in [
      InternetAddress('255.255.255.255'),
      InternetAddress('${room.ip.substring(0, room.ip.lastIndexOf('.'))}.255'),
    ]) {
      try {
        socket.send(payload, broadcastAddress, discoveryPort);
      } catch (_) {}
    }
  }

  void _handleHostHttpRequest(HttpRequest request) async {
    if (request.uri.path == '/party/ws') {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        _handleIncomingClientSocket(socket);
      } else {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
      }
      return;
    }

    // Serve local/offline audio files to speakers if requested
    if (request.uri.path.startsWith('/party/audio/')) {
      final ytid = request.uri.pathSegments.last;
      String? localPath;
      for (final s in userOfflineSongs.value) {
        if (s['ytid'] == ytid && s['audioPath'] != null) {
          localPath = s['audioPath'] as String;
          break;
        }
      }
      if (localPath != null) {
        final file = File(localPath);
        if (await file.exists()) {
          request.response.headers.contentType = ContentType('audio', 'mpeg');
          await file.openRead().pipe(request.response);
          return;
        }
      }
    }

    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  void _handleIncomingClientSocket(WebSocket socket) {
    ConnectedSpeaker? speaker;

    socket.listen(
      (data) {
        final message = PartyMessage.tryDeserialize(data.toString());
        if (message == null) return;

        switch (message.type) {
          case PartyMessageType.join:
            final id = message.payload['id'] as String? ?? 'speaker';
            final name = message.payload['name'] as String? ?? 'Speaker';
            final platform =
                message.payload['platform'] as String? ?? 'unknown';
            final clientIp =
                message.payload['ip'] as String? ?? '0.0.0.0';

            speaker = ConnectedSpeaker(
              id: id,
              name: name,
              platform: platform,
              ip: clientIp,
            );
            _clientSockets[socket] = speaker!;
            _updateConnectedSpeakersList();

            // Send Welcome with current state
            final welcome = PartyMessage(
              type: PartyMessageType.welcome,
              payload: {
                'room': currentRoom.value?.toJson(),
                'song': _currentHostSong,
                'isPlaying': _isHostPlaying,
                'positionMs': _lastKnownHostPositionMs > 0
                    ? _lastKnownHostPositionMs
                    : _currentPositionMs,
              },
            );
            socket.add(welcome.serialize());

            // If a song is currently playing on the host, command the new speaker to prepare & sync
            if (_currentHostSong != null) {
              _sendPrepareToSocket(socket, _currentHostSong!);
            }
            break;

          case PartyMessageType.ping:
            final t0 = (message.payload['t0'] as num?)?.toInt() ?? 0;
            final t1 = clock.localNowMicros;
            final t2 = clock.localNowMicros;
            final pong = PartyMessage(
              type: PartyMessageType.pong,
              payload: {'t0': t0, 't1': t1, 't2': t2},
            );
            socket.add(pong.serialize());
            break;

          case PartyMessageType.ready:
            if (speaker != null) {
              speaker!
                ..isReady = true
                ..status = 'ready';
              _updateConnectedSpeakersList();

              if (_hostPrepareTimeoutTimer?.isActive == true) {
                final allReady = _clientSockets.values.every((s) => s.isReady);
                if (allReady) {
                  _hostPrepareTimeoutTimer?.cancel();
                  _triggerSynchronizedStart(positionMs: 0);
                }
              } else if (_isHostPlaying) {
                // Speaker joined while Host is ALREADY playing:
                // Automatically send synchronized play command to this newly ready speaker!
                final currentPos = _currentPositionMs;
                const leadTimeMs = 350;
                final targetHostTimeMs = clock.localNowMs + leadTimeMs;
                final playMsg = PartyMessage(
                  type: PartyMessageType.play,
                  payload: {
                    'positionMs': currentPos + leadTimeMs,
                    'targetHostTimeMs': targetHostTimeMs,
                  },
                );
                try {
                  socket.add(playMsg.serialize());
                } catch (_) {}
              }
            }
            break;

          case PartyMessageType.status:
            if (speaker != null) {
              speaker!.driftMs =
                  (message.payload['driftMs'] as num?)?.toInt() ?? 0;
              speaker!.rttMs =
                  (message.payload['rttMs'] as num?)?.toInt() ?? 0;
              speaker!.status =
                  message.payload['status'] as String? ?? 'playing';
              _updateConnectedSpeakersList();
            }
            break;

          case PartyMessageType.leave:
            _clientSockets.remove(socket);
            _updateConnectedSpeakersList();
            socket.close();
            break;

          default:
            break;
        }
      },
      onDone: () {
        _clientSockets.remove(socket);
        _updateConnectedSpeakersList();
      },
      onError: (_) {
        _clientSockets.remove(socket);
        _updateConnectedSpeakersList();
      },
    );
  }

  void _updateConnectedSpeakersList() {
    connectedSpeakers.value = _clientSockets.values.toList();
  }

  void _broadcastToSpeakers(PartyMessage message) {
    final raw = message.serialize();
    for (final socket in _clientSockets.keys) {
      try {
        socket.add(raw);
      } catch (_) {}
    }
  }

  void _sendPrepareToSocket(WebSocket socket, Map song) {
    final hostPort = _hostServer?.port ?? 0;
    final hostIp = currentRoom.value?.ip ?? '127.0.0.1';
    final isOffline = song['isOffline'] == true;
    final ytid = song['ytid'];

    final prepareMsg = PartyMessage(
      type: PartyMessageType.prepare,
      payload: {
        'song': song,
        'streamUrl': isOffline
            ? 'http://$hostIp:$hostPort/party/audio/$ytid'
            : null,
        'isHostStream': isOffline,
      },
    );
    socket.add(prepareMsg.serialize());
  }

  void _triggerSynchronizedStart({
    required int positionMs,
    int leadTimeMs = 350,
  }) {
    _hostPlayScheduleTimer?.cancel();
    final targetHostTimeMs = clock.localNowMs + leadTimeMs;

    final msg = PartyMessage(
      type: PartyMessageType.play,
      payload: {
        'positionMs': positionMs,
        'targetHostTimeMs': targetHostTimeMs,
      },
    );
    _broadcastToSpeakers(msg);

    // Host schedules its own playback at targetHostTimeMs
    _hostPlayScheduleTimer = Timer(Duration(milliseconds: leadTimeMs), () {
      if (isHost && _isHostPlaying) {
        unawaited(audioHandler.audioPlayer.play());
      }
    });
  }

  /// Coordinates a synchronized play/resume command for both Host and all connected Speakers.
  void coordinateHostPlay({
    required int positionMs,
    int leadTimeMs = 300,
  }) {
    if (!isHost) {
      unawaited(audioHandler.audioPlayer.play());
      return;
    }
    _isHostPlaying = true;
    _lastKnownHostPositionMs = positionMs;

    if (_clientSockets.isEmpty) {
      unawaited(audioHandler.audioPlayer.play());
      return;
    }

    _triggerSynchronizedStart(positionMs: positionMs, leadTimeMs: leadTimeMs);
  }

  /// Coordinates synchronized start of a new song on Host and all Speakers.
  void coordinateHostSongStart(Map song) {
    if (!isHost) return;
    _currentHostSong = song;
    _isHostPlaying = true;
    _lastKnownHostPositionMs = 0;

    // Reset readiness on speakers
    for (final s in _clientSockets.values) {
      s
        ..isReady = false
        ..status = 'buffering';
    }
    _updateConnectedSpeakersList();

    // Broadcast prepare to all speakers
    for (final socket in _clientSockets.keys) {
      _sendPrepareToSocket(socket, song);
    }

    if (_clientSockets.isEmpty) {
      unawaited(audioHandler.audioPlayer.play());
      return;
    }

    // Wait up to 1500ms for speakers to prepare, then start synchronized play
    _hostPrepareTimeoutTimer?.cancel();
    _hostPrepareTimeoutTimer = Timer(const Duration(milliseconds: 1500), () {
      _triggerSynchronizedStart(positionMs: 0);
    });
  }

  /// Coordinates synchronized pause on Host and all Speakers.
  void coordinateHostPause({required int positionMs}) {
    if (!isHost) return;
    _isHostPlaying = false;
    _lastKnownHostPositionMs = positionMs;
    _hostPlayScheduleTimer?.cancel();
    _hostPrepareTimeoutTimer?.cancel();

    final msg = PartyMessage(
      type: PartyMessageType.pause,
      payload: {'positionMs': positionMs},
    );
    _broadcastToSpeakers(msg);
  }

  /// Coordinates synchronized seek on Host and all Speakers.
  void coordinateHostSeek({
    required int positionMs,
    int leadTimeMs = 350,
  }) {
    if (!isHost) return;
    _lastKnownHostPositionMs = positionMs;
    _hostPlayScheduleTimer?.cancel();

    final targetHostTimeMs = clock.localNowMs + leadTimeMs;
    final msg = PartyMessage(
      type: PartyMessageType.seek,
      payload: {
        'positionMs': positionMs,
        'targetHostTimeMs': targetHostTimeMs,
      },
    );
    _broadcastToSpeakers(msg);

    if (_isHostPlaying) {
      _hostPlayScheduleTimer = Timer(Duration(milliseconds: leadTimeMs), () {
        if (isHost && _isHostPlaying) {
          unawaited(audioHandler.audioPlayer.play());
        }
      });
    }
  }

  // ===========================================================================
  // SPEAKER / CLIENT IMPLEMENTATION
  // ===========================================================================

  /// Starts listening for Party Rooms broadcasted on the local Wi-Fi.
  Future<void> startDiscovery() async {
    discoveredRooms.value = [];
    state.value = PartyState.discovering;

    try {
      if (isAndroidPlatform) {
        try {
          await _multicastLock.acquireMulticastLock();
        } catch (_) {}
      }

      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reusePort: true,
      );

      _discoverySocket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = _discoverySocket?.receive();
        if (datagram == null) return;

        try {
          final text = utf8.decode(datagram.data);
          final json = jsonDecode(text) as Map<String, dynamic>;
          if (json['protocol'] == discoveryProtocol && json['room'] != null) {
            final room = PartyRoomInfo.fromJson(
              (json['room'] as Map).cast<String, dynamic>(),
            );

            // Avoid adding own room if running in test / same device
            if (isHost && room.id == currentRoom.value?.id) return;

            final existing = List<PartyRoomInfo>.from(discoveredRooms.value);
            final index = existing.indexWhere((r) => r.id == room.id);
            if (index >= 0) {
              existing[index] = room;
            } else {
              existing.add(room);
            }
            discoveredRooms.value = existing;
          }
        } catch (_) {}
      });
    } catch (e) {
      logger.log('Could not start Party room discovery: $e');
    }
  }

  /// Stops room discovery.
  void stopDiscovery() {
    _discoverySocket?.close();
    _discoverySocket = null;
    if (state.value == PartyState.discovering) {
      state.value = PartyState.idle;
    }
  }

  /// Joins a discovered Party Room as a synchronized Speaker.
  Future<bool> joinRoom(PartyRoomInfo room) async {
    return joinByAddress(room.ip, room.port, roomInfo: room);
  }

  /// Joins a Party Room directly via IP and Port.
  Future<bool> joinByAddress(
    String ip,
    int port, {
    PartyRoomInfo? roomInfo,
  }) async {
    await leaveParty();
    stopDiscovery();

    state.value = PartyState.connecting;
    currentRoom.value = roomInfo ??
        PartyRoomInfo(
          id: 'manual',
          name: 'Party ($ip)',
          hostName: 'Host',
          ip: ip,
          port: port,
        );

    try {
      final wsUrl = Uri.parse('ws://$ip:$port/party/ws');
      _speakerSocket = await WebSocket.connect(
        wsUrl.toString(),
      ).timeout(const Duration(seconds: 6));

      role.value = PartyRole.speaker;
      state.value = PartyState.connectedSpeaker;

      clock.reset();
      _driftController = PartyDriftController(
        clock: clock,
        audioPlayer: audioHandler.audioPlayer,
      );

      _setupSpeakerSocketListener(_speakerSocket!);

      // Send Join Message
      final joinMsg = PartyMessage(
        type: PartyMessageType.join,
        payload: {
          'id': deviceName,
          'name': deviceName,
          'platform': defaultTargetPlatform.name,
          'ip': await _findLocalIp() ?? '127.0.0.1',
        },
      );
      _speakerSocket!.add(joinMsg.serialize());

      // Start Clock Sync Ping Loop
      _startClockSyncLoop();

      // Start Periodic Status Reporting
      _startSpeakerStatusReporting();

      logger.log('Joined Party Room at $ip:$port as Speaker');
      return true;
    } catch (e, st) {
      logger.log('Failed to join Party Room: $e', error: e, stackTrace: st);
      await leaveParty();
      return false;
    }
  }

  void _setupSpeakerSocketListener(WebSocket socket) {
    socket.listen(
      (data) async {
        final message = PartyMessage.tryDeserialize(data.toString());
        if (message == null) return;

        switch (message.type) {
          case PartyMessageType.pong:
            final t0 = (message.payload['t0'] as num?)?.toInt() ?? 0;
            final t1 = (message.payload['t1'] as num?)?.toInt() ?? 0;
            final t2 = (message.payload['t2'] as num?)?.toInt() ?? 0;
            final t3 = clock.localNowMicros;
            clock.recordSample(t0: t0, t1: t1, t2: t2, t3: t3);
            break;

          case PartyMessageType.welcome:
            // Sync with current song if playing
            final song = message.payload['song'] as Map?;
            if (song != null) {
              await _prepareSpeakerAudio(song);
            }
            break;

          case PartyMessageType.prepare:
            final song = message.payload['song'] as Map?;
            final streamUrl = message.payload['streamUrl'] as String?;
            if (song != null) {
              await _prepareSpeakerAudio(song, overrideUrl: streamUrl);
            }
            break;

          case PartyMessageType.play:
            final positionMs =
                (message.payload['positionMs'] as num?)?.toInt() ?? 0;
            final targetHostTimeMs =
                (message.payload['targetHostTimeMs'] as num?)?.toInt() ?? 0;

            final delay = clock.delayUntilHostTime(targetHostTimeMs);

            // Pre-seek immediately while paused so no seek lag occurs when the timer fires
            if (positionMs > 0 &&
                (audioHandler.audioPlayer.position.inMilliseconds - positionMs)
                        .abs() >
                    150) {
              unawaited(
                audioHandler.audioPlayer
                    .seek(Duration(milliseconds: positionMs)),
              );
            }

            Timer(delay, () async {
              if (role.value != PartyRole.speaker) return;
              try {
                await audioHandler.audioPlayer.play();
                _driftController?.onPlaybackScheduled(
                  startPositionMs: positionMs,
                  targetHostTimeMs: targetHostTimeMs,
                );
              } catch (e) {
                logger.log('Error executing synchronized play: $e');
              }
            });
            break;

          case PartyMessageType.pause:
            final positionMs =
                (message.payload['positionMs'] as num?)?.toInt() ?? 0;
            await audioHandler.audioPlayer.pause();
            _driftController?.onPlaybackPaused(positionMs: positionMs);
            break;

          case PartyMessageType.seek:
            final positionMs =
                (message.payload['positionMs'] as num?)?.toInt() ?? 0;
            final targetHostTimeMs =
                (message.payload['targetHostTimeMs'] as num?)?.toInt() ?? 0;
            final delay = clock.delayUntilHostTime(targetHostTimeMs);

            // Pre-seek immediately while paused
            unawaited(
              audioHandler.audioPlayer.seek(Duration(milliseconds: positionMs)),
            );

            Timer(delay, () async {
              if (role.value != PartyRole.speaker) return;
              try {
                await audioHandler.audioPlayer.play();
                _driftController?.onPlaybackScheduled(
                  startPositionMs: positionMs,
                  targetHostTimeMs: targetHostTimeMs,
                );
              } catch (_) {}
            });
            break;

          case PartyMessageType.roomClosed:
            await leaveParty();
            break;

          default:
            break;
        }
      },
      onDone: leaveParty,
      onError: (_) => leaveParty(),
    );
  }

  Future<void> _prepareSpeakerAudio(Map song, {String? overrideUrl}) async {
    try {
      final ytid = song['ytid'];
      if (overrideUrl != null && overrideUrl.isNotEmpty) {
        // Stream directly from Host's HTTP server
        final source = AudioSource.uri(Uri.parse(overrideUrl));
        await audioHandler.audioPlayer.setAudioSource(source);
      } else {
        // Prepare via standard Musify stream resolution
        await audioHandler.playSong(song);
        await audioHandler.audioPlayer.pause();
      }

      // Pre-buffer: wait until audio player has primed its decoder buffer
      try {
        await audioHandler.audioPlayer.playerStateStream
            .firstWhere(
              (s) =>
                  s.processingState == ProcessingState.ready ||
                  s.processingState == ProcessingState.buffering,
            )
            .timeout(const Duration(milliseconds: 1500));
      } catch (_) {}

      // Notify Host that this speaker is pre-buffered and ready
      final readyMsg = PartyMessage(
        type: PartyMessageType.ready,
        payload: {'ytid': ytid},
      );
      _speakerSocket?.add(readyMsg.serialize());
    } catch (e) {
      logger.log('Could not prepare speaker audio: $e');
    }
  }

  void _startClockSyncLoop() {
    _clockSyncTimer?.cancel();
    var pingsSent = 0;

    // Send 5 initial pings quickly (every 250ms), then steady state every 1.5s
    void sendPing() {
      if (_speakerSocket == null) return;
      final t0 = clock.localNowMicros;
      final ping = PartyMessage(
        type: PartyMessageType.ping,
        payload: {'t0': t0},
      );
      _speakerSocket?.add(ping.serialize());
      pingsSent++;
    }

    _clockSyncTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (role.value != PartyRole.speaker) {
        timer.cancel();
        return;
      }
      sendPing();
      if (pingsSent >= 5) {
        timer.cancel();
        _clockSyncTimer = Timer.periodic(
          const Duration(milliseconds: 1500),
          (_) => sendPing(),
        );
      }
    });
  }

  void _startSpeakerStatusReporting() {
    _speakerStatusTimer?.cancel();
    _speakerStatusTimer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) {
        if (_speakerSocket == null || role.value != PartyRole.speaker) return;
        final statusMsg = PartyMessage(
          type: PartyMessageType.status,
          payload: {
            'driftMs': lastMeasuredDriftMs,
            'rttMs': clock.rttMs,
            'status': audioHandler.audioPlayer.playing ? 'playing' : 'paused',
          },
        );
        _speakerSocket?.add(statusMsg.serialize());
      },
    );
  }

  // ===========================================================================
  // CLEANUP & LIFECYCLE
  // ===========================================================================

  /// Leaves or closes the active party session, cleaning up all sockets and timers.
  Future<void> leaveParty() async {
    if (isHost) {
      _broadcastToSpeakers(
        const PartyMessage(type: PartyMessageType.roomClosed),
      );
    } else if (isSpeaker) {
      try {
        _speakerSocket?.add(
          const PartyMessage(type: PartyMessageType.leave).serialize(),
        );
      } catch (_) {}
    }

    _hostBroadcastTimer?.cancel();
    _hostBroadcastTimer = null;
    _hostPlayScheduleTimer?.cancel();
    _hostPlayScheduleTimer = null;
    _hostPrepareTimeoutTimer?.cancel();
    _hostPrepareTimeoutTimer = null;
    _hostBroadcastSocket?.close();
    _hostBroadcastSocket = null;

    for (final s in _clientSockets.keys) {
      try {
        unawaited(s.close());
      } catch (_) {}
    }
    _clientSockets.clear();
    await _hostServer?.close(force: true);
    _hostServer = null;

    _clockSyncTimer?.cancel();
    _clockSyncTimer = null;
    _speakerStatusTimer?.cancel();
    _speakerStatusTimer = null;

    try {
      await _speakerSocket?.close();
    } catch (_) {}
    _speakerSocket = null;

    _discoverySocket?.close();
    _discoverySocket = null;

    _driftController?.dispose();
    _driftController = null;
    clock.reset();

    if (isAndroidPlatform) {
      try {
        await _multicastLock.releaseMulticastLock();
      } catch (_) {}
    }

    role.value = PartyRole.none;
    state.value = PartyState.idle;
    connectedSpeakers.value = [];
    currentRoom.value = null;
    _currentHostSong = null;
    _isHostPlaying = false;
  }

  Future<String?> _findLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && !addr.isLinkLocal) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return null;
  }
}

