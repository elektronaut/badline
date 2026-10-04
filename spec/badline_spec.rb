# frozen_string_literal: true

require "spec_helper"

describe Badline do
  describe ".rom_path" do
    let(:bundled) { File.expand_path("../lib/badline/roms", __dir__) }

    around do |example|
      saved = ENV.fetch("BADLINE_ROM_PATH", nil)
      ENV.delete("BADLINE_ROM_PATH")
      described_class.rom_path = nil
      example.run
    ensure
      ENV["BADLINE_ROM_PATH"] = saved
      described_class.rom_path = nil
    end

    it "defaults to the bundled roms directory" do
      expect(described_class.rom_path).to eq(bundled)
    end

    it "is seeded from BADLINE_ROM_PATH" do
      ENV["BADLINE_ROM_PATH"] = "/opt/c64/roms"
      expect(described_class.rom_path).to eq("/opt/c64/roms")
    end

    it "can be assigned" do
      described_class.rom_path = "/opt/c64/roms"
      expect(described_class.rom_path).to eq("/opt/c64/roms")
    end

    it "goes back to the default when assigned nil" do
      described_class.rom_path = "/opt/c64/roms"
      described_class.rom_path = nil
      expect(described_class.rom_path).to eq(bundled)
    end

    it "is where ROM.load reads from" do
      Dir.mktmpdir do |dir|
        File.binwrite(File.join(dir, "basic.rom"), "\x01\x02\x03")
        described_class.rom_path = dir
        expect(Badline::ROM.load("basic.rom", 0xa000)[0xa002]).to eq(0x03)
      end
    end
  end

  describe ".data_path" do
    around do |example|
      saved = ENV.fetch("BADLINE_DATA_PATH", nil)
      ENV.delete("BADLINE_DATA_PATH")
      described_class.data_path = nil
      example.run
    ensure
      ENV["BADLINE_DATA_PATH"] = saved
      described_class.data_path = nil
    end

    it "is seeded from BADLINE_DATA_PATH" do
      ENV["BADLINE_DATA_PATH"] = "/opt/c64/data"
      expect(described_class.data_path).to eq("/opt/c64/data")
    end

    it "can be assigned" do
      described_class.data_path = "/opt/c64/data"
      expect(described_class.data_path).to eq("/opt/c64/data")
    end

    it "defaults to the folder for this platform" do
      expect(described_class.data_path).to eq(described_class.default_data_path(RUBY_PLATFORM))
    end
  end

  describe ".default_data_path" do
    around do |example|
      saved = ENV.fetch("XDG_DATA_HOME", nil)
      example.run
    ensure
      ENV["XDG_DATA_HOME"] = saved
    end

    it "is in Application Support on macOS" do
      expect(described_class.default_data_path("arm64-darwin24"))
        .to eq(File.join(Dir.home, "Library/Application Support/badline"))
    end

    it "is in XDG_DATA_HOME on Linux" do
      ENV["XDG_DATA_HOME"] = "/srv/share"
      expect(described_class.default_data_path("x86_64-linux")).to eq("/srv/share/badline")
    end

    it "is in ~/.local/share on Linux when XDG_DATA_HOME is unset" do
      ENV.delete("XDG_DATA_HOME")
      expect(described_class.default_data_path("x86_64-linux")).to eq(File.join(Dir.home, ".local/share/badline"))
    end

    it "is in ~/.local/share on Linux when XDG_DATA_HOME is empty" do
      ENV["XDG_DATA_HOME"] = ""
      expect(described_class.default_data_path("x86_64-linux")).to eq(File.join(Dir.home, ".local/share/badline"))
    end

    it "ignores a relative XDG_DATA_HOME" do
      ENV["XDG_DATA_HOME"] = "share"
      expect(described_class.default_data_path("x86_64-linux")).to eq(File.join(Dir.home, ".local/share/badline"))
    end

    it "uses the XDG folder on other platforms" do
      ENV["XDG_DATA_HOME"] = "/srv/share"
      expect(described_class.default_data_path("amd64-freebsd14")).to eq("/srv/share/badline")
    end
  end

  describe ".data_folder" do
    around do |example|
      Dir.mktmpdir do |dir|
        described_class.data_path = File.join(dir, "badline")
        example.run
      ensure
        described_class.data_path = nil
      end
    end

    it "leaves the data folder uncreated until a subfolder is asked for" do
      expect(Dir.exist?(described_class.data_path)).to be(false)
    end

    it "creates the data folder and the subfolder" do
      path = described_class.data_folder("quicksaves")
      expect(Dir.exist?(path)).to be(true)
    end

    it "is named after the subfolder, inside the data folder" do
      expect(described_class.data_folder("autosaves")).to eq(File.join(described_class.data_path, "autosaves"))
    end

    it "returns an existing subfolder as it is" do
      File.write(File.join(described_class.data_folder("saves"), "game.vsf"), "")
      expect(Dir.children(described_class.data_folder("saves"))).to eq(["game.vsf"])
    end

    it "refuses folders it doesn't know" do
      expect { described_class.data_folder("roms") }.to raise_error(ArgumentError, /roms/)
    end
  end
end
