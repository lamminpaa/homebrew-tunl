# Homebrew tap for tunl

`tunl` controls [Tunl](https://tunl.works), the WireGuard client for macOS,
from the command line and from AI agents over MCP. Tunl itself comes from the
Mac App Store; this installs only the command.

```sh
brew install lamminpaa/tunl/tunl
claude mcp add tunl -- tunl mcp   # optional: use it from Claude Code
```

See [cli/README.md](cli/README.md) for the commands. The source in `cli/` is
published here from the app's repository by its release script.
