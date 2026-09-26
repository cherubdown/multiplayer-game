# Multiplayer Survival Game

An open-source, Valheim-style co-op survival game built with Godot 4 (GDScript) and ENet networking.

## Running

Open the folder in Godot 4.3 or newer and press Play to get the Host / Join menu.

The same project runs in three modes, picked by command-line flags:

| Mode | Command |
| :--- | :--- |
| Host and play (listen server) | `godot --path . --host [--port=7777]` |
| Client | `godot --path . --join=127.0.0.1 [--port=7777]` |
| Headless dedicated server | `godot --headless --path . --server [--port=7777]` |

Flags can also go after `--` (for example `godot --path . -- --host`), which is how you pass them to an exported build without Godot warning about unknown arguments. Running headless, or an export with the `dedicated_server` feature, starts a dedicated server even without `--server`.

## Layout

- `scripts/network.gd` is the `Network` autoload that owns the `ENetMultiplayerPeer` and the three launch modes.
- `scenes/main.tscn` with `scripts/main.gd` is the entry scene: it reads the flags, or shows the Host / Join menu and a lobby of connected players.
