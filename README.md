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

To keep strangers out, give the server a password with `--server-password=<password>` (quote it if it has spaces), or type one in the **Server password** box before pressing **Host**. Players then type the same password in that box before pressing **Join**, or pass the same flag with `--join`. A client with the wrong password is disconnected before it can log in. Leave it empty for an open server.

Use the `_console.exe` build for the dedicated server so its log prints in the terminal. Flags can also go after `--` (for example `... --path . -- --host`), which keeps Godot from warning about arguments it doesn't know. Running headless, or a dedicated server export, starts a dedicated server even without `--server`.

## The world

Each server plays on one island, generated from a **world seed**: any text, like `--seed="Chris's world"`. The same seed always makes the same island, with the same biomes, hills and trees, on every PC. The world is created the first time a server (or host) starts:

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . --server --seed="Chris's world"
```

Without `--seed` the server makes up a random seed such as `raven-elder-5319` and prints it. When hosting from the menu, type the seed in the **World seed** box before pressing **Host**. The seed is saved in the server's `accounts.db`, so every later start loads the same world; a different `--seed` after that is ignored with a warning. To start over with a new world, stop the server and delete `accounts.db` (which also deletes the accounts). Clients never need the seed: the server sends it when they connect and each client builds the island itself.

The island is 1 km across and ringed by ocean. Like Valheim, it gets harsher away from the middle:

| Biome | Where |
| :--- | :--- |
| Meadows | The calm middle, where everyone spawns. Grass, scattered leafy trees. |
| Black Forest | The ring around the Meadows. Dense pines. |
| Swamp | Flat, soggy patches between the Meadows and the coast, with dead trees. |
| Plains | Dry, open land near the coast, with rocks. |
| Mountains | Wherever the land rises high, with snow on the peaks. |
| Ocean | Around the edge, and in lakes inland. |

Each biome also has its own plants: grass and wildflowers in the Meadows, ferns, mushrooms and fallen logs in the Black Forest, reeds and cattails in the Swamp, dry grass on the Plains, plus bushes and birches. They sway in the wind and grow in the same places for everyone. Trees, rocks and plants are scenery for now: you can walk through them.

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

## Accounts and characters

After you host or join, you log in to that server. The first time, type a username and password and press **Create account**; after that, **Log in**. Then the character select screen lets you create up to 5 characters, delete them, and pick one with **Play** (or double-click it) to enter the world.

Every character is a **Human**, an **Elf**, a **Dwarf** or an **Ogre**, and **Male** or **Female**. Pick both with the buttons above the name box before pressing **Create**; the preview shows that model, and selecting a character in the list shows theirs. Race and sex are saved with the character and can't be changed later. Characters made before races existed are humans, and characters made before sexes could be picked are male.

New characters start with nothing: an empty inventory, wearing only a plain t-shirt and trousers, barefoot.

The character models are built in code (`scripts/character_model.gd`) from each race and sex's body measurements in `scripts/races.gd`, so there are no model files to import. Humans are average in every way; elves are tall and slender with long pointed ears; dwarves are short and broad, the men with a braided beard and the women with braids; ogres are huge, green-skinned and tusked. Tweak a number in `races.gd` to reshape a race. The idle, walk, run, jump and cheer animations are keyframed on the model's joints in the same script.

Accounts belong to the server, not to your PC. The host (or dedicated server) keeps every account and its characters in a SQLite database, `accounts.db`, in its user data folder, which on Windows is `%APPDATA%\Godot\app_userdata\Multiplayer Survival Game\`. There is nothing to install or set up: the server creates the database the first time it starts and prints its full path. Pass `--accounts=<path>` to the host or server to keep it somewhere else. To back up a server's accounts, stop the server and copy `accounts.db`. If an older build left an `accounts.json` there, its accounts move into the new database on first start and the file is renamed `accounts.json.imported`.

Passwords are never stored: the database holds a random per-account salt and a PBKDF2-HMAC-SHA256 hash (100,000 iterations). Account and server passwords do cross the network unencrypted, so don't reuse a password you care about.

The database is handled by the [godot-sqlite](https://github.com/2shady4u/godot-sqlite) extension (MIT licensed), vendored in `addons/godot-sqlite/` with its Windows and Linux x86_64 libraries. Exports copy the DLL next to the .exe, so keep the two together when you move a server build.

## Playing

Once you pick a character you're on the island: a new character starts in the Meadows, and after that you come back where you left off, facing the same way. The server saves where every character stands when they leave the world or disconnect, and every 15 seconds in case it stops without warning. Move with WASD or the arrow keys (hold Left Ctrl to walk instead of run), jump with Space, and look around with the mouse. Esc shows the menu (with Character select and Leave) and frees the mouse; click to go back in. Other players' character names float above their heads.

### Items and chests

Every character has a 20-slot inventory. Press **Tab** (or **I**) to look at it. Walk up to an item lying on the ground until a prompt appears, then press **E** to pick it up. Items of the same kind stack, up to 50 in a slot.

Every item has an icon; hover over one to see what it is and what it's for. Drag a stack onto another slot to move it: onto the same item it tops that stack up, onto a different item the two swap. Drag a stack off the panel and let go to drop it on the ground in front of you, where anyone can pick it up again with **E**. Dropped items stay until someone picks them up or the server restarts.

Next to the spawn point there is a test chest, with some wood, stone, flint and raspberries scattered around it. Walk up to the chest and press **E** to open it: your inventory and the chest show side by side. Drag stacks between them (or within either one), or click a stack to send it straight to the other side. Press **E**, **Tab** or **Esc** to close it. Picked up test items come back after a minute, so there's always something to try.

The server owns every inventory and chest; clients only ask it to move things. Inventories are saved with each character and the chest's contents with the world, both in `accounts.db`, so they survive a restart. `scripts/items.gd` lists the kinds of items.

To try two players on one machine, start one copy with `--host` and another with `--join=127.0.0.1`.

Movement is server-authoritative: each client only sends its input (`PlayerInput`), and the server runs the physics and replicates every player's position, rotation and velocity to everyone. Each peer picks the animation (idle, walk, run or jump) from that. Dedicated and headless servers never build the models.

## Layout

- `scripts/network.gd` is the `Network` autoload that owns the `ENetMultiplayerPeer` and the three launch modes.
- `scenes/main.tscn` with `scripts/main.gd` is the entry scene: it reads the flags, or shows the Host / Join menu, then the login and character select screens, and in game a list of who is playing.
- `scripts/session.gd` is the `Session` autoload: the login, character and enter-world requests clients send to the server, and the server's record of who is logged in and who is in the world.
- `scripts/account_store.gd` (`AccountStore`) saves accounts, password hashes, characters and the world seed on the server in SQLite, creating and upgrading the tables as needed.
- `addons/godot-sqlite/` is the vendored SQLite extension.
- `scenes/test_world.tscn` with `scripts/test_world.gd` is the game world. It builds the terrain once the world seed is known, and on the server spawns a player per peer through a `MultiplayerSpawner`.
- `scripts/world_gen.gd` turns a seed into the island's heights and biomes (deterministic noise, so every peer agrees). `scripts/terrain.gd` builds the ground collision from it, plus the biome-colored ground, sea, trees and rocks on peers that draw.
- `scripts/races.gd` defines the races and their body measurements; `scripts/character_model.gd` builds and animates the model for a race and sex, for players and for the character select preview (`scripts/character_preview.gd`).
- `scenes/player.tscn` is the third-person `CharacterBody3D` player. `scripts/player.gd` moves it on the server; `scripts/player_input.gd` collects the owning client's input and syncs it to the server.
- `tests/` has headless tests for the account store, the world generator and the whole login flow; `.github/scripts/run-tests.sh` runs them (CI does too).
- `export_presets.cfg` holds the Windows game and dedicated server export presets.
