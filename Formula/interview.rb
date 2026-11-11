class Interview < Formula
  desc "Connect your local Codex or Claude Code to the StaffEngineer interview board"
  homepage "https://staffengineer.ru/systemdesign/mcp"
  url "file://#{File.expand_path("../packages/interview-0.1.1.tar.gz", __dir__)}"
  version "0.1.1"
  sha256 "bcd655dbec761b98d8567462891f60e420cf16739ee76a23d9ac6c57649a63ea"

  depends_on :macos
  on_macos do
    depends_on macos: :ventura
  end

  resource "runtime" do
    if Hardware::CPU.arm?
      url "https://nodejs.org/dist/v22.23.5/node-v22.23.5-darwin-arm64.tar.gz"
      sha256 "e7131995759b61a0170b646010d2ad35a5d37b4cb0d471f3e8317eac6f742f3d"
    else
      url "https://nodejs.org/dist/v22.23.5/node-v22.23.5-darwin-x64.tar.gz"
      sha256 "c53383238206b9ae4db23c5d8a63645e2e753bec8ab51a49cc81939aa64e9422"
    end
  end

  def install
    contents = libexec/"StaffEngineer Interview.app/Contents"
    (contents/"MacOS").mkpath
    (contents/"Resources").install "desktop.mjs", "sandbox-agent.mjs"
    resource("runtime").stage do
      (contents/"Resources").install "bin/node", "LICENSE" => "NODE-LICENSE"
    end
    contents.install "Info.plist"
    system "/usr/bin/xcrun", "swiftc", "-O", "main.swift", "-o", contents/"MacOS/StaffEngineer"
    system "/usr/bin/codesign", "--force", "--sign", "-", contents.parent
    (bin/"staffengineer-register").write <<~SH
      #!/bin/sh
      exec "#{opt_libexec}/StaffEngineer Interview.app/Contents/MacOS/StaffEngineer" --register
    SH
  end

  def caveats
    "To enable the connection buttons in your browser, run: staffengineer-register"
  end

  test do
    assert_path_exists libexec/"StaffEngineer Interview.app/Contents/MacOS/StaffEngineer"
  end
end
