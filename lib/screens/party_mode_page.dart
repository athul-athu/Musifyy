import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:musify/constants/app_constants.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/services/party_sync/party_protocol.dart';
import 'package:musify/services/party_sync/party_sync_service.dart';
import 'package:musify/utilities/app_utils.dart';
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
  // IDLE VIEW (Host or Join)
  // ===========================================================================

  Widget _buildIdleView(BuildContext context) {
    final l10n = context.l10n!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(
                  FluentIcons.speaker_2_24_filled,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.partyModeTitle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.partyModeDescription,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  icon: const Icon(FluentIcons.play_24_filled),
                  label: Text(l10n.partyHostButton),
                  onPressed: () async {
                    final success = await _service.startHosting();
                    if (!mounted) return;
                    if (!success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not start Party Host.'),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        SectionHeader(
          title: l10n.partyJoinButton,
          icon: FluentIcons.wifi_1_24_filled,
        ),
        ValueListenableBuilder<List<PartyRoomInfo>>(
          valueListenable: _service.discoveredRooms,
          builder: (context, rooms, _) {
            if (rooms.isEmpty) {
              return Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 24,
                    horizontal: 16,
                  ),
                  child: Column(
                    children: [
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.partyScanningRooms,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
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
                      child: Text(l10n.partyJoinButton),
                      onPressed: () => _service.joinRoom(rooms[i]),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton.icon(
            icon: const Icon(FluentIcons.link_24_regular),
            label: Text(l10n.partyManualJoin),
            onPressed: () => _showManualJoinDialog(context),
          ),
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
        Card(
          elevation: 0,
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            room?.name ?? 'Musify Party',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.partyRoomCode(room?.id ?? '----'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'IP: ${room?.ip}:${room?.port}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(FluentIcons.dismiss_24_regular, size: 16),
                      label: Text(l10n.partyEndButton),
                      onPressed: _service.leaveParty,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        ValueListenableBuilder<List<ConnectedSpeaker>>(
          valueListenable: _service.connectedSpeakers,
          builder: (context, speakers, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: l10n.partySpeakersConnected(speakers.length),
                  icon: FluentIcons.speaker_2_24_filled,
                ),
                if (speakers.isEmpty)
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l10n.partyNoSpeakersYet,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  for (var i = 0; i < speakers.length; i++)
                    CustomBar(
                      speakers[i].name,
                      FluentIcons.phone_24_regular,
                      description:
                          '${speakers[i].ip} • Latency: ${speakers[i].rttMs}ms • Drift: ${speakers[i].driftMs}ms',
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
        Card(
          elevation: 0,
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(
                  FluentIcons.speaker_2_24_filled,
                  size: 44,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.partyConnectedTo(room?.name ?? 'Host'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Host: ${room?.ip}:${room?.port} • RTT: ${_service.clock.rttMs}ms',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  icon: const Icon(FluentIcons.dismiss_24_regular, size: 16),
                  label: Text(l10n.partyLeaveButton),
                  onPressed: _service.leaveParty,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        SectionHeader(
          title: l10n.partyFineTuneSync,
          icon: FluentIcons.options_24_filled,
        ),
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
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
          title: const Text('Join Party Room'),
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

