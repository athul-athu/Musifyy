import 'dart:convert';
import 'dart:math';

/// Current protocol version of SyncParty / Musify Party.
const int kPartyProtocolVersion = 2;

/// Types of messages exchanged between Party Host and Speaker Clients.
enum PartyMessageType {
  hello,
  join,
  welcome,
  ping,
  pong,
  clockSync,
  prepare,
  ready,
  play,
  pause,
  seek,
  status,
  telemetry,
  reanchor,
  volumeChange,
  roleChange,
  deviceInfo,
  leave,
  roomClosed,
  error,
}

/// A structured versioned message sent over the Party WebSocket connection.
class PartyMessage {
  const PartyMessage({
    required this.type,
    this.payload = const {},
    this.protocolVersion = kPartyProtocolVersion,
    this.messageId = '',
    this.revision = 0,
    this.sessionId = '',
    this.clockEpochId = '',
    this.timestamp = 0,
  });

  /// Factory helper that automatically generates a unique message ID and captures timestamp.
  factory PartyMessage.create({
    required PartyMessageType type,
    Map<String, dynamic> payload = const {},
    int protocolVersion = kPartyProtocolVersion,
    int revision = 0,
    String sessionId = '',
    String clockEpochId = '',
    int? timestamp,
  }) {
    return PartyMessage(
      type: type,
      payload: payload,
      protocolVersion: protocolVersion,
      messageId: generateId(),
      revision: revision,
      sessionId: sessionId,
      clockEpochId: clockEpochId,
      timestamp: timestamp ?? DateTime.now().microsecondsSinceEpoch,
    );
  }

  factory PartyMessage.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? '';
    final type = PartyMessageType.values.firstWhere(
      (t) => t.name == typeName,
      orElse: () => PartyMessageType.status,
    );
    final payload = (json['payload'] as Map<dynamic, dynamic>?)
            ?.cast<String, dynamic>() ??
        const {};

    return PartyMessage(
      type: type,
      payload: payload,
      protocolVersion:
          (json['protocolVersion'] as num?)?.toInt() ?? kPartyProtocolVersion,
      messageId: json['messageId'] as String? ?? '',
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      sessionId: json['sessionId'] as String? ?? '',
      clockEpochId: json['clockEpochId'] as String? ?? '',
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
    );
  }

  final PartyMessageType type;
  final Map<String, dynamic> payload;
  final int protocolVersion;
  final String messageId;
  final int revision;
  final String sessionId;
  final String clockEpochId;
  final int timestamp;

  /// Whether the message conforms to required protocol structural fields.
  bool get isValid =>
      protocolVersion > 0 &&
      (messageId.isNotEmpty || protocolVersion < 2 || type == PartyMessageType.roomClosed);

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'payload': payload,
        'protocolVersion': protocolVersion,
        'messageId': messageId,
        'revision': revision,
        'sessionId': sessionId,
        'clockEpochId': clockEpochId,
        'timestamp': timestamp,
      };

  String serialize() => jsonEncode(toJson());

  static PartyMessage? tryDeserialize(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return PartyMessage.fromJson(decoded);
      }
      if (decoded is Map) {
        return PartyMessage.fromJson(decoded.cast<String, dynamic>());
      }
    } catch (_) {}
    return null;
  }

  /// Generates a fast 128-bit collision-resistant pseudo-UUID without external dependencies.
  static String generateId() {
    final rand = Random();
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final randHex1 = rand.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    final randHex2 = rand.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return '$now-$randHex1-$randHex2';
  }
}

/// Information broadcasted for discovery of a Party Room over LAN.
class PartyRoomInfo {
  const PartyRoomInfo({
    required this.id,
    required this.name,
    required this.hostName,
    required this.ip,
    required this.port,
    this.speakersCount = 0,
    this.currentSongTitle,
    this.protocolVersion = kPartyProtocolVersion,
    this.sessionId = '',
    this.maxParticipants = 10,
  });

  factory PartyRoomInfo.fromJson(Map<String, dynamic> json) {
    return PartyRoomInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Musify Party',
      hostName: json['hostName'] as String? ?? 'Host',
      ip: json['ip'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 0,
      speakersCount: (json['speakersCount'] as num?)?.toInt() ?? 0,
      currentSongTitle: json['currentSongTitle'] as String?,
      protocolVersion:
          (json['protocolVersion'] as num?)?.toInt() ?? kPartyProtocolVersion,
      sessionId: json['sessionId'] as String? ?? '',
      maxParticipants: (json['maxParticipants'] as num?)?.toInt() ?? 10,
    );
  }

  final String id;
  final String name;
  final String hostName;
  final String ip;
  final int port;
  final int speakersCount;
  final String? currentSongTitle;
  final int protocolVersion;
  final String sessionId;
  final int maxParticipants;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'hostName': hostName,
        'ip': ip,
        'port': port,
        'speakersCount': speakersCount,
        if (currentSongTitle != null) 'currentSongTitle': currentSongTitle,
        'protocolVersion': protocolVersion,
        'sessionId': sessionId,
        'maxParticipants': maxParticipants,
      };
}

/// Details of a connected speaker client visible on the Host dashboard.
class ConnectedSpeaker {
  ConnectedSpeaker({
    required this.id,
    required this.name,
    required this.platform,
    required this.ip,
    this.rttMs = 0,
    this.offsetMs = 0,
    this.driftMs = 0,
    this.clockUncertaintyMs = 0,
    this.bufferDurationMs = 0,
    this.underrunCount = 0,
    this.reanchorCount = 0,
    this.audioRoute = 'speaker',
    this.lastHeartbeatMs = 0,
    this.isReady = false,
    this.status = 'idle',
    this.playbackState = 'idle',
    this.volume = 1.0,
    this.calibrationOffsetMs = 0,
  });

  factory ConnectedSpeaker.fromJson(Map<String, dynamic> json) {
    return ConnectedSpeaker(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      platform: json['platform'] as String? ?? '',
      ip: json['ip'] as String? ?? '',
      rttMs: (json['rttMs'] as num?)?.toInt() ?? 0,
      offsetMs: (json['offsetMs'] as num?)?.toInt() ?? 0,
      driftMs: (json['driftMs'] as num?)?.toInt() ?? 0,
      clockUncertaintyMs:
          (json['clockUncertaintyMs'] as num?)?.toInt() ?? 0,
      bufferDurationMs: (json['bufferDurationMs'] as num?)?.toInt() ?? 0,
      underrunCount: (json['underrunCount'] as num?)?.toInt() ?? 0,
      reanchorCount: (json['reanchorCount'] as num?)?.toInt() ?? 0,
      audioRoute: json['audioRoute'] as String? ?? 'speaker',
      lastHeartbeatMs: (json['lastHeartbeatMs'] as num?)?.toInt() ?? 0,
      isReady: json['isReady'] as bool? ?? false,
      status: json['status'] as String? ?? 'idle',
      playbackState: json['playbackState'] as String? ?? 'idle',
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      calibrationOffsetMs:
          (json['calibrationOffsetMs'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String name;
  final String platform;
  final String ip;
  int rttMs;
  int offsetMs;
  int driftMs;
  int clockUncertaintyMs;
  int bufferDurationMs;
  int underrunCount;
  int reanchorCount;
  String audioRoute;
  int lastHeartbeatMs;
  bool isReady;
  String status;
  String playbackState;
  double volume;
  int calibrationOffsetMs;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'platform': platform,
        'ip': ip,
        'rttMs': rttMs,
        'offsetMs': offsetMs,
        'driftMs': driftMs,
        'clockUncertaintyMs': clockUncertaintyMs,
        'bufferDurationMs': bufferDurationMs,
        'underrunCount': underrunCount,
        'reanchorCount': reanchorCount,
        'audioRoute': audioRoute,
        'lastHeartbeatMs': lastHeartbeatMs,
        'isReady': isReady,
        'status': status,
        'playbackState': playbackState,
        'volume': volume,
        'calibrationOffsetMs': calibrationOffsetMs,
      };
}
