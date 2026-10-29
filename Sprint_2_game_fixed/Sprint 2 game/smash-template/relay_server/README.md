# Smash relay server (Cloudflare Worker)

A tiny relay: up to four players connect to it over WebSockets using the same
room code, and it forwards messages between them. It has zero knowledge
of the game - positions, damage, hits, all of that lives in the Godot
client. This just lets two players find each other without either one
needing to open a port or share an IP address.

## One-time setup

You need a free Cloudflare account (cloudflare.com - no credit card
required for this) and Node.js installed.

```bash
cd relay_server
npm install -g wrangler   # Cloudflare's CLI, one-time global install
wrangler login            # opens a browser tab to sign in / sign up
```

## Deploy

```bash
wrangler deploy
```

That's it. Wrangler prints a URL like:

```
https://smash-relay.YOUR-SUBDOMAIN.workers.dev
```

Copy that URL - you'll need it in the Godot project.

## Wire it into the game

Open `autoload/NetworkManager.gd` in the Godot project and set:

```gdscript
const RELAY_URL := "wss://smash-relay.YOUR-SUBDOMAIN.workers.dev"
```

(Same host wrangler gave you, just `wss://` instead of `https://`.)

## Redeploying after changes

If you ever edit `src/worker.js`, just run `wrangler deploy` again - it
updates the same Worker at the same URL.

## Costs

Cloudflare's free plan includes 100,000 Worker requests/day and a
Durable Objects allowance well beyond what casual play between friends
will ever use. There's no sleep/cold-start behavior like some free
hosts - a room responds immediately whenever someone connects to it.

## How it works, briefly

- `export default { fetch }` is the entry point every request hits. It
  only accepts requests shaped like `/room/<code>`; anything else gets a
  plain "yes I'm running" response (useful for checking the deploy
  worked - visit the workers.dev URL in a browser).
- Cloudflare Durable Objects give us one guaranteed single-threaded
  instance per unique name - `env.ROOMS.idFromName(code)` always resolves
  to the *same* instance for the same code, which is exactly the "one
  room per code" behavior we want, with no database needed.
- Each `RelayRoom` instance just holds up to 4 open WebSocket
  connections and forwards messages between them. When a 2nd player
  joins, both get a `{"type":"ready"}` message. If either disconnects,
  the other gets `{"type":"peer_left"}`.
