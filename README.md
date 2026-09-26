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

## Accounts and characters

After you host or join, you log in to that server. The first time, type a username and password and press **Create account**; after that, **Log in**. Then the character select screen lets you create up to 5 characters, delete them, and pick one with **Play** (or double-click it) to enter the world.

Accounts belong to the server, not to your PC. A dedicated server should keep them in PostgreSQL (see [Accounts database](#accounts-database)). Without a database, the host or server keeps every account and its characters in `accounts.json` in its user data folder, which on Windows is `%APPDATA%\Godot\app_userdata\Multiplayer Survival Game\`; that's fine for hosting a game with friends from your own PC. Pass `--accounts=<path>` to keep that file somewhere else (it also wins over a database). The server prints where accounts are kept as it starts.

Passwords are only ever stored as salted hashes: bcrypt in PostgreSQL, PBKDF2-SHA256 in `accounts.json`. They still cross the game network unencrypted, so don't reuse a password you care about.

## Accounts database

The dedicated server stores accounts in PostgreSQL when the `DATABASE_URL` environment variable is set. The server creates its tables itself the first time it connects, and won't start if it can't reach the database, so a typo shows up right away. Credentials stay out of the repository: the password lives only in your environment and in a `.env` file that git ignores.

`DATABASE_URL` looks like `postgres://game:<password>@127.0.0.1:5432/game`. Percent-encode special characters in the password (`@` is `%40`, `:` is `%3A`). For a database on another machine, add `?sslmode=require` to use TLS, or `?sslmode=verify-full&sslrootcert=C:/path/to/root.crt` to also check its certificate.

### With Docker Desktop

1. Install [Docker Desktop](https://www.docker.com/products/docker-desktop/).
2. In PowerShell in this folder, copy the example settings and set your own password in `.env`:
   ```powershell
   Copy-Item .env.example .env
   notepad .env
   ```
3. Start the database. It keeps running in the background and restarts with Docker; the data lives in a Docker volume.
   ```powershell
   docker compose up -d
   ```
4. Start the server with the same password in `DATABASE_URL`:
   ```powershell
   $env:DATABASE_URL = "postgres://game:<password>@127.0.0.1:5432/game"
   Godot_v4.3-stable_win64_console.exe --headless --path . --server
   ```
   The log should say `Accounts are saved in PostgreSQL database game on 127.0.0.1:5432 as game`. `$env:` only lasts for that PowerShell window; `setx DATABASE_URL "..."` keeps it for new windows.

`docker compose down` stops the database and keeps the data; `docker compose down -v` deletes it.

### Without Docker

1. Install PostgreSQL 16 for Windows from https://www.postgresql.org/download/windows/ (the installer includes the pgcrypto extension the server needs).
2. Open **SQL Shell (psql)** from the Start menu, log in as `postgres`, and make a user and database for the game:
   ```sql
   CREATE ROLE game LOGIN PASSWORD '<password>';
   CREATE DATABASE game OWNER game;
   ```
3. Start the server with `DATABASE_URL` set, as in step 4 above.

To look at the accounts, connect with `psql -h 127.0.0.1 -U game game` (or `docker compose exec db psql -U game game`) and `SELECT username, created_at, last_login_at FROM accounts;`. The `password_hash` column holds bcrypt hashes, never passwords.

## Playing

Once you pick a character you're in a flat test world. Move with WASD or the arrow keys, jump with Space, and look around with the mouse. Esc shows the menu (with Character select and Leave) and frees the mouse; click to go back in. Other players' character names float above their heads.

To try two players on one machine, start one copy with `--host` and another with `--join=127.0.0.1`.

Movement is server-authoritative: each client only sends its input (`PlayerInput`), and the server runs the physics and replicates every player's position and rotation to everyone.

## Layout

- `scripts/network.gd` is the `Network` autoload that owns the `ENetMultiplayerPeer` and the three launch modes.
- `scenes/main.tscn` with `scripts/main.gd` is the entry scene: it reads the flags, or shows the Host / Join menu, then the login and character select screens, and in game a list of who is playing.
- `scripts/session.gd` is the `Session` autoload: the login, character and enter-world requests clients send to the server, and the server's record of who is logged in and who is in the world.
- `scripts/account_store.gd` (`AccountStore`) saves accounts, password hashes and characters in a JSON file; `scripts/postgres_account_store.gd` does the same in PostgreSQL, using `scripts/postgres_client.gd`, a small PostgreSQL client written in GDScript. `scripts/account_worker.gd` runs their work on a background thread so hashing and queries don't stall the game.
- `compose.yaml` runs PostgreSQL for local development.
- `scenes/test_world.tscn` with `scripts/test_world.gd` is the flat test world. On the server it spawns a player per peer through a `MultiplayerSpawner`.
- `scenes/player.tscn` is the third-person `CharacterBody3D` player. `scripts/player.gd` moves it on the server; `scripts/player_input.gd` collects the owning client's input and syncs it to the server.
- `tests/` has headless tests for the account stores and the whole login flow; `.github/scripts/run-tests.sh` runs them (CI does too, against a PostgreSQL service). Set `DATABASE_URL` to include the PostgreSQL checks locally.
- `export_presets.cfg` holds the Windows game and dedicated server export presets.
