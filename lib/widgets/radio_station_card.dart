import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/models/radio_model.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/utilities/artwork_provider.dart';
import 'package:musify/widgets/shapes/eight_leaf_clover_shape.dart';

class RadioStationCard extends StatefulWidget {
  const RadioStationCard({
    super.key,
    required this.station,
    required this.onPressed,
    this.onFavoritesChanged,
  });

  final RadioStation station;
  final VoidCallback onPressed;
  final VoidCallback? onFavoritesChanged;

  @override
  State<RadioStationCard> createState() => _RadioStationCardState();
}

class _RadioStationCardState extends State<RadioStationCard> {
  late final ValueNotifier<bool> _isFavorited = ValueNotifier<bool>(
    isRadioStationLiked(widget.station.id),
  );

  @override
  void initState() {
    super.initState();
    userLikedRadioStations.addListener(_onFavoritesUpdated);
  }

  void _onFavoritesUpdated() {
    final newStatus = isRadioStationLiked(widget.station.id);
    if (_isFavorited.value != newStatus) {
      _isFavorited.value = newStatus;
    }
  }

  @override
  void dispose() {
    userLikedRadioStations.removeListener(_onFavoritesUpdated);
    _isFavorited.dispose();
    super.dispose();
  }

  Future<void> _handleFavoriteTap() async {
    final wasFavorited = _isFavorited.value;
    _isFavorited.value = !wasFavorited;

    try {
      if (wasFavorited) {
        await removeRadioStationFromLiked(widget.station.id);
      } else {
        await addRadioStationToLiked(widget.station.id);
      }
      widget.onFavoritesChanged?.call();
    } catch (e) {
      _isFavorited.value = wasFavorited; // revert on failure
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.zero,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image(
                  image: ArtworkProvider.get(widget.station.image),
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 56,
                    height: 56,
                    color: colorScheme.primaryContainer,
                    child: Icon(
                      FluentIcons.sound_source_24_regular,
                      color: colorScheme.onPrimaryContainer,
                      size: 26,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.station.name,
                      style: textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.station.genre ?? 'Radio Station',
                      style: textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              ValueListenableBuilder<bool>(
                valueListenable: _isFavorited,
                builder: (context, isFavorited, _) {
                  return IconButton.filledTonal(
                    onPressed: _handleFavoriteTap,
                    icon: Icon(
                      isFavorited
                          ? FluentIcons.heart_24_filled
                          : FluentIcons.heart_24_regular,
                      size: 18,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: isFavorited
                          ? colorScheme.primaryContainer
                          : colorScheme.surfaceContainerHighest,
                      foregroundColor: isFavorited
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                      minimumSize: const Size(36, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  );
                },
              ),
              const SizedBox(width: 5),
              EightLeafClover(
                size: 48,
                color: colorScheme.secondaryContainer,
                onTap: widget.onPressed,
                child: Icon(
                  FluentIcons.play_24_filled,
                  size: 18,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
