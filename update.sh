#!/bin/bash

# Read the version from pubspec.yaml
version=$(grep version pubspec.yaml | awk -F'[ +]' '{print $2}' | tr -d "'")

# Define the variable name and file name
variable="appVersion"
filename="lib/constants/version.dart"

# Write the version to the Dart file
echo "const $variable = '$version';" > $filename

# Write the version to update/check.json
cat <<EOF > update/check.json
{
  "version": "$version",
  "url": "https://github.com/athul-athu/Musifyy/releases/latest/download/musify.apk",
  "arm64url": "https://github.com/athul-athu/Musifyy/releases/latest/download/musify.apk",
  "ipaUrl": "https://github.com/athul-athu/Musifyy/releases/latest/download/Musify.ipa",
  "announcementurl": null
}
EOF
