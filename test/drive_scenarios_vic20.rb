# frozen_string_literal: true

require "badline/core"
require "badline/vic20"

# The VIC-20's true-drive scenarios: the same 1541 and DOS ROM on the
# VIC-20's serial bus, which the KERNAL drives from its VIAs. They save and
# load a program, autostart a disk and read the error channel, as the C64's
# scenarios in test/drive_scenarios.rb do.
module DriveScenarios
  module Vic20Runs
    # 10 PRINT"HELLO", as an unexpanded VIC-20's SAVE writes it.
    SAVED = [0x01, 0x10, 0x0e, 0x10, 0x0a, 0x00, 0x99, 0x22, *"HELLO".bytes, 0x22, 0x00, 0x00, 0x00].freeze

    # 10 PRINT"TRUE DRIVE"
    AUTOSTART = [0x01, 0x10, 0x13, 0x10, 0x0a, 0x00, 0x99, 0x22, *"TRUE DRIVE".bytes, 0x22, 0x00, 0x00,
                 0x00].freeze

    module_function

    def run(report, name, dir)
      case name
      when "vic20-write" then save(report, dir)
      when "vic20-autoboot" then autostart(report, dir)
      else error_channel(report)
      end
    end

    # SAVE through the DOS to a blank disk, then NEW, LOAD and LIST it back.
    def save(report, dir)
      path = File.join(dir, "vic20-write.d64")
      Images.blank_d64(path, "SAVE TEST")
      machine = Badline::Vic20.new
      drive = Badline::Drive1541.new
      drive.insert(Badline::Drive1541::Disk.from_d64(Badline::Storage::D64Image.new(path)))
      machine.attach_drive1541(drive)
      output = machine.capture_output
      machine.on_init { machine.type_text("10 print\"hello\"\rsave\"test\",8\rnew\rload\"test\",8\rlist\r") }
      run_until(machine, 150_000_000) { output.output.upcase.scan("READY.").length >= 5 }
      run_until(machine, 150_000_000) { !drive.mechanism.motor_on? }
      text = output.output.upcase
      report.check("no-error", !text.include?("ERROR"), "printed an error")
      report.check("loads-back", text.include?("LOADING") && text.include?("10 PRINT\"HELLO\""),
                   "listed no 10 PRINT\"HELLO\"")
      report.check("file-in-image", Badline::Storage::D64Image.new(path).read_file("test") == SAVED,
                   "no TEST as saved in the image")
    end

    # A disk attached with a true drive autostarts its first program.
    def autostart(report, dir)
      path = File.join(dir, "vic20-autoboot.d64")
      Images.blank_d64(path, "BLANK")
      Badline::Storage::D64Image.new(path).write_file("hello", AUTOSTART)
      machine = Badline::Vic20.new
      output = machine.capture_output
      Badline::Media::TrueDrive.plug(machine)
      Badline::Media.attach(machine, path)
      run_until(machine, 30_000_000) { output.output.upcase.include?("TRUE DRIVE\n") }
      text = output.output.upcase
      report.check("loads-and-runs", text.include?("LOADING") && text.include?("TRUE DRIVE\n"),
                   "printed no LOADING and TRUE DRIVE")
    end

    # BASIC reads the power-on message from the drive's error channel over
    # the serial bus.
    def error_channel(report)
      machine = Badline::Vic20.new
      machine.attach_drive1541(Badline::Drive1541.new)
      output = machine.capture_output
      machine.on_init { machine.type_text("1open15,8,15:input#15,a,b$,c,d:printa;b$;c;d\rrun\r") }
      run_until(machine, 6_000_000) { output.output.upcase.include?(" 0 0\n") }
      report.check("power-on-message", output.output.upcase.include?(" 73CBM DOS V2.6 1541 0 0"),
                   "printed no 73,CBM DOS V2.6 1541,0,0")
    end

    def run_until(machine, limit)
      machine.run_cycles(100_000) until yield || machine.cycles > limit
    end
  end
end
