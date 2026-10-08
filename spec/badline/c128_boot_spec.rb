# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

# The C128 booted into C64 mode, as BASIC and the KERNAL's traps see it.
describe Badline::C128, :slow do
  subject(:machine) { described_class.new }

  # The first +rows+ rows of the 40-column screen, as text.
  def screen(rows = 25)
    Array.new(rows) do |row|
      Array.new(40) { |col| character(machine.ram.peek(0x0400 + (row * 40) + col)) }.join.rstrip
    end
  end

  def character(code)
    code &= 0x7f
    code.between?(1, 26) ? (code + 64).chr : code.chr
  end

  it "boots to the C64's BASIC" do
    machine.run_cycles(machine.init_threshold)
    expect(screen[1, 3]).to eq(["    **** COMMODORE 64 BASIC V2 ****", "", " 64K RAM SYSTEM  38911 BASIC BYTES FREE"])
  end

  it "runs a line typed into the keyboard buffer" do
    machine.type_text("print 6*7\r")
    machine.run_cycles(3_500_000)
    expect(screen[6, 2]).to eq(["PRINT 6*7", " 42"])
  end

  it "reads an extra key once $D02F selects its row" do
    machine.keyboard.press(:help)
    machine.type_text("poke53295,254:print peek(56321):poke53295,255\r")
    machine.run_cycles(3_500_000)
    expect(screen).to include(" 254")
  end

  describe "a directory mounted as device 8" do
    # 10 PRINT 6
    let(:program) { [0x01, 0x08, 0x09, 0x08, 0x0a, 0x00, 0x99, 0x36, 0x00, 0x00, 0x00].pack("C*") }

    before do
      Dir.mktmpdir do |dir|
        File.binwrite(File.join(dir, "six.prg"), program)
        Badline::Media.attach(machine, dir)
        machine.type_text(%(load"six",8\rrun\r))
        machine.run_cycles(4_000_000)
      end
    end

    it "loads a program through the KERNAL traps" do
      expect(screen).to include(" 6")
    end
  end
end
