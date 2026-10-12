# frozen_string_literal: true

require "badline/core"
require "badline/plus4"

# The 264 series' 1551 scenarios: the 1551's DOS ROM on TCBM, the parallel
# cable to the TIA in the expansion port, which the KERNAL tries ahead of
# the serial bus. They format a disk, save and load a program, autostart a
# disk and read the error channel, as the serial drive's do in
# test/support/drive_scenarios_plus4.rb, on a PAL Plus/4, and the error
# channel on a C16 too.
module DriveScenarios
  module Plus4TCBMRuns
    # The scenarios and the checks each makes, the longest-running first.
    CHECKS = {
      "plus4-1551-format" => %w[no-error lists-new-disk trap-readable],
      "plus4-1551-save" => %w[no-error loads-back file-in-image trap-readable],
      "plus4-1551-autostart" => %w[loads-and-runs],
      "plus4-1551-error-channel" => %w[power-on-message],
      "plus4-1551-c16-error-channel" => %w[power-on-message]
    }.freeze

    module_function

    def run(report, name, dir)
      case name
      when "plus4-1551-format" then format(report, dir)
      when "plus4-1551-save" then save(report, dir)
      when "plus4-1551-autostart" then autostart(report, dir)
      when "plus4-1551-error-channel" then error_channel(report, "plus4")
      else error_channel(report, "c16")
      end
    end

    # N: on an image of zeros, then SAVE to it and LOAD the directory, which
    # the traps read back too.
    def format(report, dir)
      path = File.join(dir, "plus4-1551-format.d64")
      File.binwrite(path, Array.new(Images::D64_SIZE, 0).pack("C*"))
      text = "10 open1,8,15,\"n:new disk,xy\":input#1,a,b$:close1:print a;b$\r" \
             "run\rsave\"prog\",8\rload\"$\",8\rlist\r"
      output = write_run(path, text, 5)
      report.check("no-error", Runs.number_before?(output, " 0", "OK"), "the error channel said no 0, OK")
      report.check("lists-new-disk", output.include?("\"NEW DISK        \" XY 2A") && output.include?("\"PROG\"") &&
                                     output.include?("663 BLOCKS FREE"), "listed no NEW DISK with PROG and 663 free")
      report.check("trap-readable", Plus4Runs.trap_listing(path, "$").include?("663 BLOCKS FREE"),
                   "the traps listed no 663 BLOCKS FREE")
    end

    # SAVE through the DOS to a blank disk, then NEW, LOAD and LIST it back.
    def save(report, dir)
      path = File.join(dir, "plus4-1551-save.d64")
      Images.blank_d64(path, "SAVE TEST")
      output = write_run(path, Plus4Runs::SAVE_TEXT, 5)
      Plus4Runs.saved(report, output, Badline::Storage::D64Image.new(path).read_file("test"))
      report.check("trap-readable", Plus4Runs.trap_listing(path, "test").include?("10 PRINT\"HELLO\""),
                   "the traps listed no 10 PRINT\"HELLO\"")
    end

    # A disk attached with the true drive a 1551 autostarts its first
    # program.
    def autostart(report, dir)
      path = File.join(dir, "plus4-1551-autostart.d64")
      Images.blank_d64(path, "BLANK")
      Badline::Storage::D64Image.new(path).write_file("hello", Plus4Runs::AUTOSTART)
      machine = Badline::Plus4.new(true_drive_model: "1551")
      output = machine.capture_output
      Badline::Media::TrueDrive.plug(machine)
      Badline::Media.attach(machine, path)
      Runs.run_until(machine, 30_000_000) { output.output.upcase.include?("TRUE DRIVE\n") }
      text = output.output.upcase
      report.check("loads-and-runs", text.include?("LOADING") && text.include?("TRUE DRIVE\n"),
                   "printed no LOADING and TRUE DRIVE")
    end

    # BASIC reads the power-on message from the drive's error channel over
    # TCBM.
    def error_channel(report, model)
      machine = Badline::Plus4.new(model:)
      machine.attach_drive1551(Badline::Drives::Model1551.new)
      output = machine.capture_output
      machine.on_init { machine.type_text("1open15,8,15:input#15,a,b$,c,d:printa;b$;c;d\rrun\r") }
      Runs.run_until(machine, 6_000_000) { output.output.upcase.include?(" 0 0\n") }
      report.check("power-on-message", output.output.upcase.include?(" 73CBM DOS V2.6 TDISK 0 0"),
                   "printed no 73,CBM DOS V2.6 TDISK,0,0")
    end

    # A Plus/4 with a 1551 on TCBM and the D64 at path in it, typing text
    # once booted. Runs until BASIC has printed READY. readies times, and
    # then until the drive's motor stops, and returns what it printed.
    def write_run(path, text, readies)
      machine = Badline::Plus4.new
      drive = Badline::Drives::Model1551.new
      drive.insert(Badline::Drives::Model1541::Disk.from_d64(Badline::Storage::D64Image.new(path)))
      machine.attach_drive1551(drive)
      output = machine.capture_output
      machine.on_init { machine.type_text(text) }
      Runs.run_until(machine, 150_000_000) { output.output.upcase.scan("READY.").length >= readies }
      Runs.run_until(machine, 150_000_000) { !drive.mechanism.motor_on? }
      output.output.upcase
    end
  end
end
