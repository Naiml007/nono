# nono

Godot 4.7 project. Ziva AI agent is installed in `addons/`.

## Folder structure

| Folder            | Purpose                                              |
| ----------------- | ---------------------------------------------------- |
| `scenes/`         | All `.tscn` scenes (main, UI, entities)              |
| `scripts/`        | All `.gd` scripts (mirror the `scenes/` layout)      |
| `assets/sprites/` | Character / object / UI sprites                      |
| `assets/textures/`| Textures, materials                                  |
| `assets/tilesets/`| TileSet atlas sheets                                 |
| `assets/audio/`   | `sfx/` sound effects, `music/` music tracks          |
| `assets/fonts/`   | Fonts                                                |
| `resources/`      | `.tres` resources (themes, palettes, data, configs)  |
| `shaders/`        | `.gdshader` shader files                             |
| `tests/`          | Test scripts (GUT-style)                             |
| `addons/`         | Editor plugins (Ziva) — do not edit manually        |

## Conventions
- Keep scenes and their scripts in matching folders (`scenes/player.tscn` → `scripts/player.gd`).
- Assets live under `assets/`, referenced by relative `res://assets/...` paths.
- Put reusable logic in `scripts/`; put reusable data/resources in `resources/`.
