# frozen_string_literal: true

require "badline/core"
require "badline/c128"

# The 1571's true-drive scenarios: the C128D's built-in drive running DOS
# 3.0 on the serial bus of a C128 in C64 mode. It stays in 1541 mode
# there, as with a C64, so the C64's scenarios in test/support/drive_scenarios.rb
# run on it unchanged: a save, the error channel, a write-protected disk,
# an autostart and the idle loop. A double-sided format puts it in 1571
# mode first with U0>M1, which runs it at 2 MHz and writes both sides of
# a .d71.
module DriveScenarios
  module C128Runs
    D71_SIZE = 349_696

    # The free blocks of tracks 36-38 that 18/0 counts from $DD.
    SIDE_TWO_FREE = [21, 21, 21].freeze

    module_function

    def run(report, name, dir)
      case name
      when "1571-save" then save(report, dir)
      when "1571-format" then format(report, dir)
      when "1571-read-only" then read_only(report, dir)
      when "1571-autostart" then autostart(report, dir)
      when "1571-error-channel" then error_channel(report)
      else Idle1571.run(report)
      end
    end

    # SAVE through the DOS to a blank disk, then NEW, LOAD and LIST it back.
    def save(report, dir)
      path = File.join(dir, "1571-save.d64")
      Images.blank_d64(path, "SAVE TEST")
      output = write_run(path, "10 print\"hello\"\rsave\"test\",8\rnew\rload\"test\",8\rlist\r", 5)
      report.check("no-error", !output.include?("ERROR"), "printed an error")
      report.check("loads-back", output.include?("LOADING") && output.include?("10 PRINT\"HELLO\""),
                   "listed no 10 PRINT\"HELLO\"")
      report.check("file-in-image", Badline::Storage::D64Image.new(path).read_file("test") == SAVED,
                   "no TEST as saved in the image")
    end

    # U0>M1 and N: on a .d71 of zeros, then SAVE to it and LOAD the
    # directory: both sides formatted, 1327 blocks free beside PROG, and
    # the BAM counting the second side's blocks.
    def format(report, dir)
      path = File.join(dir, "1571-format.d71")
      File.binwrite(path, Array.new(D71_SIZE, 0).pack("C*"))
      text = "10 open1,8,15,\"u0>m1\":print#1,\"n:new disk,xy\":input#1,a,b$:close1:print a;b$\r" \
             "run\rsave\"prog\",8\rload\"$\",8\rlist\r"
      output = write_run(path, text, 5)
      report.check("no-error", Runs.number_before?(output, " 0", "OK"), "the error channel said no 0, OK")
      report.check("lists-new-disk", output.include?("\"NEW DISK        \" XY 2A") && output.include?("\"PROG\"") &&
                                     output.include?("1327 BLOCKS FREE"),
                   "listed no NEW DISK with PROG and 1327 free")
      image = Badline::Storage::D71Image.new(path)
      bam = image.read_block(18, 0)
      report.check("second-side", bam[3].anybits?(0x80) && bam[0xdd, 3] == SIDE_TWO_FREE,
                   "18/0 flags no second side, or counts no 21 blocks free on tracks 36-38")
      report.check("trap-readable", trap_listing(path).include?("10 OPEN1,8,15,\"U0>M1\""),
                   "the traps listed no 10 OPEN1")
    end

    # SAVE goes through the DOS to a disk put in write-protected, which
    # answers 26,WRITE PROTECT ON and leaves the file alone.
    def read_only(report, dir)
      path = File.join(dir, "1571-read-only.d64")
      Images.blank_d64(path, "BLANK")
      before = File.binread(path)
      machine = Badline::C128.new
      output = machine.capture_output
      Badline::Media::TrueDrive.plug(machine)
      Badline::Media.attach(machine, path, autostart: false, disk: { read_only: true })
      machine.on_init { machine.type_text("10 print\rsave\"x\",8\r") }
      Runs.run_until(machine, 40_000_000) { output.output.upcase.scan("READY.").length >= 2 }
      machine.drive1571.flush
      report.check("saves", output.output.upcase.include?("SAVING"), "printed no SAVING")
      report.check("image-unchanged", File.binread(path) == before, "the image changed")
    end

    # A disk attached with the true drive autostarts its first program.
    def autostart(report, dir)
      path = File.join(dir, "1571-autostart.d64")
      Images.blank_d64(path, "BLANK")
      Badline::Storage::D64Image.new(path).write_file("hello", AUTOSTART)
      machine = Badline::C128.new
      output = machine.capture_output
      Badline::Media::TrueDrive.plug(machine)
      Badline::Media.attach(machine, path)
      Runs.run_until(machine, 30_000_000) { output.output.upcase.include?("TRUE DRIVE\n") }
      text = output.output.upcase
      report.check("loads-and-runs", text.include?("LOADING") && text.include?("TRUE DRIVE\n"),
                   "printed no LOADING and TRUE DRIVE")
    end

    # BASIC reads DOS 3.0's power-on message from the error channel.
    def error_channel(report)
      machine = Badline::C128.new
      machine.attach_drive1571(Badline::Drive1571.new)
      output = machine.capture_output
      machine.on_init { machine.type_text("1open15,8,15:input#15,a,b$,c,d:printa;b$;c;d\rrun\r") }
      Runs.run_until(machine, 7_000_000) { output.output.upcase.include?(" 0 0\n") }
      report.check("power-on-message", output.output.upcase.include?(" 73CBM DOS V3.0 1571 0 0"),
                   "printed no 73,CBM DOS V3.0 1571,0,0")
    end

    # A C128 with the 1571 on its bus and the image at path in it, typing
    # text once booted. Runs until BASIC has printed READY. readies times,
    # and then until the drive's motor stops, and returns what it printed.
    def write_run(path, text, readies)
      machine = Badline::C128.new
      drive = Badline::Drive1571.new
      drive.insert(Badline::Drive1541::Disk.open(path))
      machine.attach_drive1571(drive)
      output = machine.capture_output
      machine.on_init { machine.type_text(text) }
      Runs.run_until(machine, 300_000_000) { output.output.upcase.scan("READY.").length >= readies }
      Runs.run_until(machine, 300_000_000) { !drive.mechanism.motor_on? }
      drive.flush
      output.output.upcase
    end

    # The .d71 through the C64's traps: what a LOAD of PROG and a LIST
    # print.
    def trap_listing(path)
      computer = Badline::Computer.new
      computer.mount(Badline::Storage::D71Image.new(path))
      output = computer.capture_output
      computer.on_init { computer.type_text("load\"prog\",8\rlist\r") }
      Runs.run_until(computer, 150_000_000) { output.output.upcase.scan("READY.").length >= 3 }
      output.output.upcase
    end
  end

  module Idle1571
    module_function

    # Idle's run (DriveScenarios::Idle) on two 1571s. Their DOS spins the
    # motor for about 4.4M cycles from power-on before it idles, so the
    # lines move later.
    def run(report)
      skipping = idle_drive(true)
      stepping = idle_drive(false)
      asleep = 0
      cycle = 0
      differs = []
      [5_000_000, 5_250_000, 5_300_100, 5_301_000, 5_450_000, 5_500_000, 6_000_000].each do |checkpoint|
        while cycle < checkpoint
          lines = Idle::LINES[cycle - 4_000_000]
          if lines
            skipping.serial_bus.host_lines = lines
            stepping.serial_bus.host_lines = lines
          end
          skipping.host_cycle!
          stepping.host_cycle!
          asleep += 1 if skipping.asleep?
          cycle += 1
        end
        differs << checkpoint unless same_drive?(skipping, stepping)
      end
      report.check("sleeps", asleep > 1_000_000, "slept #{asleep} cycles, not over 1000000")
      report.check("matches-stepping", differs.empty?, "differs at #{differs.join(',')}")
    end

    def idle_drive(idle_skip)
      drive = Badline::Drive1571.new(host_clock_hz: 985_248)
      drive.idle_skip = idle_skip
      bus = Badline::IECBus.new
      bus.host_lines = 0x07
      drive.connect(bus)
      drive
    end

    # Idle's comparison, with the CIA's counters, ICR and serial port.
    def same_drive?(one, other)
      Idle.same_drive?(one, other) && cia_state(one.cia) == cia_state(other.cia)
    end

    def cia_state(cia)
      [cia.timer_a, cia.timer_b, cia.interrupt_status.value, cia.serial.idle, *cia.timers.map(&:toggle),
       cia.time_of_day.cycles_to_tenth]
    end
  end
end
