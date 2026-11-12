/// Converts the duration formats used by song maps into a positive duration.
///
/// A zero duration is treated as unknown. Publishing zero to Android's media
/// session makes the system player render a misleading `00:00` total.
Duration? readMediaDuration(dynamic value) {
  Duration? duration;

  if (value is Duration) {
    duration = value;
  } else if (value is num) {
    if (!value.isFinite) return null;
    duration = Duration(milliseconds: (value * 1000).round());
  } else {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;

    final numericSeconds = double.tryParse(text);
    if (numericSeconds != null && numericSeconds.isFinite) {
      duration = Duration(milliseconds: (numericSeconds * 1000).round());
    } else {
      final parts = text.split(':').map(int.tryParse).toList();
      if (parts.any((part) => part == null)) return null;
      if (parts.length == 2) {
        duration = Duration(minutes: parts[0]!, seconds: parts[1]!);
      } else if (parts.length == 3) {
        duration = Duration(
          hours: parts[0]!,
          minutes: parts[1]!,
          seconds: parts[2]!,
        );
      }
    }
  }

  return duration != null && duration > Duration.zero ? duration : null;
}

/// Chooses a reported player duration while keeping an unknown report from
/// replacing a valid value.
///
/// A clipped source can temporarily report the duration of only its current
/// segment. Callers that know the report came from such a source may preserve
/// the longer known total until the complete source duration is available.
Duration? preferStableMediaDuration(
  Duration? known,
  Duration? reported, {
  bool preserveLongerKnown = false,
}) {
  final validKnown = readMediaDuration(known);
  final validReported = readMediaDuration(reported);

  if (validReported == null) return validKnown;
  if (validKnown != null && validKnown > Duration.zero) {
    // Protect against native iOS AVPlayer doubling bug:
    // When playing certain AAC/VBR streams, AVPlayer calculates/reports roughly double the duration.
    final ratio = validReported.inMilliseconds / validKnown.inMilliseconds;
    if (ratio >= 1.5) {
      return validKnown;
    }
  }
  if (preserveLongerKnown && validKnown != null && validReported < validKnown) {
    return validKnown;
  }
  return validReported;
}
