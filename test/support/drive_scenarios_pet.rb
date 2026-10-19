# frozen_string_literal: true

require "badline/core"

# The PET's 2031 scenarios: the 2031's DOS ROM on the IEEE-488 bus, every
# line of the handshake run by both sides. They format a disk, save and
# load a program, save to a write-protected disk, autostart a disk and read
# the error channel, as the C64's do in test/support/drive_scenarios.rb, on
# a 4032 with BASIC 4, and the error channel on a 3032 with BASIC 2 and a
# 2001 with BASIC 1 too. The idle scenario runs a PET with a sleeping
# drive beside one whose drive steps every cycle. The KERNAL prints
# SEARCHING, LOADING and SAVING without CHROUT, and BASIC 4 the READY.
# after a LOAD, so the checks go by what BASIC prints and count READY.
# without the LOADs.
module DriveScenarios
  module PETRuns
    # The scenarios and the checks each makes, the longest-running first.
    CHECKS = {
      "pet-2031-format" => %w[no-error lists-new-disk trap-readable],
      "pet-2031-save" => %w[no-error loads-back file-in-image trap-readable],
      "pet-2031-idle" => %w[sleeps matches-stepping],
      "pet-2031-read-only" => %w[write-protect-on image-unchanged],
      "pet-2031-autostart" => %w[loads-and-runs],
      "pet-2031-error-channel" => %w[power-on-message],
      "pet-2031-basic2-error-channel" => %w[power-on-message],
      "pet-2031-basic1-error-channel" => %w[power-on-message]
    }.freeze

    # 10 PRINT"HELLO", as SAVE writes it from the start of BASIC.
    SAVED = [0x01, 0x04, 0x0e, 0x04, 0x0a, 0x00, 0x99, 0x22, *"HELLO".bytes, 0x22, 0x00, 0x00, 0x00].freeze

    # 10 PRINT"TRUE DRIVE"
    AUTOSTART = [0x01, 0x04, 0x13, 0x04, 0x0a, 0x00, 0x99, 0x22, *"TRUE DRIVE".bytes, 0x22, 0x00, 0x00,
                 0x00].freeze

    SAVE_TEXT = "10 print\"hello\"\rsave\"test\",8\rnew\rload\"test\",8\rlist\r"

    ERROR_CHANNEL_TEXT = "1open15,8,15:input#15,a,b$,c,d:printa;b$;c;d\rrun\r"

    module_function

    def run(report, name, dir)
      case name
      when "pet-2031-format" then format(report, dir)
      when "pet-2031-save" then save(report, dir)
      when "pet-2031-idle" then idle(report, dir)
      when "pet-2031-read-only" then read_only(report, dir)
      when "pet-2031-autostart" then autostart(report, dir)
      when "pet-2031-error-channel" then error_channel(report, "4032")
      when "pet-2031-basic2-error-channel" then error_channel(report, "3032")
      else error_channel(report, "2001")
      end
    end

    # N: on an image of zeros, then SAVE to it and LOAD the directory, which
    # the traps read back too.
    def format(report, dir)
      path = File.join(dir, "pet-2031-format.d64")
      File.binwrite(path, Array.new(Images::D64_SIZE, 0).pack("C*"))
      text = "10 open1,8,15,\"n:new disk,xy\":input#1,a,b$:close1:print a;b$\r" \
             "run\rsave\"prog\",8\rload\"$\",8\rlist\r"
      output = write_run(path, text, 4)
      report.check("no-error", Runs.number_before?(output, " 0", "OK"), "the error channel said no 0, OK")
      report.check("lists-new-disk", output.include?("\"NEW DISK        \" XY 2A") && output.include?("\"PROG\"") &&
                                     output.include?("663 BLOCKS FREE"), "listed no NEW DISK with PROG and 663 free")
      report.check("trap-readable", trap_listing(path, "$").include?("663 BLOCKS FREE"),
                   "the traps listed no 663 BLOCKS FREE")
    end

    # SAVE through the DOS to a blank disk, then NEW, LOAD and LIST it back.
    def save(report, dir)
      path = File.join(dir, "pet-2031-save.d64")
      Images.blank_d64(path, "SAVE TEST")
      output = write_run(path, SAVE_TEXT, 4)
      report.check("no-error", !output.include?("ERROR"), "printed an error")
      report.check("loads-back", output.include?("10 PRINT\"HELLO\""),
                   "listed no 10 PRINT\"HELLO\"")
      report.check("file-in-image", Badline::Storage::D64Image.new(path).read_file("test") == SAVED,
                   "no TEST as saved in the image")
      report.check("trap-readable", trap_listing(path, "test").include?("10 PRINT\"HELLO\""),
                   "the traps listed no 10 PRINT\"HELLO\"")
    end

    # SAVE goes through the DOS to a disk put in write-protected, which
    # answers 26,WRITE PROTECT ON, as BASIC 4's DS$ reads, and leaves the
    # file alone.
    def read_only(report, dir)
      path = File.join(dir, "pet-2031-read-only.d64")
      Images.blank_d64(path, "BLANK")
      before = File.binread(path)
      machine = Badline::PET.new(model: "4032")
      output = machine.capture_output
      Badline::Media::TrueDrive.plug(machine)
      Badline::Media.attach(machine, path, autostart: false, disk: { read_only: true })
      machine.on_init { machine.type_text("10 print\rsave\"x\",8\rprint ds$\r") }
      Runs.run_until(machine, 40_000_000) { output.output.upcase.scan("READY.").length >= 3 }
      machine.true_drive.flush
      report.check("write-protect-on", output.output.upcase.include?("WRITE PROTECT ON"),
                   "printed no WRITE PROTECT ON")
      report.check("image-unchanged", File.binread(path) == before, "the image changed")
    end

    # A disk attached with the true drive a 2031 autostarts its first
    # program.
    def autostart(report, dir)
      path = File.join(dir, "pet-2031-autostart.d64")
      Images.blank_d64(path, "BLANK")
      Badline::Storage::D64Image.new(path).write_file("hello", AUTOSTART)
      machine = Badline::PET.new(model: "4032")
      output = machine.capture_output
      Badline::Media::TrueDrive.plug(machine)
      Badline::Media.attach(machine, path)
      Runs.run_until(machine, 30_000_000) { output.output.upcase.include?("TRUE DRIVE\n") }
      text = output.output.upcase
      report.check("loads-and-runs", text.include?("TRUE DRIVE\n"), "printed no TRUE DRIVE")
    end

    # The host cycles at which idle compares its two machines.
    IDLE_CHECKPOINTS = [1_000_000, 2_000_000, 3_000_000, 4_000_000, 5_000_000].freeze

    # Two PETs with a 2031 side by side, one drive sleeping through its
    # idle loop and one stepping every cycle, through the DOS's boot, a
    # LOAD of the directory and the idle after it. Both machines hold the
    # same at every checkpoint.
    def idle(report, dir)
      path = File.join(dir, "pet-2031-idle.d64")
      Images.blank_d64(path, "IDLE")
      skipping = idle_machine(path, true)
      stepping = idle_machine(path, false)
      drive = skipping.true_drive
      asleep = 0
      differs = []
      IDLE_CHECKPOINTS.each do |checkpoint|
        while skipping.cycles < checkpoint
          skipping.cycle!
          stepping.cycle!
          asleep += 1 if drive.asleep?
        end
        differs << checkpoint unless idle_state(skipping) == idle_state(stepping)
      end
      report.check("sleeps", asleep > 500_000, "slept #{asleep} host cycles, not over 500000")
      report.check("matches-stepping", differs.empty?, "differs at #{differs.join(',')}")
    end

    # What the machine and its drive hold: the machine's CPU and RAM, and
    # the drive's cycle counts, CPU, VIAs, head and RAM.
    def idle_state(machine)
      cpu = machine.cpu
      drive = machine.true_drive
      drive_cpu = drive.cpu
      state = [machine.cycles, cpu.program_counter, cpu.a, cpu.x, cpu.y, cpu.stack_pointer, cpu.p, cpu.cycles,
               drive.cycles, drive_cpu.cycles, drive_cpu.instructions]
      state.concat(drive_cpu.idle_state)
      [drive.via1, drive.via2].each do |via|
        state.concat(via.idle_state)
        state.push(via.timer1, via.timer2, via.port_a_output, via.port_b_output)
      end
      mechanism = drive.mechanism
      state.push(mechanism.half_track, mechanism.zone, mechanism.motor_on?, mechanism.led_on?, mechanism.writing?,
                 mechanism.sync?, mechanism.latched_byte)
      state.concat(drive.ram.read(0, 0x0800))
      state.concat(machine.ram.read(0, machine.ram.length))
    end

    def idle_machine(path, idle_skip)
      machine = Badline::PET.new(model: "4032")
      drive = Badline::Drives::Model2031.new
      drive.idle_skip = idle_skip
      drive.insert(Badline::Drives::Model1541::Disk.from_d64(Badline::Storage::D64Image.new(path)))
      machine.attach_ieee_drive(drive)
      machine.on_init { machine.type_text("load\"$\",8\r") }
      machine
    end

    # BASIC reads the power-on message from the drive's error channel over
    # the IEEE-488 bus.
    def error_channel(report, model)
      machine = Badline::PET.new(model:)
      machine.attach_ieee_drive(Badline::Drives::Model2031.new)
      output = machine.capture_output
      machine.on_init { machine.type_text(ERROR_CHANNEL_TEXT) }
      Runs.run_until(machine, 8_000_000) { output.output.upcase.include?(" 0 0\n") }
      report.check("power-on-message", output.output.upcase.include?(" 73CBM DOS V2.6 2031 0 0"),
                   "printed no 73,CBM DOS V2.6 2031,0,0")
    end

    # A 4032 with a 2031 on the bus and the D64 at path in it, typing text
    # once booted. Runs until BASIC has printed READY. readies times, and
    # then until the drive's motor stops, and returns what it printed.
    def write_run(path, text, readies)
      machine = Badline::PET.new(model: "4032")
      drive = Badline::Drives::Model2031.new
      drive.insert(Badline::Drives::Model1541::Disk.from_d64(Badline::Storage::D64Image.new(path)))
      machine.attach_ieee_drive(drive)
      output = machine.capture_output
      machine.on_init { machine.type_text(text) }
      Runs.run_until(machine, 150_000_000) { output.output.upcase.scan("READY.").length >= readies }
      Runs.run_until(machine, 150_000_000) { !drive.mechanism.motor_on? }
      output.output.upcase
    end

    # The same image through the PET's traps, without a drive: what a LOAD
    # of name and a LIST print.
    def trap_listing(path, name)
      machine = Badline::PET.new(model: "4032")
      machine.mount(Badline::Storage::D64Image.new(path))
      output = machine.capture_output
      machine.on_init { machine.type_text("load\"#{name}\",8\rlist\r") }
      Runs.run_until(machine, 150_000_000) { output.output.upcase.scan("READY.").length >= 2 }
      output.output.upcase
    end
  end
end
