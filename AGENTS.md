# Project instructions

## Prototype 0 paths

- Godot project root (the directory containing `project.godot`): `C:\RomainOpen\perso\Studio\game-source`
- Godot 4.7.2 install directory: `C:\RomainOpen\perso\Godot_4.7.2`
- Godot GUI executable: `C:\RomainOpen\perso\Godot_4.7.2\Godot_v4.7.2-stable_win64.exe`
- Godot console executable for CLI, imports, and headless runs: `C:\RomainOpen\perso\Godot_4.7.2\Godot_v4.7.2-stable_win64_console.exe`

The Godot folder is named `Godot_4.7.2` (with an underscore after `Godot`); there is no `Godot\_4.7.2` directory. Always use the absolute executable paths above instead of assuming `godot` is on `PATH`.

## Common commands

Open the game in the Godot editor:

```powershell
& 'C:\RomainOpen\perso\Godot_4.7.2\Godot_v4.7.2-stable_win64.exe' --path 'C:\RomainOpen\perso\Studio\game-source'
```

Import project resources and check editor-side script loading:

```powershell
& 'C:\RomainOpen\perso\Godot_4.7.2\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\RomainOpen\perso\Studio\game-source' --editor --quit
```

Run the game from the console executable:

```powershell
& 'C:\RomainOpen\perso\Godot_4.7.2\Godot_v4.7.2-stable_win64_console.exe' --path 'C:\RomainOpen\perso\Studio\game-source'
```
