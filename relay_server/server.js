// Tic Tac Toe relay server.
//
// A minimal WebSocket relay that pairs two clients into a "room" and
// forwards opaque JSON payloads between them. The relay never inspects
// game state — it just routes envelopes:
//
//   client -> server: { "type": "create" }
//                     { "type": "join", "code": "ABC123" }
//                     { "type": "msg", "data": <opaque payload> }
//                     { "type": "leave" }
//
//   server -> client: { "type": "created", "code": "ABC123" }
//                     { "type": "joined", "code": "ABC123" }
//                     { "type": "opponent_joined" }
//                     { "type": "msg", "data": <opaque payload> }
//                     { "type": "opponent_left" }
//                     { "type": "error", "message": "..." }
//
// One process, in-memory state — perfect for a hobby project. If the
// process restarts, in-flight rooms are lost, which is fine for tic-tac-toe.

const { WebSocketServer, WebSocket } = require('ws');

const PORT = process.env.PORT ? parseInt(process.env.PORT, 10) : 8080;

// roomCode -> { host: WebSocket, guest: WebSocket | null, createdAt: number }
const rooms = new Map();

// Reject ambiguous characters so codes are easy to read aloud or type.
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const CODE_LENGTH = 6;

function makeCode() {
  // Brute-force collision check is fine; with 31^6 codes a clash is negligible.
  let code;
  do {
    code = '';
    for (let i = 0; i < CODE_LENGTH; i++) {
      code += CODE_ALPHABET.charAt(Math.floor(Math.random() * CODE_ALPHABET.length));
    }
  } while (rooms.has(code));
  return code;
}

function send(ws, obj) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(obj));
  }
}

function peerOf(ws) {
  const room = ws.roomCode ? rooms.get(ws.roomCode) : null;
  if (!room) return null;
  return ws.role === 'host' ? room.guest : room.host;
}

function tearDownRoom(code, reasonForRemainingPeer) {
  const room = rooms.get(code);
  if (!room) return;
  for (const peer of [room.host, room.guest]) {
    if (peer && peer.readyState === WebSocket.OPEN) {
      send(peer, { type: 'opponent_left', reason: reasonForRemainingPeer });
      peer.close(1000, 'room closed');
    }
    if (peer) {
      peer.roomCode = null;
      peer.role = null;
    }
  }
  rooms.delete(code);
}

const wss = new WebSocketServer({ port: PORT });
console.log(`Tic Tac Toe relay listening on :${PORT}`);

// Heartbeat — drop sockets that go silent for >60s. Cheap insurance against
// orphaned rooms when a client's network dies without a clean close.
setInterval(() => {
  for (const ws of wss.clients) {
    if (ws.isAlive === false) {
      ws.terminate();
      continue;
    }
    ws.isAlive = false;
    try { ws.ping(); } catch (e) { /* ignore */ }
  }
}, 30000);

wss.on('connection', (ws) => {
  ws.isAlive = true;
  ws.roomCode = null;
  ws.role = null;

  ws.on('pong', () => { ws.isAlive = true; });

  ws.on('message', (raw) => {
    let envelope;
    try {
      envelope = JSON.parse(raw.toString('utf8'));
    } catch (e) {
      send(ws, { type: 'error', message: 'malformed JSON' });
      return;
    }
    if (!envelope || typeof envelope !== 'object') {
      send(ws, { type: 'error', message: 'envelope must be an object' });
      return;
    }

    switch (envelope.type) {
      case 'create': {
        if (ws.roomCode) {
          send(ws, { type: 'error', message: 'already in a room' });
          return;
        }
        const code = makeCode();
        rooms.set(code, { host: ws, guest: null, createdAt: Date.now() });
        ws.roomCode = code;
        ws.role = 'host';
        send(ws, { type: 'created', code });
        break;
      }
      case 'join': {
        if (ws.roomCode) {
          send(ws, { type: 'error', message: 'already in a room' });
          return;
        }
        const code = String(envelope.code || '').trim().toUpperCase();
        const room = rooms.get(code);
        if (!room) {
          send(ws, { type: 'error', message: 'room not found' });
          return;
        }
        if (room.guest) {
          send(ws, { type: 'error', message: 'room is full' });
          return;
        }
        room.guest = ws;
        ws.roomCode = code;
        ws.role = 'guest';
        send(ws, { type: 'joined', code });
        send(room.host, { type: 'opponent_joined' });
        break;
      }
      case 'msg': {
        const peer = peerOf(ws);
        if (!peer) {
          // Silently drop — client probably sent a message before the room
          // was set up. Surface as a soft error rather than tearing down.
          send(ws, { type: 'error', message: 'no peer in room yet' });
          return;
        }
        send(peer, { type: 'msg', data: envelope.data });
        break;
      }
      case 'leave': {
        if (ws.roomCode) {
          tearDownRoom(ws.roomCode, 'opponent left');
        }
        break;
      }
      default: {
        send(ws, { type: 'error', message: `unknown type: ${envelope.type}` });
      }
    }
  });

  ws.on('close', () => {
    if (ws.roomCode) {
      tearDownRoom(ws.roomCode, 'opponent disconnected');
    }
  });

  ws.on('error', (err) => {
    console.error('socket error:', err.message);
  });
});
