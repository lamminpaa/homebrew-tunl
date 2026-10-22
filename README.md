# Homebrew tap for tunl

`tunl` controls [Tunl](https://tunl.works), the WireGuard client for macOS,
from the command line and from AI agents over MCP. Tunl itself comes from the
Mac App Store; this installs only the command.

```sh
brew install lamminpaa/tunl/tunl
claude mcp add tunl -- tunl mcp   # optional: use it from Claude Code
```

`tunl status`, `events`, `connect`, `disconnect` and `repair` each take
`--json`; `tunl mcp` serves them to AI agents over stdio. Each release's
source is attached to its GitHub release, built from the app's repository by
its release script.
