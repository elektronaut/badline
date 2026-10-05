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

    it "is the model --model names" do
      expect(built("--model", "c64c")).to eq(%i[mos8565 mos6526a mos8580 pal])
    end

    it "fits the SID --sid names over the model's" do
      expect(built("--model", "c64c", "--sid", "6581")).to eq(%i[mos8565 mos6526a mos6581 pal])
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
end
