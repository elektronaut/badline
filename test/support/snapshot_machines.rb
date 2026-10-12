# frozen_string_literal: true

require "fileutils"
require_relative "machine_families"
require_relative "drive_scenarios_1581"

# The media and the runs SnapshotMachines' scenarios are built from.
# Media are copied into the scenario's directory, so nothing writes to
# vendor/.
module SnapshotSetups
  VENDOR = File.expand_path("../../vendor/VICE-testprogs", __dir__)
  D64 = "#{VENDOR}/vdrive/test.d64".freeze
  D71 = "#{VENDOR}/c128/burstmode/burstcheck.d71".freeze
  VIC20_CRT = "#{VENDOR}/VIC20/raminitpattern/ae.crt".freeze
  T64 = "#{VENDOR}/testbench/autostart/autostart-c64-none.t64".freeze

  module_function

  def run(machine, cycles)
    cycles.times { machine.cycle! }
    machine
  end

  # The file at `path`, copied into `dir`.
  def copy(path, dir)
    File.join(dir, File.basename(path)).tap { |copy| FileUtils.cp(path, copy) }
  end

  def demo(dir) = MachineFamilies.write_demo(dir, { family: "c64" })

  def demo_dir(dir)
    File.join(dir, "host").tap do |host|
      FileUtils.mkdir_p(host)
      MachineFamilies.write_demo(host, { family: "c64" })
    end
  end

  def tap_file(dir)
    pulses = ([0x30] * 20_000) + ([0x42, 0x56] * 4000) + ([0x30] * 5000)
    data = pulses.pack("C*")
    File.join(dir, "tape.tap").tap do |path|
      File.binwrite(path, "C64-TAPE-RAW".b + [1, 0, 0, 0].pack("C*") + [data.bytesize].pack("V") + data)
    end
  end

  def easyflash_crt(dir)
    chips = Array.new(4) do |bank|
      [0x8000, 0xa000].map do |address|
        Badline::Storage::CRTFile::Chip.new(chip_type: 2, bank:, address:,
                                            data: [(address == 0x8000 ? 0x10 : 0x20) + bank] * 0x2000)
      end
    end
    image = Badline::Storage::CRTFile::Image.new(hardware_type: 32, subtype: 0, exrom: 1, game: 0, name: "EF",
                                                 chips: chips.flatten)
    File.join(dir, "ef.crt").tap { |path| File.binwrite(path, Badline::Storage::CRTFile.encode(image)) }
  end

  def typing(machine, text)
    machine.on_init { machine.type_text(text) }
    machine
  end

  # An REU stash of 4K, saved halfway through.
  def reu_transfer(machine)
    run(machine, 3_000_000)
    [[0xdf02, 0x00], [0xdf03, 0x04], [0xdf04, 0x10], [0xdf05, 0x00], [0xdf06, 0x01], [0xdf07, 0x00],
     [0xdf08, 0x10], [0xdf01, 0x90]].each { |address, value| machine.address_bus.poke(address, value) }
    run(machine, 2_011)
  end

  # Bank 1 on the cartridge's port, its RAM written, and a byte
  # programmed through the flash's unlock sequence.
  def flash_program(machine)
    run(machine, 2_000_000)
    cartridge = machine.address_bus.cartridge
    machine.address_bus.poke(0xdf10, 0x42)
    machine.address_bus.poke(0xde00, 1)
    [[0xe555, 0xaa], [0xe2aa, 0x55], [0xe555, 0xa0], [0xe100, 0x12]].each do |address, value|
      cartridge.romh.poke(address, value)
    end
    run(machine, 1_000_003)
  end

  # A version 2 tape of half waves, as the 264 series' datasette plays
  # them, with nothing on it the KERNAL finds.
  def tap264_file(dir)
    data = (([0x30] * 20_000) + ([0x21, 0x2b] * 4000) + ([0x30] * 5000)).pack("C*")
    File.join(dir, "tape264.tap").tap do |path|
      File.binwrite(path, "C16-TAPE-RAW".b + [2, 2, 0, 0].pack("C*") + [data.bytesize].pack("V") + data)
    end
  end

  # A 16K cartridge for the 264 series' cartridge 1 slot, signed for the
  # KERNAL to start at reset, that counts at $0C00 and shows the count in
  # the border colour.
  def plus4_cartridge(dir)
    rom = Array.new(0x4000, 0xea)
    [0x4c, 0x10, 0x80, 0x4c, 0x10, 0x80, 0x01, 0x43, 0x42, 0x4d].each_with_index { |byte, i| rom[i] = byte }
    [0x78, 0xee, 0x00, 0x0c, 0xad, 0x00, 0x0c, 0x8d, 0x19, 0xff, 0x4c, 0x11, 0x80].each_with_index do |byte, i|
      rom[0x10 + i] = byte
    end
    File.join(dir, "cart.bin").tap { |path| File.binwrite(path, rom.pack("C*")) }
  end
end

# Named machines for bin/snapshot_check, each one built with its media and
# then run to the point where it is saved. bin/machine_diff builds them too,
# without that run.
module SnapshotMachines
  extend SnapshotSetups
  include SnapshotSetups

  # `build` takes the scenario's directory and returns the machine with its
  # media, and `advance` runs it to the save point.
  Scenario = Data.define(:name, :family, :build, :advance)

  # A voice on the second SID at $D420, its pitch following the jiffy clock.
  SID2_BASIC = "10 s=54304:pokes+24,15:pokes+5,9:pokes+4,33\r20 pokes+1,peek(162):goto20\rrun\r"

  module_function

  def c64_scenarios
    [
      Scenario.new("c64-plain", :c64, ->(_dir) { typing(Badline::C64.new, "print 6*7\r") },
                   ->(m) { run(m, 3_000_000) }),
      Scenario.new("c64-demo", :c64, ->(dir) { Badline::C64.new.tap { |m| Badline::Media.attach(m, demo(dir)) } },
                   ->(m) { run(m, 3_001_234) }),
      Scenario.new("c64-reu", :c64, lambda { |dir|
        Badline::C64.new(reu: 512).tap do |m|
          Badline::Media.attach(m, demo(dir))
        end
      },
                   ->(m) { reu_transfer(m) }),
      Scenario.new("c64-easyflash", :c64,
                   ->(dir) { Badline::C64.new.tap { |m| Badline::Media.attach(m, easyflash_crt(dir)) } },
                   ->(m) { flash_program(m) }),
      Scenario.new("c64-plus256k", :c64, ->(_dir) { typing(Badline::C64.new(ram_expansion: :plus256k), "print 6*7\r") },
                   ->(m) { run(m, 3_000_000) }),
      Scenario.new("c64-sid2", :c64, lambda { |_dir|
        machine = Badline::C64.new
        machine.address_bus.add_sid(Badline::Chips::SID.new(model: :mos8580, at: 0xd420))
        typing(machine, SID2_BASIC)
      }, ->(m) { run(m, 3_500_000) }),
      Scenario.new("c64-jam", :c64, ->(_dir) { typing(Badline::C64.new, "poke 49152,2:sys 49152\r") },
                   ->(m) { run(m, 3_500_000) })
    ]
  end

  def c64_media_scenarios
    [
      Scenario.new("c64-directory", :c64,
                   lambda { |dir|
                     machine = Badline::C64.new
                     Badline::Media.attach(machine, demo_dir(dir), autostart: false)
                     typing(machine, "load\"*\",8,1\rrun\r")
                   },
                   ->(m) { run(m, 3_500_000) }),
      Scenario.new("c64-traps-d64", :c64, lambda { |dir|
        Badline::C64.new.tap do |m|
          Badline::Media.attach(m, copy(D64, dir))
        end
      },
                   ->(m) { run(m, 3_500_000) }),
      Scenario.new("c64-t64", :c64, ->(dir) { Badline::C64.new.tap { |m| Badline::Media.attach(m, copy(T64, dir)) } },
                   ->(m) { run(m, 3_500_000) }),
      Scenario.new("c64-tape", :c64, ->(dir) { Badline::C64.new.tap { |m| Badline::Media.attach(m, tap_file(dir)) } },
                   ->(m) { run(m, 3_500_000) })
    ]
  end

  def c64_drive_scenarios
    [
      Scenario.new("c64-1541-d64", :c64, lambda { |dir|
        Badline::C64.new.tap do |m|
          m.plug_true_drive
          Badline::Media.attach(m, copy(D64, dir))
        end
      }, ->(m) { run(m, 4_000_000) }),
      Scenario.new("c64-1541-written", :c64, lambda { |dir|
        machine = Badline::C64.new
        Badline::Media::TrueDrive.insert(machine, copy(D64, dir))
        typing(machine, "10 print\"snapshot\"\rsave\"snapshot\",8\r")
      }, ->(m) { run(m, 9_000_000) }),
      Scenario.new("c64-1581", :c64, lambda { |dir|
        path = File.join(dir, "blank.d81")
        DriveScenarios::Images1581.blank_d81(path, "BLANK", "BL")
        machine = Badline::C64.new
        Badline::Media::TrueDrive.insert(machine, path)
        typing(machine, "load\"$\",8\rlist\r")
      }, ->(m) { run(m, 5_000_000) })
    ]
  end

  def vic20_scenarios
    [
      Scenario.new("vic20-cart-1541", :vic20, lambda { |dir|
        Badline::Vic20.new(ram: :unexpanded).tap do |m|
          m.plug_true_drive
          Badline::Media.attach(m, copy(VIC20_CRT, dir))
          Badline::Media.insert_disk(m, copy(D64, dir))
        end
      }, ->(m) { run(m, 3_000_000) }),
      Scenario.new("vic20-tape", :vic20,
                   ->(dir) { Badline::Vic20.new(ram: :unexpanded).tap { |m| Badline::Media.attach(m, tap_file(dir)) } },
                   ->(m) { run(m, 3_000_000) })
    ]
  end

  def c128_scenarios
    [
      Scenario.new("c128-c128-1571", :c128, lambda { |dir|
        machine = Badline::C128.new(model: "c128", sid_model: :mos6581, mode: :c128)
        machine.plug_true_drive
        Badline::Media.insert_disk(machine, copy(D71, dir))
        typing(machine, "directory\r")
      }, ->(m) { run(m, 4_000_000) }),
      Scenario.new("c128-c64-1571", :c128, lambda { |dir|
        Badline::Machine.build(:c128, model: "c128dcr").tap do |m|
          m.plug_true_drive
          Badline::Media.attach(m, copy(D64, dir))
        end
      }, ->(m) { run(m, 4_000_000) }),
      Scenario.new("c128-z80", :c128, ->(_dir) { Badline::C128.new(mode: :c128) }, ->(m) { run(m, 500) }),
      Scenario.new("c128-vdc", :c128, ->(_dir) { typing(Badline::C128.new(mode: :c128), "graphic 5\rprint 6*7\r") },
                   ->(m) { run(m, 4_000_000) })
    ]
  end

  # A program that plays both voices and keeps changing the background
  # and screen RAM while the TED's timers run.
  PLUS4_BASIC = "10 vol8:sound1,600,30:sound3,800,30\r20 t=tiand255:color0,t/16+1:poke3072+t,t:goto20\rrun\r"

  def plus4_scenarios
    [
      Scenario.new("plus4-boot", :plus4, ->(_dir) { Badline::Plus4.new }, ->(m) { run(m, 60_001) }),
      Scenario.new("plus4-basic", :plus4, ->(_dir) { typing(Badline::Plus4.new, PLUS4_BASIC) },
                   ->(m) { run(m, 1_500_000) }),
      Scenario.new("plus4-c16-basic", :plus4, ->(_dir) { typing(Badline::Plus4.new(model: "c16"), PLUS4_BASIC) },
                   ->(m) { run(m, 1_500_000) }),
      Scenario.new("plus4-c16-tape", :plus4, lambda { |dir|
        Badline::Plus4.new(model: "c16").tap { |m| Badline::Media.attach(m, tap264_file(dir)) }
      }, ->(m) { run(m, 1_500_000) }),
      Scenario.new("plus4-cartridge", :plus4, lambda { |dir|
        Badline::Plus4.new.tap { |m| Badline::Media.attach(m, plus4_cartridge(dir)) }
      }, ->(m) { run(m, 300_000) }),
      Scenario.new("plus4-traps-d64", :plus4, lambda { |dir|
        Badline::Plus4.new.tap { |m| Badline::Media.attach(m, copy(D64, dir)) }
      }, ->(m) { run(m, 1_500_000) }),
      Scenario.new("plus4-1541", :plus4, lambda { |dir|
        machine = Badline::Plus4.new
        Badline::Media::TrueDrive.insert(machine, copy(D64, dir))
        typing(machine, "load\"$\",8\rlist\r")
      }, ->(m) { run(m, 2_500_000) })
    ]
  end

  def all
    c64_scenarios + c64_media_scenarios + c64_drive_scenarios + vic20_scenarios + c128_scenarios + plus4_scenarios
  end

  def named(name) = all.find { |scenario| scenario.name == name }

  # The scenarios whose names include `filter`, or all of them.
  def matching(filter) = filter ? all.select { |scenario| scenario.name.include?(filter) } : all
end
