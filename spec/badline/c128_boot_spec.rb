# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../support/c128_boot"

# The C128 booted into C64 mode, as BASIC and the KERNAL's traps see it.
describe Badline::C128, :slow do
  include C128Boot

  subject(:machine) { booted }

  context "when booted" do
    subject(:machine) { booted_once }

    it "boots to the C64's BASIC" do
      expect(screen[1, 3]).to eq(["    **** COMMODORE 64 BASIC V2 ****", "", " 64K RAM SYSTEM  38911 BASIC BYTES FREE"])
    end
  end

  it "runs a line typed into the keyboard buffer" do
    machine.type_text("print 6*7\r")
    run_to(3_500_000)
    expect(screen[6, 2]).to eq(["PRINT 6*7", " 42"])
  end

  it "reads an extra key once $D02F selects its row" do
    machine.keyboard.press(:help)
    machine.type_text("poke53295,254:print peek(56321):poke53295,255\r")
    run_to(3_500_000)
    expect(screen).to include(" 254")
  end

  describe "a directory mounted as device 8" do
    before do
      Dir.mktmpdir do |dir|
        File.binwrite(File.join(dir, "six.prg"), program(0x08, "6"))
        Badline::Media.attach(machine, dir)
        machine.type_text(%(load"six",8\rrun\r))
        run_to(4_000_000)
      end
    end

    it "loads a program through the KERNAL traps" do
      expect(screen).to include(" 6")
    end
  end

  context "when built for C128 mode" do
    subject(:machine) { booted(:c128) }

    context "when booted" do
      subject(:machine) { booted_once(:c128) }

      it "boots to BASIC 7.0 on the 40 column screen" do
        expect(screen[1, 6]).to eq([" COMMODORE BASIC V7.0 122365 BYTES FREE", "   (C)1986 COMMODORE ELECTRONICS, LTD.",
                                    "         (C)1977 MICROSOFT CORP.", "           ALL RIGHTS RESERVED", "",
                                    "READY."])
      end

      it "prints to the VIC-IIe's screen" do
        expect(machine.active_screen).to eq(:vic)
      end
    end

    context "when booted with the 40/80 key down" do
      subject(:machine) { booted_once(:c128, display_key: true) }

      it "boots on the VDC's 80 columns" do
        expect(vdc_screen(7)[1].strip).to eq("COMMODORE BASIC V7.0 122365 BYTES FREE")
      end

      it "prints to the VDC's screen" do
        expect(machine.active_screen).to eq(:vdc)
      end
    end

    it "runs a line typed into BASIC 7.0's keyboard buffer" do
      machine.type_text("print 6*7\r")
      run_to(2_500_000)
      expect(screen[7, 2]).to eq(["PRINT 6*7", " 42"])
    end

    it "moves to the VDC's screen on GRAPHIC 5" do
      machine.type_text("graphic5\r")
      run_to(2_500_000)
      expect(machine.active_screen).to eq(:vdc)
    end

    it "moves back to the VIC-IIe's screen on ESC X" do
      machine.type_text("graphic5\r\ex")
      run_to(2_500_000)
      expect(machine.active_screen).to eq(:vic)
    end

    describe "with a directory mounted as device 8" do
      let(:dir) { Dir.mktmpdir }

      before do
        File.binwrite(File.join(dir, "six.prg"), program(0x1c, "6"))
        Badline::Media.attach(machine, dir)
      end

      it "loads and runs a BASIC 7.0 program through the C128 KERNAL's traps" do
        machine.type_text(%(dload"six"\rrun\r))
        run_to(3_500_000)
        expect(screen).to include(" 6")
      end

      it "saves through the traps" do
        machine.type_text(%(10 print 7\rdsave"seven"\r))
        run_to(3_500_000)
        expect(File.binread(File.join(dir, "seven.prg")).bytes.first(2)).to eq([0x01, 0x1c])
      end
    end

    it "runs a program that loads at $1C01" do
      path = File.join(Dir.mktmpdir, "six.prg")
      File.binwrite(path, program(0x1c, "6"))
      Badline::Media.attach(machine, path)
      run_to(2_500_000)
      expect(screen).to include(" 6")
    end
  end
end
