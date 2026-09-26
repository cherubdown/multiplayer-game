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

## Playing

Hosting or joining drops you into a flat test world. Move with WASD or the arrow keys, jump with Space, and look around with the mouse. Esc shows the menu (with Leave) and frees the mouse; click to go back in.

To try two players on one machine, start one copy with `--host` and another with `--join=127.0.0.1`.

Movement is server-authoritative: each client only sends its input (`PlayerInput`), and the server runs the physics and replicates every player's position and rotation to everyone.

## Layout

- `scripts/network.gd` is the `Network` autoload that owns the `ENetMultiplayerPeer` and the three launch modes.
- `scenes/main.tscn` with `scripts/main.gd` is the entry scene: it reads the flags, or shows the Host / Join menu and a lobby of connected players.
- `scenes/test_world.tscn` with `scripts/test_world.gd` is the flat test world. On the server it spawns a player per peer through a `MultiplayerSpawner`.
- `scenes/player.tscn` is the third-person `CharacterBody3D` player. `scripts/player.gd` moves it on the server; `scripts/player_input.gd` collects the owning client's input and syncs it to the server.
