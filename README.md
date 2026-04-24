# Tic Tac Toe — Godot 4 Project

A complete two-player Tic Tac Toe game built with Godot 4. Supports local
hot-seat play out of the box, plus optional **Steam-based online multiplayer**
via the GodotSteam plugin (see `tictactoe/SETUP_STEAM.md`).

The Godot project itself lives in the `tictactoe/` subfolder — everything
in this README that talks about scene files, scripts, or Godot paths
refers to files inside that folder.

## Requirements
- **Godot 4.2+** (download free at https://godotengine.org)
- *(Optional, for online play)* GodotSteam GDExtension + Steam client — see
  `tictactoe/SETUP_STEAM.md`.

## How to Open
1. Download and install Godot 4
2. Open Godot and click **Import**
3. Navigate to the `tictactoe/` subfolder and select `project.godot`
4. Click **Import & Edit**
5. Press **F5** (or the Play button) to run the game

## Features
- Two-player local play (X and O take turns)
- Winning line highlights when someone wins
- Score tracking across rounds (X wins / O wins / Draws)
- **New Game Settings dialog**: clicking **New Game** opens a popup that holds every game-config option in one place — Grid Size, Arrow Uses per Player, Arrows End Turn, and Corner Bonus. The controls are pre-filled with the currently-applied settings every time you open the dialog. Click **Start Game** to apply the settings and reset the board, or **Cancel** to discard any changes and leave the current game alone.
- Dark themed UI with colored X (blue) and O (orange)
- **Turn indicator**: two chips near the top of the screen showing **X** and **O**. The active player's chip lights up with a bright player-colored border, a tinted background, and a full-color letter; the inactive chip is dimmed. When the game ends both chips are dimmed.
- Directional shift arrows (▲ ▼ ◀ ▶) that slide every piece one cell in that direction; pieces sliding off the edge are removed
- **Per-player arrow-use limit** *(in the New Game dialog)*: a SpinBox lets you set how many times each player can click an arrow per game (default **3**). Remaining counts for each player are shown above the board. When a player runs out, the arrows disable on their turn.
- **Arrows end turn toggle** *(in the New Game dialog)*: a CheckBox (**on by default**). When enabled (default), pressing an arrow also ends the current player's turn — just like placing a piece. When disabled, a player can keep pressing arrows until they run out of uses or place a piece.
- **Online multiplayer (Steam)**: with the GodotSteam plugin installed, one player clicks **Host** to create a Steam lobby and receives a Lobby ID; the other pastes the ID and clicks **Join**. Host is X, joiner is O, and the turn indicator adds a **"(You)"** marker next to your side so it's clear who's who. The host is authoritative — only the host can open the New Game dialog, change rules, or Reset Scores; the client's controls for those are locked while connected. Every click, arrow press, New Game, and Reset Scores is synced over Steam's lobby chat channel. The game still runs fine without the plugin — the Host/Join buttons just display a "plugin not installed" notice. See `SETUP_STEAM.md` for the one-time plugin install steps.
- **Selectable grid size** *(in the New Game dialog)*: an OptionButton lets you choose between **3x3**, **4x4**, and **MNK (custom)**.
  - 3x3 wins: rows, columns, and the two main diagonals (classic).
  - 4x4 wins: rows (4-in-a-row), columns, the two main diagonals, **any 2x2 square** of four matching marks, and **diamonds** — four matching marks in the cells directly above, below, left, and right of any single center cell. (The center cell itself is not part of the diamond — only the four surrounding cells must match.)
  - **MNK (custom)** lets you configure an **m,n,k-game** ([Wikipedia](https://en.wikipedia.org/wiki/M,n,k-game)): pick **M** = number of rows (3–12), **N** = number of columns (3–12), and **K** = in-a-row length needed to win (3–10, automatically clamped to max(M, N)). Wins are any **K matching marks in a horizontal, vertical, or diagonal line**. Classic tic-tac-toe is 3,3,3; Gomoku-style play is 12,12,5. The 4x4 preset's squares+diamonds are *not* included in MNK mode — it's strict k-in-a-row. The M/N/K spinboxes sit just below the Grid Size dropdown in the New Game dialog and are always visible; they're editable only when Grid Size is set to **MNK (custom)** and greyed out otherwise, since they only apply to that mode.
- **Arrow Bonus** *(in the New Game dialog)*: a dropdown labeled **"Arrow Bonus (+1 arrow on ★ squares)"** with options **Off**, **Corners**, and **Random** (default: **Corners**). In **Corners** mode, each new game spawns a small yellow ★ icon on the four corner squares of the board. In **Random** mode, every cell on the board independently has a **25% chance** of being armed with a ★ at the start of each new game (so each game gets a different pattern, which is rolled once by the host and synced to the client in online play). In either mode, the first time a player *places* (clicks) on a ★ cell, they gain **+1 arrow use** and the bonus is consumed. The bonus is only triggered by direct placement, not by pieces shifting onto an armed cell. Choose **Off** to disable ★s entirely. The dropdown is designed to take more patterns (center, edges, etc.) as they're added.

## Project Files
- `project.godot` — Godot project config (registers the `Multiplayer` autoload)
- `Main.tscn` — Main scene with all UI nodes
- `Main.gd` — Game logic (win detection, score, turn management, network input gating)
- `GameLogic.gd` — Pure static helpers (win-line generation, corner indices, winner detection). Lives here so the unit tests can exercise it without the scene tree.
- `Cell.gd` — Individual board cell button behavior
- `Multiplayer.gd` — Steam multiplayer autoload (host/join/send/receive). Gracefully reports "not installed" when the GodotSteam plugin isn't present.
- `steam_appid.txt` — Contains `480`, the public Spacewar test App ID that lets Steam init work without publishing the game.
- `SETUP_STEAM.md` — One-time setup steps for installing the GodotSteam plugin.
- `tests/` — GDScript unit tests (`test_game_logic.gd`) and the headless runner (`run_tests.gd`).
- `icon.svg` — App icon

## Running Tests
Unit tests cover the pure board math in `GameLogic.gd` — win-line generation for every grid mode, corner indices, and winner detection (row/column/diagonal/draw/in-progress plus the 4x4 square and diamond cases).

To run them locally (from the repo root):

```
godot --headless --path tictactoe --script res://tests/run_tests.gd
```

The runner exits with status 0 on success and 1 on any failure. Every pull request is automatically checked by the GitHub Actions workflow at `.github/workflows/tests.yml`, which downloads the headless Godot binary and runs the same command.
