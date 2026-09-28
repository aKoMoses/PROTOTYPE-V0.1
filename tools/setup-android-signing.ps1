param(
    [string]$Repository = 'aKoMoses/PROTOTYPE-V0.1'
)

$ErrorActionPreference = 'Stop'
$directory = Join-Path (Split-Path $PSScriptRoot -Parent) '.android-signing'
$keystore = Join-Path $directory 'prototype0-test.jks'
$passwordFile = Join-Path $directory 'prototype0-test-password.txt'

$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) {
    throw 'GitHub CLI absent. Installer gh, lancer gh auth login, puis relancer ce script.'
}
& gh auth status 2>$null
if ($LASTEXITCODE -ne 0) {
    throw 'Connexion GitHub requise : gh auth login'
}

if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin\keytool.exe'))) {
    $keytool = Join-Path $env:JAVA_HOME 'bin\keytool.exe'
} else {
    $command = Get-Command keytool -ErrorAction SilentlyContinue
    if (-not $command) { throw 'keytool absent. Ajouter le JDK 17 au PATH, puis relancer.' }
    $keytool = $command.Source
}

New-Item -ItemType Directory -Force -Path $directory | Out-Null
if ((Test-Path $keystore) -xor (Test-Path $passwordFile)) {
    throw 'La cle et son mot de passe doivent rester ensemble. Restaurer la sauvegarde avant de continuer.'
}
if (-not (Test-Path $keystore)) {
    $randomBytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($randomBytes) } finally { $rng.Dispose() }
    $password = [Convert]::ToBase64String($randomBytes)
    & $keytool -genkeypair -noprompt -storetype PKCS12 -keyalg RSA -keysize 3072 `
        -validity 10000 -alias prototype0test -dname 'CN=Prototype 0 test' `
        -keystore $keystore -storepass $password -keypass $password
    if ($LASTEXITCODE -ne 0) { throw 'Creation de la cle impossible.' }
    [IO.File]::WriteAllText($passwordFile, $password)
} else {
    $password = [IO.File]::ReadAllText($passwordFile).Trim()
}

& $keytool -list -keystore $keystore -alias prototype0test -storepass $password > $null
if ($LASTEXITCODE -ne 0) { throw 'Cle ou mot de passe invalide.' }

$encoded = [Convert]::ToBase64String([IO.File]::ReadAllBytes($keystore))
& gh secret set PROTOTYPE0_KEYSTORE_BASE64 --repo $Repository --body $encoded
if ($LASTEXITCODE -ne 0) { throw 'Envoi de la cle GitHub impossible.' }
& gh secret set PROTOTYPE0_KEYSTORE_PASSWORD --repo $Repository --body $password
if ($LASTEXITCODE -ne 0) { throw 'Envoi du mot de passe GitHub impossible.' }

Write-Host 'Signature Android configuree. Sauvegarder hors du depot le dossier .android-signing ; ne jamais publier son contenu.'
