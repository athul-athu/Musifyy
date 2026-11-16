#!/bin/bash

# Read version and build number from pubspec.yaml
raw_version=$(grep '^version:' pubspec.yaml | sed -E 's/version: *//' | sed -E 's/ *#.*//' | tr -d "'\"")
version=$(echo "$raw_version" | awk -F'+' '{print $1}')
build_number=$(echo "$raw_version" | awk -F'+' '{print $2}')
if [ -z "$build_number" ]; then
  build_number="1"
fi

# Write to lib/constants/version.dart
cat <<EOF > lib/constants/version.dart
const appVersion = '$version';
const appVersionCode = '$build_number';
EOF

# Write to update/check.json
cat <<EOF > update/check.json
{
  "version": "$version",
  "versionCode": $build_number,
  "url": "https://github.com/athul-athu/Musifyy/releases/latest/download/Musify.apk",
  "arm64url": "https://github.com/athul-athu/Musifyy/releases/latest/download/Musify-arm64-v8a.apk",
  "ipaUrl": "https://github.com/athul-athu/Musifyy/releases/latest/download/Musify.ipa",
  "announcementurl": null
}
EOF

echo "Successfully updated to version $version (versionCode: $build_number)"
