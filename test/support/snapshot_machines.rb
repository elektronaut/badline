# frozen_string_literal: true

require "fileutils"
require_relative "machine_families"
require_relative "drive_scenarios_1581"
require_relative "snapshot_cbm2"

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

  def demo(dir, family = "c64") = MachineFamilies.write_demo(dir, { family: })

  # +machine+ with the media at +path+ attached.
  def attached(machine, path) = machine.tap { Badline::Media.attach(machine, path) }

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

  # +machine+ with the disk image at +path+ in its true drive, typing
  # LOAD"$" and LIST once booted.
  def listing(machine, path)
    Badline::Media::TrueDrive.insert(machine, path)
    typing(machine, "load\"$\",8\rlist\r")
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

  # A blank tape for the platform in the datasette, and a program SAVEd to
  # it typed at the prompt.
  def saving_to_tape(machine, dir, platform)
    machine.datasette.insert(Badline::Storage::TAP.create(File.join(dir, "saved.tap"), platform:))
    typing(machine, "10 print\"hello\"\rsave\"test\"\r")
  end

  # RECORD and PLAY pressed while the KERNAL asks for them, and the SAVE
  # run partway, so the datasette is recording at the save point.
  def recording(machine)
    run(machine, 4_000_000)
    machine.datasette.record!
    run(machine, 4_000_000)
  end

  # A version 2 tape of half waves, as the 264 series' datasette plays
  # them, with nothing on it the KERNAL finds.
  def tap264_file(dir)
    data = (([0x30] * 20_000) + ([0x21, 0x2b] * 4000) + ([0x30] * 5000)).pack("C*")
    File.join(dir, "tape264.tap").tap do |path|
      File.binwrite(path, "C16-TAPE-RAW".b + [2, 2, 0, 0].pack("C*") + [data.bytesize].pack("V") + data)
    end
  end

  # A tape for the PET, platform 3, with nothing on it the KERNAL finds.
  def pet_tap_file(dir)
    data = (([0x30] * 20_000) + ([0x42, 0x56] * 4000) + ([0x30] * 5000)).pack("C*")
    File.join(dir, "pet.tap").tap do |path|
      File.binwrite(path, "C64-TAPE-RAW".b + [1, 3, 0, 0].pack("C*") + [data.bytesize].pack("V") + data)
    end
  end

  # An 8096 once BASIC runs, with a pattern written to each of its board's
  # four banks through the control register at $FFF0, the register cleared
  # again and the program run on.
  def pet_banks(machine)
    run(machine, 2_600_000)
    [0x80, 0x8c].each do |control|
      machine.poke(0xfff0, control)
      0x100.times { |offset| machine.poke(0x9000 + offset, control ^ offset) }
      0x100.times { |offset| machine.poke(0xc000 + offset, (control + offset) & 0xff) }
    end
    machine.poke(0xfff0, 0)
    run(machine, 100_001)
  end

  # An 8296 with its user port jumpered, its banks written as the 8096's
  # are, a pattern written under BASIC and at $9000-$90FF, and the user
  # port's PA0 and PA1 driven low to show the RAM at $9000 and $A000.
  def pet_8296_board(machine)
    pet_banks(machine)
    0x100.times { |offset| machine.poke(0xb000 + offset, offset ^ 0x5a) }
    0x100.times { |offset| machine.poke(0x9000 + offset, offset ^ 0xa5) }
    machine.poke(0xe843, 0x07)
    machine.poke(0xe841, 0x04)
    run(machine, 100_001)
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
                   ->(m) { run(m, 3_500_000) }),
      Scenario.new("c64-tape-save", :c64, ->(dir) { saving_to_tape(Badline::C64.new, dir, 0) },
                   ->(m) { recording(m) })
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
        listing(Badline::C64.new, path)
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
                   ->(m) { run(m, 3_000_000) }),
      Scenario.new("vic20-tape-save", :vic20, ->(dir) { saving_to_tape(Badline::Vic20.new(ram: :unexpanded), dir, 1) },
                   ->(m) { recording(m) })
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
      Scenario.new("plus4-c16-tape-save", :plus4, ->(dir) { saving_to_tape(Badline::Plus4.new(model: "c16"), dir, 2) },
                   ->(m) { recording(m) }),
      Scenario.new("plus4-cartridge", :plus4, lambda { |dir|
        Badline::Plus4.new.tap { |m| Badline::Media.attach(m, plus4_cartridge(dir)) }
      }, ->(m) { run(m, 300_000) }),
      Scenario.new("plus4-traps-d64", :plus4, lambda { |dir|
        Badline::Plus4.new.tap { |m| Badline::Media.attach(m, copy(D64, dir)) }
      }, ->(m) { run(m, 1_500_000) })
    ]
  end

  # The 264's true drives: a 1541 on the serial bus and a 1551 on TCBM,
  # saved part way through a LOAD.
  def plus4_drive_scenarios
    [
      Scenario.new("plus4-1541", :plus4, lambda { |dir|
        listing(Badline::Plus4.new(true_drive_model: "1541"), copy(D64, dir))
      }, ->(m) { run(m, 2_500_000) }),
      Scenario.new("plus4-1551", :plus4, lambda { |dir|
        listing(Badline::Plus4.new(true_drive_model: "1551"), copy(D64, dir))
      }, ->(m) { run(m, 2_400_000) })
    ]
  end

  # A program that rings the bell and keeps writing the screen RAM, where
  # the video shows it, while the jiffy clock runs.
  PET_BASIC = "10 print chr$(7);\r20 t=tiand255:poke32768+t,t:goto20\rrun\r"

  # The PETs: a CRTC board with 80 columns and one with 40, the 2001's
  # discrete video, an 8096 and an 8296 with their boards written, and the
  # media a PET takes: a disk through the traps and in a 2031 loading its
  # directory, a program and a tape played and recorded on cassette #1.
  def pet_scenarios
    basic = [["8032", 50, 2_600_001], ["4032", 60, 2_600_001], ["2001", 60, 900_001]].map do |model, refresh_hz, cycles|
      Scenario.new("pet-#{model}-basic", :pet, ->(_dir) { typing(Badline::PET.new(model:, refresh_hz:), PET_BASIC) },
                   ->(m) { run(m, cycles) })
    end
    basic + [
      Scenario.new("pet-8096-banks", :pet, ->(_dir) { typing(Badline::PET.new(model: "8096"), PET_BASIC) },
                   ->(m) { pet_banks(m) }),
      Scenario.new("pet-8296-board", :pet,
                   ->(_dir) { typing(Badline::PET.new(model: "8296", jumpers: %w[userport]), PET_BASIC) },
                   ->(m) { pet_8296_board(m) }),
      Scenario.new("pet-demo", :pet, ->(dir) { attached(Badline::PET.new(model: "3032"), demo(dir, "pet")) },
                   ->(m) { run(m, 2_000_001) }),
      Scenario.new("pet-traps-d64", :pet, ->(dir) { attached(Badline::PET.new, copy(D64, dir)) },
                   ->(m) { run(m, 2_600_001) }),
      Scenario.new("pet-2031", :pet, ->(dir) { listing(Badline::PET.new(model: "4032"), copy(D64, dir)) },
                   ->(m) { run(m, 2_600_001) }),
      Scenario.new("pet-tape", :pet, ->(dir) { attached(Badline::PET.new, pet_tap_file(dir)) },
                   ->(m) { run(m, 3_000_000) }),
      Scenario.new("pet-tape-save", :pet, ->(dir) { saving_to_tape(Badline::PET.new(model: "3032"), dir, 3) },
                   ->(m) { recording(m) })
    ]
  end

  def all
    c64_scenarios + c64_media_scenarios + c64_drive_scenarios + vic20_scenarios + c128_scenarios + plus4_scenarios +
      plus4_drive_scenarios + pet_scenarios + cbm2_scenarios
  end

  def named(name) = all.find { |scenario| scenario.name == name }

  # The scenarios whose names include `filter`, or all of them.
  def matching(filter) = filter ? all.select { |scenario| scenario.name.include?(filter) } : all
end
