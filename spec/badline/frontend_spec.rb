# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"
require_relative "../support/sdl_dummy_drivers"

describe Badline::Frontend do
  include_context "with SDL's dummy drivers"

  def run(*argv) = described_class.run(Badline::Options.parse(argv))

  it "plays the machine and returns 0" do
    expect(run("--frames", "1", "--unpaced")).to eq(0)
  end

  it "warns about media that won't attach and returns 1" do
    File.write("bad.crt", "junk")
    expect { run("bad.crt") }.to output(/badline-ruby: bad.crt: Missing CRT signature/).to_stderr
  end

  describe "an --at insert that fails" do
    def insert_bad = run("--unpaced", "--frames", "5", "--at", "1:insert=bad.crt")

    before { File.write("bad.crt", "junk") }

    it "warns" do
      expect { insert_bad }.to output(/badline-ruby: bad\.crt: Missing CRT signature/).to_stderr
    end

    it "returns 1" do
      allow($stderr).to receive(:write)
      expect(insert_bad).to eq(1)
    end
  end

  describe ".media_problem" do
    it "is empty when the block raises nothing" do
      expect(described_class.media_problem { nil }).to eq("")
    end

    it "gives the message of a media error the block raises" do
      expect(described_class.media_problem { raise Badline::Storage::TAP::FormatError, "not a tape" })
        .to eq("not a tape")
    end

    it "lets other errors through" do
      expect { described_class.media_problem { raise IndexError } }.to raise_error(IndexError)
    end
  end

  it "restores a .vsf" do
    Badline::Computer.new.save_snapshot("saved.vsf")
    expect { run("saved.vsf", "--frames", "1", "--unpaced") }.to output(/Restored saved.vsf/).to_stdout
  end

  describe "the machine it builds" do
    def machine(*argv)
      computer = nil
      allow(Badline::Frontend::App).to receive(:new) do |built|
        computer = built
        instance_double(Badline::Frontend::App, run: nil)
      end
      run(*argv)
      computer
    end

    def built(*argv)
      computer = machine(*argv)
      [computer.vic.model, computer.cia1.model, computer.sid.model, computer.region.name]
    end

    it "is an NTSC C64 with --ntsc" do
      expect(built("--ntsc")).to eq(%i[mos6569 mos6526 mos6581 ntsc])
    end

    it "is a C64 with c64" do
      expect(built("c64")).to eq(%i[mos6569 mos6526 mos6581 pal])
    end

    it "is the model --model names" do
      expect(built("--model", "c64c")).to eq(%i[mos8565 mos6526a mos8580 pal])
    end

    it "fits the SID --sid names over the model's" do
      expect(built("--model", "c64c", "--sid", "6581")).to eq(%i[mos8565 mos6526a mos6581 pal])
    end

    it "is the C128 --model names with c128" do
      computer = machine("c128", "--model", "c128dcrntsc")
      expect([computer.family, computer.model.name, computer.mode]).to eq([:c128, "c128dcrntsc", :c128])
    end

    it "holds C= through a C128's reset with --c64" do
      computer = machine("c128", "--c64")
      expect(computer.keyboard.keys).to include(:cbm)
    end

    it "boots a C128 in C128 mode, C= up" do
      expect(machine("c128").keyboard.keys).not_to include(:cbm)
    end

    it "holds C= through a C128's reset for a program that loads at $0801" do
      File.binwrite("game64.prg", "\x01\x08\x00\x00\x00")
      allow($stdout).to receive(:write)
      expect(machine("c128", "game64.prg").keyboard.keys).to include(:cbm)
    end

    it "fits the SID --sid names in a C128" do
      expect(built("c128", "--sid", "8580")).to eq(%i[mos8566 mos6526 mos8580 pal])
    end

    it "is a C128 for a program that loads at $1C01" do
      File.binwrite("game.prg", "\x01\x1c\x00\x00\x00")
      allow($stdout).to receive(:write)
      expect(machine("game.prg").family).to eq(:c128)
    end

    it "restores a C128's .vsf" do
      Badline::C128.new.save_snapshot("c128.vsf")
      allow($stdout).to receive(:write)
      expect(machine("c128.vsf").family).to eq(:c128)
    end

    it "is a VIC-20 with the RAM --ram names with vic20" do
      computer = machine("vic20", "--ram", "24k")
      expect([computer.family, computer.ram_configuration]).to eq(%i[vic20 24k])
    end

    it "is an unexpanded VIC-20 for a program at $1001, which it says" do
      File.binwrite("game.prg", "\x01\x10\x00\x00\x00")
      expect { machine("vic20", "game.prg") }.to output(/RAM expansion: unexpanded/).to_stdout
    end

    it "is a VIC-20 with the RAM a program at $1201 needs" do
      File.binwrite("game.prg", "\x01\x12\x00\x00\x00")
      allow($stdout).to receive(:write)
      expect(machine("vic20", "game.prg").ram_configuration).to eq(:"8k")
    end

    it "keeps --ram over what the program needs" do
      File.binwrite("game.prg", "\x01\x12\x00\x00\x00")
      expect(machine("vic20", "--ram", "3k", "game.prg").ram_configuration).to eq(:"3k")
    end

    it "plugs a true 1541 into a VIC-20 with --true-drive" do
      expect(machine("vic20", "--true-drive").drive1541).not_to be_nil
    end

    it "is an SX-64 with its KERNAL and no datasette with --model sx64" do
      computer = machine("--model", "sx64")
      expect([computer.address_bus.kernal, computer.datasette.connected?]).to eq([:sx64, false])
    end
  end

  it "warns that an SX-64 takes no tape and returns 1" do
    File.binwrite("game.tap", "C64-TAPE-RAW".b + [1, 0, 0, 0, 1].pack("C4V") + "\x30".b)
    expect { run("--model", "sx64", "game.tap") }.to output(/game.tap: this machine has no datasette/).to_stderr
  end

  it "warns that a VIC-20 takes no .sid tune and returns 1" do
    File.binwrite("tune.sid", "PSID")
    expect { run("vic20", "tune.sid") }.to output(/tune.sid: doesn't go in a VIC-20/).to_stderr
  end
end
