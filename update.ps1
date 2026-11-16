# Read version from pubspec.yaml
$pubspecContent = Get-Content pubspec.yaml
$versionLine = $pubspecContent | Where-Object { $_ -match '^version:\s*(.+)' }

if ($versionLine -match '^version:\s*([^\s#]+)') {
    $rawVersion = $matches[1].Replace("'", "").Replace('"', "")
    $parts = $rawVersion.Split('+')
    $version = $parts[0]
    $versionCode = if ($parts.Length -gt 1) { $parts[1] } else { "1" }

    # Write to lib/constants/version.dart
    $versionDartContent = "const appVersion = '$version';`nconst appVersionCode = '$versionCode';`n"
    [System.IO.File]::WriteAllText("lib/constants/version.dart", $versionDartContent)

    # Write to update/check.json
    $checkJsonContent = @"
{
  "version": "$version",
  "versionCode": $versionCode,
  "url": "https://github.com/athul-athu/Musifyy/releases/latest/download/Musify.apk",
  "arm64url": "https://github.com/athul-athu/Musifyy/releases/latest/download/Musify-arm64-v8a.apk",
  "ipaUrl": "https://github.com/athul-athu/Musifyy/releases/latest/download/Musify.ipa",
  "announcementurl": null
}
"@
    [System.IO.File]::WriteAllText("update/check.json", $checkJsonContent + "`n")

    Write-Host "Successfully updated to version $version (versionCode: $versionCode)"
} else {
    Write-Error "Could not find 'version:' line in pubspec.yaml"
}
