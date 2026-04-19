# Steam Multiplayer Setup

The game's multiplayer mode uses Steam's lobby/chat system, routed through the
**GodotSteam** GDExtension plugin. Local (hot-seat) play works out of the box
with no extra setup — the steps below are only needed if you want to play over
the internet.

> **Overview:** both players install the GodotSteam plugin into the project,
> run Steam on their machine, and open the project in Godot. One player
> clicks **Host** (which creates a Steam lobby and shows a Lobby ID); the other
> clicks **Join** after pasting that Lobby ID.

## 1. Install Steam + have a Steam account

Download the Steam client from <https://store.steampowered.com/about/> and sign
in. Keep it running whenever you play the game — the GodotSteam plugin talks
to the running Steam client.

## 2. Download the GodotSteam plugin

1. Go to <https://github.com/GodotSteam/GodotSteam/releases>
2. Download the release that matches your **Godot 4.x** version. Pick the
   **GDExtension** asset (not the editor build). There are separate zips per OS
   — download the one that matches your OS.
3. Extract the zip. You'll get a folder called `addons/` containing
   `godotsteam/`.

## 3. Drop the plugin into this project

Copy the extracted `addons/` folder so it sits next to `project.godot`:

```
tictactoe/
├── addons/
│   └── godotsteam/
│       ├── godotsteam.gdextension
│       ├── bin/                  (platform-specific libraries)
│       └── ...
├── Main.gd
├── Main.tscn
├── Multiplayer.gd
├── project.godot
├── steam_appid.txt               (already included — contains "480")
└── ...
```

The `steam_appid.txt` file is already in the project. It contains the number
`480`, which is Valve's public "Spacewar" test App ID — that lets Steam init
work without publishing your own app. You can change it later if you have
your own Steam App ID.

## 4. Open the project in Godot

1. Launch Godot 4
2. Import the project (select `project.godot`)
3. If Godot asks about new files/extensions, accept and **restart the editor**
   — the GDExtension binary is only loaded on startup.
4. Open **Project → Project Settings → Plugins** and make sure
   **GodotSteam** is enabled.
5. Press **F5** (or the Play button) to run.

If the plugin loaded correctly, the multiplayer status label near the bottom
of the window will say **"Not connected"** and the Host/Join buttons will be
enabled. If it didn't, you'll see
**"GodotSteam plugin not installed — see SETUP_STEAM.md"** and the buttons
stay disabled.

## 5. Play online

**Host:**
1. Click **Host**.
2. Wait for the Lobby ID to appear in the text field. Click **Copy** to put
   it on the clipboard.
3. Send the Lobby ID to your friend (Discord, SMS, email — whatever).
4. When they join, you'll see "Opponent joined. You are X." and a fresh
   board appears.

**Joiner:**
1. Paste the Lobby ID into the text field.
2. Click **Join**.
3. You're O. Wait briefly for the host to start the game.

While connected, only the host can change rules (grid size, arrow limit,
corner bonus, arrows-end-turn, New Game, Reset Scores). The X/O turn chip
shows **"(You)"** next to your side so you know who's who.

## Troubleshooting

- **"Steam init failed"** when you click Host/Join → Steam client isn't
  running, or the plugin can't find `steam_appid.txt` / the Steam runtime.
  Make sure Steam is running and that `steam_appid.txt` is in the project
  folder.
- **Plugin loads but Host does nothing** → Check Godot's Output panel for
  errors. If you see something like `createLobby is not a method`, your
  plugin version is older than expected. Grab the latest release.
- **"Failed to join lobby"** → Lobby IDs are long numbers. Make sure you
  copied the full value and that the host hasn't closed their session.
- **Corporate / university networks** sometimes block Steam P2P traffic.
  Try a different network or use a mobile hotspot to test.

## Notes

- App ID 480 is a public test ID — it's fine for development and personal
  play, but it isn't tied to any specific game and anyone using it appears
  as playing "Spacewar" in Steam. To ship this as a real Steam game, you'd
  register your own App ID on Steamworks and replace the `480` in
  `steam_appid.txt`.
- The entire networking layer is in `Multiplayer.gd`. If you want to swap
  to ENet or WebSockets later, that's the only file that would need
  substantial changes.
