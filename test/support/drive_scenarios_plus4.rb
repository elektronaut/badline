# frozen_string_literal: true

require "badline/core"
require "badline/plus4"

# The 264 series' true-drive scenarios: the same 1541 and 1581 DOS ROMs on
# the serial bus the 7501's port drives. They format a disk, save and load
# a program, save to a write-protected disk, autostart a disk and read the
# error channel, as the C64's scenarios in test/support/drive_scenarios.rb
# and test/support/drive_scenarios_1581.rb do, on a PAL Plus/4, and the
# error channel on a C16 too.
module DriveScenarios
  module Plus4Runs
    # The scenarios and the checks each makes, the longest-running first.
    CHECKS = {
      "plus4-format" => %w[no-error lists-new-disk trap-readable],
      "plus4-1581-save" => %w[no-error loads-back file-in-image],
      "plus4-save" => %w[no-error loads-back file-in-image trap-readable],
      "plus4-read-only" => %w[saves image-unchanged],
      "plus4-autostart" => %w[loads-and-runs],
      "plus4-1581-autostart" => %w[loads-and-runs],
      "plus4-error-channel" => %w[power-on-message],
      "plus4-c16-error-channel" => %w[power-on-message]
    }.freeze

    # 10 PRINT"HELLO", as SAVE writes it from the start of BASIC 3.5.
    SAVED = [0x01, 0x10, 0x0e, 0x10, 0x0a, 0x00, 0x99, 0x22, *"HELLO".bytes, 0x22, 0x00, 0x00, 0x00].freeze

    # 10 PRINT"TRUE DRIVE"
    AUTOSTART = [0x01, 0x10, 0x13, 0x10, 0x0a, 0x00, 0x99, 0x22, *"TRUE DRIVE".bytes, 0x22, 0x00, 0x00,
                 0x00].freeze

    SAVE_TEXT = "10 print\"hello\"\rsave\"test\",8\rnew\rload\"test\",8\rlist\r"

    module_function

    def run(report, name, dir)
      case name
      when "plus4-format" then format(report, dir)
      when "plus4-save" then save(report, dir)
      when "plus4-1581-save" then save1581(report, dir)
      when "plus4-read-only" then read_only(report, dir)
      when "plus4-autostart" then autostart(report, dir, "plus4-autostart.d64")
      when "plus4-1581-autostart" then autostart(report, dir, "plus4-1581-autostart.d81")
      when "plus4-error-channel" then error_channel(report, "plus4")
      else error_channel(report, "c16")
      end
    end

    # N: on an image of zeros, then SAVE to it and LOAD the directory, which
    # the traps read back too.
    def format(report, dir)
      path = File.join(dir, "plus4-format.d64")
      File.binwrite(path, Array.new(Images::D64_SIZE, 0).pack("C*"))
      text = "10 open1,8,15,\"n:new disk,xy\":input#1,a,b$:close1:print a;b$\r" \
             "run\rsave\"prog\",8\rload\"$\",8\rlist\r"
      output = write_run(path, text, 5)
      report.check("no-error", Runs.number_before?(output, " 0", "OK"), "the error channel said no 0, OK")
      report.check("lists-new-disk", output.include?("\"NEW DISK        \" XY 2A") && output.include?("\"PROG\"") &&
                                     output.include?("663 BLOCKS FREE"), "listed no NEW DISK with PROG and 663 free")
      report.check("trap-readable", trap_listing(path, "$").include?("663 BLOCKS FREE"),
                   "the traps listed no 663 BLOCKS FREE")
    end

    # SAVE through the DOS to a blank disk, then NEW, LOAD and LIST it back.
    def save(report, dir)
      path = File.join(dir, "plus4-save.d64")
      Images.blank_d64(path, "SAVE TEST")
      output = write_run(path, SAVE_TEXT, 5)
      saved(report, output, Badline::Storage::D64Image.new(path).read_file("test"))
      report.check("trap-readable", trap_listing(path, "test").include?("10 PRINT\"HELLO\""),
                   "the traps listed no 10 PRINT\"HELLO\"")
    end

    # The same through a 1581.
    def save1581(report, dir)
      path = File.join(dir, "plus4-1581-save.d81")
      Images1581.blank_d81(path, "SAVE TEST", "ST")
      machine = Badline::Plus4.new
      drive = Badline::Drives::Model1581.new
      drive.insert(Badline::Drives::Model1581::Disk.open(path))
      machine.attach_drive1581(drive)
      output = machine.capture_output
      machine.on_init { machine.type_text(SAVE_TEXT) }
      Runs.run_until(machine, 300_000_000) { output.output.upcase.scan("READY.").length >= 5 }
      Runs.run_until(machine, 300_000_000) { !drive.mechanism.motor_on? }
      drive.flush
      saved(report, output.output.upcase, Badline::Storage::D81Image.new(path).read_file("test"))
    end

    # What SAVE_TEXT printed, and the file it left on the disk.
    def saved(report, output, file)
      report.check("no-error", !output.include?("ERROR"), "printed an error")
      report.check("loads-back", output.include?("LOADING") && output.include?("10 PRINT\"HELLO\""),
                   "listed no 10 PRINT\"HELLO\"")
      report.check("file-in-image", file == SAVED, "no TEST as saved in the image")
    end

    # SAVE goes through the DOS to a disk put in write-protected, which
    # leaves the file alone.
    def read_only(report, dir)
      path = File.join(dir, "plus4-read-only.d64")
      Images.blank_d64(path, "BLANK")
      before = File.binread(path)
      machine = Badline::Plus4.new(true_drive_model: "1541")
      output = machine.capture_output
      Badline::Media::TrueDrive.plug(machine)
      Badline::Media.attach(machine, path, autostart: false, disk: { read_only: true })
      machine.on_init { machine.type_text("10 print\rsave\"x\",8\r") }
      Runs.run_until(machine, 40_000_000) { output.output.upcase.scan("READY.").length >= 2 }
      machine.drive1541.flush
      report.check("saves", output.output.upcase.include?("SAVING"), "printed no SAVING")
      report.check("image-unchanged", File.binread(path) == before, "the image changed")
    end

    # A disk attached with a true drive autostarts its first program: a
    # .d64 in a 1541, and a .d81 in a 1581 that takes the 1541's place.
    def autostart(report, dir, name)
      path = File.join(dir, name)
      if name.end_with?(".d81")
        Images1581.blank_d81(path, "BLANK", "BL")
        Badline::Storage::D81Image.new(path).write_file("hello", AUTOSTART)
      else
        Images.blank_d64(path, "BLANK")
        Badline::Storage::D64Image.new(path).write_file("hello", AUTOSTART)
      end
      machine = Badline::Plus4.new(true_drive_model: "1541")
      output = machine.capture_output
      Badline::Media::TrueDrive.plug(machine)
      Badline::Media.attach(machine, path)
      Runs.run_until(machine, 30_000_000) { output.output.upcase.include?("TRUE DRIVE\n") }
      text = output.output.upcase
      report.check("loads-and-runs", text.include?("LOADING") && text.include?("TRUE DRIVE\n"),
                   "printed no LOADING and TRUE DRIVE")
    end

    # BASIC reads the power-on message from the drive's error channel over
    # the serial bus.
    def error_channel(report, model)
      machine = Badline::Plus4.new(model:)
      machine.attach_drive1541(Badline::Drives::Model1541.new)
      output = machine.capture_output
      machine.on_init { machine.type_text("1open15,8,15:input#15,a,b$,c,d:printa;b$;c;d\rrun\r") }
      Runs.run_until(machine, 6_000_000) { output.output.upcase.include?(" 0 0\n") }
      report.check("power-on-message", output.output.upcase.include?(" 73CBM DOS V2.6 1541 0 0"),
                   "printed no 73,CBM DOS V2.6 1541,0,0")
    end

    # A Plus/4 with a 1541 on its bus and the D64 at path in it, typing
    # text once booted. Runs until BASIC has printed READY. readies times,
    # and then until the drive's motor stops, and returns what it printed.
    def write_run(path, text, readies)
      machine = Badline::Plus4.new
      drive = Badline::Drives::Model1541.new
      drive.insert(Badline::Drives::Model1541::Disk.from_d64(Badline::Storage::D64Image.new(path)))
      machine.attach_drive1541(drive)
      output = machine.capture_output
      machine.on_init { machine.type_text(text) }
      Runs.run_until(machine, 150_000_000) { output.output.upcase.scan("READY.").length >= readies }
      Runs.run_until(machine, 150_000_000) { !drive.mechanism.motor_on? }
      output.output.upcase
    end

    # The same image through the Plus/4's traps, without a drive: what a
    # LOAD of name and a LIST print.
    def trap_listing(path, name)
      machine = Badline::Plus4.new
      machine.mount(Badline::Storage::D64Image.new(path))
      output = machine.capture_output
      machine.on_init { machine.type_text("load\"#{name}\",8\rlist\r") }
      Runs.run_until(machine, 10_000_000) { output.output.upcase.scan("READY.").length >= 3 }
      output.output.upcase
    end
  end
end
