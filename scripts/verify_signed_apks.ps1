param(
    [string]$ReleaseDirectory = '',
    [string]$AndroidSdk = '',
    [string]$JavaHome = $env:JAVA_HOME
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = Split-Path -Parent $PSScriptRoot
$expectedPackage = 'com.aetikyue.hormone'
$expectedCertificate = '7206848b62105dcc9ea3e62a7a2f11158f14b6705849e10441dcf68fae52a6f6'

$pubspec = Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Raw
$versions = [regex]::Matches($pubspec, '(?m)^version:[ \t]*(\d+\.\d+\.\d+)\+([1-9]\d*)[ \t]*(?:#[^\r\n]*)?\r?$')
if ($versions.Count -ne 1) {
    throw 'pubspec.yaml must contain exactly one stable version with a positive build number (X.Y.Z+N).'
}
$expectedVersionName = $versions[0].Groups[1].Value
$expectedVersionCode = $versions[0].Groups[2].Value
if ([string]::IsNullOrWhiteSpace($ReleaseDirectory)) {
    $ReleaseDirectory = Join-Path $projectRoot 'build/release'
}
$ReleaseDirectory = (Resolve-Path -LiteralPath $ReleaseDirectory).Path

# Flutter writes Java properties escapes, including doubled Windows backslashes.
# Decode one escape at a time so paths containing spaces or literal backslashes survive.
function ConvertFrom-JavaProperty([string]$Value) {
    return [regex]::Replace($Value, '\\(u[0-9a-fA-F]{4}|.)', {
        param($match)
        $escaped = $match.Groups[1].Value
        if ($escaped.Length -eq 5 -and $escaped.StartsWith('u')) {
            return [string][char][Convert]::ToInt32($escaped.Substring(1), 16)
        }
        switch -CaseSensitive ($escaped) {
            't' { return "`t" }
            'r' { return "`r" }
            'n' { return "`n" }
            'f' { return [string][char]12 }
            default { return $escaped }
        }
    })
}

if ([string]::IsNullOrWhiteSpace($AndroidSdk)) {
    $localProperties = Join-Path $projectRoot 'android/local.properties'
    if (Test-Path -LiteralPath $localProperties -PathType Leaf) {
        foreach ($line in Get-Content -LiteralPath $localProperties) {
            if ($line -match '^\s*sdk\.dir\s*[=:]\s*(.*)$') {
                $AndroidSdk = ConvertFrom-JavaProperty $Matches[1]
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($AndroidSdk) -and -not [IO.Path]::IsPathRooted($AndroidSdk)) {
            $AndroidSdk = Join-Path (Split-Path -Parent $localProperties) $AndroidSdk
        }
    }
    if ([string]::IsNullOrWhiteSpace($AndroidSdk)) { $AndroidSdk = $env:ANDROID_HOME }
    if ([string]::IsNullOrWhiteSpace($AndroidSdk)) { $AndroidSdk = $env:ANDROID_SDK_ROOT }
}
if ([string]::IsNullOrWhiteSpace($AndroidSdk)) {
    throw 'Android SDK not found. Supply -AndroidSdk, sdk.dir in android/local.properties, or ANDROID_HOME.'
}
$AndroidSdk = (Resolve-Path -LiteralPath $AndroidSdk).Path
$buildTools = @(Get-ChildItem -LiteralPath (Join-Path $AndroidSdk 'build-tools') -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
    Sort-Object { [version]$_.Name } -Descending |
    Where-Object {
        (Test-Path -LiteralPath (Join-Path $_.FullName 'aapt.exe') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'lib/apksigner.jar') -PathType Leaf)
    })
if ($buildTools.Count -eq 0) {
    throw 'No stable Android build-tools installation contains both aapt.exe and lib/apksigner.jar.'
}
$aapt = Join-Path $buildTools[0].FullName 'aapt.exe'
$apksigner = Join-Path $buildTools[0].FullName 'lib/apksigner.jar'
if ([string]::IsNullOrWhiteSpace($JavaHome)) {
    $java = (Get-Command java -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
} else {
    $java = Join-Path $JavaHome 'bin/java.exe'
    if (-not (Test-Path -LiteralPath $java -PathType Leaf)) {
        throw "Java executable not found: $java. Correct JAVA_HOME or supply -JavaHome."
    }
}

foreach ($abi in @('android', 'arm64-v8a', 'armeabi-v7a', 'x86_64')) {
    $apkName = "hormone-v$expectedVersionName-$abi.apk"
    $apk = Join-Path $ReleaseDirectory $apkName
    if (-not (Test-Path -LiteralPath $apk -PathType Leaf)) {
        throw "Required APK not found: $apk"
    }

    # Invoke the JAR directly to avoid apksigner.bat reparsing paths with spaces.
    $signatureLines = @(& $java -jar $apksigner verify --verbose --print-certs $apk)
    if ($LASTEXITCODE -ne 0) { throw "APK signature verification failed: $apkName" }
    $signature = $signatureLines -join "`n"
    if ($signature -notmatch '(?m)^Number of signers: 1\r?$') {
        throw "APK must have exactly one signer: $apkName"
    }
    $certificates = [regex]::Matches($signature, '(?m)^Signer #1 certificate SHA-256 digest: ([0-9a-fA-F]{64})\r?$')
    if ($certificates.Count -ne 1 -or $certificates[0].Groups[1].Value -ine $expectedCertificate) {
        throw "APK does not use the established Hormone release certificate: $apkName"
    }

    $badgingLines = @(& $aapt dump badging $apk)
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect APK metadata: $apkName" }
    $packages = [regex]::Matches(($badgingLines -join "`n"), "(?m)^package: name='([^']+)' versionCode='([0-9]+)' versionName='([^']+)'")
    if ($packages.Count -ne 1) { throw "Unable to parse APK package metadata: $apkName" }
    $package = $packages[0]
    if ($package.Groups[1].Value -cne $expectedPackage -or
        $package.Groups[2].Value -cne $expectedVersionCode -or
        $package.Groups[3].Value -cne $expectedVersionName) {
        throw "APK package/version mismatch: $apkName. Expected $expectedPackage $expectedVersionName ($expectedVersionCode); found $($package.Value)."
    }
    Write-Output "$apkName : package, version $expectedVersionName ($expectedVersionCode), and release signature verified."
}
