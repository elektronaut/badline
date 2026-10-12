# frozen_string_literal: true

require "fileutils"
require "badline"
require "badline/c128"
require "badline/plus4"
require_relative "../../spec/support/blank_disk"

# The golden snapshot fixtures each release saves once, under
# spec/fixtures/snapshots/<version>/, for snapshot_load_golden_spec to load
# in every later badline: a C64, a VIC-20, a C128 and a Plus/4 typing PRINT
# 6*7, a C64 loading the directory from a true 1541, and a C64 running the
# Super Games cartridge test from VICE-testprogs, whose mapper has a
# register.
# Beside each snapshot goes the text screen 100,000 cycles after it, as
# this release runs on from it.
module SnapshotGolden
  extend BlankDisk

  MACHINES = {
    "c64" => -> { typed(Badline::C64.new, "print 6*7\r", 3_000_000) },
    "vic20" => -> { typed(Badline::Vic20.new, "print 6*7\r", 3_000_000) },
    "c128" => -> { typed(Badline::C128.new(mode: :c128), "print 6*7\r", 3_000_000) },
    "plus4" => -> { typed(Badline::Plus4.new, "print 6*7\r", 1_000_000) },
    "c64-1541" => -> { directory_listing(4_400_000) },
    "c64-cartridge" => -> { cartridge(3_000_000) }
  }.freeze

  module_function

  # Writes each machine's .vsf and .txt into `dir`, and yields each name
  # with its snapshot's path.
  def write(dir)
    FileUtils.mkdir_p(dir)
    MACHINES.each do |name, build|
      machine = build.call
      path = File.join(dir, "#{name}.vsf")
      machine.save_snapshot(path)
      machine.run_cycles(100_000)
      File.write(File.join(dir, "#{name}.txt"), screen(machine))
      yield name, path if block_given?
    end
  end

  # The text screen in RAM, as bin/snapshot_check reads it, which
  # snapshot_load_golden_spec compares against the .txt.
  def screen(machine)
    ram = machine.ram
    base, columns, rows = case machine.family
                          when :vic20 then [ram.peek(0x0288) << 8, 22, 23]
                          when :plus4 then [0x0c00, 40, 25]
                          else [0x0400, 40, 25]
                          end
    lines = Array.new(rows) do |row|
      Array.new(columns) { |column| character(ram.peek(base + (row * columns) + column)) }.join.rstrip
    end
    "#{lines.join("\n")}\n"
  end

  def character(code)
    code &= 0x7f
    return "@" if code.zero?
    return (code + 96).chr if code < 27

    code < 64 ? code.chr : " "
  end

  def typed(machine, text, cycles)
    machine.type_text(text)
    machine.run_cycles(cycles)
    machine
  end

  def cartridge(cycles)
    crt = File.expand_path("../../vendor/VICE-testprogs/C64/carts/supergames/supergames.crt", __dir__)
    Badline::C64.new.tap do |machine|
      Badline::Media.attach(machine, crt)
      machine.run_cycles(cycles)
    end
  end

  # The disk's module keeps the image's path as given, so the image goes
  # at the same absolute path on every machine, outside the checkout.
  def directory_listing(cycles)
    FileUtils.mkdir_p("/tmp/badline-golden")
    disk = blank_d64("/tmp/badline-golden/blank.d64", name: "GOLDEN")
    Badline::C64.new.tap do |machine|
      Badline::Media::TrueDrive.plug(machine)
      Badline::Media.attach(machine, disk, autostart: false)
      typed(machine, "load\"$\",8\r", cycles)
    end
  end
end
