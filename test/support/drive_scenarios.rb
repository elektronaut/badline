# frozen_string_literal: true

require_relative "drive_scenarios_vic20"
require_relative "drive_scenarios_1571"
require_relative "drive_scenarios_1581"
require_relative "drive_scenarios_cpm"

# Whole-machine scenarios for the true 1541 running the real DOS ROM: saving
# and loading a program, formatting a disk, reading the error channel, the
# idle loop, a write-protected disk and autostart, on the VIC-20's
# serial bus a save, an autostart and the error channel
# (drive_scenarios_vic20.rb), the same on the C128's 1571, with a
# double-sided format (drive_scenarios_1571.rb), on a C64's 1581
# (drive_scenarios_1581.rb), and CP/M 3.0 booting on a C128 from a 1581
# (drive_scenarios_cpm.rb). Each takes tens of
# millions of cycles with two CPUs. A scenario runs on fresh machines and
# checks what they left behind, one baseline row per check:
# `scenario/check<TAB>PASS`, or `scenario/check<TAB>FAIL<TAB>detail`.
#
# It stays inside the Ruby subset Spinel compiles, so bin/drive_scenarios on
# CRuby and spinel/drive_scenarios.rb on a Spinel build score a scenario
# the same way.
module DriveScenarios
  # The scenarios and the checks each makes, the longest-running first.
  CHECKS = Runs1581::CHECKS.merge(CpmRuns::CHECKS).merge(
    "1571-format" => %w[no-error lists-new-disk second-side trap-readable],
    "format" => %w[no-error lists-new-disk name-and-id bam-free trap-readable],
    "save" => %w[no-error loads-back file-in-image trap-readable],
    "vic20-write" => %w[no-error loads-back file-in-image],
    "read-only" => %w[saves image-unchanged],
    "autostart" => %w[loads-and-runs],
    "vic20-autoboot" => %w[loads-and-runs],
    "error-channel" => %w[power-on-message],
    "vic20-status" => %w[power-on-message],
    "idle" => %w[sleeps matches-stepping],
    "1571-save" => %w[no-error loads-back file-in-image],
    "1571-read-only" => %w[saves image-unchanged],
    "1571-autostart" => %w[loads-and-runs],
    "1571-error-channel" => %w[power-on-message],
    "1571-idle" => %w[sleeps matches-stepping]
  ).freeze

  # The scenarios that run only when a filter names them.
  LONG_CHECKS = CpmRuns::LONG_CHECKS

  # 10 PRINT"HELLO", as SAVE writes it.
  SAVED = [0x01, 0x08, 0x0e, 0x08, 0x0a, 0x00, 0x99, 0x22, *"HELLO".bytes, 0x22, 0x00, 0x00, 0x00].freeze

  # 10 PRINT"TRUE DRIVE"
  AUTOSTART = [0x01, 0x08, 0x13, 0x08, 0x0a, 0x00, 0x99, 0x22, *"TRUE DRIVE".bytes, 0x22, 0x00, 0x00, 0x00].freeze

  # Runs the named scenario, writing its disk images into dir, and returns
  # its rows. A String in and a String out, so that `spin ext` can export
  # it to CRuby as it stands.
  def self.run(name, dir)
    report = Report.new(name)
    case name
    when "save" then save(report, dir)
    when "format" then format(report, dir)
    when "error-channel" then error_channel(report)
    when "idle" then Idle.run(report)
    when "read-only" then read_only(report, dir)
    when "autostart" then autostart(report, dir)
    when "vic20-write", "vic20-autoboot", "vic20-status" then Vic20Runs.run(report, name, dir)
    when "1571-save", "1571-format", "1571-read-only", "1571-autostart", "1571-error-channel", "1571-idle"
      C128Runs.run(report, name, dir)
    when "cpm-boot", "cpm-zexdoc", "cpm-zexall" then CpmRuns.run(report, name, dir)
    else
      raise ArgumentError, "No drive scenario #{name}" unless Runs1581::CHECKS.key?(name)

      Runs1581.run(report, name, dir)
    end
    report.rows
  end

  # SAVE through the DOS to a blank disk, then NEW, LOAD and LIST it back.
  def self.save(report, dir)
    path = File.join(dir, "save.d64")
    Images.blank_d64(path, "SAVE TEST")
    output = Runs.write_run(path, "10 print\"hello\"\rsave\"test\",8\rnew\rload\"test\",8\rlist\r", 5)
    report.check("no-error", !output.include?("ERROR"), "printed an error")
    report.check("loads-back", output.include?("LOADING") && output.include?("10 PRINT\"HELLO\""),
                 "listed no 10 PRINT\"HELLO\"")
    report.check("file-in-image", Badline::Storage::D64Image.new(path).read_file("test") == SAVED,
                 "no TEST as saved in the image")
    report.check("trap-readable", Runs.trap_listing(path, "test").include?("10 PRINT\"HELLO\""),
                 "the traps listed no 10 PRINT\"HELLO\"")
  end

  # N: on an image of zeros, then SAVE to it and LOAD the directory. The
  # trap path has no directory listing to LOAD, so it reads back the
  # program saved after the format, and the image the header and BAM.
  def self.format(report, dir)
    path = File.join(dir, "format.d64")
    File.binwrite(path, Array.new(Images::D64_SIZE, 0).pack("C*"))
    text = "10 open1,8,15,\"n:new disk,xy\":input#1,a,b$:close1:print a;b$\r" \
           "run\rsave\"prog\",8\rload\"$\",8\rlist\r"
    output = Runs.write_run(path, text, 5)
    report.check("no-error", Runs.number_before?(output, " 0", "OK"), "the error channel said no 0, OK")
    report.check("lists-new-disk", output.include?("\"NEW DISK        \" XY 2A") && output.include?("\"PROG\"") &&
                                   output.include?("663 BLOCKS FREE"), "listed no NEW DISK with PROG and 663 free")
    image = Badline::Storage::D64Image.new(path)
    report.check("name-and-id", image.read_block(18, 0)[0x90, 27] == Images.disk_header("NEW DISK", "XY"),
                 "no NEW DISK,XY in 18/0")
    report.check("bam-free", Images.free_blocks(image) == 663 + 17,
                 "the BAM has #{Images.free_blocks(image)} blocks free, not 680")
    report.check("trap-readable", Runs.trap_listing(path, "prog").include?("10 OPEN1,8,15,\"N:NEW DISK,XY\""),
                 "the traps listed no 10 OPEN1")
  end

  # BASIC reads the power-on message from the drive's error channel over
  # the real serial bus, since the serial traps don't answer device 8 with
  # a true drive attached. INPUT# is illegal in direct mode, so it runs as
  # a program line.
  def self.error_channel(report)
    computer = Badline::Computer.new
    computer.attach_drive1541(Badline::Drive1541.new)
    output = computer.capture_output
    computer.on_init { computer.type_text("1open15,8,15:input#15,a,b$,c,d:printa;b$;c;d\rrun\r") }
    computer.run_cycles(7_000_000)
    # PRINT follows each number with a cursor right, which CHROUT capture drops
    report.check("power-on-message", output.output.upcase.include?(" 73CBM DOS V2.6 1541 0 0"),
                 "printed no 73,CBM DOS V2.6 1541,0,0")
  end

  # SAVE goes through the DOS to a disk put in write-protected, which
  # answers 26,WRITE PROTECT ON and leaves the file alone.
  def self.read_only(report, dir)
    path = File.join(dir, "read-only.d64")
    Images.blank_d64(path, "BLANK")
    before = File.binread(path)
    computer = Badline::Computer.new
    output = computer.capture_output
    Badline::Media::TrueDrive.plug(computer)
    Badline::Media.attach(computer, path, autostart: false, disk: { read_only: true })
    computer.on_init { computer.type_text("10 print\rsave\"x\",8\r") }
    Runs.run_until(computer, 40_000_000) { output.output.upcase.scan("READY.").length >= 2 }
    computer.drive1541.flush
    report.check("saves", output.output.upcase.include?("SAVING"), "printed no SAVING")
    report.check("image-unchanged", File.binread(path) == before, "the image changed")
  end

  # A disk attached with a true drive autostarts its first program.
  def self.autostart(report, dir)
    path = File.join(dir, "autostart.d64")
    Images.blank_d64(path, "BLANK")
    Badline::Storage::D64Image.new(path).write_file("hello", AUTOSTART)
    computer = Badline::Computer.new
    output = computer.capture_output
    Badline::Media::TrueDrive.plug(computer)
    Badline::Media.attach(computer, path)
    Runs.run_until(computer, 30_000_000) { output.output.upcase.include?("TRUE DRIVE\n") }
    text = output.output.upcase
    report.check("loads-and-runs", text.include?("LOADING") && text.include?("TRUE DRIVE\n"),
                 "printed no LOADING and TRUE DRIVE")
  end
end

module DriveScenarios
  # The rows of one check each.
  class Report
    attr_reader :rows

    def initialize(scenario)
      @scenario = scenario
      @rows = +""
    end

    def check(name, passed, detail)
      @rows << "#{@scenario}/#{name}\t"
      @rows << (passed ? "PASS\n" : "FAIL\t#{detail}\n")
    end
  end

  module Idle
    # The C64's lines, keyed by the host cycle they change on: CLK, then
    # DATA, then ATN, while the drive idles. The DOS answers ATN and waits
    # for a byte that never comes until ATN goes.
    LINES = { 1_200_000 => 0x17, 1_210_000 => 0x07, 1_230_000 => 0x27, 1_233_333 => 0x07,
              1_300_000 => 0x0f, 1_300_500 => 0x07, 1_400_000 => 0x1f, 1_420_000 => 0x07 }.freeze
    CHECKPOINTS = [1_000_000, 1_250_000, 1_300_100, 1_301_000, 1_450_000, 1_500_000].freeze

    module_function

    # Two drives boot side by side, one skipping its idle loop and one not,
    # while the C64's lines move. The DOS reaches its idle loop about 1M
    # cycles after power-on, and the lines move from 1.2M.
    def run(report)
      skipping = idle_drive(true)
      stepping = idle_drive(false)
      asleep = 0
      cycle = 0
      differs = []
      CHECKPOINTS.each do |checkpoint|
        while cycle < checkpoint
          lines = LINES[cycle]
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
      report.check("sleeps", asleep > 400_000, "slept #{asleep} cycles, not over 400000")
      report.check("matches-stepping", differs.empty?, "differs at #{differs.join(',')}")
    end

    # A drive on a bus of its own, the C64's lines released.
    def idle_drive(idle_skip)
      drive = Badline::Drive1541.new(host_clock_hz: 985_248)
      drive.idle_skip = idle_skip
      bus = Badline::IECBus.new
      bus.host_lines = 0x07
      drive.connect(bus)
      drive
    end

    # Whether the two drives hold the same: cycle counts, CPU, VIAs,
    # mechanism and RAM.
    def same_drive?(one, other)
      drive_state(one) == drive_state(other) && one.ram.read(0, 0x0800) == other.ram.read(0, 0x0800)
    end

    def drive_state(drive)
      cpu = drive.cpu
      state = [drive.cycles, cpu.cycles, cpu.instructions]
      state.concat(cpu.idle_state)
      [drive.via1, drive.via2].each do |via|
        state.concat(via.idle_state)
        state.push(via.timer1, via.timer2, via.port_b_output)
      end
      state.concat(drive.mechanism.idle_state)
    end
  end

  # Driving the machines and reading what they printed.
  module Runs
    module_function

    # A C64 with the true drive on its bus and the D64 at path in it, typing
    # text once booted. Runs until BASIC has printed READY. readies times,
    # and then until the drive's motor stops, and returns what it printed.
    def write_run(path, text, readies)
      computer = Badline::Computer.new
      drive = Badline::Drive1541.new
      drive.insert(Badline::Drive1541::Disk.from_d64(Badline::Storage::D64Image.new(path)))
      computer.attach_drive1541(drive)
      output = computer.capture_output
      computer.on_init { computer.type_text(text) }
      run_until(computer, 150_000_000) { output.output.upcase.scan("READY.").length >= readies }
      run_until(computer, 150_000_000) { !drive.mechanism.motor_on? }
      output.output.upcase
    end

    # The same image through the traps, without a drive: what a LOAD of name
    # and a LIST print.
    def trap_listing(path, name)
      computer = Badline::Computer.new
      computer.mount(Badline::Storage::D64Image.new(path))
      output = computer.capture_output
      computer.on_init { computer.type_text("load\"#{name}\",8\rlist\r") }
      run_until(computer, 150_000_000) { output.output.upcase.scan("READY.").length >= 3 }
      output.output.upcase
    end

    # Runs in steps of 100,000 cycles until the block holds or the machine
    # has run limit cycles.
    def run_until(computer, limit)
      computer.run_cycles(100_000) until yield || computer.cycles > limit
    end

    # Whether text has number, then only what isn't a letter, then word, as
    # PRINT prints a number and a string with the cursor rights dropped.
    def number_before?(text, number, word)
      at = text.index(number)
      while at
        after = at + number.length
        after += 1 while after < text.length && !letter?(text[after])
        return true if text[after, word.length] == word

        at = text.index(number, at + 1)
      end
      false
    end

    def letter?(char) = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".include?(char)
  end

  # Building D64 images and reading them back.
  module Images
    D64_SECTORS = ([21] * 17) + ([19] * 7) + ([18] * 6) + ([17] * 5)
    D64_SIZE = 174_848

    module_function

    # The disk name, padding and ID as 18/0 holds them from $90.
    def disk_header(name, id)
      [*name.bytes, *Array.new(16 - name.length, 0xa0), 0xa0, 0xa0, *id.bytes, 0xa0, *"2A".bytes,
       *Array.new(4, 0xa0)]
    end

    def free_blocks(image)
      free = 0
      (1..35).each do |track|
        image.sectors_in(track).times { |sector| free += 1 if image.block_free?(track, sector) }
      end
      free
    end

    # A freshly formatted D64, as the DOS's NEW command leaves one: every
    # block free but the header, the BAM and the first directory block, and
    # an empty directory.
    def blank_d64(path, name)
      bytes = Array.new(D64_SIZE, 0)
      header = d64_offset(18, 0)
      D64_SECTORS.each_with_index do |sectors, index|
        used = index == 17 ? [0, 1] : []
        bytes[header + 4 + (4 * index), 4] = [sectors - used.length, *free_bitmap(sectors, used)]
      end
      bytes[header, 3] = [18, 1, 0x41]
      bytes[header + 0x90, 16] = [*name.bytes, *Array.new(16 - name.length, 0xa0)]
      bytes[d64_offset(18, 1), 2] = [0, 0xff]
      File.binwrite(path, bytes.pack("C*"))
    end

    def d64_offset(track, sector)
      (D64_SECTORS.first(track - 1).sum + sector) * 256
    end

    def free_bitmap(sectors, used)
      bits = 0
      sectors.times { |sector| bits |= 1 << sector unless used.include?(sector) }
      [bits & 0xff, (bits >> 8) & 0xff, (bits >> 16) & 0xff]
    end
  end
end
