# Tic Tac Toe — Godot 4 Project

A complete two-player Tic Tac Toe game built with Godot 4.

## Requirements
- **Godot 4.2+** (download free at https://godotengine.org)

## How to Open
1. Download and install Godot 4
2. Open Godot and click **Import**
3. Navigate to this folder and select `project.godot`
4. Click **Import & Edit**
5. Press **F5** (or the Play button) to run the game

## Features
- Two-player local play (X and O take turns)
- Winning line highlights when someone wins
- Score tracking across rounds (X wins / O wins / Draws)
- "New Game" button to reset the board
- Dark themed UI with colored X (blue) and O (orange)
- **Turn indicator**: two chips near the top of the screen showing **X** and **O**. The active player's chip lights up with a bright player-colored border, a tinted background, and a full-color letter; the inactive chip is dimmed. When the game ends both chips are dimmed.
- Directional shift arrows (▲ ▼ ◀ ▶) that slide every piece one cell in that direction; pieces sliding off the edge are removed
- **Per-player arrow-use limit**: a SpinBox lets you set how many times each player can click an arrow per game (default **3**). Remaining counts for each player are shown above the board. When a player runs out, the arrows disable on their turn. The new limit takes effect on the next **New Game** (lowering the limit mid-game clamps each player's remaining count down to the new cap).
- **Arrows end turn toggle**: a CheckBox (off by default). When enabled, pressing an arrow also ends the current player's turn — just like placing a piece. When disabled (default), a player can keep pressing arrows until they run out of uses or place a piece. This setting takes effect immediately (it's a pure rule change with no board state to rebuild).
- **Selectable grid size**: an OptionButton lets you choose between a **3x3** and a **4x4** board. The change takes effect on the next **New Game**.
  - 3x3 wins: rows, columns, and the two main diagonals (classic).
  - 4x4 wins: rows (4-in-a-row), columns, the two main diagonals, **any 2x2 square** of four matching marks, and **diamonds** — four matching marks in the cells directly above, below, left, and right of any single center cell. (The center cell itself is not part of the diamond — only the four surrounding cells must match.)
- **Corner bonuses**: a CheckBox (on by default). When enabled, each new game spawns a small yellow ★ icon on the four corner squares of the board. The first time a player *places* (clicks) on a ★ corner, they gain **+1 arrow use** and the bonus is consumed. The bonus is only triggered by direct placement, not by pieces shifting onto a corner. The setting takes effect on the next **New Game**.

## Project Files
- `project.godot` — Godot project config
- `Main.tscn` — Main scene with all UI nodes
- `Main.gd` — Game logic (win detection, score, turn management)
- `Cell.gd` — Individual board cell button behavior
- `icon.svg` — App icon

## License
All rights reserved. 