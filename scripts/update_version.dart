import 'dart:io';

void main() {
  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    stderr.writeln('pubspec.yaml not found');
    exit(1);
  }

  final lines = pubspecFile.readAsLinesSync();
  String? rawVersion;
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.startsWith('version:')) {
      rawVersion = trimmed.substring('version:'.length).trim();
      final commentIndex = rawVersion.indexOf('#');
      if (commentIndex != -1) {
        rawVersion = rawVersion.substring(0, commentIndex).trim();
      }
      rawVersion = rawVersion.replaceAll("'", '').replaceAll('"', '');
      break;
    }
  }

  if (rawVersion == null || rawVersion.isEmpty) {
    stderr.writeln('Could not find version in pubspec.yaml');
    exit(1);
  }

  final parts = rawVersion.split('+');
  final version = parts[0].trim();
  final versionCode = parts.length > 1 ? parts[1].trim() : '1';

  final versionDart = File('lib/constants/version.dart');
  versionDart.writeAsStringSync(
    "const appVersion = '$version';\nconst appVersionCode = '$versionCode';\n",
  );

  final checkJson = File('update/check.json');
  checkJson.writeAsStringSync(
    '{\n'
    '  "version": "$version",\n'
    '  "versionCode": ${int.tryParse(versionCode) ?? 1},\n'
    '  "url": "https://github.com/athul-athu/Musifyy/releases/latest/download/Musify.apk",\n'
    '  "arm64url": "https://github.com/athul-athu/Musifyy/releases/latest/download/Musify-arm64-v8a.apk",\n'
    '  "ipaUrl": "https://github.com/athul-athu/Musifyy/releases/latest/download/Musify.ipa",\n'
    '  "announcementurl": null\n'
    '}\n',
  );

  stdout.writeln(
    'Successfully updated to version $version (versionCode: $versionCode)',
  );
}
