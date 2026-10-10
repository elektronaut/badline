# frozen_string_literal: true

require "badline/core"

# The 1581's true-drive scenarios: the 3.5" drive running its own DOS on a
# C64's serial bus, through a save, a format, the error channel, a
# write-protected disk, an autostart and its idle loop, as the 1541's in
# test/drive_scenarios.rb. A .d81 holds 3160 free blocks once formatted.
module DriveScenarios
  module Runs1581
    D81_SIZE = 819_200

    # The scenarios and the checks each makes, the longest-running first.
    CHECKS = {
      "1581-format" => %w[no-error lists-new-disk header trap-readable],
      "1581-save" => %w[no-error loads-back file-in-image trap-readable],
      "1581-read-only" => %w[saves image-unchanged],
      "1581-autostart" => %w[loads-and-runs],
      "1581-error-channel" => %w[power-on-message],
      "1581-idle" => %w[sleeps matches-stepping]
    }.freeze

    module_function

    def run(report, name, dir)
      case name
      when "1581-save" then save(report, dir)
      when "1581-format" then format(report, dir)
      when "1581-read-only" then read_only(report, dir)
      when "1581-autostart" then autostart(report, dir)
      when "1581-error-channel" then error_channel(report)
      else Idle1581.run(report)
      end
    end

    # SAVE through the DOS to a blank disk, then NEW, LOAD and LIST it back.
    def save(report, dir)
      path = File.join(dir, "1581-save.d81")
      Images1581.blank_d81(path, "SAVE TEST", "ST")
      output = write_run(path, "10 print\"hello\"\rsave\"test\",8\rnew\rload\"test\",8\rlist\r", 5)
      report.check("no-error", !output.include?("ERROR"), "printed an error")
      report.check("loads-back", output.include?("LOADING") && output.include?("10 PRINT\"HELLO\""),
                   "listed no 10 PRINT\"HELLO\"")
      report.check("file-in-image", Badline::Storage::D81Image.new(path).read_file("test") == SAVED,
                   "no TEST as saved in the image")
      report.check("trap-readable", trap_listing(path, "test").include?("10 PRINT\"HELLO\""),
                   "the traps listed no 10 PRINT\"HELLO\"")
    end

    # N: on an image of zeros, then SAVE to it and LOAD the directory: the
    # header and BAM as the DOS's format leaves them, every cylinder written
    # on both sides, and 3159 blocks free beside PROG.
    def format(report, dir)
      path = File.join(dir, "1581-format.d81")
      File.binwrite(path, Array.new(D81_SIZE, 0).pack("C*"))
      text = "10 open1,8,15,\"n:new disk,xy\":input#1,a,b$:close1:print a;b$\r" \
             "run\rsave\"prog\",8\rload\"$\",8\rlist\r"
      output = write_run(path, text, 5)
      report.check("no-error", Runs.number_before?(output, " 0", "OK"), "the error channel said no 0, OK")
      report.check("lists-new-disk", output.include?("\"NEW DISK        \" XY 3D") && output.include?("\"PROG\"") &&
                                     output.include?("3159 BLOCKS FREE"),
                   "listed no NEW DISK with PROG and 3159 free")
      image = Badline::Storage::D81Image.new(path)
      report.check("header", image.read_block(40, 0)[0, 32] == Images1581.header("NEW DISK", "XY"),
                   "40/0 holds no NEW DISK,XY header")
      report.check("trap-readable", trap_listing(path, "prog").include?("10 OPEN1,8,15,\"N:NEW DISK,XY\""),
                   "the traps listed no 10 OPEN1")
    end

    # SAVE goes through the DOS to a disk put in write-protected, which
    # answers 26,WRITE PROTECT ON and leaves the file alone.
    def read_only(report, dir)
      path = File.join(dir, "1581-read-only.d81")
      Images1581.blank_d81(path, "BLANK", "BL")
      before = File.binread(path)
      computer = Badline::Computer.new
      output = computer.capture_output
      Badline::Media::TrueDrive.plug(computer)
      Badline::Media.attach(computer, path, autostart: false, disk: { read_only: true })
      computer.on_init { computer.type_text("10 print\rsave\"x\",8\r") }
      Runs.run_until(computer, 40_000_000) { output.output.upcase.scan("READY.").length >= 2 }
      computer.drive1581.flush
      report.check("saves", output.output.upcase.include?("SAVING"), "printed no SAVING")
      report.check("image-unchanged", File.binread(path) == before, "the image changed")
    end

    # A .d81 attached with a true drive autostarts its first program, the
    # 1581 taking the 1541's place.
    def autostart(report, dir)
      path = File.join(dir, "1581-autostart.d81")
      Images1581.blank_d81(path, "BLANK", "BL")
      Badline::Storage::D81Image.new(path).write_file("hello", AUTOSTART)
      computer = Badline::Computer.new
      output = computer.capture_output
      Badline::Media::TrueDrive.plug(computer)
      Badline::Media.attach(computer, path)
      Runs.run_until(computer, 30_000_000) { output.output.upcase.include?("TRUE DRIVE\n") }
      text = output.output.upcase
      report.check("loads-and-runs", text.include?("LOADING") && text.include?("TRUE DRIVE\n"),
                   "printed no LOADING and TRUE DRIVE")
    end

    # BASIC reads the DOS's power-on message from the error channel.
    def error_channel(report)
      computer = Badline::Computer.new
      computer.attach_drive1581(Badline::Drive1581.new)
      output = computer.capture_output
      computer.on_init { computer.type_text("1open15,8,15:input#15,a,b$,c,d:printa;b$;c;d\rrun\r") }
      Runs.run_until(computer, 7_000_000) { output.output.upcase.include?(" 0 0\n") }
      report.check("power-on-message", output.output.upcase.include?(" 73COPYRIGHT CBM DOS V10 1581 0 0"),
                   "printed no 73,COPYRIGHT CBM DOS V10 1581,0,0")
    end

    # A C64 with a 1581 on its bus and the image at path in it, typing text
    # once booted. Runs until BASIC has printed READY. readies times, and
    # then until the drive's motor stops, and returns what it printed.
    def write_run(path, text, readies)
      computer = Badline::Computer.new
      drive = Badline::Drive1581.new
      drive.insert(Badline::Drive1581::Disk.open(path))
      computer.attach_drive1581(drive)
      output = computer.capture_output
      computer.on_init { computer.type_text(text) }
      Runs.run_until(computer, 300_000_000) { output.output.upcase.scan("READY.").length >= readies }
      Runs.run_until(computer, 300_000_000) { !drive.mechanism.motor_on? }
      drive.flush
      output.output.upcase
    end

    # The .d81 through the C64's traps: what a LOAD of name and a LIST
    # print.
    def trap_listing(path, name)
      computer = Badline::Computer.new
      computer.mount(Badline::Storage::D81Image.new(path))
      output = computer.capture_output
      computer.on_init { computer.type_text("load\"#{name}\",8\rlist\r") }
      Runs.run_until(computer, 150_000_000) { output.output.upcase.scan("READY.").length >= 3 }
      output.output.upcase
    end
  end

  module Idle1581
    module_function

    # Idle's run (DriveScenarios::Idle) on two 1581s without a disk. Their
    # DOS boots for about 2.3M cycles, so the lines move from 3.2M.
    def run(report)
      skipping = idle_drive(true)
      stepping = idle_drive(false)
      asleep = 0
      cycle = 0
      differs = []
      [3_000_000, 3_250_000, 3_300_100, 3_301_000, 3_450_000, 3_500_000, 4_000_000].each do |checkpoint|
        while cycle < checkpoint
          lines = Idle::LINES[cycle - 2_000_000]
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
      drive = Badline::Drive1581.new(host_clock_hz: 985_248)
      drive.idle_skip = idle_skip
      bus = Badline::IECBus.new
      bus.host_lines = 0x07
      drive.connect(bus)
      drive
    end

    # The cycle counts, the CPU, the 8520's counters and registers, the
    # WD1772's registers and RAM.
    def same_drive?(one, other)
      drive_state(one) == drive_state(other) && one.ram.read(0, 0x2000) == other.ram.read(0, 0x2000)
    end

    def drive_state(drive)
      cpu = drive.cpu
      cia = drive.cia
      fdc = drive.fdc
      state = [drive.cycles, cpu.cycles, cpu.instructions]
      state.concat(cpu.idle_state)
      state.push(cia.timer_a, cia.timer_b, cia.interrupt_status.value, cia.port_a_lines, cia.port_b_lines,
                 cia.serial.idle, *cia.timers.map(&:toggle))
      state.push(fdc.now, fdc.status, fdc.track, fdc.sector, fdc.data, fdc.motor_on?)
    end
  end

  # Building D81 images as the 1581 DOS's format leaves them.
  module Images1581
    module_function

    # 40/0's first 32 bytes: the link to the first directory block, the
    # format letter, the disk name, the ID and the DOS version.
    def header(name, id)
      [40, 3, 0x44, 0, *name.bytes, *Array.new(16 - name.length, 0xa0), 0xa0, 0xa0, *id.bytes, 0xa0,
       *"3D".bytes, 0xa0, 0xa0, 0, 0, 0]
    end

    # A freshly formatted D81: the header, the two BAM blocks with every
    # block free but track 40's first four, and an empty directory.
    def blank_d81(path, name, id)
      bytes = Array.new(Runs1581::D81_SIZE, 0)
      track = 39 * 40 * 256
      bytes[track, 32] = header(name, id)
      bytes[track + 256, 8] = [40, 2, 0x44, 0xbb, *id.bytes, 0xc0, 0]
      bytes[track + 512, 8] = [0, 0xff, 0x44, 0xbb, *id.bytes, 0xc0, 0]
      80.times do |index|
        entry = track + 256 + (index >= 40 ? 256 : 0) + 0x10 + (6 * (index % 40))
        bytes[entry, 6] = index == 39 ? [36, 0xf0, 0xff, 0xff, 0xff, 0xff] : [40, 0xff, 0xff, 0xff, 0xff, 0xff]
      end
      bytes[track + 768, 2] = [0, 0xff]
      File.binwrite(path, bytes.pack("C*"))
    end
  end
end
