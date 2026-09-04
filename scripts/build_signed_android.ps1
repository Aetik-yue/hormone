param(
    [string]$FlutterSdk = $env:FLUTTER_ROOT,
    [string]$SigningDirectory = (Join-Path $env:USERPROFILE '.android/hormone-release')
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
    & $dart $flutterTools build apk --release --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Signed APK build failed.' }
    & $dart $flutterTools build appbundle --release --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Signed AAB build failed.' }
} finally {
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
    }
    Pop-Location
    $credential = $null
}
