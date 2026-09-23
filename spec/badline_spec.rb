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
end
