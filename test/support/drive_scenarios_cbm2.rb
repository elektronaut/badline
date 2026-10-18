# frozen_string_literal: true

require "badline/core"
require "badline/cbm2"

# The CBM-II's true drives on its IEEE-488 bus (CBM2::IEEEPorts): a 2031,
# an 8050 and an 8250 on a 610, every line of the handshake run by both
# sides. As the PET's scenarios do (drive_scenarios_pet.rb and
# drive_scenarios_8050.rb), they format a disk, save and load a program,
# autostart a disk and read the error channel, and the idle scenario runs
# a 610 with a sleeping 2031 beside one whose 2031 steps every cycle. The
# P500's scenarios save to an 8050 and read a 2031's error channel on a
# 510, on the same ports.
# BASIC's text is in segment 1, from $0003. BASIC prints READY. once
# booted and after every command, LOAD included, so the runs count each.
module DriveScenarios
  module CBM2Runs
    # The scenarios and the checks each makes, the longest-running first.
    CHECKS = {
      "cbm2-8050-format" => %w[no-error lists-new-disk trap-readable],
      "cbm2-2031-format" => %w[no-error lists-new-disk trap-readable],
      "cbm2-8050-save" => %w[no-error loads-back file-in-image trap-readable],
      "cbm2-2031-save" => %w[no-error loads-back file-in-image trap-readable],
      "cbm2-2031-idle" => %w[sleeps matches-stepping],
      "cbm2-8050-autostart" => %w[loads-and-runs],
      "cbm2-2031-error-channel" => %w[power-on-message],
      "cbm2-8050-error-channel" => %w[power-on-message],
      "cbm2-8250-error-channel" => %w[power-on-message],
      "p500-8050-save" => %w[no-error loads-back file-in-image trap-readable],
      "p500-2031-error-channel" => %w[power-on-message]
    }.freeze

    # 10 PRINT"HELLO", as SAVE writes it from the start of BASIC's text.
    SAVED = [0x03, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x99, 0x22, *"HELLO".bytes, 0x22, 0x00, 0x00, 0x00].freeze

    # 10 PRINT"TRUE DRIVE"
    AUTOSTART = [0x03, 0x00, 0x15, 0x00, 0x0a, 0x00, 0x99, 0x22, *"TRUE DRIVE".bytes, 0x22, 0x00, 0x00,
                 0x00].freeze

    # The power-on message each model's error channel reads.
    MESSAGES = { "2031" => " 73CBM DOS V2.6 2031 0 0", "8050" => " 73CBM DOS V2.7 0 0",
                 "8250" => " 73CBM DOS V2.7 0 0" }.freeze

    # The blocks free on a newly formatted disk, less one for PROG.
    FREE_AFTER_PROG = { "2031" => "663 BLOCKS FREE", "8050" => "2051 BLOCKS FREE" }.freeze

    # The disk's header line once formatted as NEW DISK with the ID XY.
    NEW_DISK = { "2031" => "\"NEW DISK        \" XY 2A", "8050" => "\"NEW DISK        \" XY 2C" }.freeze

    module_function

    def run(report, name, dir)
      p500 = name.start_with?("p500-")
      model = name[/\A(?:cbm2|p500)-(\d{4})-/, 1]
      case name.delete_prefix("#{p500 ? 'p500' : 'cbm2'}-#{model}-")
      when "format" then format(report, dir, model)
      when "save" then save(report, dir, model, p500)
      when "idle" then idle(report, dir)
      when "autostart" then autostart(report, dir, model)
      else error_channel(report, model, p500)
      end
    end

    # A 610, or a 510 for the P500's scenarios.
    def machine(p500) = p500 ? Badline::CBM2::P500.new : Badline::CBM2.new

    # N: on an image of zeros, then SAVE to it and LOAD the directory, which
    # the traps read back too.
    def format(report, dir, model)
      path = File.join(dir, "cbm2-#{model}-format#{extension(model)}")
      File.binwrite(path, Array.new(image_size(model), 0).pack("C*"))
      text = "10 open1,8,15,\"n:new disk,xy\":input#1,a,b$:close1:print a;b$\r" \
             "run\rsave\"prog\",8\rload\"$\",8\rlist\r"
      output = write_run(path, model, text, 5, false)
      free = FREE_AFTER_PROG.fetch(model)
      report.check("no-error", Runs.number_before?(output, " 0", "OK"), "the error channel said no 0, OK")
      report.check("lists-new-disk", output.include?(NEW_DISK.fetch(model)) && output.include?("\"PROG\"") &&
                                     output.include?(free), "listed no NEW DISK with PROG and #{free}")
      report.check("trap-readable", trap_listing(path, model, "$").include?(free), "the traps listed no #{free}")
    end

    # SAVE through the DOS to a blank disk, then NEW, LOAD and LIST it back.
    def save(report, dir, model, p500)
      path = blank(dir, "#{p500 ? 'p500' : 'cbm2'}-#{model}-save", model)
      output = write_run(path, model, PETRuns::SAVE_TEXT, 5, p500)
      report.check("no-error", !output.include?("ERROR"), "printed an error")
      report.check("loads-back", output.include?("10 PRINT\"HELLO\""), "listed no 10 PRINT\"HELLO\"")
      report.check("file-in-image", open_image(path, model).read_file("test") == SAVED,
                   "no TEST as saved in the image")
      report.check("trap-readable", trap_listing(path, model, "test").include?("10 PRINT\"HELLO\""),
                   "the traps listed no 10 PRINT\"HELLO\"")
    end

    # A .d80 attached with an 8050 plugged in autostarts its first program.
    # A 610's first LOAD from a 2031 after power-on finds no file, on
    # xcbm2 as here, so the 2031 has no autostart scenario.
    def autostart(report, dir, model)
      path = blank(dir, "cbm2-#{model}-autostart", model)
      open_image(path, model).write_file("hello", AUTOSTART)
      machine = Badline::CBM2.new
      output = machine.capture_output
      Badline::Media::TrueDrive.plug(machine)
      Badline::Media.attach(machine, path)
      Runs.run_until(machine, 60_000_000) { output.output.upcase.include?("TRUE DRIVE\n") }
      report.check("loads-and-runs", output.output.upcase.include?("TRUE DRIVE\n"), "printed no TRUE DRIVE")
    end

    # The host cycles at which idle compares its two machines.
    IDLE_CHECKPOINTS = [9_000_000, 10_000_000, 11_000_000, 12_000_000].freeze

    # Two 610s with a 2031 side by side, one drive sleeping through its
    # idle loop and one stepping every cycle, through the RAM test, a LOAD
    # of the directory and the idle after it. Both machines hold the same at
    # every checkpoint.
    def idle(report, dir)
      skipping = idle_machine(blank(dir, "cbm2-2031-idle-a", "2031"), true)
      stepping = idle_machine(blank(dir, "cbm2-2031-idle-b", "2031"), false)
      drive = skipping.drive2031
      asleep = 0
      differs = []
      IDLE_CHECKPOINTS.each do |checkpoint|
        while skipping.cycles < checkpoint
          skipping.cycle!
          stepping.cycle!
          asleep += 1 if drive.asleep?
        end
        differs << checkpoint unless PETRuns.idle_state(skipping) == PETRuns.idle_state(stepping)
      end
      report.check("sleeps", asleep > 4_000_000, "slept #{asleep} host cycles, not over 4000000")
      report.check("matches-stepping", differs.empty?, "differs at #{differs.join(',')}")
    end

    def idle_machine(path, idle_skip)
      machine = Badline::CBM2.new
      drive = Badline::Drives::Model2031.new
      drive.idle_skip = idle_skip
      drive.insert(Badline::Drives::Model1541::Disk.from_d64(Badline::Storage::D64Image.new(path)))
      machine.attach_drive2031(drive)
      machine.on_init { machine.type_text("load\"$\",8\r") }
      machine
    end

    # BASIC reads the power-on message from the drive's error channel.
    def error_channel(report, model, p500)
      machine = machine(p500)
      plug(machine, model)
      output = machine.capture_output
      machine.on_init { machine.type_text(PETRuns::ERROR_CHANNEL_TEXT) }
      Runs.run_until(machine, 20_000_000) { output.output.upcase.include?(" 0 0\n") }
      message = MESSAGES.fetch(model)
      report.check("power-on-message", output.output.upcase.include?(message), "printed no#{message}")
    end

    # A 610, or a 510, with the model on the bus and the image at path in it, typing
    # text once booted. Runs until BASIC has printed READY. readies times,
    # and then until the motor stops, and returns what it printed.
    def write_run(path, model, text, readies, p500)
      machine = machine(p500)
      drive = plug(machine, model)
      drive.insert_image(path)
      output = machine.capture_output
      machine.on_init { machine.type_text(text) }
      Runs.run_until(machine, 600_000_000) { output.output.upcase.scan("READY.").length >= readies }
      Runs.run_until(machine, 600_000_000) { !drive.mechanism.motor_on? }
      drive.flush
      output.output.upcase
    end

    def plug(machine, model)
      model == "2031" ? machine.plug_true_drive : machine.plug_drive8050(model)
    end

    # The same image through the 610's traps, without a drive: what a LOAD
    # of name and a LIST print, once LIST's READY. is out.
    def trap_listing(path, model, name)
      machine = Badline::CBM2.new
      machine.mount(open_image(path, model))
      output = machine.capture_output
      machine.on_init { machine.type_text("load\"#{name}\",8\rlist\r") }
      Runs.run_until(machine, 150_000_000) { output.output.upcase.scan("READY.").length >= 3 }
      output.output.upcase
    end

    # A newly formatted image, named BLANK with the ID AB.
    def blank(dir, name, model)
      return PET8050Runs.blank(dir, name, model) unless model == "2031"

      path = File.join(dir, "#{name}.d64")
      Images.blank_d64(path, "BLANK")
      path
    end

    def open_image(path, model)
      return Badline::Storage::D64Image.new(path) if model == "2031"

      PET8050Runs.open_image(path, model)
    end

    def extension(model) = model == "2031" ? ".d64" : PET8050Runs.extension(model)

    def image_size(model) = model == "2031" ? Images::D64_SIZE : PET8050Runs.image_size(model)
  end
end
