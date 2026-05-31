# Tic Tac Toe Relay Server

A minimal WebSocket relay that pairs two Tic Tac Toe clients into a "room" and forwards JSON game messages between them. ~150 lines of Node.js, one in-memory `Map`, no database.

The Godot client (`tictactoe/Multiplayer.gd`) connects to this server, asks for a room code, and from that point the relay is just a dumb pipe — it never inspects game state.

## Local development

You'll need [Node.js 18+](https://nodejs.org).

```
cd relay_server
npm install
npm start
```

The server listens on `ws://localhost:8080`. Point the Godot client at that address by editing `tictactoe/Multiplayer.gd`:

```gdscript
const RELAY_URL := "ws://localhost:8080"
```

Run the game in two Godot windows on the same machine to smoke-test the flow: one clicks **Host**, copies the code, the other pastes and clicks **Join**.

## Deploying for free

For two-friends-on-the-internet play, the relay needs to live on a public host. Three options that have a free tier and zero-config WebSocket support:

### Fly.io (recommended)

1. Install the Fly CLI: <https://fly.io/docs/hands-on/install-flyctl/>
2. From this folder, run `fly launch` and accept the prompts (skip Postgres, skip Redis, accept the Dockerfile). Fly will detect the `Dockerfile` and deploy.
3. After deploy, `fly status` shows your URL. Use the `wss://` form of it (e.g. `wss://my-tictactoe-relay.fly.dev`) as the `RELAY_URL` in Godot.

Fly's free tier easily covers a tic-tac-toe relay; the app idles to zero RAM when nobody's connected.

### Railway

1. Create a new project at <https://railway.com> (formerly railway.app).
2. Connect the GitHub repo containing this folder; Railway will auto-detect Node and deploy.
3. Set the *Root Directory* to `relay_server` in the service settings so it doesn't try to build the Godot project.
4. Railway gives you a public URL — use the `wss://...` form as `RELAY_URL`.

### Render

1. Create a new **Web Service** at <https://render.com> from your GitHub repo.
2. Set *Root Directory* to `relay_server`, *Build Command* to `npm install`, *Start Command* to `node server.js`.
3. Free instances spin down after ~15 minutes of inactivity, so the first connect after a quiet period takes ~30 seconds while the dyno wakes up. Fine for casual play.

## Wire format

All messages are single-frame UTF-8 JSON. Client → server envelopes:

| `type`   | Other fields            | Meaning                                   |
| -------- | ----------------------- | ----------------------------------------- |
| `create` | —                       | Open a fresh room and assign me a code.   |
| `join`   | `code`                  | Add me to the room with this code.        |
| `msg`    | `data` (any JSON value) | Forward this to the peer in my room.      |
| `leave`  | —                       | Close the room and notify my peer.        |

Server → client envelopes:

| `type`            | Other fields | Meaning                                         |
| ----------------- | ------------ | ----------------------------------------------- |
| `created`         | `code`       | Room is open; share this code.                  |
| `joined`          | `code`       | You're in.                                      |
| `opponent_joined` | —            | (Host only) the second player connected.        |
| `msg`             | `data`       | Game message forwarded from your peer.          |
| `opponent_left`   | `reason`     | Your peer disconnected; the room is gone.       |
| `error`           | `message`    | Something went wrong — see message for details. |

The relay never looks inside `data` — it's whatever the Godot client sends (`{"t": "click", ...}`, `{"t": "shift", ...}`, etc.).
