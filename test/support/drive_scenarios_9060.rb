# frozen_string_literal: true

require "badline/core"

# The PET's scenarios for the D9060 and D9090 hard disks: DOS 3.0 on the
# interface processor and the SASI host's program on the other, every SASI
# command run through the controller against a .d90. On a 4032 with BASIC
# 4 they read the power-on message, list a directory, save and load a
# program, scratch a file and read a DOS error from the error channel.
#
# None formats: each starts from a blank image as c1541 formats it, which
# Storage::D90Image#format writes byte for byte, with files written into it
# beforehand where it needs them. Each scenario is named
# pet-MODEL-SCENARIO.
module DriveScenarios
  module PET9060Runs
    # The scenarios and the checks each makes.
    CHECKS = {
      "pet-9060-save" => %w[no-error loads-back file-in-image],
      "pet-9060-scratch" => %w[scratched gone-from-image],
      "pet-9090-directory" => %w[lists-files],
      "pet-9060-not-found" => %w[file-not-found],
      "pet-9060-error-channel" => %w[power-on-message],
      "pet-9090-error-channel" => %w[power-on-message]
    }.freeze

    # The size of each model's image.
    IMAGE_SIZES = { "9060" => 5_013_504, "9090" => 7_520_256 }.freeze

    # The blocks free on each model's blank disk.
    BLANK_FREE = { "9060" => 19_441, "9090" => 29_162 }.freeze

    POWER_ON = " 73CBM DOS V3.0 0 0"

    # 10 PRINT"HARD DISK"
    PROGRAM = [0x01, 0x04, 0x12, 0x04, 0x0a, 0x00, 0x99, 0x22, *"HARD DISK".bytes, 0x22, 0x00, 0x00, 0x00].freeze

    module_function

    def run(report, name, dir)
      model = name[/\Apet-(\d{4})-/, 1]
      case name.delete_prefix("pet-#{model}-")
      when "save" then save(report, dir, model)
      when "scratch" then scratch(report, dir, model)
      when "directory" then directory(report, dir, model)
      when "not-found" then not_found(report, dir, model)
      else error_channel(report, dir, model)
      end
    end

    # SAVE through the DOS to a blank disk, then NEW, LOAD and LIST it back.
    def save(report, dir, model)
      path = blank(dir, "pet-#{model}-save", model)
      output = typed_run(path, model, PETRuns::SAVE_TEXT, 4)
      report.check("no-error", !output.include?("ERROR"), "printed an error")
      report.check("loads-back", output.include?("10 PRINT\"HELLO\""), "listed no 10 PRINT\"HELLO\"")
      report.check("file-in-image", Badline::Storage::D90Image.new(path).read_file("test") == PETRuns::SAVED,
                   "no TEST as saved in the image")
    end

    # S through the error channel scratches a file the image held, and its
    # blocks come back free.
    def scratch(report, dir, model)
      path = blank(dir, "pet-#{model}-scratch", model)
      Badline::Storage::D90Image.new(path).write_file("old", PROGRAM)
      text = "10 open1,8,15,\"s0:old\":input#1,a,b$,c:close1:print a;b$;c\rrun\r"
      output = typed_run(path, model, text, 2)
      image = Badline::Storage::D90Image.new(path)
      report.check("scratched", output.include?(" 1FILES SCRATCHED 1"), "printed no 1,FILES SCRATCHED,1")
      report.check("gone-from-image", image.read_file("old").nil? && image.directory.blocks_free == BLANK_FREE[model],
                   "OLD is still in the image, or its block isn't free")
    end

    # LOAD"$" lists the disk's name, its files and its free blocks.
    def directory(report, dir, model)
      path = blank(dir, "pet-#{model}-directory", model)
      image = Badline::Storage::D90Image.new(path)
      image.write_file("hard disk", PROGRAM)
      image.write_file("notes", "NOTES\r".bytes * 100, type: :seq)
      output = typed_run(path, model, "load\"$\",8\rlist\r", 2)
      listed = ["\"BLANK           \" AB 3A", "1    \"HARD DISK\"        PRG", "3    \"NOTES\"            SEQ",
                "#{BLANK_FREE[model] - 4} BLOCKS FREE"]
      report.check("lists-files", listed.all? { |line| output.include?(line) }, "listed no #{listed.join(', ')}")
    end

    # Opening a file the disk doesn't hold leaves 62,FILE NOT FOUND on the
    # error channel.
    def not_found(report, dir, model)
      path = blank(dir, "pet-#{model}-not-found", model)
      text = "10 open1,8,15:open2,8,2,\"0:missing,s,r\":input#1,a,b$:close2:close1:print a;b$\rrun\r"
      output = typed_run(path, model, text, 2)
      report.check("file-not-found", output.include?(" 62FILE NOT FOUND"), "printed no 62,FILE NOT FOUND")
    end

    # BASIC reads the power-on message from the unit's error channel.
    def error_channel(report, dir, model)
      path = blank(dir, "pet-#{model}-error-channel", model)
      output = typed_run(path, model, PETRuns::ERROR_CHANNEL_TEXT, 2)
      report.check("power-on-message", output.include?(POWER_ON), "printed no#{POWER_ON}")
    end

    # A 4032 with the model on the bus and the image at path in it, typing
    # text once booted. Runs until BASIC has printed READY. readies times,
    # and returns what it printed.
    def typed_run(path, model, text, readies)
      machine = Badline::PET.new(model: "4032")
      machine.plug_ieee_drive(model).insert_image(path)
      output = machine.capture_output
      machine.on_init { machine.type_text(text) }
      Runs.run_until(machine, 40_000_000) { output.output.upcase.scan("READY.").length >= readies }
      output.output.upcase
    end

    # A blank image, named BLANK with the ID AB.
    def blank(dir, name, model)
      path = File.join(dir, "#{name}.d90")
      File.binwrite(path, Array.new(IMAGE_SIZES.fetch(model), 0).pack("C*"))
      Badline::Storage::D90Image.new(path).format("blank", "ab".bytes)
      path
    end
  end
end
