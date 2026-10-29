// Smash relay server - Cloudflare Worker + two Durable Objects.
//
// RelayRoom (one per room code): groups up to 4 WebSocket connections, gives
// each a slot number (0-3), and forwards whatever one sends to all the
// others (adding a "from" slot). It does NOT run the game - positions,
// damage and hits all live in the Godot clients. The only thing it
// understands beyond forwarding is the small set of "relay messages" below,
// so it can run the lobby, rematches, and record leaderboard results.
//
// Leaderboard (ONE global instance): a small SQLite database of registered
// players (username, wins, games played). It is the only place stats live.
//
// How stats stay honest: clients never write stats directly. At the end of
// an online match every player's game sends {"type":"result","winner":slot};
// the relay only records the match when EVERY player still connected agrees
// on the same winner, and only when at least 2 different registered
// accounts took part (so one person with 4 windows can't farm wins).
//
// Messages the relay itself understands (everything else is just forwarded):
//   hello    client -> relay  {id, token}   identify + ask for the roster
//   roster   relay -> clients {slots, names, you}   who is in the room
//   go       host -> everyone                       start the match (locks the room)
//   result   client -> relay  {winner}              "slot N won" (never forwarded)
//   rematch  client -> relay  (also forwarded)      "I want to play again"
//   rematch_go relay -> everyone                    all players voted: reload the match
//   peer_left relay -> clients {slot}               someone disconnected
//
// HTTP endpoints (used by the Godot game, not by players' browsers):
//   POST /register {name}  -> {id, token, name}  creates an account
//   GET  /leaderboard      -> [{name, games, wins}, ...]

const WS_OPEN = 1; // WebSocket.OPEN, per the WHATWG WebSocket spec
const MAX_PLAYERS = 4; // slots 0-3, matching the four spawn markers on the Stage
const NAME_RE = /^[A-Za-z0-9_]{3,16}$/; // allowed usernames: 3-16 letters, digits or _

// CORS: when the game runs in a web browser (e.g. on itch.io) the page lives
// on a different domain than this relay, so the browser refuses to let it
// read our HTTP answers unless we say it's allowed. (WebSockets don't need
// this, which is why joining a room worked but registering / the leaderboard
// showed "connection error".) The desktop game never needed these headers.
const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Max-Age": "86400",
};
const JSON_HEADERS = { "Content-Type": "application/json", ...CORS_HEADERS };

// Re-wraps a response from the Leaderboard object with the CORS headers.
function withCors(response) {
  const headers = new Headers(response.headers);
  for (const [k, v] of Object.entries(CORS_HEADERS)) headers.set(k, v);
  return new Response(response.body, { status: response.status, headers: headers });
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), { status: status, headers: JSON_HEADERS });
}

// Tokens are never stored - only their SHA-256 hash - so a leaked database
// can't be used to log in as anyone.
async function sha256(text) {
  const bytes = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(hash)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// The one global leaderboard. Every call goes through fetch() below, from
// either the Worker's HTTP routes or a RelayRoom.
export class Leaderboard {
  constructor(state, env) {
    this.sql = state.storage.sql;
    // name_lower is UNIQUE so "Kal" and "kal" can't both exist.
    this.sql.exec(
      "CREATE TABLE IF NOT EXISTS players (" +
        "id TEXT PRIMARY KEY, name TEXT NOT NULL, name_lower TEXT NOT NULL UNIQUE, " +
        "token_hash TEXT NOT NULL, games INTEGER NOT NULL DEFAULT 0, " +
        "wins INTEGER NOT NULL DEFAULT 0, created INTEGER NOT NULL)"
    );
  }

  async fetch(request) {
    const path = new URL(request.url).pathname;
    let body = {};
    if (request.method === "POST") {
      try {
        body = JSON.parse(await request.text());
      } catch (err) {
        return json({ error: "Bad request" }, 400);
      }
    }

    if (path === "/register") {
      const name = String(body.name || "").trim();
      if (!NAME_RE.test(name)) {
        return json({ error: "Username must be 3-16 letters, numbers or _" }, 400);
      }
      const taken = this.sql.exec("SELECT id FROM players WHERE name_lower = ?", name.toLowerCase()).toArray();
      if (taken.length > 0) {
        return json({ error: "That username is taken" }, 409);
      }
      const id = crypto.randomUUID();
      const token = crypto.randomUUID() + crypto.randomUUID();
      this.sql.exec(
        "INSERT INTO players (id, name, name_lower, token_hash, created) VALUES (?, ?, ?, ?, ?)",
        id, name, name.toLowerCase(), await sha256(token), Date.now()
      );
      console.log("registered " + name);
      return json({ id: id, token: token, name: name });
    }

    if (path === "/verify") {
      const rows = this.sql.exec("SELECT name, token_hash FROM players WHERE id = ?", String(body.id || "")).toArray();
      if (rows.length === 1 && rows[0].token_hash === (await sha256(String(body.token || "")))) {
        return json({ ok: true, name: rows[0].name });
      }
      return json({ ok: false });
    }

    if (path === "/record") {
      // body: { winner: <player id>, participants: [<player id>, ...] }
      const ids = [...new Set(body.participants || [])];
      for (const id of ids) {
        this.sql.exec("UPDATE players SET games = games + 1 WHERE id = ?", String(id));
      }
      if (body.winner) {
        this.sql.exec("UPDATE players SET wins = wins + 1 WHERE id = ?", String(body.winner));
      }
      console.log("recorded match, " + ids.length + " players");
      return json({ ok: true });
    }

    if (path === "/top") {
      const rows = this.sql
        .exec("SELECT name, games, wins FROM players WHERE games > 0 ORDER BY wins DESC, games ASC LIMIT 200")
        .toArray();
      return json(rows);
    }

    return json({ error: "Not found" }, 404);
  }
}

export class RelayRoom {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    // The live connections in this room (up to MAX_PLAYERS): an array of
    // { socket, slot, id, name } where slot is 0-3 and doubles as the player
    // number in the game (slot 0 = the host = P1, and so on). id/name are
    // filled in by the "hello" message when the player has a verified
    // account. Not saved anywhere - if Cloudflare restarts this room it
    // starts empty, which is fine for a game session that lasts a few minutes.
    this.players = [];
    // Flips to true when the host sends "go" (the match is starting). A
    // started room turns new joiners away, so nobody can pop in mid-match.
    this.started = false;
    // The match in progress, for leaderboard recording (see startMatch).
    this.match = null;
    // Slots that have asked for a rematch on the results screen.
    this.votes = new Set();
  }

  // Ask the Leaderboard object something. path is "/verify", "/record" ...
  async askLeaderboard(path, body) {
    const stub = this.env.LEADERBOARD.get(this.env.LEADERBOARD.idFromName("global"));
    const res = await stub.fetch("https://leaderboard" + path, { method: "POST", body: JSON.stringify(body) });
    return res.json();
  }

  // Tell every player who is in the room. Each player gets their OWN slot
  // number too ("you"), because that is how a client learns which fighter
  // it controls. NetworkManager.gd turns this into its roster_changed signal.
  broadcastRoster() {
    const slots = this.players.map((p) => p.slot);
    const names = {};
    for (const p of this.players) names[p.slot] = p.name || "";
    for (const p of this.players) {
      try {
        p.socket.send(JSON.stringify({ type: "roster", slots: slots, names: names, you: p.slot }));
      } catch (err) {
        // that socket is already gone; its close listener cleans it up
      }
    }
  }

  sendAll(obj) {
    const text = JSON.stringify(obj);
    for (const p of this.players) {
      try {
        p.socket.send(text);
      } catch (err) {
        // gone; cleanup will handle it
      }
    }
  }

  // A new match begins (first "go", or a rematch): remember who is playing,
  // so results can be credited to the right accounts later.
  startMatch() {
    this.match = {
      participants: this.players.filter((p) => p.id).map((p) => ({ slot: p.slot, id: p.id })),
      reports: {},
      done: false,
    };
    this.votes = new Set();
  }

  // If everybody still in the room has voted for a rematch, start it.
  checkRematch() {
    if (this.players.length >= 2 && this.players.every((p) => this.votes.has(p.slot))) {
      this.startMatch();
      this.sendAll({ type: "rematch_go" });
    }
  }

  // Records the finished match once every connected player has reported and
  // all of them agree on the winner. Called after each report and whenever
  // someone leaves (they will never report, so the rest may now be complete).
  async maybeRecord() {
    const m = this.match;
    if (!m || m.done) return;
    if (this.players.some((p) => !(p.slot in m.reports))) return; // still waiting on someone
    m.done = true; // decided either way - never record twice
    const winners = new Set(this.players.map((p) => m.reports[p.slot]));
    if (winners.size !== 1) {
      console.log("result disagreement - not recorded");
      return;
    }
    const winnerSlot = [...winners][0];
    const winner = m.participants.find((p) => p.slot === winnerSlot);
    const ids = [...new Set(m.participants.map((p) => p.id))];
    if (!winner || ids.length < 2) {
      console.log("result not recorded (draw, unregistered winner or fewer than 2 accounts)");
      return;
    }
    try {
      await this.askLeaderboard("/record", { winner: winner.id, participants: ids });
    } catch (err) {
      console.log("record failed: " + err);
    }
  }

  async fetch(request) {
    // A WebSocket connection starts as a normal HTTP request with an
    // "Upgrade: websocket" header (Godot's WebSocketPeer.connect_to_url
    // sends it). Anything else - like opening the URL in a browser - gets rejected.
    const upgradeHeader = request.headers.get("Upgrade") || "";
    if (upgradeHeader.toLowerCase() !== "websocket") {
      return new Response("Expected a WebSocket upgrade request", { status: 400 });
    }

    // Fifth player, or someone joining after the match started: turn them
    // away. (The Godot side sees this as the socket closing before the room
    // was ever ready, so online_lobby.gd shows "Couldn't connect".)
    if (this.players.length >= MAX_PLAYERS || this.started) {
      console.log("rejected: players=" + this.players.length + " started=" + this.started);
      return new Response("Room is full or already started", { status: 403 });
    }

    // Give the newcomer the lowest slot nobody is using (so if player 2
    // leaves and someone new joins, they take slot 1 again).
    let slot = 0;
    while (this.players.some((p) => p.slot === slot)) slot++;

    // A WebSocketPair is two linked ends of one connection: `client` goes
    // back to the player in the 101 response at the bottom, `server` is the
    // end this code keeps and talks through.
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);

    server.accept();
    const me = { socket: server, slot: slot, id: null, name: "" };
    this.players.push(me);

    // The relay: whatever this player sends (state / hit / pick messages
    // from the Godot game) is forwarded to everyone ELSE in the room, with
    // a "from" field added so receivers know which player it came from.
    // The relay-only messages are handled first (see the list at the top).
    server.addEventListener("message", async (event) => {
      let data;
      try {
        data = JSON.parse(event.data);
      } catch (err) {
        return; // not JSON - ignore it
      }
      if (typeof data !== "object" || data === null) return;

      if (data.type === "hello") {
        // Identify (if the player has an account), then tell the room who is in.
        // The roster is sent in reply to this instead of at connect time:
        // a message sent in the same instant as the handshake can confuse
        // Godot's WebSocket client.
        if (data.id && data.token) {
          try {
            const check = await this.askLeaderboard("/verify", { id: data.id, token: data.token });
            if (check.ok) {
              me.id = String(data.id);
              me.name = check.name;
            }
          } catch (err) {
            console.log("verify failed: " + err);
          }
        }
        console.log("hello from slot " + me.slot + (me.name ? " (" + me.name + ")" : ""));
        this.broadcastRoster();
        return; // relay-only message, not forwarded
      }
      if (data.type === "go") {
        if (me.slot !== 0 || this.players.length < 2) return;
        this.started = true;
        this.startMatch();
      }
      if (data.type === "result") {
        if (this.match && !this.match.done) {
          this.match.reports[me.slot] = Number.isInteger(data.winner) ? data.winner : -1;
          await this.maybeRecord();
        }
        return; // relay-only message, not forwarded
      }
      if (data.type === "to_select") {
        // Someone sent the whole room back to Character Select: the next
        // match is a new one, so start a fresh record for the leaderboard.
        if (!this.started) return;
        this.startMatch();
        // (falls through so the other players are told too)
      }
      if (data.type === "rematch") {
        if (!this.started) return;
        this.votes.add(me.slot);
        // (falls through so the other players see who voted)
      }

      data.from = me.slot;
      const text = JSON.stringify(data);
      for (const other of this.players) {
        if (other !== me && other.socket.readyState === WS_OPEN) {
          other.socket.send(text);
        }
      }
      if (data.type === "rematch") this.checkRematch();
    });

    // When this player disconnects: drop them, tell the others WHICH slot
    // left (so the game can remove just that fighter), and refresh the
    // roster. An empty room resets so the code can be reused.
    const cleanup = () => {
      if (!this.players.includes(me)) return; // close + error can both fire
      console.log("leave slot " + me.slot);
      this.players = this.players.filter((p) => p !== me);
      this.votes.delete(me.slot);
      for (const other of this.players) {
        try {
          other.socket.send(JSON.stringify({ type: "peer_left", slot: me.slot }));
        } catch (err) {
          // other socket is already gone too; nothing to notify
        }
      }
      if (this.players.length === 0) {
        this.started = false;
        this.match = null;
      }
      this.broadcastRoster();
      this.maybeRecord(); // the rest may all have reported already
      if (this.started) this.checkRematch();
    };
    server.addEventListener("close", cleanup);
    server.addEventListener("error", cleanup);

    console.log("join slot " + slot + " (" + this.players.length + " in room)");

    // 101 = "Switching Protocols" - completes the WebSocket handshake and
    // hands the player their end of the connection.
    return new Response(null, { status: 101, webSocket: client });
  }
}

// The front door - every request to the worker URL hits this first.
// It decides WHICH object the request belongs to: a room (WebSocket on
// /room/<code>), or the global leaderboard (HTTP /register, /leaderboard).
export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // --- accounts + leaderboard -------------------------------------------
    if (url.pathname === "/register" || url.pathname === "/leaderboard") {
      // The browser sends an OPTIONS "preflight" before a JSON POST.
      if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });
      const board = env.LEADERBOARD.get(env.LEADERBOARD.idFromName("global"));
      if (url.pathname === "/register") {
        if (request.method !== "POST") return json({ error: "POST only" }, 405);
        const text = await request.text();
        if (text.length > 512) return json({ error: "Too large" }, 413);
        return withCors(await board.fetch("https://leaderboard/register", { method: "POST", body: text }));
      }
      return withCors(await board.fetch("https://leaderboard/top"));
    }

    // --- rooms --------------------------------------------------------------
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
    // always maps the same code to the same RelayRoom instance, so all
    // players end up talking to the same one.
    const code = match[1].toUpperCase();
    const id = env.ROOMS.idFromName(code);
    const stub = env.ROOMS.get(id);
    return stub.fetch(request);
  },
};
