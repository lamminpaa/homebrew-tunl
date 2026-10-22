# tunl

Tunl from the command line, and for AI agents over MCP. It drives the Tunl app
from the Mac App Store; it does not replace it, and it is installed separately
because an App Store app cannot put anything on your `PATH`.

```sh
brew install lamminpaa/tunl/tunl
```

## Commands

| Command | What it does |
|---|---|
| `tunl status [name]` | Every tunnel, whether it is up, and for the connected one whether it actually carries traffic |
| `tunl events [name]` | Recent connects, drops, stalls and repairs |
| `tunl connect <name>` | Connects (disconnecting any other tunnel) and waits until it is up |
| `tunl disconnect [name]` | Disconnects the connected tunnel |
| `tunl repair [name]` | Reconnects a tunnel that is up but carrying nothing |
| `tunl mcp` | Serves the same commands as MCP tools over stdio |

Add `--json` to any command for machine-readable output. Exit codes: 0 done,
64 usage, 66 no such tunnel, 69 Tunl unavailable or nothing to act on, 75 timed
out.

## For AI agents

```sh
claude mcp add tunl -- tunl mcp
```

Other agents: run `tunl mcp` as a stdio MCP server. The tools are
`tunl_status`, `tunl_events`, `tunl_connect`, `tunl_disconnect` and
`tunl_repair`.

## How it works

- Whether a tunnel is up comes from macOS itself (`scutil --nc list`), so it is
  right even with the app closed.
- Health, latency and history come from a status file the app writes to its
  own container. They are reported only while the app is running; a file left
  by an app that has quit describes a moment that is over. The first read may
  make macOS ask whether your terminal may access data from other apps.
- Connecting, disconnecting and repairing go through the app's `tunl://` URLs,
  never straight to `scutil`, so the app still stops the other tunnel, applies
  the kill switch and records the history.
- Nothing it prints contains a key, an endpoint or an address.

The status file format is a contract with the app:
`Tests/TunlCLICoreTests/Fixtures/status-v1.json` is decoded by these tests and
must be exactly what the app writes (`AgentStatusTests` in the app).
