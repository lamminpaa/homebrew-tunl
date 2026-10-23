class Tunl < Formula
  desc "Command-line and MCP control for the Tunl WireGuard app for macOS"
  homepage "https://tunl.works"
  url "https://github.com/lamminpaa/homebrew-tunl/releases/download/cli-v0.1.1/tunl-0.1.1.tar.gz"
  sha256 "123ea611becd802d2f4f2c8a995cbfc13c8227e18d7920f1d4512551d36afbf5"
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
