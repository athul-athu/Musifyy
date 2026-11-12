import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart';
import 'package:musify/models/position_data.dart';
import 'package:musify/utilities/formatter.dart';

PositionData _positionData = PositionData(
  Duration.zero,
  Duration.zero,
  Duration.zero,
);

class PositionSlider extends StatefulWidget {
  const PositionSlider({super.key});

  @override
  State<PositionSlider> createState() => _PositionSliderState();
}

class _PositionSliderState extends State<PositionSlider> {
  bool _isDragging = false;
  double _dragValue = 0;
  Object? _currentMediaId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PositionData>(
      stream: audioHandler.positionDataStream,
      builder: (context, snapshot) {
        final mediaId = audioHandler.mediaItem.valueOrNull?.id;
        if (mediaId != _currentMediaId) {
          _currentMediaId = mediaId;
          _positionData = PositionData(
            Duration.zero,
            Duration.zero,
            Duration.zero,
          );
        }

        if (snapshot.data != null) {
          _positionData = snapshot.data!;
        }

        final maxDuration = _positionData.duration.inSeconds > 0
            ? _positionData.duration.inSeconds.toDouble()
            : 1.0;

        final currentValue = _isDragging
            ? _dragValue
            : _positionData.position.inSeconds.toDouble();

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Slider(
              value: currentValue.clamp(0.0, maxDuration),
              onChanged: (value) {
                setState(() {
                  _isDragging = true;
                  _dragValue = value;
                });
              },
              onChangeEnd: (value) {
                audioHandler.seek(Duration(seconds: value.toInt()));
                setState(() {
                  _isDragging = false;
                });
              },
              max: maxDuration,
              semanticFormatterCallback: (value) =>
                  formatDuration(value.toInt()),
            ),
            _buildPositionRow(context, _positionData),
          ],
        );
      },
    );
  }

  static const _textStyle = TextStyle(fontSize: 15);

  Widget _buildPositionRow(BuildContext context, PositionData positionData) {
    final positionText = formatDuration(
      _isDragging ? _dragValue.toInt() : positionData.position.inSeconds,
    );
    final durationText = formatDuration(positionData.duration.inSeconds);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(positionText, style: _textStyle),
          Text(durationText, style: _textStyle),
        ],
      ),
    );
  }
}
