import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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

  /// Jukebox control permission mode (DJ mode or Collaborative Jukebox).
  final ValueNotifier<PartyJukeboxMode> jukeboxMode =
      ValueNotifier(PartyJukeboxMode.collaborative);

  /// Synchronized party queue with requester info and votes.
  final ValueNotifier<List<PartyQueueItem>> partyQueue = ValueNotifier([]);

  /// Device ID for speaker (generated once per session).
  final String speakerDeviceId = PartyMessage.generateId();

  final Map<String, PartyQueueItem> _queueItemMetadata = {};
  StreamSubscription<List<Map>>? _hostQueueSubscription;
  StreamSubscription<MediaItem?>? _hostMediaItemSubscription;
  bool _isReorderingQueue = false;

  void _safeSet<T>(ValueNotifier<T> notifier, T newValue) {
    if (notifier.value == newValue) return;
    try {
      final binding = WidgetsBinding.instance;
      if (binding.schedulerPhase != SchedulerPhase.idle) {
        binding.addPostFrameCallback((_) {
          notifier.value = newValue;
        });
        return;
      }
    } catch (_) {}
    notifier.value = newValue;
  }

  void _safeSetList<T>(ValueNotifier<List<T>> notifier, List<T> newList) {
    if (notifier.value.isEmpty && newList.isEmpty) return;
    if (listEquals(notifier.value, newList)) return;
    _safeSet(notifier, newList);
  }

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
  String? _currentHostStreamUrl;
  bool _isHostPlaying = false;
  bool _isHostResuming = false;
  bool _isHostSeeking = false;
  bool _pendingResumeAfterSeek = false;
  int _lastKnownHostPositionMs = 0;

  // Speaker / Client properties
  WebSocket? _speakerSocket;
  RawDatagramSocket? _discoverySocket;
  StreamSubscription<RawSocketEvent>? _discoverySubscription;
  Timer? _clockSyncTimer;
  Timer? _speakerStatusTimer;
  Timer? _speakerPlayScheduleTimer;
  int _userCalibrationOffsetMs = 0;

  String _sessionId = '';
  String _clockEpochId = '';
  int _revision = 0;

  bool get isHost => role.value == PartyRole.host;
  bool get isSpeaker => role.value == PartyRole.speaker;
  bool get isInParty => role.value != PartyRole.none;

  String get sessionId => _sessionId;
  String get clockEpochId => _clockEpochId;
  int get revision => _revision;
  SyncQuality get syncQuality => clock.quality;
  int get clockUncertaintyMs => clock.uncertaintyMs;
  double get clockDriftRatePpm => clock.driftRatePpm;
  int get reanchorCount => _driftController?.reanchorCount ?? 0;

  int get calibrationOffsetMs => _userCalibrationOffsetMs;
  set calibrationOffsetMs(int value) {
    _userCalibrationOffsetMs = value;
    _driftController?.manualCalibrationOffsetMs = value;
  }

  int get lastMeasuredDriftMs => _driftController?.lastMeasuredDriftMs ?? 0;

  String get deviceName {
    if (kIsWeb) return 'Musify (Web)';
    if (isAndroidPlatform) return 'Musify (Android)';
    if (isIosPlatform) return 'Musify (iOS)';
    return 'Musify (${Platform.localHostname})';
  }

  bool get _isAudioHandlerAvailable {
    try {
      audioHandler.toString();
      return true;
    } catch (_) {
      return false;
    }
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
    if (kIsWeb) {
      logger.log('Party hosting is not supported on web platforms');
      return false;
    }
    await leaveParty();

    try {
      if (isAndroidPlatform) {
        try {
          await _multicastLock.acquireMulticastLock();
        } catch (_) {}
      }

      final hostIp = await _findLocalIp() ?? '127.0.0.1';
      _hostServer = await HttpServer.bind(InternetAddress.anyIPv4, 0);

      _sessionId = PartyMessage.generateId();
      _clockEpochId = PartyMessage.generateId();
      _revision = 0;
      clock.setClockEpoch(_clockEpochId);

      final roomCode = (1000 + Random().nextInt(9000)).toString();
      final roomName = customRoomName ?? '$deviceName Party';

      final room = PartyRoomInfo(
        id: roomCode,
        name: roomName,
        hostName: deviceName,
        ip: hostIp,
        port: _hostServer!.port,
        currentSongTitle: _currentSongTitle,
        sessionId: _sessionId,
      );

      _safeSet(currentRoom, room);
      _safeSet(role, PartyRole.host);
      _safeSet(state, PartyState.hosting);
      _safeSetList(connectedSpeakers, <ConnectedSpeaker>[]);

      _queueItemMetadata.clear();
      if (_isAudioHandlerAvailable) {
        _syncHostPartyQueue(audioHandler.currentQueueList);
        unawaited(_hostQueueSubscription?.cancel());
        _hostQueueSubscription =
            audioHandler.queueAsMapStream.listen(_syncHostPartyQueue);
        unawaited(_hostMediaItemSubscription?.cancel());
        _hostMediaItemSubscription =
            audioHandler.mediaItem.listen(_updateHostCurrentPlayingItem);
      }

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
      Future.delayed(
        const Duration(milliseconds: 150),
        () => _sendHostBroadcast(room),
      );
      Future.delayed(
        const Duration(milliseconds: 400),
        () => _sendHostBroadcast(room),
      );
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
      sessionId: _sessionId,
    );

    final payload = utf8.encode(
      jsonEncode({
        'protocol': discoveryProtocol,
        'room': updatedRoom.toJson(),
      }),
    );

    final broadcastAddresses = <InternetAddress>[
      InternetAddress('255.255.255.255'),
    ];
    if (room.ip.contains('.')) {
      final lastDot = room.ip.lastIndexOf('.');
      if (lastDot > 0) {
        final subnetPrefix = room.ip.substring(0, lastDot);
        if (subnetPrefix != '127.0.0') {
          broadcastAddresses.add(InternetAddress('$subnetPrefix.255'));
        }
      }
    }

    for (final broadcastAddress in broadcastAddresses) {
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
            final welcome = PartyMessage.create(
              type: PartyMessageType.welcome,
              sessionId: _sessionId,
              clockEpochId: _clockEpochId,
              revision: ++_revision,
              payload: {
                'room': currentRoom.value?.toJson(),
                'song': _currentHostSong,
                'isPlaying': _isHostPlaying,
                'positionMs': _lastKnownHostPositionMs > 0
                    ? _lastKnownHostPositionMs
                    : _currentPositionMs,
                'sessionId': _sessionId,
                'clockEpochId': _clockEpochId,
                'jukeboxMode': jukeboxMode.value.name,
                'queue': partyQueue.value.map((e) => e.toJson()).toList(),
              },
            );
            socket.add(welcome.serialize());

            // Send immediate queue update to new speaker
            final queueMsg = PartyMessage.create(
              type: PartyMessageType.queueUpdate,
              sessionId: _sessionId,
              revision: ++_revision,
              payload: {
                'items': partyQueue.value.map((item) => item.toJson()).toList(),
                'jukeboxMode': jukeboxMode.value.name,
              },
            );
            socket.add(queueMsg.serialize());

            // If a song is currently playing on the host, command the new speaker to prepare & sync
            if (_currentHostSong != null) {
              _sendPrepareToSocket(
                socket,
                _currentHostSong!,
                overrideStreamUrl: _currentHostStreamUrl,
              );
            }
            break;

          case PartyMessageType.ping:
            final t0 = (message.payload['t0'] as num?)?.toInt() ?? 0;
            final t1 = clock.localNowMicros;
            final t2 = clock.localNowMicros;
            final pong = PartyMessage.create(
              type: PartyMessageType.pong,
              sessionId: _sessionId,
              clockEpochId: _clockEpochId,
              revision: ++_revision,
              payload: {
                't0': t0,
                't1': t1,
                't2': t2,
                'clockEpochId': _clockEpochId,
              },
            );
            socket.add(pong.serialize());
            break;

          case PartyMessageType.ready:
            if (speaker != null) {
              speaker!.isReady = true;
              speaker!.status = 'ready';
              _updateConnectedSpeakersList();

              if (_isHostSeeking && _hostPrepareTimeoutTimer?.isActive == true) {
                final allReady = _clientSockets.values.every((s) => s.isReady);
                if (allReady) {
                  _hostPrepareTimeoutTimer?.cancel();
                  _isHostSeeking = false;
                  if (_pendingResumeAfterSeek) {
                    final leadTimeMs = _calculateSafeLeadTime();
                    _triggerSynchronizedStart(
                      positionMs: _lastKnownHostPositionMs,
                      leadTimeMs: leadTimeMs,
                    );
                  }
                }
              } else if (_isHostResuming && _hostPrepareTimeoutTimer?.isActive == true) {
                final allReady = _clientSockets.values.every((s) => s.isReady);
                if (allReady) {
                  _hostPrepareTimeoutTimer?.cancel();
                  _isHostResuming = false;
                  final leadTimeMs = _calculateSafeLeadTime();
                  _triggerSynchronizedStart(
                    positionMs: _lastKnownHostPositionMs,
                    leadTimeMs: leadTimeMs,
                  );
                }
              } else if (_hostPrepareTimeoutTimer?.isActive == true) {
                final allReady = _clientSockets.values.every((s) => s.isReady);
                if (allReady) {
                  _hostPrepareTimeoutTimer?.cancel();
                  final leadTimeMs = _calculateSafeLeadTime(baseMs: 2000);
                  _triggerSynchronizedStart(positionMs: 0, leadTimeMs: leadTimeMs);
                }
              } else if (_isHostPlaying) {
                // Speaker joined or finished buffering while Host is ALREADY playing:
                // Send synchronized play command only once per playback session
                if (speaker!.status != 'playing') {
                  final currentPos = _currentPositionMs;
                  final leadTimeMs = _calculateSafeLeadTime();
                  final targetHostTimeMs = clock.localNowMs + leadTimeMs;
                  final playMsg = PartyMessage.create(
                    type: PartyMessageType.play,
                    sessionId: _sessionId,
                    clockEpochId: _clockEpochId,
                    revision: ++_revision,
                    payload: {
                      'positionMs': currentPos + leadTimeMs,
                      'targetHostTimeMs': targetHostTimeMs,
                    },
                  );
                  try {
                    socket.add(playMsg.serialize());
                  } catch (_) {}
                  speaker!.status = 'playing';
                  _updateConnectedSpeakersList();
                }
              }
            }
            break;

          case PartyMessageType.status:
            if (speaker != null) {
              speaker!.driftMs =
                  (message.payload['driftMs'] as num?)?.toInt() ?? 0;
              speaker!.rttMs =
                  (message.payload['rttMs'] as num?)?.toInt() ?? 0;
              speaker!.clockUncertaintyMs =
                  (message.payload['clockUncertaintyMs'] as num?)?.toInt() ?? 0;
              speaker!.reanchorCount =
                  (message.payload['reanchorCount'] as num?)?.toInt() ?? 0;
              final incomingStatus = message.payload['status'] as String?;
              if (incomingStatus != null && incomingStatus.isNotEmpty) {
                speaker!.status = incomingStatus;
                if (incomingStatus == 'loading' || incomingStatus == 'buffering') {
                  speaker!.isReady = false;
                } else if (incomingStatus == 'ready' || incomingStatus == 'paused') {
                  speaker!.isReady = true;
                }
              }
              speaker!.playbackState =
                  message.payload['playbackState'] as String? ?? 'playing';
              speaker!.lastHeartbeatMs = DateTime.now().millisecondsSinceEpoch;
              _updateConnectedSpeakersList();
            }
            break;

          case PartyMessageType.requestSong:
            final song = (message.payload['song'] as Map<dynamic, dynamic>?)
                ?.cast<String, dynamic>();
            final requestedBy = message.payload['requestedBy'] as String? ??
                (speaker?.name ?? 'Guest');
            final requesterId = message.payload['requesterId'] as String? ??
                (speaker?.id ?? '');
            if (song != null) {
              unawaited(handleSongRequest(
                songData: song,
                requestedBy: requestedBy,
                requesterId: requesterId,
              ));
            }
            break;

          case PartyMessageType.voteSong:
            final ytid = message.payload['ytid'] as String? ?? '';
            final voterId = message.payload['voterId'] as String? ??
                (speaker?.id ?? '');
            if (ytid.isNotEmpty && voterId.isNotEmpty) {
              _applyVote(voterId, ytid);
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
    _safeSetList(connectedSpeakers, _clientSockets.values.toList());
  }

  void _broadcastToSpeakers(PartyMessage message) {
    final raw = message.serialize();
    for (final socket in _clientSockets.keys) {
      try {
        socket.add(raw);
      } catch (_) {}
    }
  }

  int _calculateSafeLeadTime({int baseMs = 1800}) {
    if (_clientSockets.isEmpty) return baseMs;
    var maxRtt = 0;
    for (final s in _clientSockets.values) {
      if (s.rttMs > maxRtt) maxRtt = s.rttMs;
    }
    return max(baseMs, (maxRtt * 2) + 1200);
  }

  void _sendPrepareToSocket(
    WebSocket socket,
    Map song, {
    String? overrideStreamUrl,
  }) {
    final hostPort = _hostServer?.port ?? 0;
    final hostIp = currentRoom.value?.ip ?? '127.0.0.1';
    final isOffline = song['isOffline'] == true;
    final ytid = song['ytid'];

    final prepareMsg = PartyMessage.create(
      type: PartyMessageType.prepare,
      sessionId: _sessionId,
      clockEpochId: _clockEpochId,
      revision: ++_revision,
      payload: {
        'song': song,
        'streamUrl': isOffline
            ? 'http://$hostIp:$hostPort/party/audio/$ytid'
            : (overrideStreamUrl ?? _currentHostStreamUrl),
        'isHostStream': isOffline,
      },
    );
    try {
      socket.add(prepareMsg.serialize());
    } catch (_) {}
  }

  void _triggerSynchronizedStart({
    required int positionMs,
    int leadTimeMs = 1800,
  }) {
    _hostPlayScheduleTimer?.cancel();
    final targetHostTimeMs = clock.localNowMs + leadTimeMs;

    final msg = PartyMessage.create(
      type: PartyMessageType.play,
      sessionId: _sessionId,
      clockEpochId: _clockEpochId,
      revision: ++_revision,
      payload: {
        'positionMs': positionMs,
        'targetHostTimeMs': targetHostTimeMs,
      },
    );
    _broadcastToSpeakers(msg);

    // Host schedules its own playback at targetHostTimeMs, compensating for hardware buffer latency
    final hostHardwareLatencyMs = isMobilePlatform ? 55 : 20;
    final effectiveHostDelayMs = max(0, leadTimeMs - hostHardwareLatencyMs);

    _hostPlayScheduleTimer = Timer(Duration(milliseconds: effectiveHostDelayMs), () {
      if (isHost && _isHostPlaying) {
        unawaited(audioHandler.audioPlayer.play());
        for (final s in _clientSockets.values) {
          if (s.isReady) {
            s.status = 'playing';
          }
        }
        _updateConnectedSpeakersList();
      }
    });
  }

  /// Coordinates a synchronized play/resume command with a two-phase readiness handshake.
  void coordinateHostPlay({
    required int positionMs,
    int? leadTimeMs,
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

    _hostPlayScheduleTimer?.cancel();
    _hostPrepareTimeoutTimer?.cancel();
    _isHostResuming = true;
    _isHostSeeking = false;

    // Reset readiness on speakers
    for (final s in _clientSockets.values) {
      s
        ..isReady = false
        ..status = 'buffering';
    }
    _updateConnectedSpeakersList();

    // Broadcast prepare-resume handshake probe to all speakers
    final probe = PartyMessage.create(
      type: PartyMessageType.reanchor,
      sessionId: _sessionId,
      clockEpochId: _clockEpochId,
      revision: ++_revision,
      payload: {
        'positionMs': positionMs,
        'action': 'prepareResume',
      },
    );
    _broadcastToSpeakers(probe);

    // Safety fallback: If any speaker drops or delays beyond 2500ms, start anyway
    _hostPrepareTimeoutTimer = Timer(const Duration(milliseconds: 2500), () {
      if (_isHostResuming && _isHostPlaying) {
        _isHostResuming = false;
        final effectiveLeadTime = leadTimeMs ?? _calculateSafeLeadTime();
        _triggerSynchronizedStart(
          positionMs: positionMs,
          leadTimeMs: effectiveLeadTime,
        );
      }
    });
  }

  /// Coordinates synchronized start of a new song on Host and all Speakers.
  void coordinateHostSongStart(Map song, {String? streamUrl}) {
    if (!isHost) return;
    _currentHostSong = song;
    _currentHostStreamUrl = streamUrl;
    _isHostPlaying = true;
    _lastKnownHostPositionMs = 0;

    final currentYtid = (song['ytid'] ?? song['id'] ?? '').toString();
    if (partyQueue.value.isNotEmpty) {
      _safeSetList(
        partyQueue,
        partyQueue.value.map((item) {
          return item.copyWith(isPlaying: item.ytid == currentYtid);
        }).toList(),
      );
      _broadcastQueueUpdate();
    }

    // Reset readiness on speakers and mark as loading
    for (final s in _clientSockets.values) {
      s
        ..isReady = false
        ..status = 'loading';
    }
    _updateConnectedSpeakersList();

    // Broadcast prepare to all speakers
    for (final socket in _clientSockets.keys) {
      _sendPrepareToSocket(socket, song, overrideStreamUrl: streamUrl);
    }

    if (_clientSockets.isEmpty) {
      unawaited(audioHandler.audioPlayer.play());
      return;
    }

    // Wait up to 8000ms for speakers to prepare, then start synchronized play
    _hostPrepareTimeoutTimer?.cancel();
    _hostPrepareTimeoutTimer = Timer(const Duration(milliseconds: 8000), () {
      final leadTimeMs = _calculateSafeLeadTime(baseMs: 2000);
      _triggerSynchronizedStart(positionMs: 0, leadTimeMs: leadTimeMs);
    });
  }

  /// Coordinates synchronized pause on Host and all Speakers.
  void coordinateHostPause({required int positionMs}) {
    if (!isHost) return;
    _isHostPlaying = false;
    _isHostResuming = false;
    _isHostSeeking = false;
    _pendingResumeAfterSeek = false;
    _lastKnownHostPositionMs = positionMs;
    _hostPlayScheduleTimer?.cancel();
    _hostPrepareTimeoutTimer?.cancel();

    for (final s in _clientSockets.values) {
      s.status = 'paused';
    }
    _updateConnectedSpeakersList();

    final msg = PartyMessage.create(
      type: PartyMessageType.pause,
      sessionId: _sessionId,
      clockEpochId: _clockEpochId,
      revision: ++_revision,
      payload: {
        'positionMs': positionMs,
        'hostTimeMs': clock.localNowMs,
      },
    );
    _broadcastToSpeakers(msg);
  }

  /// Coordinates synchronized seek on Host and all Speakers with two-phase handshake.
  void coordinateHostSeek({
    required int positionMs,
    bool resumePlayback = true,
    int? leadTimeMs,
  }) {
    if (!isHost) return;
    _lastKnownHostPositionMs = positionMs;
    _hostPlayScheduleTimer?.cancel();
    _hostPrepareTimeoutTimer?.cancel();

    if (_clientSockets.isEmpty) {
      if (resumePlayback) {
        unawaited(audioHandler.audioPlayer.play());
      }
      return;
    }

    _isHostSeeking = true;
    _pendingResumeAfterSeek = resumePlayback;
    _isHostResuming = false;

    // Reset readiness on speakers
    for (final s in _clientSockets.values) {
      s
        ..isReady = false
        ..status = 'buffering';
    }
    _updateConnectedSpeakersList();

    // Broadcast seek prepare command to all speakers
    final msg = PartyMessage.create(
      type: PartyMessageType.seek,
      sessionId: _sessionId,
      clockEpochId: _clockEpochId,
      revision: ++_revision,
      payload: {
        'positionMs': positionMs,
        'requiresAck': true,
        'resumePlayback': resumePlayback,
      },
    );
    _broadcastToSpeakers(msg);

    // Timeout safety fallback: if any speaker takes longer than 3500ms, proceed anyway
    _hostPrepareTimeoutTimer = Timer(const Duration(milliseconds: 3500), () {
      if (_isHostSeeking) {
        _isHostSeeking = false;
        if (_pendingResumeAfterSeek) {
          final effectiveLeadTime = leadTimeMs ?? _calculateSafeLeadTime();
          _triggerSynchronizedStart(
            positionMs: positionMs,
            leadTimeMs: effectiveLeadTime,
          );
        }
      }
    });
  }

  // ===========================================================================
  // COLLABORATIVE JUKEBOX & QUEUE METHODS
  // ===========================================================================

  /// Toggles between DJ Mode (host controls queue) and Collaborative Jukebox.
  void setJukeboxMode(PartyJukeboxMode mode) {
    if (!isHost) return;
    _safeSet(jukeboxMode, mode);
    final msg = PartyMessage.create(
      type: PartyMessageType.partyModeChange,
      sessionId: _sessionId,
      revision: ++_revision,
      payload: {'jukeboxMode': mode.name},
    );
    _broadcastToSpeakers(msg);
    _broadcastQueueUpdate();
  }

  /// Broadcasts the current party queue to all connected speaker devices.
  void _broadcastQueueUpdate() {
    if (!isHost) return;
    final msg = PartyMessage.create(
      type: PartyMessageType.queueUpdate,
      sessionId: _sessionId,
      revision: ++_revision,
      payload: {
        'items': partyQueue.value.map((item) => item.toJson()).toList(),
        'jukeboxMode': jukeboxMode.value.name,
      },
    );
    _broadcastToSpeakers(msg);
  }

  /// Reconciles host audioHandler queue with partyQueue, preserving metadata & votes.
  void _syncHostPartyQueue(List<Map> queueList) {
    if (!isHost || _isReorderingQueue) return;
    final currentIndex = audioHandler.currentQueueIndex;

    final updated = <PartyQueueItem>[];
    for (var i = 0; i < queueList.length; i++) {
      final song = queueList[i];
      final ytid = (song['ytid'] ?? song['id'] ?? '').toString();
      final meta = _queueItemMetadata[ytid];

      final item = PartyQueueItem(
        id: meta?.id ?? ytid,
        ytid: ytid,
        title: (song['title'] ?? meta?.title ?? 'Unknown').toString(),
        artist: (song['artist'] ?? meta?.artist ?? 'Unknown').toString(),
        artworkUrl: (song['artworkUrl'] ??
                song['image'] ??
                song['lowResImage'] ??
                song['highResImage'] ??
                meta?.artworkUrl)
            ?.toString(),
        requestedBy: meta?.requestedBy ?? 'Host',
        requesterId: meta?.requesterId ?? 'host',
        voters: meta?.voters ?? [],
        isPlaying: i == currentIndex,
        songData: Map<String, dynamic>.from(song),
      );
      _queueItemMetadata[ytid] = item;
      updated.add(item);
    }

    final validYtids = queueList
        .map((s) => (s['ytid'] ?? s['id'] ?? '').toString())
        .toSet();
    _queueItemMetadata.removeWhere((key, _) => !validYtids.contains(key));

    _safeSetList(partyQueue, updated);
    _broadcastQueueUpdate();
  }

  /// Updates isPlaying status on the active Party Queue when the track changes.
  void _updateHostCurrentPlayingItem(MediaItem? currentMedia) {
    if (!isHost || partyQueue.value.isEmpty) return;
    final currentYtid = currentMedia?.id ?? '';
    final updated = partyQueue.value.map((item) {
      final isPlaying =
          item.ytid == currentYtid || item.title == currentMedia?.title;
      if (item.isPlaying != isPlaying) {
        return item.copyWith(isPlaying: isPlaying);
      }
      return item;
    }).toList();
    _safeSetList(partyQueue, updated);
    _broadcastQueueUpdate();
  }

  /// Handles a guest song request on the Host.
  Future<void> handleSongRequest({
    required Map songData,
    required String requestedBy,
    required String requesterId,
  }) async {
    if (!isHost) return;
    if (jukeboxMode.value != PartyJukeboxMode.collaborative) return;

    final ytid = (songData['ytid'] ?? songData['id'] ?? '').toString();
    if (ytid.isEmpty) return;

    // Check if song already exists in party queue
    final existingIndex =
        partyQueue.value.indexWhere((item) => item.ytid == ytid);
    if (existingIndex != -1) {
      _applyVote(requesterId, ytid);
      return;
    }

    final newItem = PartyQueueItem(
      id: ytid,
      ytid: ytid,
      title: (songData['title'] ?? 'Unknown').toString(),
      artist: (songData['artist'] ?? 'Unknown').toString(),
      artworkUrl: (songData['artworkUrl'] ??
              songData['image'] ??
              songData['lowResImage'] ??
              songData['highResImage'])
          ?.toString(),
      requestedBy: requestedBy,
      requesterId: requesterId,
      voters: [if (requesterId.isNotEmpty) requesterId],
      songData: Map<String, dynamic>.from(songData),
    );

    _queueItemMetadata[ytid] = newItem;
    if (_isAudioHandlerAvailable) {
      await audioHandler.addToQueue(songData);
      _syncHostPartyQueue(audioHandler.currentQueueList);
    } else {
      _safeSetList(partyQueue, [...partyQueue.value, newItem]);
      _broadcastQueueUpdate();
    }
    _reorderQueueByVotes();
  }

  /// Toggles an upvote on a queued song by device ID.
  void _applyVote(String voterId, String ytid) {
    if (!isHost) return;
    if (jukeboxMode.value != PartyJukeboxMode.collaborative &&
        voterId != 'host') {
      return;
    }

    final meta = _queueItemMetadata[ytid];
    if (meta != null) {
      final voters = List<String>.from(meta.voters);
      if (voters.contains(voterId)) {
        voters.remove(voterId);
      } else {
        voters.add(voterId);
      }
      _queueItemMetadata[ytid] = meta.copyWith(voters: voters);
    } else {
      final queueIdx =
          partyQueue.value.indexWhere((item) => item.ytid == ytid);
      if (queueIdx != -1) {
        final item = partyQueue.value[queueIdx];
        final voters = List<String>.from(item.voters);
        if (voters.contains(voterId)) {
          voters.remove(voterId);
        } else {
          voters.add(voterId);
        }
        _queueItemMetadata[ytid] = item.copyWith(voters: voters);
      }
    }

    if (_isAudioHandlerAvailable) {
      _syncHostPartyQueue(audioHandler.currentQueueList);
    } else {
      final queueIdx =
          partyQueue.value.indexWhere((item) => item.ytid == ytid);
      if (queueIdx != -1) {
        final q = List<PartyQueueItem>.from(partyQueue.value);
        final item = q[queueIdx];
        final voters = List<String>.from(item.voters);
        if (voters.contains(voterId)) {
          voters.remove(voterId);
        } else {
          voters.add(voterId);
        }
        q[queueIdx] = item.copyWith(voters: voters);
        _safeSetList(partyQueue, q);
      }
    }
    _reorderQueueByVotes();
  }

  /// Re-sorts upcoming queue items by vote count descending and updates audioHandler.
  void _reorderQueueByVotes() {
    if (!isHost || partyQueue.value.length < 2) return;
    final currentIdx =
        _isAudioHandlerAvailable ? audioHandler.currentQueueIndex : 0;
    final splitIndex = currentIdx >= 0 ? currentIdx + 1 : 1;
    if (splitIndex >= partyQueue.value.length) return;

    final played = partyQueue.value.sublist(0, splitIndex);
    final upcoming = partyQueue.value.sublist(splitIndex)
      ..sort((a, b) => b.voteCount.compareTo(a.voteCount));

    final targetOrder = [...played, ...upcoming];

    if (_isAudioHandlerAvailable) {
      _isReorderingQueue = true;
      try {
        for (var i = splitIndex; i < targetOrder.length; i++) {
          final ytid = targetOrder[i].ytid;
          final currentAudioIdx = audioHandler.currentQueueList.indexWhere(
            (s) => (s['ytid'] ?? s['id'] ?? '').toString() == ytid,
          );
          if (currentAudioIdx != -1 && currentAudioIdx != i) {
            audioHandler.reorderQueue(currentAudioIdx, i);
          }
        }
      } finally {
        _isReorderingQueue = false;
      }
    }

    _safeSetList(partyQueue, targetOrder);
    _broadcastQueueUpdate();
  }

  /// Allows Host to remove a song from the Party Queue.
  Future<void> removeSongFromPartyQueue(int index) async {
    if (!isHost) return;
    if (index >= 0 && index < partyQueue.value.length) {
      final ytid = partyQueue.value[index].ytid;
      _queueItemMetadata.remove(ytid);
      if (_isAudioHandlerAvailable) {
        await audioHandler.removeFromQueue(index);
      } else {
        final q = List<PartyQueueItem>.from(partyQueue.value)..removeAt(index);
        _safeSetList(partyQueue, q);
        _broadcastQueueUpdate();
      }
    }
  }

  /// Sends a song request to the Host (used by Speakers, or executed locally by Host).
  void requestSong(Map songData) {
    if (isHost) {
      unawaited(handleSongRequest(
        songData: songData,
        requestedBy: 'Host',
        requesterId: 'host',
      ));
      return;
    }
    if (!isSpeaker || _speakerSocket == null) return;
    final msg = PartyMessage.create(
      type: PartyMessageType.requestSong,
      sessionId: _sessionId,
      payload: {
        'song': songData,
        'requestedBy': deviceName,
        'requesterId': speakerDeviceId,
      },
    );
    try {
      _speakerSocket?.add(msg.serialize());
    } catch (_) {}
  }

  /// Toggles an upvote for a song (used by Speakers or Host).
  void toggleVote(String ytid) {
    if (isHost) {
      _applyVote('host', ytid);
      return;
    }
    if (!isSpeaker || _speakerSocket == null) return;
    final msg = PartyMessage.create(
      type: PartyMessageType.voteSong,
      sessionId: _sessionId,
      payload: {
        'ytid': ytid,
        'voterId': speakerDeviceId,
      },
    );
    try {
      _speakerSocket?.add(msg.serialize());
    } catch (_) {}
  }

  // ===========================================================================
  // SPEAKER / CLIENT IMPLEMENTATION
  // ===========================================================================

  /// Starts listening for Party Rooms broadcasted on the local Wi-Fi.
  Future<void> startDiscovery() async {
    _safeSetList(discoveredRooms, <PartyRoomInfo>[]);
    if (kIsWeb) {
      _safeSet(state, PartyState.idle);
      return;
    }
    _safeSet(state, PartyState.discovering);

    // If socket is already bound and actively listening, no need to re-bind
    if (_discoverySocket != null && _discoverySubscription != null) {
      return;
    }

    stopDiscovery();

    try {
      if (isAndroidPlatform) {
        try {
          await _multicastLock.acquireMulticastLock();
        } catch (_) {}
      }

      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
      );

      _discoverySubscription = _discoverySocket!.listen(
        (event) {
          if (event != RawSocketEvent.read) return;
          try {
            final datagram = _discoverySocket?.receive();
            if (datagram == null) return;

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
              _safeSetList(discoveredRooms, existing);
            }
          } catch (_) {}
        },
        onError: (e) {
          logger.log('Discovery socket stream error: $e');
        },
        cancelOnError: false,
      );
    } catch (e) {
      logger.log('Could not start Party room discovery: $e');
      stopDiscovery();
    }
  }

  /// Stops room discovery.
  void stopDiscovery() {
    try {
      _discoverySubscription?.cancel();
    } catch (_) {}
    _discoverySubscription = null;

    try {
      _discoverySocket?.close();
    } catch (_) {}
    _discoverySocket = null;

    if (state.value == PartyState.discovering) {
      _safeSet(state, PartyState.idle);
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
    if (kIsWeb) {
      logger.log('Party joining via raw sockets is not supported on web');
      return false;
    }
    await leaveParty();
    stopDiscovery();

    _safeSet(state, PartyState.connecting);
    _safeSet(
      currentRoom,
      roomInfo ??
          PartyRoomInfo(
            id: 'manual',
            name: 'Party ($ip)',
            hostName: 'Host',
            ip: ip,
            port: port,
          ),
    );

    try {
      final wsUrl = Uri.parse('ws://$ip:$port/party/ws');
      _speakerSocket = await WebSocket.connect(
        wsUrl.toString(),
      ).timeout(const Duration(seconds: 6));

      _safeSet(role, PartyRole.speaker);
      _safeSet(state, PartyState.connectedSpeaker);

      clock.reset();
      _driftController = PartyDriftController(
        clock: clock,
        audioPlayer: audioHandler.audioPlayer,
      )..manualCalibrationOffsetMs = _userCalibrationOffsetMs;

      _setupSpeakerSocketListener(_speakerSocket!);

      // Send Join Message
      final joinMsg = PartyMessage.create(
        type: PartyMessageType.join,
        sessionId: currentRoom.value?.sessionId ?? '',
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
            final epoch = message.clockEpochId.isNotEmpty
                ? message.clockEpochId
                : (message.payload['clockEpochId'] as String? ?? '');
            if (epoch.isNotEmpty && epoch != clock.clockEpochId) {
              clock.setClockEpoch(epoch);
            }
            final t0 = (message.payload['t0'] as num?)?.toInt() ?? 0;
            final t1 = (message.payload['t1'] as num?)?.toInt() ?? 0;
            final t2 = (message.payload['t2'] as num?)?.toInt() ?? 0;
            final t3 = clock.localNowMicros;
            clock.recordSample(t0: t0, t1: t1, t2: t2, t3: t3);
            break;

          case PartyMessageType.welcome:
            final epoch = message.clockEpochId.isNotEmpty
                ? message.clockEpochId
                : (message.payload['clockEpochId'] as String? ?? '');
            if (epoch.isNotEmpty) {
              clock.setClockEpoch(epoch);
            }
            final sess = message.sessionId.isNotEmpty
                ? message.sessionId
                : (message.payload['sessionId'] as String? ?? '');
            if (sess.isNotEmpty) {
              _sessionId = sess;
            }
            final welcomeQueue =
                message.payload['queue'] as List<dynamic>?;
            if (welcomeQueue != null) {
              _safeSetList(
                partyQueue,
                welcomeQueue
                    .map((e) => PartyQueueItem.fromJson(
                        Map<String, dynamic>.from(e as Map)))
                    .toList(),
              );
            }
            final welcomeMode = message.payload['jukeboxMode'] as String?;
            if (welcomeMode != null) {
              _safeSet(
                jukeboxMode,
                welcomeMode == PartyJukeboxMode.djOnly.name
                    ? PartyJukeboxMode.djOnly
                    : PartyJukeboxMode.collaborative,
              );
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

            _speakerPlayScheduleTimer?.cancel();

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

            // Acknowledge receipt of play command
            final playAck = PartyMessage.create(
              type: PartyMessageType.status,
              sessionId: _sessionId,
              clockEpochId: clock.clockEpochId,
              payload: {
                'status': 'ready',
                'isReady': true,
                'positionMs': positionMs,
              },
            );
            try {
              _speakerSocket?.add(playAck.serialize());
            } catch (_) {}

            final rawDelay = clock.delayUntilHostTime(targetHostTimeMs);

            // Compensate for hardware acoustic output latency (AudioTrack buffer fill)
            final hardwareLatencyMs = isMobilePlatform ? 55 : 20;
            final effectiveDelayMs = max(
              0,
              rawDelay.inMilliseconds -
                  hardwareLatencyMs +
                  _userCalibrationOffsetMs,
            );

            _speakerPlayScheduleTimer = Timer(Duration(milliseconds: effectiveDelayMs), () async {
              if (role.value != PartyRole.speaker) return;
              try {
                await audioHandler.audioPlayer.play();
                _driftController?.onPlaybackScheduled(
                  startPositionMs: positionMs,
                  targetHostTimeMs: targetHostTimeMs,
                );
                final playingMsg = PartyMessage.create(
                  type: PartyMessageType.status,
                  sessionId: _sessionId,
                  clockEpochId: clock.clockEpochId,
                  payload: {
                    'status': 'playing',
                    'playbackState': 'playing',
                  },
                );
                try {
                  _speakerSocket?.add(playingMsg.serialize());
                } catch (_) {}
              } catch (e) {
                logger.log('Error executing synchronized play: $e');
              }
            });
            break;

          case PartyMessageType.reanchor:
            final positionMs =
                (message.payload['positionMs'] as num?)?.toInt() ?? 0;
            _speakerPlayScheduleTimer?.cancel();
            try {
              await audioHandler.audioPlayer.pause();
            } catch (_) {}
            if (positionMs > 0 &&
                (audioHandler.audioPlayer.position.inMilliseconds - positionMs)
                        .abs() >
                    50) {
              unawaited(
                audioHandler.audioPlayer
                    .seek(Duration(milliseconds: positionMs)),
              );
            }
            _driftController?.onPlaybackPaused(positionMs: positionMs);

            // Acknowledge prepareResume probe so Host knows speaker is ready
            final resumeAck = PartyMessage.create(
              type: PartyMessageType.ready,
              sessionId: _sessionId,
              clockEpochId: clock.clockEpochId,
              payload: {
                'status': 'ready',
                'isReady': true,
                'positionMs': positionMs,
                'ackType': 'resume',
              },
            );
            try {
              _speakerSocket?.add(resumeAck.serialize());
            } catch (_) {}
            break;

          case PartyMessageType.pause:
            final positionMs =
                (message.payload['positionMs'] as num?)?.toInt() ?? 0;
            _speakerPlayScheduleTimer?.cancel();
            await audioHandler.audioPlayer.pause();
            if (positionMs > 0 &&
                (audioHandler.audioPlayer.position.inMilliseconds - positionMs)
                        .abs() >
                    100) {
              unawaited(
                audioHandler.audioPlayer
                    .seek(Duration(milliseconds: positionMs)),
              );
            }
            _driftController?.onPlaybackPaused(positionMs: positionMs);

            // Re-sync clock while paused to achieve millisecond precision
            _startClockSyncBurst();

            final pauseAck = PartyMessage.create(
              type: PartyMessageType.status,
              sessionId: _sessionId,
              clockEpochId: clock.clockEpochId,
              payload: {
                'status': 'paused',
                'isReady': true,
                'positionMs': positionMs,
              },
            );
            try {
              _speakerSocket?.add(pauseAck.serialize());
            } catch (_) {}
            break;

          case PartyMessageType.seek:
            final positionMs =
                (message.payload['positionMs'] as num?)?.toInt() ?? 0;
            final targetHostTimeMs =
                (message.payload['targetHostTimeMs'] as num?)?.toInt() ?? 0;

            _speakerPlayScheduleTimer?.cancel();

            // Pause immediately while seeking so no audio plays from old position
            try {
              await audioHandler.audioPlayer.pause();
            } catch (_) {}
            _driftController?.onPlaybackPaused(positionMs: positionMs);

            // Pre-seek to target position
            unawaited(
              audioHandler.audioPlayer.seek(Duration(milliseconds: positionMs)),
            );

            // Send "OK" (ready) acknowledgement back to Host immediately after seek
            final seekReadyAck = PartyMessage.create(
              type: PartyMessageType.ready,
              sessionId: _sessionId,
              clockEpochId: clock.clockEpochId,
              payload: {
                'status': 'ready',
                'isReady': true,
                'positionMs': positionMs,
                'ackType': 'seek',
              },
            );
            try {
              _speakerSocket?.add(seekReadyAck.serialize());
            } catch (_) {}

            if (targetHostTimeMs > 0) {
              final rawDelay = clock.delayUntilHostTime(targetHostTimeMs);
              final hardwareLatencyMs = isMobilePlatform ? 55 : 20;
              final effectiveDelayMs = max(
                0,
                rawDelay.inMilliseconds -
                    hardwareLatencyMs +
                    _userCalibrationOffsetMs,
              );

              _speakerPlayScheduleTimer = Timer(Duration(milliseconds: effectiveDelayMs), () async {
                if (role.value != PartyRole.speaker) return;
                try {
                  await audioHandler.audioPlayer.play();
                  _driftController?.onPlaybackScheduled(
                    startPositionMs: positionMs,
                    targetHostTimeMs: targetHostTimeMs,
                  );
                  final playingMsg = PartyMessage.create(
                    type: PartyMessageType.status,
                    sessionId: _sessionId,
                    clockEpochId: clock.clockEpochId,
                    payload: {
                      'status': 'playing',
                      'playbackState': 'playing',
                    },
                  );
                  try {
                    _speakerSocket?.add(playingMsg.serialize());
                  } catch (_) {}
                } catch (_) {}
              });
            }
            break;

          case PartyMessageType.queueUpdate:
            final rawItems =
                (message.payload['items'] as List<dynamic>?) ?? [];
            _safeSetList(
              partyQueue,
              rawItems
                  .map((e) => PartyQueueItem.fromJson(
                      Map<String, dynamic>.from(e as Map)))
                  .toList(),
            );
            final modeName = message.payload['jukeboxMode'] as String?;
            if (modeName != null) {
              _safeSet(
                jukeboxMode,
                modeName == PartyJukeboxMode.djOnly.name
                    ? PartyJukeboxMode.djOnly
                    : PartyJukeboxMode.collaborative,
              );
            }
            break;

          case PartyMessageType.partyModeChange:
            final modeName = message.payload['jukeboxMode'] as String?;
            if (modeName != null) {
              _safeSet(
                jukeboxMode,
                modeName == PartyJukeboxMode.djOnly.name
                    ? PartyJukeboxMode.djOnly
                    : PartyJukeboxMode.collaborative,
              );
            }
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

  String? _currentlyPreparedYtid;
  bool _isPreparingSpeakerAudio = false;
  int _speakerPrepareEpoch = 0;

  Future<void> _prepareSpeakerAudio(Map song, {String? overrideUrl}) async {
    final ytid = song['ytid']?.toString();
    if (ytid == null || ytid.isEmpty) return;

    if (_currentlyPreparedYtid == ytid && !_isPreparingSpeakerAudio) {
      final readyMsg = PartyMessage.create(
        type: PartyMessageType.ready,
        sessionId: _sessionId,
        clockEpochId: clock.clockEpochId,
        payload: {'ytid': ytid},
      );
      try {
        _speakerSocket?.add(readyMsg.serialize());
      } catch (_) {}
      return;
    }

    final currentEpoch = ++_speakerPrepareEpoch;
    _isPreparingSpeakerAudio = true;

    try {
      // 1. Pause current audio immediately so old track does not keep playing while loading new song
      try {
        await audioHandler.audioPlayer.pause();
      } catch (_) {}
      _driftController?.onPlaybackPaused(positionMs: 0);

      // 2. Immediately notify Host that this speaker is loading the new song
      final loadingMsg = PartyMessage.create(
        type: PartyMessageType.status,
        sessionId: _sessionId,
        clockEpochId: clock.clockEpochId,
        payload: {
          'status': 'loading',
          'ytid': ytid,
        },
      );
      try {
        _speakerSocket?.add(loadingMsg.serialize());
      } catch (_) {}

      if (currentEpoch != _speakerPrepareEpoch) return;

      // 3. Resolve stream URL: try host's overrideUrl first, fall back to direct fetch
      var streamUrl = overrideUrl;
      if (streamUrl == null || streamUrl.isEmpty) {
        streamUrl = await fetchSongStreamUrl(ytid, song['isLive'] ?? false);
      }

      if (currentEpoch != _speakerPrepareEpoch) return;

      if (streamUrl == null || streamUrl.isEmpty) {
        logger.log('Could not resolve stream URL for speaker: $ytid');
        return;
      }

      // 4. Update media item in UI so speaker sees title & artwork
      final mediaItem = MediaItem(
        id: ytid,
        title: song['title']?.toString() ?? 'Party Audio',
        artist: song['artist']?.toString() ?? 'Party Host',
        artUri: song['image'] != null
            ? Uri.tryParse(song['image'].toString())
            : null,
      );
      audioHandler.mediaItem.add(mediaItem);

      // 5. Pre-load audio source in paused state
      try {
        final source = AudioSource.uri(Uri.parse(streamUrl));
        await audioHandler.audioPlayer.setAudioSource(source);
      } catch (err) {
        if (overrideUrl != null && overrideUrl.isNotEmpty) {
          logger.log('Host stream URL failed on speaker, falling back to direct resolve: $err');
          streamUrl = await fetchSongStreamUrl(ytid, song['isLive'] ?? false);
          if (streamUrl != null &&
              streamUrl.isNotEmpty &&
              currentEpoch == _speakerPrepareEpoch) {
            final fallbackSource = AudioSource.uri(Uri.parse(streamUrl));
            await audioHandler.audioPlayer.setAudioSource(fallbackSource);
          } else {
            rethrow;
          }
        } else {
          rethrow;
        }
      }

      if (currentEpoch != _speakerPrepareEpoch) return;
      _currentlyPreparedYtid = ytid;

      // 6. Pre-buffer: wait until audio player has primed its decoder buffer
      try {
        await audioHandler.audioPlayer.playerStateStream
            .firstWhere(
              (s) =>
                  s.processingState == ProcessingState.ready ||
                  s.processingState == ProcessingState.buffering,
            )
            .timeout(const Duration(milliseconds: 6000));
      } catch (_) {}

      if (currentEpoch != _speakerPrepareEpoch) return;

      // 7. Notify Host that this speaker is pre-buffered and ready!
      final readyMsg = PartyMessage.create(
        type: PartyMessageType.ready,
        sessionId: _sessionId,
        clockEpochId: clock.clockEpochId,
        payload: {'ytid': ytid},
      );
      try {
        _speakerSocket?.add(readyMsg.serialize());
      } catch (_) {}
    } catch (e) {
      if (e is! PlatformException || e.code != 'abort') {
        logger.log('Could not prepare speaker audio: $e');
      }
    } finally {
      if (currentEpoch == _speakerPrepareEpoch) {
        _isPreparingSpeakerAudio = false;
      }
    }
  }

  void _startClockSyncBurst() {
    var count = 0;
    Timer.periodic(const Duration(milliseconds: 80), (timer) {
      if (_speakerSocket == null ||
          role.value != PartyRole.speaker ||
          count >= 5) {
        timer.cancel();
        return;
      }
      count++;
      final t0 = clock.localNowMicros;
      final ping = PartyMessage.create(
        type: PartyMessageType.ping,
        sessionId: _sessionId,
        clockEpochId: clock.clockEpochId,
        payload: {'t0': t0},
      );
      try {
        _speakerSocket?.add(ping.serialize());
      } catch (_) {
        timer.cancel();
      }
    });
  }

  void _startClockSyncLoop() {
    _clockSyncTimer?.cancel();
    var pingsSent = 0;

    // Send 8 initial pings quickly (every 200ms), then steady state every 1.5s
    void sendPing() {
      if (_speakerSocket == null) return;
      final t0 = clock.localNowMicros;
      final ping = PartyMessage.create(
        type: PartyMessageType.ping,
        sessionId: _sessionId,
        clockEpochId: clock.clockEpochId,
        payload: {'t0': t0},
      );
      _speakerSocket?.add(ping.serialize());
      pingsSent++;
    }

    _clockSyncTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (role.value != PartyRole.speaker) {
        timer.cancel();
        return;
      }
      sendPing();
      if (pingsSent >= 8) {
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
        final statusMsg = PartyMessage.create(
          type: PartyMessageType.status,
          sessionId: _sessionId,
          clockEpochId: clock.clockEpochId,
          payload: {
            'driftMs': lastMeasuredDriftMs,
            'rttMs': clock.rttMs,
            'clockUncertaintyMs': clock.uncertaintyMs,
            'reanchorCount': reanchorCount,
            'status': audioHandler.audioPlayer.playing ? 'playing' : 'paused',
            'playbackState': audioHandler.audioPlayer.playing ? 'playing' : 'paused',
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
        PartyMessage.create(
          type: PartyMessageType.roomClosed,
          sessionId: _sessionId,
          clockEpochId: _clockEpochId,
          revision: ++_revision,
        ),
      );
    } else if (isSpeaker) {
      try {
        _speakerSocket?.add(
          PartyMessage.create(
            type: PartyMessageType.leave,
            sessionId: _sessionId,
            clockEpochId: clock.clockEpochId,
          ).serialize(),
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
    _speakerPlayScheduleTimer?.cancel();
    _speakerPlayScheduleTimer = null;

    try {
      await _speakerSocket?.close();
    } catch (_) {}
    _speakerSocket = null;

    stopDiscovery();

    _currentlyPreparedYtid = null;
    _isPreparingSpeakerAudio = false;

    _driftController?.dispose();
    _driftController = null;
    clock.reset();

    if (isAndroidPlatform) {
      try {
        await _multicastLock.releaseMulticastLock();
      } catch (_) {}
    }

    await _hostQueueSubscription?.cancel();
    _hostQueueSubscription = null;
    await _hostMediaItemSubscription?.cancel();
    _hostMediaItemSubscription = null;
    _queueItemMetadata.clear();
    _safeSetList(partyQueue, <PartyQueueItem>[]);

    _safeSet(role, PartyRole.none);
    _safeSet(state, PartyState.idle);
    _safeSetList(connectedSpeakers, <ConnectedSpeaker>[]);
    _safeSet(currentRoom, null);
    _currentHostSong = null;
    _isHostPlaying = false;
    _isHostResuming = false;
    _isHostSeeking = false;
    _pendingResumeAfterSeek = false;
    _sessionId = '';
    _clockEpochId = '';
    _revision = 0;
  }

  Future<String?> _findLocalIp() async {
    if (kIsWeb) return null;
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );

      String? bestIp;
      var bestScore = -1;

      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();

        // Skip cellular data, tunnels, virtual interfaces, loopback
        if (name.startsWith('lo') ||
            name.startsWith('pdp_ip') ||
            name.startsWith('utun') ||
            name.startsWith('tun') ||
            name.startsWith('tap') ||
            name.startsWith('dummy')) {
          continue;
        }

        for (final addr in iface.addresses) {
          if (addr.isLoopback || addr.isLinkLocal) continue;
          final ip = addr.address;

          var score = 0;
          // High preference for standard Wi-Fi / Ethernet interface names (en0 is iOS/macOS Wi-Fi)
          if (name == 'en0' ||
              name == 'en1' ||
              name.contains('wlan') ||
              name.contains('wi-fi') ||
              name.contains('wifi') ||
              name.contains('eth')) {
            score += 100;
          }

          // Preference for standard private IPv4 ranges:
          if (ip.startsWith('192.168.')) {
            score += 50;
          } else if (ip.startsWith('10.')) {
            score += 40;
          } else if (RegExp(r'^172\.(1[6-9]|2[0-9]|3[0-1])\.').hasMatch(ip)) {
            score += 30;
          }

          if (score > bestScore) {
            bestScore = score;
            bestIp = ip;
          }
        }
      }

      if (bestIp != null) return bestIp;

      // Fallback: any non-loopback IPv4 address
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

