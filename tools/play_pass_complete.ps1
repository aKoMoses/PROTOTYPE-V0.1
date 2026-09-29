$projectDirectory = Split-Path -Parent $PSScriptRoot
$packPath = Join-Path $projectDirectory 'exports\pass_complete\prototype0-pass-complete.pck'
$engineCandidates = @(
    'C:\RomainOpen\perso\Godot_4.7.2\Godot_v4.7.2-stable_win64.exe',
    (Join-Path $projectDirectory '.godot\pass-runtime\Godot_v4.7.2-stable_win64.exe')
)
$enginePath = $engineCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $enginePath) { throw 'Godot 4.7.2 introuvable dans les chemins du projet.' }
if (-not (Test-Path -LiteralPath $packPath)) { throw 'Le paquet de la passe complete est absent de exports/pass_complete.' }
& $enginePath --main-pack $packPath
