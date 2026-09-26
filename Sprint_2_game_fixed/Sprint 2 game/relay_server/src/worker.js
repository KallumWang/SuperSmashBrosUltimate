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
    this.sockets = [];
  }

  async fetch(request) {
    const upgradeHeader = request.headers.get("Upgrade") || "";
    if (upgradeHeader.toLowerCase() !== "websocket") {
      return new Response("Expected a WebSocket upgrade request", { status: 400 });
    }

    if (this.sockets.length >= 2) {
      return new Response("Room is full", { status: 403 });
    }

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);

    server.accept();
    this.sockets.push(server);
    const justFilled = this.sockets.length === 2;

    server.addEventListener("message", (event) => {
      for (const other of this.sockets) {
        if (other !== server && other.readyState === WS_OPEN) {
          other.send(event.data);
        }
      }
    });

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

    if (justFilled) {
      for (const s of this.sockets) {
        try {
          s.send(JSON.stringify({ type: "ready" }));
        } catch (err) {
          // ignore - the close/error listener above will clean this up
        }
      }
    }

    return new Response(null, { status: 101, webSocket: client });
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const match = url.pathname.match(/^\/room\/([A-Za-z0-9]{3,12})$/);
    if (!match) {
      return new Response(
        "Smash relay is running. Connect to /room/<code> as a WebSocket.",
        { status: 200 }
      );
    }
    const code = match[1].toUpperCase();
    const id = env.ROOMS.idFromName(code);
    const stub = env.ROOMS.get(id);
    return stub.fetch(request);
  },
};
