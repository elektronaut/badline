# frozen_string_literal: true

require "spec_helper"
require_relative "../native/build"

describe NativeBuild do
  describe ".command" do
    it "puts the generated build info ahead of native/lib and passes the SDL2 flags to the C compiler" do
      expect(described_class.command("spinel", cc: "cc", sdl2_flags: "-L/opt/homebrew/lib", out: "out/badline"))
        .to eq(["spinel", "-I", "tmp/native/lib", "-I", "native/lib", "-I", "lib", "--no-line-map",
                "--rbs", "spinel/sig", "native/badline.rb", "-o", "out/badline", "--cc=cc -L/opt/homebrew/lib"])
    end

    it "passes the compiler alone when SDL2 needs no flags" do
      expect(described_class.command("spinel", cc: "clang", sdl2_flags: "", out: "b").last).to eq("--cc=clang")
    end
  end

  describe ".sdl2_flags" do
    it "keeps only the library directories pkg-config gives" do
      allow(described_class).to receive(:capture).with("pkg-config", "--libs", "sdl2")
                                                 .and_return("-L/opt/homebrew/lib -lSDL2")
      expect(described_class.sdl2_flags).to eq("-L/opt/homebrew/lib")
    end

    it "asks sdl2-config when pkg-config can't say" do
      allow(described_class).to receive(:capture).with("pkg-config", "--libs", "sdl2").and_return(nil)
      allow(described_class).to receive(:capture).with("sdl2-config", "--libs")
                                                 .and_return("-L/usr/local/lib -Wl,-rpath,/usr/local/lib -lSDL2")
      expect(described_class.sdl2_flags).to eq("-L/usr/local/lib")
    end

    it "falls back to the Homebrew directories that exist when neither tool is there" do
      allow(described_class).to receive(:capture).and_return(nil)
      allow(Dir).to receive(:exist?).with("/opt/homebrew/lib").and_return(true)
      allow(Dir).to receive(:exist?).with("/usr/local/lib").and_return(false)
      expect(described_class.sdl2_flags).to eq("-L/opt/homebrew/lib")
    end
  end

  describe ".revision" do
    it "counts the lightweight release tags" do
      allow(described_class).to receive(:capture)
        .with("git", "describe", "--tags", "--always", "--dirty", "--abbrev=8").and_return("v0.3.0-2-gabcdef12")
      expect(described_class.revision).to eq("v0.3.0-2-gabcdef12")
    end
  end

  describe ".spinel_version" do
    it "is what the compiler prints" do
      allow(described_class).to receive(:capture).with("spinel", "--version")
                                                 .and_return("spinel 2026.09.12+1155 (9346225f) [gcc 13.3.0 (cc)]")
      expect(described_class.spinel_version("spinel")).to eq("spinel 2026.09.12+1155 (9346225f) [gcc 13.3.0 (cc)]")
    end

    it "is empty when the command isn't Spinel" do
      allow(described_class).to receive(:capture).with("true", "--version").and_return("")
      expect(described_class.spinel_version("true")).to eq("")
    end
  end

  describe ".build_info" do
    it "defines the revision and the compiler as constants" do
      mod = Module.new
      mod.module_eval(described_class.build_info(revision: "v0.3.0-2-gabc", spinel: "spinel 2026.09.12"))
      expect([mod::Badline::Native::REVISION, mod::Badline::Native::SPINEL])
        .to eq(["v0.3.0-2-gabc", "spinel 2026.09.12"])
    end
  end
end
