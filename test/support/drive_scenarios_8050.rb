# frozen_string_literal: true

require "badline/core"

# The PET's scenarios for the units with two processors, an 8050 and an
# 8250: DOS 2.7 on the interface processor and the controller's program in
# its 6530, on the IEEE-488 bus, every line of the handshake run by both
# sides. On a 4032 with BASIC 4 they format a disk, save and load a
# program, save to a write-protected disk, autostart a disk and read the
# error channel, as the 2031's do (drive_scenarios_pet.rb), the 8250 on its
# double-sided .d82. The idle scenario runs a PET with a sleeping unit
# beside one whose unit steps every cycle. Each scenario is named
# pet-MODEL-SCENARIO, and the tables below say where the models differ.
module DriveScenarios
  module PET8050Runs
    # The scenarios and the checks each makes, the longest-running first.
    CHECKS = {
      "pet-8250-format" => %w[no-error lists-new-disk trap-readable],
      "pet-8050-format" => %w[no-error lists-new-disk trap-readable],
      "pet-8250-save" => %w[no-error loads-back file-in-image trap-readable],
      "pet-8050-idle" => %w[sleeps matches-stepping],
      "pet-8050-save" => %w[no-error loads-back file-in-image trap-readable],
      "pet-8050-read-only" => %w[write-protect-on image-unchanged],
      "pet-8050-autostart" => %w[loads-and-runs],
      "pet-8250-autostart" => %w[loads-and-runs],
      "pet-8050-error-channel" => %w[power-on-message],
      "pet-8250-error-channel" => %w[power-on-message]
    }.freeze

    # Each model's disk image, by its extension.
    EXTENSIONS = { "8050" => ".d80", "8250" => ".d82" }.freeze

    # The size of a disk image of each kind.
    IMAGE_SIZES = { ".d80" => 533_248, ".d82" => 1_066_496 }.freeze

    # The blocks free on a newly formatted disk: 2052 on an 8050, 4133 on an
    # 8250, less one for PROG.
    FREE_AFTER_PROG = { "8050" => "2051 BLOCKS FREE", "8250" => "4132 BLOCKS FREE" }.freeze

    # The disk's header line once formatted as NEW DISK with the ID XY.
    NEW_DISK = { "8050" => "\"NEW DISK        \" XY 2C", "8250" => "\"NEW DISK        \" XY 2C" }.freeze

    # The power-on message each model's error channel reads.
    MESSAGES = { "8050" => " 73CBM DOS V2.7 0 0", "8250" => " 73CBM DOS V2.7 0 0" }.freeze

    module_function

    def run(report, name, dir)
      model = name[/\Apet-(\d{4})-/, 1]
      case name.delete_prefix("pet-#{model}-")
      when "format" then format(report, dir, model)
      when "save" then save(report, dir, model)
      when "read-only" then read_only(report, dir, model)
      when "idle" then idle(report, dir, model)
      when "autostart" then autostart(report, dir, model)
      else error_channel(report, model)
      end
    end

    # N: on an image of zeros, then SAVE to it and LOAD the directory, which
    # the traps read back too.
    def format(report, dir, model)
      path = File.join(dir, "pet-#{model}-format#{extension(model)}")
      File.binwrite(path, Array.new(image_size(model), 0).pack("C*"))
      text = "10 open1,8,15,\"n:new disk,xy\":input#1,a,b$:close1:print a;b$\r" \
             "run\rsave\"prog\",8\rload\"$\",8\rlist\r"
      output = write_run(path, model, text, 4)
      free = FREE_AFTER_PROG.fetch(model)
      report.check("no-error", Runs.number_before?(output, " 0", "OK"), "the error channel said no 0, OK")
      report.check("lists-new-disk", output.include?(NEW_DISK.fetch(model)) && output.include?("\"PROG\"") &&
                                     output.include?(free), "listed no NEW DISK with PROG and #{free}")
      report.check("trap-readable", trap_listing(path, "$").include?(free), "the traps listed no #{free}")
    end

    # SAVE through the DOS to a blank disk, then NEW, LOAD and LIST it back.
    def save(report, dir, model)
      path = blank(dir, "pet-#{model}-save", model)
      output = write_run(path, model, PETRuns::SAVE_TEXT, 4)
      report.check("no-error", !output.include?("ERROR"), "printed an error")
      report.check("loads-back", output.include?("10 PRINT\"HELLO\""), "listed no 10 PRINT\"HELLO\"")
      report.check("file-in-image", open_image(path, model).read_file("test") == PETRuns::SAVED,
                   "no TEST as saved in the image")
      report.check("trap-readable", trap_listing(path, "test").include?("10 PRINT\"HELLO\""),
                   "the traps listed no 10 PRINT\"HELLO\"")
    end

    # SAVE to a disk put in write-protected answers 26,WRITE PROTECT ON, as
    # BASIC 4's DS$ reads, and leaves the file alone.
    def read_only(report, dir, model)
      path = blank(dir, "pet-#{model}-read-only", model)
      before = File.binread(path)
      machine = Badline::PET.new(model: "4032")
      output = machine.capture_output
      Badline::Media::TrueDrive.plug(machine)
      Badline::Media.attach(machine, path, autostart: false, disk: { read_only: true })
      machine.on_init { machine.type_text("10 print\rsave\"x\",8\rprint ds$\r") }
      Runs.run_until(machine, 60_000_000) { output.output.upcase.scan("READY.").length >= 3 }
      machine.true_drive.flush
      report.check("write-protect-on", output.output.upcase.include?("WRITE PROTECT ON"),
                   "printed no WRITE PROTECT ON")
      report.check("image-unchanged", File.binread(path) == before, "the image changed")
    end

    # A disk attached with the true drive autostarts its first program,
    # the .d80 in an 8050 and the .d82 in an 8250.
    def autostart(report, dir, model)
      path = blank(dir, "pet-#{model}-autostart", model)
      open_image(path, model).write_file("hello", PETRuns::AUTOSTART)
      machine = Badline::PET.new(model: "4032")
      output = machine.capture_output
      Badline::Media::TrueDrive.plug(machine)
      Badline::Media.attach(machine, path)
      Runs.run_until(machine, 60_000_000) { output.output.upcase.include?("TRUE DRIVE\n") }
      report.check("loads-and-runs", output.output.upcase.include?("TRUE DRIVE\n"), "printed no TRUE DRIVE")
    end

    # The host cycles at which idle compares its two machines.
    IDLE_CHECKPOINTS = [2_000_000, 6_000_000, 10_000_000, 14_000_000].freeze

    # Two PETs with the model side by side, one unit sleeping through its idle
    # loops and one stepping every cycle, through the unit's boot, a LOAD of
    # the directory, the motor's run-down and the idle after it. Both
    # machines hold the same at every checkpoint.
    def idle(report, dir, model)
      skipping = idle_machine(blank(dir, "pet-#{model}-idle-a", model), model, true)
      stepping = idle_machine(blank(dir, "pet-#{model}-idle-b", model), model, false)
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
      report.check("sleeps", asleep > 4_000_000, "slept #{asleep} host cycles, not over 4000000")
      report.check("matches-stepping", differs.empty?, "differs at #{differs.join(',')}")
    end

    def idle_machine(path, model, idle_skip)
      machine = Badline::PET.new(model: "4032")
      drive = machine.plug_ieee_drive(model)
      drive.idle_skip = idle_skip
      drive.insert_image(path)
      machine.on_init { machine.type_text("load\"$\",8\r") }
      machine
    end

    # What the machine and the unit hold: the machine's CPU and RAM, and the
    # unit's cycle counts, both processors, its chips with their counters,
    # the drives and every RAM.
    def idle_state(machine)
      cpu = machine.cpu
      drive = machine.true_drive
      state = [machine.cycles, cpu.program_counter, cpu.a, cpu.x, cpu.y, cpu.stack_pointer, cpu.p, cpu.cycles,
               drive.cycles]
      [drive.ip_cpu, drive.fdc_cpu].each { |unit| state.push(unit.cycles, unit.instructions).concat(unit.idle_state) }
      [drive.data_riot, drive.control_riot].each { |riot| state.push(riot.timer.counter).concat(riot.idle_state) }
      state.push(drive.rriot.timer.counter).concat(drive.rriot.idle_state)
      via = drive.via
      state.push(via.timer1, via.timer2).concat(via.idle_state)
      state.concat(drive.mechanism.idle_state)
      state.concat(drive.common.read(0, 0x1000))
      state.concat(machine.ram.read(0, machine.ram.length))
    end

    # BASIC reads the power-on message from the unit's error channel.
    def error_channel(report, model)
      machine = Badline::PET.new(model: "4032")
      machine.plug_ieee_drive(model)
      output = machine.capture_output
      machine.on_init { machine.type_text(PETRuns::ERROR_CHANNEL_TEXT) }
      Runs.run_until(machine, 10_000_000) { output.output.upcase.include?(" 0 0\n") }
      message = MESSAGES.fetch(model)
      report.check("power-on-message", output.output.upcase.include?(message), "printed no#{message}")
    end

    # A 4032 with the model on the bus and the image at path in drive 0,
    # typing text once booted. Runs until BASIC has printed READY. readies
    # times, and then until the motor stops, and returns what it printed.
    def write_run(path, model, text, readies)
      machine = Badline::PET.new(model: "4032")
      drive = machine.plug_ieee_drive(model)
      drive.insert_image(path)
      output = machine.capture_output
      machine.on_init { machine.type_text(text) }
      Runs.run_until(machine, 400_000_000) { output.output.upcase.scan("READY.").length >= readies }
      Runs.run_until(machine, 400_000_000) { !drive.mechanism.motor_on? }
      drive.flush
      output.output.upcase
    end

    # The same image through the PET's traps, without a drive: what a LOAD
    # of name and a LIST print.
    def trap_listing(path, name)
      machine = Badline::PET.new(model: "4032")
      machine.mount(image_at(path))
      output = machine.capture_output
      machine.on_init { machine.type_text("load\"#{name}\",8\rlist\r") }
      Runs.run_until(machine, 150_000_000) { output.output.upcase.scan("READY.").length >= 2 }
      output.output.upcase
    end

    # A newly formatted image, named BLANK with the ID AB.
    def blank(dir, name, model)
      path = File.join(dir, "#{name}#{extension(model)}")
      File.binwrite(path, Array.new(image_size(model), 0).pack("C*"))
      open_image(path, model).format("blank", "ab".bytes)
      path
    end

    def open_image(path, model) = image_at(path, extension(model))

    # The image at path, of the kind the extension names.
    def image_at(path, extension = File.extname(path))
      extension == ".d82" ? Badline::Storage::D82Image.new(path) : Badline::Storage::D80Image.new(path)
    end

    def extension(model) = EXTENSIONS.fetch(model)

    def image_size(model) = IMAGE_SIZES.fetch(extension(model))
  end
end
