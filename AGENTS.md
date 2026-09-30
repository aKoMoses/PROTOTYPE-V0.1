# Project instructions

## Coordination of development work (both contributors)

Before changing files for a development request, run `node tools/coordinate.cjs context`. Check active, interrupted, locally finished and recently published work for the same intent. Questions, reviews and analysis alone do not create reservations. Do not upload the raw user prompt or transcript.

Read `docs/coordination-codex.md`. Get valid sector identifiers with `node tools/coordinate.cjs catalog`, then reserve one precise modification using `node tools/coordinate.cjs claim --title "Short public description" --topic "stable-specific-topic" --sectors "sector-id" --files "scripts/relevant.gd"`. Use CODEX_THREAD_ID or the `--session` value supplied by the hook. Reuse this reservation throughout the work and do not create one per follow-up prompt. Different modifications in the same sector are allowed. Shared files and similar titles are warnings: inspect the other work before proceeding. A duplicate or failed reservation must be resolved before writing, never bypassed by renaming the topic.

If a lease expires, recheck the board and claim again. Finish with `node tools/coordinate.cjs finish --summary "Short French description of the verified result"` only after meaningful verification. The public summary must contain at most two short sentences, with no secrets, prompt quotes or implementation logs; it feeds the next morning's Discord report by sector. Include `Prototype-Work: <reservation id>` as a commit trailer for commits containing this work. The GitHub main push workflow confirms publication; never report a local commit as published. Use `cancel` only when abandoning that work, without discarding any files. Do not finish because a response ended or the user asked a status question.

If the local setup is missing, prepare read-only work and request activation with `node tools/coordinate.cjs setup` and `/hooks`. Never commit the local identity/token, disable the hooks, use a trust bypass, or silently continue edits when coordination is unavailable. Preserve unrelated changes and stage only the requested work.

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
