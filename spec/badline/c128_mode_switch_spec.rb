# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../support/c128_boot"

# The C128 built for C128 mode going to C64 mode through its KERNAL.
describe Badline::C128, :slow do
  include C128Boot

  subject(:machine) { booted(:c128) }

  it "goes to C64 mode on GO64" do
    machine.type_text("go64\ry\r")
    run_to(5_000_000)
    expect([machine.mode, screen[1]]).to eq([:c64, "    **** COMMODORE 64 BASIC V2 ****"])
  end

  describe "with a directory mounted as device 8" do
    before do
      dir = Dir.mktmpdir
      File.binwrite(File.join(dir, "c64.prg"), program(0x08, "7"))
      Badline::Media.attach(machine, dir)
    end

    it "moves the traps to the C64 KERNAL after GO64" do
      machine.type_text("go64\ry\r")
      run_to(5_000_000)
      machine.type_text(%(load"c64",8\rrun\r))
      machine.run_cycles(2_000_000)
      expect(screen).to include(" 7")
    end
  end

  context "when C= is held at reset" do
    subject(:machine) { described_class.new(mode: :c128) }

    it "goes to C64 mode through the KERNAL" do
      machine.keyboard.press(:cbm)
      machine.run_cycles(4_000_000)
      expect([machine.mode, screen[1]]).to eq([:c64, "    **** COMMODORE 64 BASIC V2 ****"])
    end

    it "boots the C64 KERNAL, then types into its keyboard buffer" do
      machine.hold_commodore_key
      machine.type_text("print 6*7\r")
      machine.run_cycles(4_000_000)
      expect([machine.mode, screen]).to match([:c64, include(" 42")])
    end
  end
end
