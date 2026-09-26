# Multiplayer Survival Game

An open-source, Valheim-style co-op survival game built with Godot 4 (GDScript) and ENet networking. Windows is the primary target.

## Running in the editor

Install Godot 4.3 or newer for Windows from https://godotengine.org/download/windows/ (the standard build, not .NET). Open this folder in Godot and press Play (F5) to get the Host / Join menu.

## Launch modes

The same project runs in three modes, picked by command-line flags. From a PowerShell or Command Prompt window in this folder, with the Godot executable on your PATH or given by its full path:

| Mode | Command |
| :--- | :--- |
| Host and play (listen server) | `Godot_v4.3-stable_win64.exe --path . --host [--port=7777]` |
| Client | `Godot_v4.3-stable_win64.exe --path . --join=127.0.0.1 [--port=7777]` |
| Dedicated server (no window) | `Godot_v4.3-stable_win64_console.exe --headless --path . --server [--port=7777]` |

Use the `_console.exe` build for the dedicated server so its log prints in the terminal. Flags can also go after `--` (for example `... --path . -- --host`), which keeps Godot from warning about arguments it doesn't know. Running headless, or a dedicated server export, starts a dedicated server even without `--server`.

The first time you host or run a server, Windows Firewall asks whether to allow Godot on the network. Allow it on private networks, and forward UDP port 7777 on your router if friends join over the internet.

## Exporting for Windows

`export_presets.cfg` has two presets. Install the Godot 4.3 export templates first (Editor > Manage Export Templates), then use Project > Export, or from the command line:

```
Godot_v4.3-stable_win64_console.exe --headless --path . --export-release "Windows Desktop" build/windows/MultiplayerSurvival.exe
Godot_v4.3-stable_win64_console.exe --headless --path . --export-release "Windows Dedicated Server" build/windows-server/MultiplayerSurvivalServer.exe
```

- **Windows Desktop** is the game players run. Double-click it for the menu, or pass `--host` / `--join=<address>`.
- **Windows Dedicated Server** strips graphics and audio resources and writes `MultiplayerSurvivalServer.exe` plus a `MultiplayerSurvivalServer.console.exe` wrapper. Run the server with `MultiplayerSurvivalServer.console.exe --headless [--port=7777]`.

Both presets leave "Modify Resources" off so they export without rcedit. Turn it on in the export dialog if you want a custom .exe icon and version info.

## Layout

- `scripts/network.gd` is the `Network` autoload that owns the `ENetMultiplayerPeer` and the three launch modes.
- `scenes/main.tscn` with `scripts/main.gd` is the entry scene: it reads the flags, or shows the Host / Join menu and a lobby of connected players.
- `export_presets.cfg` holds the Windows game and dedicated server export presets.
