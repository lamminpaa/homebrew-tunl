class Tunl < Formula
  desc "Command-line and MCP control for the Tunl WireGuard app for macOS"
  homepage "https://tunl.works"
  url "https://github.com/lamminpaa/homebrew-tunl/releases/download/cli-v0.1.2/tunl-0.1.2.tar.gz"
  sha256 "29ec20e8328832ffc7709e2720598d91eade2560e353392fce5dae0bae98dbb5"
  license "MIT"

  depends_on xcode: ["15.0", :build]
  depends_on :macos

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release", "--package-path", "cli"
    bin.install "cli/.build/release/tunl"
    pkgshare.install "cli/skill"
  end

  test do
    assert_predicate pkgshare/"skill/tunl/SKILL.md", :exist?
    assert_equal version.to_s, shell_output("#{bin}/tunl version").strip
    request = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}'
    assert_match '"protocolVersion":"2025-06-18"', pipe_output("#{bin}/tunl mcp", "#{request}\n")
  end
end
