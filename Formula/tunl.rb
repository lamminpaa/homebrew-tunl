class Tunl < Formula
  desc "Command-line and MCP control for the Tunl WireGuard app for macOS"
  homepage "https://tunl.works"
  url "https://github.com/lamminpaa/homebrew-tunl/archive/refs/tags/cli-v0.1.0.tar.gz"
  sha256 "740c584643bb39a887f30ce6a7f8967e565bec219b1ac9243d461ceada14b83d"
  license "MIT"

  depends_on xcode: ["15.0", :build]
  depends_on :macos

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release", "--package-path", "cli"
    bin.install "cli/.build/release/tunl"
  end

  test do
    assert_equal version.to_s, shell_output("#{bin}/tunl version").strip
    request = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}'
    assert_match '"protocolVersion":"2025-06-18"', pipe_output("#{bin}/tunl mcp", "#{request}\n")
  end
end
