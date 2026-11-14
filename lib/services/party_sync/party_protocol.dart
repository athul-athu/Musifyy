import 'dart:convert';

/// Types of messages exchanged between Party Host and Speaker Clients.
enum PartyMessageType {
  hello,
  join,
  welcome,
  ping,
  pong,
  prepare,
  ready,
  play,
  pause,
  seek,
  status,
  leave,
  roomClosed,
}

/// A structured message sent over the Party WebSocket connection.
class PartyMessage {
  const PartyMessage({
    required this.type,
    this.payload = const {},
  });

  factory PartyMessage.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? '';
    final type = PartyMessageType.values.firstWhere(
      (t) => t.name == typeName,
      orElse: () => PartyMessageType.status,
    );
    final payload = (json['payload'] as Map<dynamic, dynamic>?)
            ?.cast<String, dynamic>() ??
        const {};
    return PartyMessage(type: type, payload: payload);
  }

  final PartyMessageType type;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'payload': payload,
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
    );
  }

  final String id;
  final String name;
  final String hostName;
  final String ip;
  final int port;
  final int speakersCount;
  final String? currentSongTitle;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'hostName': hostName,
        'ip': ip,
        'port': port,
        'speakersCount': speakersCount,
        if (currentSongTitle != null) 'currentSongTitle': currentSongTitle,
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
    this.isReady = false,
    this.status = 'idle',
    this.volume = 1.0,
    this.calibrationOffsetMs = 0,
  });

  final String id;
  final String name;
  final String platform;
  final String ip;
  int rttMs;
  int offsetMs;
  int driftMs;
  bool isReady;
  String status;
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
        'isReady': isReady,
        'status': status,
        'volume': volume,
        'calibrationOffsetMs': calibrationOffsetMs,
      };
}

