import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/app_constants.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/party_sync/party_protocol.dart';
import 'package:musify/services/party_sync/party_sync_service.dart';
import 'package:musify/utilities/app_utils.dart';
import 'package:musify/utilities/flutter_bottom_sheet.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/utilities/mediaitem.dart';
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
    _service.role.addListener(_onRoleChanged);
  }

  void _onRoleChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _service.role.removeListener(_onRoleChanged);
    _ipController.dispose();
    _portController.dispose();
    _service.stopDiscovery();
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
        ValueListenableBuilder<PartyState>(
          valueListenable: _service.state,
          builder: (context, partyState, _) {
            return ValueListenableBuilder<List<PartyRoomInfo>>(
              valueListenable: _service.discoveredRooms,
              builder: (context, rooms, _) {
                if (rooms.isEmpty) {
                  if (partyState == PartyState.discovering) {
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
                  return CustomBar(
                    'Scan for Party Rooms',
                    FluentIcons.wifi_1_24_regular,
                    description: 'Search for active Party Hosts on your local Wi-Fi network.',
                    borderRadius: commonCustomBarRadius,
                    trailing: FilledButton.tonal(
                      onPressed: () {
                        _service.startDiscovery();
                        showToast(context, 'Scanning for party rooms...');
                      },
                      child: const Text('Scan'),
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
                          '${speakers[i].ip} • Ping: ${speakers[i].rttMs}ms • Drift: ${speakers[i].driftMs}ms${speakers[i].clockUncertaintyMs > 0 ? ' (±${speakers[i].clockUncertaintyMs}ms)' : ''}',
                      borderRadius: getItemBorderRadius(i, speakers.length),
                      trailing: () {
                        final status = speakers[i].status.toLowerCase();
                        final isPlaying = status == 'playing';
                        final isReady = status == 'ready';
                        final isPaused = status == 'paused';
                        final isLoading = status == 'loading' || status == 'buffering';

                        final Color badgeBg;
                        final Color badgeFg;
                        final IconData badgeIcon;
                        final String badgeText;

                        if (isPlaying) {
                          badgeBg = theme.colorScheme.primaryContainer;
                          badgeFg = theme.colorScheme.onPrimaryContainer;
                          badgeIcon = FluentIcons.speaker_2_16_filled;
                          badgeText = 'Playing';
                        } else if (isReady) {
                          badgeBg = theme.colorScheme.secondaryContainer;
                          badgeFg = theme.colorScheme.onSecondaryContainer;
                          badgeIcon = FluentIcons.checkmark_16_regular;
                          badgeText = 'Ready';
                        } else if (isPaused) {
                          badgeBg = theme.colorScheme.surfaceContainerHighest;
                          badgeFg = theme.colorScheme.onSurfaceVariant;
                          badgeIcon = FluentIcons.pause_16_regular;
                          badgeText = 'Paused';
                        } else {
                          badgeBg = theme.colorScheme.surfaceContainerHighest;
                          badgeFg = theme.colorScheme.onSurfaceVariant;
                          badgeIcon = FluentIcons.arrow_sync_16_regular;
                          badgeText = isLoading ? 'Buffering...' : 'Connecting...';
                        }

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: badgeBg,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                badgeIcon,
                                size: 13,
                                color: badgeFg,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                badgeText,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: badgeFg,
                                ),
                              ),
                            ],
                          ),
                        );
                      }(),
                    ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        const SectionHeader(
          title: 'Party Jukebox',
          icon: FluentIcons.music_note_2_24_filled,
        ),
        ValueListenableBuilder<PartyJukeboxMode>(
          valueListenable: _service.jukeboxMode,
          builder: (context, mode, _) {
            final isCollaborative = mode == PartyJukeboxMode.collaborative;
            return Material(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: commonCustomBarRadius,
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      isCollaborative
                          ? FluentIcons.people_community_24_filled
                          : FluentIcons.person_24_filled,
                      color: isCollaborative
                          ? theme.colorScheme.primary
                          : theme.colorScheme.secondary,
                      size: 28,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isCollaborative
                                ? 'Collaborative Jukebox'
                                : 'DJ Mode (Host Only)',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isCollaborative
                                ? 'Guests can search songs, request, & vote'
                                : 'Only host controls playback & queue',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: isCollaborative,
                      onChanged: (val) {
                        _service.setJukeboxMode(
                          val
                              ? PartyJukeboxMode.collaborative
                              : PartyJukeboxMode.djOnly,
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        ValueListenableBuilder<List<PartyQueueItem>>(
          valueListenable: _service.partyQueue,
          builder: (context, queue, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: 'Party Queue (${queue.length})',
                  icon: FluentIcons.list_24_filled,
                ),
                if (queue.isEmpty)
                  CustomBar(
                    'Queue is empty',
                    FluentIcons.music_note_2_24_regular,
                    description:
                        'Play a track in Musify or allow guests to request songs!',
                    borderRadius: commonCustomBarRadius,
                  )
                else
                  for (var i = 0; i < queue.length; i++)
                    _buildHostQueueTile(context, queue[i], i, queue.length),
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
              'Host: ${room?.ip}:${room?.port} • Ping: ${_service.clock.rttMs}ms • Sync: ${_service.syncQuality.name.toUpperCase()}',
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
        ValueListenableBuilder<PartyJukeboxMode>(
          valueListenable: _service.jukeboxMode,
          builder: (context, mode, _) {
            final isCollaborative = mode == PartyJukeboxMode.collaborative;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: isCollaborative ? 'Party Jukebox' : 'Party Queue',
                  icon: FluentIcons.music_note_2_24_filled,
                ),
                if (isCollaborative)
                  Material(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                    borderRadius: commonCustomBarRadius,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Icon(
                            FluentIcons.sparkle_24_filled,
                            color: theme.colorScheme.primary,
                            size: 26,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Collaborative Jukebox',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Request tracks & vote to play them next!',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            icon: const Icon(FluentIcons.add_16_regular, size: 16),
                            label: const Text('Request'),
                            onPressed: () => _showSongRequestSheet(context),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  CustomBar(
                    'DJ Mode Active',
                    FluentIcons.lock_closed_24_regular,
                    description:
                        'Only the Host controls the queue. View upcoming songs below.',
                    borderRadius: commonCustomBarRadius,
                  ),
                const SizedBox(height: 16),
                ValueListenableBuilder<List<PartyQueueItem>>(
                  valueListenable: _service.partyQueue,
                  builder: (context, queue, _) {
                    if (queue.isEmpty) {
                      return CustomBar(
                        'Party queue is empty',
                        FluentIcons.music_note_2_24_regular,
                        description: isCollaborative
                            ? 'Tap "Request" to add the first song to the party!'
                            : 'Host has not queued any songs yet.',
                        borderRadius: commonCustomBarRadius,
                      );
                    }

                    return Column(
                      children: [
                        for (var i = 0; i < queue.length; i++)
                          _buildSpeakerQueueTile(
                            context,
                            queue[i],
                            i,
                            queue.length,
                            isCollaborative,
                          ),
                      ],
                    );
                  },
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

  Widget _buildHostQueueTile(
    BuildContext context,
    PartyQueueItem item,
    int index,
    int totalCount,
  ) {
    final theme = Theme.of(context);
    final hasVoted = item.hasVoted('host');

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: getItemBorderRadius(index, totalCount),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SongArtworkWidget(
              size: 46,
              metadata: mapToMediaItem(item.songData),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: item.isPlaying
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (item.isPlaying)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Playing Now',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.requestedBy == 'Host'
                                ? 'Added by Host'
                                : 'Requested by ${item.requestedBy}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (!item.isPlaying) ...[
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(40, 32),
                  backgroundColor: hasVoted
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                ),
                onPressed: () => _service.toggleVote(item.ytid),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasVoted
                          ? FluentIcons.thumb_like_16_filled
                          : FluentIcons.thumb_like_16_regular,
                      size: 14,
                      color: hasVoted
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${item.voteCount}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: hasVoted
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(FluentIcons.delete_16_regular, size: 18),
                tooltip: 'Remove',
                color: theme.colorScheme.error,
                onPressed: () => _service.removeSongFromPartyQueue(index),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSpeakerQueueTile(
    BuildContext context,
    PartyQueueItem item,
    int index,
    int totalCount,
    bool isCollaborative,
  ) {
    final theme = Theme.of(context);
    final hasVoted = item.hasVoted(_service.speakerDeviceId);

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: getItemBorderRadius(index, totalCount),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SongArtworkWidget(
              size: 46,
              metadata: mapToMediaItem(item.songData),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: item.isPlaying
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (item.isPlaying)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Playing Now',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.requestedBy == 'Host'
                                ? 'Added by Host'
                                : 'Requested by ${item.requestedBy}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (!item.isPlaying && isCollaborative)
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: const Size(44, 34),
                  backgroundColor: hasVoted
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                ),
                onPressed: () => _service.toggleVote(item.ytid),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasVoted
                          ? FluentIcons.thumb_like_16_filled
                          : FluentIcons.thumb_like_16_regular,
                      size: 15,
                      color: hasVoted
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${item.voteCount}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: hasVoted
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showSongRequestSheet(BuildContext context) {
    showCustomBottomSheet<void>(
      context,
      const _PartySongRequestSheet(),
    );
  }
}

class _PartySongRequestSheet extends StatefulWidget {
  const _PartySongRequestSheet();

  @override
  State<_PartySongRequestSheet> createState() => _PartySongRequestSheetState();
}

class _PartySongRequestSheetState extends State<_PartySongRequestSheet> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  bool _isLoading = false;
  List<dynamic> _searchResults = [];

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _isLoading = false;
        _searchResults = [];
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _isLoading = true);
      try {
        final results = await fetchSongsList(query.trim());
        if (!mounted) return;
        setState(() {
          _searchResults = results;
          _isLoading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _isLoading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);

    return SizedBox(
      height: size.height * 0.72,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Request a Song',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              IconButton(
                icon: const Icon(FluentIcons.dismiss_20_regular),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _searchController,
            autofocus: true,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search title, artist, or YouTube URL...',
              prefixIcon: const Icon(FluentIcons.search_24_regular),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(FluentIcons.dismiss_16_regular),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            )
          else if (_searchResults.isEmpty &&
              _searchController.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Column(
                children: [
                  Icon(
                    FluentIcons.search_visual_24_regular,
                    size: 40,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No songs found for "${_searchController.text.trim()}"',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          else if (_searchResults.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Icon(
                    FluentIcons.music_note_2_24_regular,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Search for music to add to the party jukebox!',
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: _searchResults.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final song = _searchResults[index];
                  final songMap = song is Map ? song : <dynamic, dynamic>{};
                  final title = songMap['title']?.toString() ?? 'Unknown';
                  final artist = songMap['artist']?.toString() ?? 'Unknown';

                  return Material(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          SongArtworkWidget(
                            size: 44,
                            metadata: mapToMediaItem(songMap),
                            borderRadius: 8,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                            ),
                            onPressed: () {
                              PartySyncService.instance.requestSong(songMap);
                              Navigator.pop(context);
                              showToast(
                                context,
                                'Requested "$title" for the party!',
                              );
                            },
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(FluentIcons.add_16_regular, size: 14),
                                SizedBox(width: 4),
                                Text('Request'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
