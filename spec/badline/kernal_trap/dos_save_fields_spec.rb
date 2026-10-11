# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../../support/blank_disk"

# Machines with device 8 served through the KERNAL traps, booted once for
# every example that reads them.
module TrapDOSSamples
  extend BlankDisk

  module_function

  def booted(path, text, cycles)
    Badline::C64.new.tap do |machine|
      Badline::Media.attach(machine, path, autostart: false)
      machine.on_init { machine.type_text(text) }
      machine.run_cycles(cycles)
    end
  end

  # A disk image with a file open for writing.
  def writing
    @writing ||= booted(blank_d64(File.join(Dir.mktmpdir, "blank.d64")),
                        "open2,8,2,\"notes,s,w\":print#2,\"hello\"\r", 3_200_000)
  end

  # A directory part way through a LOAD.
  def loading
    @loading ||= begin
      dir = Dir.mktmpdir
      File.binwrite(File.join(dir, "prog.prg"), ([0x01, 0x08] + Array.new(3000) { |i| i & 0xff }).pack("C*"))
      booted(dir, "load\"prog\",8\r", 2_700_000)
    end
  end
end

# Device 8 through the KERNAL traps, keyed, against the positional state the
# machine saves for it, which restores exactly.
describe Badline::KernalTrap::DOS, "#save_fields" do
  def positional(machine)
    out = Badline::Snapshot::StateWriter.new
    machine.send(:save_trap_dos, out)
    out.state
  end

  def round_trip(machine)
    out = Badline::Snapshot::Keyed::Writer.new
    machine.save_trap_dos_fields(out)
    Badline::C64.new.tap do |fresh|
      fresh.load_trap_dos_fields(Badline::Snapshot::Keyed::Reader.parse(out.section("BL-TRAPDOS")))
    end
  end

  it "restores a disk image with a file open for writing, its channels and the traps", :slow do
    machine = TrapDOSSamples.writing
    channels = machine.instance_variable_get(:@dos).instance_variable_get(:@channels)
    expect([positional(round_trip(machine)), channels.open?(2)]).to eq([positional(machine), true])
  end

  it "restores a directory part way through a LOAD", :slow do
    expect(positional(round_trip(TrapDOSSamples.loading))).to eq(positional(TrapDOSSamples.loading))
  end

  it "unmounts a machine whose snapshot has nothing on device 8" do
    machine = Badline::C64.new.tap { |c64| Badline::Media.attach(c64, Dir.mktmpdir, autostart: false) }
    machine.load_trap_dos_fields(Badline::Snapshot::Keyed::Reader.missing("BL-TRAPDOS"))
    expect(machine).not_to be_mounted
  end
end
