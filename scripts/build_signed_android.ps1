param(
    [string]$FlutterSdk = $env:FLUTTER_ROOT,
    [string]$SigningDirectory = (Join-Path $env:USERPROFILE '.android/hormone-release'),
    [string]$UpdateBaseUrl = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($FlutterSdk)) {
    $flutterCommand = Get-Command flutter -ErrorAction Stop
    $FlutterSdk = Split-Path -Parent (Split-Path -Parent $flutterCommand.Source)
}
$dart = Join-Path $FlutterSdk 'bin/cache/dart-sdk/bin/dart.exe'
$flutterTools = Join-Path $FlutterSdk 'bin/cache/flutter_tools.snapshot'
$keystore = Join-Path $SigningDirectory 'hormone-release-key.jks'
$credentialFile = Join-Path $SigningDirectory 'credentials.clixml'
foreach ($required in @($dart, $flutterTools, $keystore, $credentialFile)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required file not found: $required"
    }
}
if (Test-Path -LiteralPath (Join-Path $projectRoot 'android/app/build.gradle')) {
    throw 'Apply the native Kotlin Gradle template first; an old android/app/build.gradle would take precedence.'
}

# Windows Export-Clixml encrypts the SecureString for the current user/machine.
$credential = Import-Clixml -LiteralPath $credentialFile
if ($credential -isnot [System.Management.Automation.PSCredential]) {
    throw 'Invalid signing credential file.'
}
$environmentNames = @(
    'HORMONE_KEYSTORE_PATH', 'HORMONE_KEYSTORE_PASSWORD',
    'HORMONE_KEY_ALIAS', 'HORMONE_KEY_PASSWORD', 'FLUTTER_ROOT'
)
$previousEnvironment = @{}
foreach ($name in $environmentNames) {
    $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
Push-Location $projectRoot
try {
    $env:FLUTTER_ROOT = $FlutterSdk
    $env:HORMONE_KEYSTORE_PATH = (Resolve-Path -LiteralPath $keystore).Path
    $env:HORMONE_KEYSTORE_PASSWORD = $credential.GetNetworkCredential().Password
    $env:HORMONE_KEY_ALIAS = $credential.UserName
    $env:HORMONE_KEY_PASSWORD = $env:HORMONE_KEYSTORE_PASSWORD
    $versionLine = Select-String -Path pubspec.yaml -Pattern '^version: (.+)$'
    $version = $versionLine.Matches[0].Groups[1].Value.Split('+')[0]
    $releaseDirectory = Join-Path $projectRoot 'build/release'
    New-Item -ItemType Directory -Force -Path $releaseDirectory | Out-Null
    # Apply the installer entry point alongside the manifest and FileProvider paths.
    Copy-Item -LiteralPath native_templates/android/app/build.gradle.kts -Destination android/app/build.gradle.kts -Force
    $mainActivityPath = Join-Path $projectRoot 'android/app/src/main/kotlin/com/aetikyue/hormone'
    New-Item -ItemType Directory -Force -Path $mainActivityPath | Out-Null
    Copy-Item -LiteralPath native_templates/android/app/src/main/kotlin/com/aetikyue/hormone/MainActivity.kt -Destination $mainActivityPath -Force
    Copy-Item -LiteralPath native_templates/android/app/src/main/AndroidManifest.xml -Destination android/app/src/main/AndroidManifest.xml -Force
    Copy-Item -LiteralPath native_templates/android/app/src/main/res/xml/filepaths.xml -Destination android/app/src/main/res/xml/filepaths.xml -Force
    $targets = [ordered]@{
        'android' = 'android-arm,android-arm64,android-x64'
        'arm64-v8a' = 'android-arm64'
        'armeabi-v7a' = 'android-arm'
        'x86_64' = 'android-x64'
    }
    foreach ($abi in $targets.Keys) {
        & $dart $flutterTools build apk --release --no-pub "--target-platform=$($targets[$abi])" "--dart-define=HORMONE_UPDATE_BASE_URL=$UpdateBaseUrl"
        if ($LASTEXITCODE -ne 0) { throw "Signed APK build failed: $abi" }
        Copy-Item -LiteralPath build/app/outputs/flutter-apk/app-release.apk -Destination (Join-Path $releaseDirectory "hormone-v$version-$abi.apk") -Force
    }
    & $dart $flutterTools build appbundle --release --no-pub "--dart-define=HORMONE_UPDATE_BASE_URL=$UpdateBaseUrl"
    if ($LASTEXITCODE -ne 0) { throw 'Signed AAB build failed.' }
    Copy-Item -LiteralPath build/app/outputs/bundle/release/app-release.aab -Destination (Join-Path $releaseDirectory "hormone-v$version-android.aab") -Force
    python scripts/verify_apk_architectures.py --tag "v$version"
    if ($LASTEXITCODE -ne 0) { throw 'APK architecture verification failed.' }
    python scripts/prepare_update_manifest.py --tag "v$version"
    if ($LASTEXITCODE -ne 0) { throw 'Update manifest generation failed.' }
} finally {
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
    }
    Pop-Location
    $credential = $null
}
