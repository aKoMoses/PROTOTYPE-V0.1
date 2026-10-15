param(
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string]$GodotConsole,
    [Parameter(Mandatory = $true)][string]$AndroidDebugTemplate,
    [Parameter(Mandatory = $true)][string]$AndroidReleaseTemplate,
    [Parameter(Mandatory = $true)][string]$DiagnosticKeystore
)
$ErrorActionPreference = 'Stop'
$perfProject = Split-Path $PSScriptRoot -Parent
$perfPresetPath = Join-Path $perfProject 'export_presets.cfg'
$perfOriginal = [System.IO.File]::ReadAllBytes($perfPresetPath)
$perfText = [System.Text.Encoding]::UTF8.GetString($perfOriginal)
$perfSection = [regex]::Match($perfText, '(?s)\[preset\.0\].*?(?=\[preset\.1\]|\z)').Value
if (-not $perfSection) { throw 'Android export preset 0 was not found.' }
$perfPreset = $perfSection.Replace('[preset.0]', '[preset.2]').Replace('[preset.0.options]', '[preset.2.options]')
$perfPreset = $perfPreset.Replace('name="Android"', 'name="Android performance"')
$perfPreset = $perfPreset.Replace('package/unique_name="com.prototype0.arena"', 'package/unique_name="com.prototype0.arena.performance"')
$perfPreset = $perfPreset.Replace('package/name="Prototype 0"', 'package/name="Prototype 0 Performance"')
$perfPreset = $perfPreset.Replace('custom_template/debug=""', 'custom_template/debug="' + $AndroidDebugTemplate.Replace('\', '/') + '"')
$perfPreset = $perfPreset.Replace('custom_template/release=""', 'custom_template/release="' + $AndroidReleaseTemplate.Replace('\', '/') + '"')
$perfOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $perfOutput | Out-Null
$perfTemporary = Join-Path $perfOutput 'temporary'
New-Item -ItemType Directory -Force -Path $perfTemporary | Out-Null
$env:TEMP = $perfTemporary
$env:TMP = $perfTemporary
$perfApk = Join-Path $perfOutput 'prototype0-android-performance.apk'
$perfLog = Join-Path $perfOutput 'export.log'
$perfSigningVariables = @('GODOT_ANDROID_KEYSTORE_RELEASE_PATH', 'GODOT_ANDROID_KEYSTORE_RELEASE_USER', 'GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD')
$perfPreviousSigning = @{}
foreach ($perfVariable in $perfSigningVariables) {
    $perfPreviousSigning[$perfVariable] = [Environment]::GetEnvironmentVariable($perfVariable, 'Process')
}
if (-not (Test-Path -LiteralPath $DiagnosticKeystore -PathType Leaf)) { throw 'Local diagnostic keystore was not found.' }
try {
    # Use the optimized release runtime, signed with the local test key.
    # This separate application never uses the shared publication key.
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = [System.IO.Path]::GetFullPath($DiagnosticKeystore)
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = 'androiddebugkey'
    $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = 'android'
    [System.IO.File]::WriteAllText($perfPresetPath, $perfText + "`n" + $perfPreset, [System.Text.UTF8Encoding]::new($false))
    & $GodotConsole --headless --audio-driver Dummy --path $perfProject --export-release 'Android performance' $perfApk *> $perfLog
    $perfCode = $LASTEXITCODE
    if ($perfCode -ne 0) { throw "Godot export failed (exit $perfCode). See $perfLog" }
    if (-not (Test-Path -LiteralPath $perfApk)) { throw 'Export finished without an APK.' }
    Write-Output $perfApk
} finally {
    # Restore the precise original bytes, including any unrelated local edits.
    [System.IO.File]::WriteAllBytes($perfPresetPath, $perfOriginal)
    foreach ($perfVariable in $perfSigningVariables) {
        [Environment]::SetEnvironmentVariable($perfVariable, $perfPreviousSigning[$perfVariable], 'Process')
    }
}
