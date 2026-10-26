// Smash relay server - Cloudflare Worker + Durable Object.
//
// This does NOT understand the game at all. It just pairs up to 2
// WebSocket connections that ask for the same room code, and forwards
// whatever one sends to the other, verbatim. All game logic (positions,
// damage, hits) lives entirely in the Godot client - this is a dumb pipe.
//
// One RelayRoom Durable Object instance = one room code. Cloudflare
// creates/looks up the right instance for us via idFromName(code), so we
// don't need our own room registry or database.

const WS_OPEN = 1; // WebSocket.OPEN, per the WHATWG WebSocket spec

export class RelayRoom {
  constructor(state, env) {
    this.state = state;
    // The (at most 2) live connections in this room. Not saved anywhere -
    // if Cloudflare ever restarts this room, it starts empty, which is fine
    // for a game session that lasts a few minutes.
    this.sockets = [];
  }

  async fetch(request) {
    // A WebSocket connection starts as a normal HTTP request with an
    // "Upgrade: websocket" header (Godot's WebSocketPeer.connect_to_url
    // sends it). Anything else - like opening the URL in a browser - gets rejected.
    const upgradeHeader = request.headers.get("Upgrade") || "";
    if (upgradeHeader.toLowerCase() !== "websocket") {
      return new Response("Expected a WebSocket upgrade request", { status: 400 });
    }

    // Third player trying the same code: turn them away. (The Godot side
    // sees this as the socket closing before the room was ever ready, so
    // online_lobby.gd shows "Couldn't connect".)
    if (this.sockets.length >= 2) {
      return new Response("Room is full", { status: 403 });
    }

    // A WebSocketPair is two linked ends of one connection: `client` goes
    // back to the player in the 101 response at the bottom, `server` is the
    // end this code keeps and talks through.
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);

    server.accept();
    this.sockets.push(server);
    // True only for the connection that makes the room full - that's the
    // moment both players get told "ready" (further down).
    const justFilled = this.sockets.length === 2;

    // The whole relay: whatever this player sends (state / hit / pick
    // messages from the Godot game), forward untouched to the other player.
    server.addEventListener("message", (event) => {
      for (const other of this.sockets) {
        if (other !== server && other.readyState === WS_OPEN) {
          other.send(event.data);
        }
      }
    });

    // When this player disconnects (closed tab, crash, backed out of the
    // lobby): drop them from the room and tell whoever is left, so the game
    // can react (Godot side: NetworkManager's peer_left signal).
    const cleanup = () => {
      this.sockets = this.sockets.filter((s) => s !== server);
      for (const other of this.sockets) {
        try {
          other.send(JSON.stringify({ type: "peer_left" }));
        } catch (err) {
          // other socket is already gone too; nothing to notify
        }
      }
    };
    server.addEventListener("close", cleanup);
    server.addEventListener("error", cleanup);

    // Second player just connected: tell BOTH sides the room is ready.
    // NetworkManager.gd turns this into its room_ready signal, which moves
    // both players on to Character Select.
    if (justFilled) {
      for (const s of this.sockets) {
        try {
          s.send(JSON.stringify({ type: "ready" }));
        } catch (err) {
          // ignore - the close/error listener above will clean this up
        }
      }
    }

    // 101 = "Switching Protocols" - completes the WebSocket handshake and
    // hands the player their end of the connection.
    return new Response(null, { status: 101, webSocket: client });
  }
}

// The front door - every request to the worker URL hits this first.
// It only decides WHICH room the request belongs to, then hands it over
// to that room's RelayRoom (above).
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    // Only URLs shaped like /room/ABC12 count (3-12 letters/digits;
    // NetworkManager.gd's codes are 5). Anything else just gets a friendly
    // "it's running" message, which is handy for checking the deploy worked.
    const match = url.pathname.match(/^\/room\/([A-Za-z0-9]{3,12})$/);
    if (!match) {
      return new Response(
        "Smash relay is running. Connect to /room/<code> as a WebSocket.",
        { status: 200 }
      );
    }
    // Upper-cased so "abc12" and "ABC12" land in the same room. env.ROOMS is
    // the Durable Object binding set up in the wrangler config - idFromName
    // always maps the same code to the same RelayRoom instance, so both
    // players end up talking to the same one.
    const code = match[1].toUpperCase();
    const id = env.ROOMS.idFromName(code);
    const stub = env.ROOMS.get(id);
    return stub.fetch(request);
  },
};
