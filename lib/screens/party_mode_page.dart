import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:musify/constants/app_constants.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/services/party_sync/party_protocol.dart';
import 'package:musify/services/party_sync/party_sync_service.dart';
import 'package:musify/utilities/app_utils.dart';
import 'package:musify/utilities/platform_utils.dart';
import 'package:musify/widgets/custom_bar.dart';
import 'package:musify/widgets/mini_player_bottom_space.dart';
import 'package:musify/widgets/section_header.dart';

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
    if (!_service.isInParty) {
      _service.startDiscovery();
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    if (!_service.isInParty) {
      _service.stopDiscovery();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.partyModeTitle),
        actions: [
          ValueListenableBuilder<PartyRole>(
            valueListenable: _service.role,
            builder: (context, role, _) {
              if (role == PartyRole.none) {
                return IconButton(
                  icon: const Icon(FluentIcons.arrow_clockwise_24_regular),
                  tooltip: 'Refresh',
                  onPressed: _service.startDiscovery,
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
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
        ),
      ),
    );
  }

  // ===========================================================================
  // IDLE VIEW (Host or Discover Rooms)
  // ===========================================================================

  Widget _buildIdleView(BuildContext context) {
    final l10n = context.l10n!;

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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not start Party Host.')),
                );
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
            onPressed: _service.startDiscovery,
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
                      onPressed: () => _service.joinRoom(rooms[i]),
                      child: Text(l10n.partyJoinButton),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        const SectionHeader(
          title: 'Direct Connect',
          icon: FluentIcons.link_24_filled,
        ),
        CustomBar(
          l10n.partyManualJoin,
          FluentIcons.link_24_regular,
          description: 'Connect directly using Host IP and Port',
          borderRadius: commonCustomBarRadius,
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
          borderRadius: commonCustomBarRadiusFirst,
          trailing: FilledButton.tonal(
            onPressed: _service.leaveParty,
            child: Text(l10n.partyEndButton),
          ),
        ),
        StreamBuilder(
          stream: audioHandler.mediaItem,
          builder: (context, snapshot) {
            final title = snapshot.data?.title ?? 'No music playing';
            final artist = snapshot.data?.artist ??
                'Play any song to sync across all speakers';
            return CustomBar(
              title,
              FluentIcons.music_note_2_24_regular,
              description: artist,
              borderRadius: commonCustomBarRadiusLast,
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
                      FluentIcons.phone_24_regular,
                      description:
                          '${speakers[i].ip} • Ping: ${speakers[i].rttMs}ms • Drift: ${speakers[i].driftMs}ms',
                      borderRadius: getItemBorderRadius(i, speakers.length),
                      trailing: Chip(
                        label: Text(
                          speakers[i].status.toUpperCase(),
                          style: const TextStyle(fontSize: 11),
                        ),
                        backgroundColor: speakers[i].status == 'ready' ||
                                speakers[i].status == 'playing'
                            ? theme.colorScheme.primaryContainer
                            : theme.colorScheme.surfaceContainerHighest,
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
          borderRadius: commonCustomBarRadiusFirst,
          trailing: FilledButton.tonal(
            onPressed: _service.leaveParty,
            child: Text(l10n.partyLeaveButton),
          ),
        ),
        StreamBuilder(
          stream: audioHandler.mediaItem,
          builder: (context, snapshot) {
            final title = snapshot.data?.title ?? 'Synchronized Audio';
            final artist = snapshot.data?.artist ??
                'Playing automatically in lockstep with Host';
            return CustomBar(
              title,
              FluentIcons.music_note_2_24_regular,
              description: artist,
              borderRadius: commonCustomBarRadiusLast,
            );
          },
        ),
        const SizedBox(height: 20),
        SectionHeader(
          title: l10n.partyFineTuneSync,
          icon: FluentIcons.options_24_filled,
        ),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: commonCustomBarRadius,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Calibration Offset',
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    '${_sliderOffset.toInt()} ms',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _sliderOffset,
                min: -50,
                max: 50,
                divisions: 20,
                label: '${_sliderOffset.toInt()} ms',
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
        const SizedBox(height: 20),
        const MiniPlayerBottomSpace(),
      ],
    );
  }

  void _showManualJoinDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Direct Connect'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _ipController,
                decoration: const InputDecoration(
                  labelText: 'Host IP Address',
                  hintText: 'e.g. 192.168.1.15',
                ),
                keyboardType: TextInputType.datetime,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _portController,
                decoration: const InputDecoration(
                  labelText: 'Host Port',
                  hintText: 'e.g. 54321',
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
              onPressed: () {
                final ip = _ipController.text.trim();
                final port = int.tryParse(_portController.text.trim()) ?? 0;
                Navigator.pop(dialogContext);
                if (ip.isNotEmpty && port > 0) {
                  _service.joinByAddress(ip, port);
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
