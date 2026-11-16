import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/app_constants.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/services/party_sync/party_protocol.dart';
import 'package:musify/services/party_sync/party_sync_service.dart';
import 'package:musify/utilities/app_utils.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/utilities/platform_utils.dart';
import 'package:musify/widgets/custom_bar.dart';
import 'package:musify/widgets/mini_player_bottom_space.dart';
import 'package:musify/widgets/section_header.dart';
import 'package:musify/widgets/song_artwork.dart';

class PartyModePage extends StatefulWidget {
  const PartyModePage({super.key});

  @override
  State<PartyModePage> createState() => _PartyModePageState();
}

class _PartyModePageState extends State<PartyModePage> {
  final PartySyncService _service = PartySyncService.instance;
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();

  double _sliderOffset = 0;

  @override
  void initState() {
    super.initState();
    _sliderOffset = _service.calibrationOffsetMs.toDouble();
    if (!_service.isInParty && !kIsWeb) {
      _service.startDiscovery();
    }
    _service.role.addListener(_onRoleChanged);
  }

  void _onRoleChanged() {
    if (!mounted) return;
    if (_service.role.value == PartyRole.none && !kIsWeb) {
      _service.startDiscovery();
    }
  }

  @override
  void dispose() {
    _service.role.removeListener(_onRoleChanged);
    _ipController.dispose();
    _portController.dispose();
    if (!_service.isInParty && !kIsWeb) {
      _service.stopDiscovery();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(l10n.partyModeTitle),
        actions: [
          if (!kIsWeb)
            ValueListenableBuilder<PartyRole>(
              valueListenable: _service.role,
              builder: (context, role, _) {
                if (role == PartyRole.none) {
                  return IconButton(
                    icon: const Icon(FluentIcons.arrow_clockwise_24_regular),
                    tooltip: 'Refresh',
                    onPressed: () {
                      _service.startDiscovery();
                      showToast(context, 'Scanning for party rooms...');
                    },
                  );
                }
                return IconButton(
                  icon: const Icon(FluentIcons.dismiss_24_regular),
                  tooltip: role == PartyRole.host
                      ? l10n.partyEndButton
                      : l10n.partyLeaveButton,
                  onPressed: _service.leaveParty,
                );
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: commonSingleChildScrollViewPadding,
        child: ValueListenableBuilder<PartyRole>(
          valueListenable: _service.role,
          builder: (context, role, _) {
            switch (role) {
              case PartyRole.host:
                return _buildHostView(context);
              case PartyRole.speaker:
                return _buildSpeakerView(context);
              case PartyRole.none:
                return _buildIdleView(context);
            }
          },
        ),
      ),
    );
  }

  // ===========================================================================
  // IDLE VIEW (Host or Discover Rooms)
  // ===========================================================================

  Widget _buildIdleView(BuildContext context) {
    final l10n = context.l10n!;

    if (kIsWeb) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: l10n.partyModeTitle,
            icon: FluentIcons.speaker_2_24_filled,
          ),
          CustomBar(
            'Party Mode on Web',
            FluentIcons.info_24_regular,
            description:
                'Multi-device synchronized playback relies on native UDP multicast and local network sockets. '
                'Please use the Musify Android, iOS, or Desktop app to host or join group speaker parties.',
            borderRadius: commonCustomBarRadius,
          ),
          const SizedBox(height: 20),
          const MiniPlayerBottomSpace(),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: l10n.partyHostButton,
          icon: FluentIcons.speaker_2_24_filled,
        ),
        CustomBar(
          _service.deviceName,
          isMobilePlatform
              ? FluentIcons.phone_24_regular
              : FluentIcons.desktop_24_regular,
          description: l10n.partyModeDescription,
          borderRadius: commonCustomBarRadius,
          trailing: FilledButton.tonal(
            child: Text(l10n.partyHostButton),
            onPressed: () async {
              final success = await _service.startHosting();
              if (!mounted) return;
              if (!success) {
                showToast(context, 'Could not start Party Host.');
              }
            },
          ),
        ),
        const SizedBox(height: 20),
        SectionHeader(
          title: l10n.partyJoinButton,
          icon: FluentIcons.wifi_1_24_filled,
          actionButton: IconButton(
            icon: const Icon(FluentIcons.arrow_clockwise_24_regular),
            tooltip: 'Scan Again',
            onPressed: () {
              _service.startDiscovery();
              showToast(context, 'Scanning for party rooms...');
            },
          ),
        ),
        ValueListenableBuilder<List<PartyRoomInfo>>(
          valueListenable: _service.discoveredRooms,
          builder: (context, rooms, _) {
            if (rooms.isEmpty) {
              return CustomBar(
                'Searching for party rooms...',
                FluentIcons.wifi_1_24_regular,
                description: l10n.partyScanningRooms,
                borderRadius: commonCustomBarRadius,
                trailing: const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }

            return Column(
              children: [
                for (var i = 0; i < rooms.length; i++)
                  CustomBar(
                    rooms[i].name,
                    FluentIcons.speaker_2_24_regular,
                    description:
                        'Host: ${rooms[i].hostName} (${rooms[i].ip}:${rooms[i].port})'
                        '${rooms[i].currentSongTitle != null ? ' • Playing: ${rooms[i].currentSongTitle}' : ''}',
                    borderRadius: getItemBorderRadius(i, rooms.length),
                    trailing: FilledButton.tonal(
                      onPressed: () async {
                        final success = await _service.joinRoom(rooms[i]);
                        if (!context.mounted) return;
                        if (!success) {
                          showToast(context, 'Could not join ${rooms[i].name}. Host port may have changed.');
                        }
                      },
                      child: Text(l10n.partyJoinButton),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        const SectionHeader(
          title: 'Direct Connect',
          icon: FluentIcons.link_24_filled,
        ),
        CustomBar(
          l10n.partyManualJoin,
          FluentIcons.link_24_regular,
          description: 'Connect directly using Host IP and Port',
          borderRadius: commonCustomBarRadius,
          trailing: const Icon(FluentIcons.chevron_right_24_regular),
          onTap: () => _showManualJoinDialog(context),
        ),
        const SizedBox(height: 20),
        const MiniPlayerBottomSpace(),
      ],
    );
  }

  // ===========================================================================
  // HOST VIEW
  // ===========================================================================

  Widget _buildHostView(BuildContext context) {
    final l10n = context.l10n!;
    final theme = Theme.of(context);
    final room = _service.currentRoom.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Active Room',
          icon: FluentIcons.speaker_2_24_filled,
        ),
        CustomBar(
          room?.name ?? 'Musify Party',
          FluentIcons.speaker_2_24_filled,
          iconColor: theme.colorScheme.primary,
          description:
              '${l10n.partyRoomCode(room?.id ?? '----')} • IP: ${room?.ip}:${room?.port}',
          borderRadius: commonCustomBarRadius,
          trailing: FilledButton.tonal(
            onPressed: _service.leaveParty,
            child: Text(l10n.partyEndButton),
          ),
        ),
        StreamBuilder(
          stream: audioHandler.mediaItem,
          builder: (context, snapshot) {
            final mediaItem = snapshot.data;
            if (mediaItem == null) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                const SectionHeader(
                  title: 'Now Streaming',
                  icon: FluentIcons.music_note_2_24_filled,
                ),
                Material(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: commonCustomBarRadius,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => context.push('/now-playing'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      child: Row(
                        children: [
                          SongArtworkWidget(
                            size: 52,
                            metadata: mediaItem,
                            borderRadius: 12,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  mediaItem.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  mediaItem.artist ?? 'Unknown Artist',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            FluentIcons.chevron_right_24_regular,
                            size: 20,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        ValueListenableBuilder<List<ConnectedSpeaker>>(
          valueListenable: _service.connectedSpeakers,
          builder: (context, speakers, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: l10n.partySpeakersConnected(speakers.length),
                  icon: FluentIcons.phone_24_filled,
                ),
                if (speakers.isEmpty)
                  CustomBar(
                    'Waiting for speakers...',
                    FluentIcons.phone_24_regular,
                    description: l10n.partyNoSpeakersYet,
                    borderRadius: commonCustomBarRadius,
                  )
                else
                  for (var i = 0; i < speakers.length; i++)
                    CustomBar(
                      speakers[i].name,
                      speakers[i].name.toLowerCase().contains('desktop') ||
                              speakers[i].name.toLowerCase().contains('windows')
                          ? FluentIcons.desktop_24_regular
                          : FluentIcons.phone_24_regular,
                      description:
                          '${speakers[i].ip} • Ping: ${speakers[i].rttMs}ms • Drift: ${speakers[i].driftMs}ms',
                      borderRadius: getItemBorderRadius(i, speakers.length),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: speakers[i].status == 'playing' ||
                                  speakers[i].status == 'ready'
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              speakers[i].status == 'playing'
                                  ? FluentIcons.speaker_2_16_filled
                                  : FluentIcons.checkmark_16_regular,
                              size: 13,
                              color: speakers[i].status == 'playing' ||
                                      speakers[i].status == 'ready'
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              speakers[i].status == 'playing'
                                  ? 'Playing'
                                  : 'Ready',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: speakers[i].status == 'playing' ||
                                        speakers[i].status == 'ready'
                                    ? theme.colorScheme.onPrimaryContainer
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        const MiniPlayerBottomSpace(),
      ],
    );
  }

  // ===========================================================================
  // SPEAKER VIEW
  // ===========================================================================

  Widget _buildSpeakerView(BuildContext context) {
    final l10n = context.l10n!;
    final theme = Theme.of(context);
    final room = _service.currentRoom.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Connected Room',
          icon: FluentIcons.speaker_2_24_filled,
        ),
        CustomBar(
          l10n.partyConnectedTo(room?.name ?? 'Host'),
          FluentIcons.speaker_2_24_filled,
          iconColor: theme.colorScheme.primary,
          description:
              'Host: ${room?.ip}:${room?.port} • Ping: ${_service.clock.rttMs}ms',
          borderRadius: commonCustomBarRadius,
          trailing: FilledButton.tonal(
            onPressed: _service.leaveParty,
            child: Text(l10n.partyLeaveButton),
          ),
        ),
        StreamBuilder(
          stream: audioHandler.mediaItem,
          builder: (context, snapshot) {
            final mediaItem = snapshot.data;
            if (mediaItem == null) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                const SectionHeader(
                  title: 'Now Playing',
                  icon: FluentIcons.music_note_2_24_filled,
                ),
                Material(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: commonCustomBarRadius,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => context.push('/now-playing'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      child: Row(
                        children: [
                          SongArtworkWidget(
                            size: 52,
                            metadata: mediaItem,
                            borderRadius: 12,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  mediaItem.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  mediaItem.artist ?? 'Synchronized with Host',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            FluentIcons.chevron_right_24_regular,
                            size: 20,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        SectionHeader(
          title: l10n.partyFineTuneSync,
          icon: FluentIcons.options_24_filled,
        ),
        Material(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: commonCustomBarRadius,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Calibration Offset',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_sliderOffset >= 0 ? '+' : ''}${_sliderOffset.toInt()} ms',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Slider(
                  value: _sliderOffset,
                  min: -50,
                  max: 50,
                  divisions: 20,
                  onChanged: (val) {
                    setState(() {
                      _sliderOffset = val;
                      _service.calibrationOffsetMs = val.toInt();
                    });
                  },
                ),
                Text(
                  l10n.partyFineTuneHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const MiniPlayerBottomSpace(),
      ],
    );
  }

  void _showManualJoinDialog(BuildContext context) {
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            'Direct Connect',
            style: TextStyle(
              fontFamily: 'paytoneOne',
              fontSize: 22,
              color: theme.colorScheme.primary,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _ipController,
                decoration: InputDecoration(
                  labelText: 'Host IP Address',
                  hintText: 'e.g. 192.168.1.15',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                keyboardType: TextInputType.datetime,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _portController,
                decoration: InputDecoration(
                  labelText: 'Host Port',
                  hintText: 'e.g. 54321',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final ip = _ipController.text.trim();
                final port = int.tryParse(_portController.text.trim()) ?? 0;
                Navigator.pop(dialogContext);
                if (ip.isNotEmpty && port > 0) {
                  final success = await _service.joinByAddress(ip, port);
                  if (!context.mounted) return;
                  if (!success) {
                    showToast(
                      context,
                      'Failed to connect to Party Host at $ip:$port',
                    );
                  }
                }
              },
              child: const Text('Join'),
            ),
          ],
        );
      },
    );
  }
}
