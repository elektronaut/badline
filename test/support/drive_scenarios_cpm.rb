# frozen_string_literal: true

require "badline/core"
require "badline/c128"

# CP/M 3.0 on the C128, booted from VICE-testprogs' c128-cpm/cpm3.d81,
# attached as the command line attaches it, which puts a boot disk in a
# true 1581 (Media::BootDisk). The C128 KERNAL reads the boot sector over the fast serial bus,
# and its boot code hands the bus to the Z80, which loads CP/M through the
# 8502's disk BIOS. Keys go in through the keyboard matrix, which CP/M scans
# itself, and the 40-column screen, wherever the VIC-IIe shows it, is what
# the checks read. The image is copied into the scenario's directory first,
# so the run can't change VICE-testprogs.
#
# cpm-boot runs in CI. ZEXDOC and ZEXALL, from the same disk, run for
# billions of cycles each, so cpm-zexdoc and cpm-zexall run only when
# named (CpmRuns::LONG_CHECKS).
module DriveScenarios
  module CpmRuns
    CHECKS = { "cpm-boot" => %w[boots-to-prompt lists-disk] }.freeze

    # Scenarios too long for a whole run, which bin/drive_scenarios runs
    # only when a filter names them: the instruction exercisers.
    LONG_CHECKS = {
      "cpm-zexall" => %w[completes all-ok],
      "cpm-zexdoc" => %w[completes all-ok]
    }.freeze

    IMAGE = "vendor/VICE-testprogs/c128-cpm/cpm3.d81"
    BANNER = "CP/M 3.0 ON THE COMMODORE 128"

    # The keys the scenarios type.
    KEYS = { "a" => :a, "c" => :c, "d" => :d, "e" => :e, "i" => :i, "l" => :l, "o" => :o, "r" => :r, "x" => :x,
             "z" => :z, "\r" => :return }.freeze

    # The tests each exerciser runs, as ZEXDOC and ZEXALL list them.
    TESTS = 67

    module_function

    def run(report, name, dir)
      machine = boot(dir)
      return prompt(report, machine) if name == "cpm-boot"

      exercise(report, machine, name == "cpm-zexdoc" ? "zexdoc" : "zexall")
    end

    # The banner, the A> prompt, and DIR listing the system and ZEXDOC.
    def prompt(report, machine)
      lines = screen(machine)
      report.check("boots-to-prompt", lines.any? { |line| line.start_with?(BANNER) } && prompt?(lines),
                   "showed no #{BANNER} and A> prompt")
      type(machine, "dir\r")
      machine.run_cycles(5_000_000)
      text = screen(machine).join("\n")
      report.check("lists-disk", text.include?("CCP      COM") && text.include?("ZEXDOC"),
                   "DIR listed no CCP.COM and ZEXDOC")
    end

    # Runs the exerciser until it reports its tests complete, keeping every
    # line it shows on the way, and checks that each of them said OK.
    def exercise(report, machine, program)
      type(machine, "#{program}\r")
      seen = {}
      log = []
      until complete?(log) || machine.cycles > 120_000_000_000
        machine.run_cycles(2_000_000)
        screen(machine).each do |line|
          next if seen[line]

          seen[line] = true
          log << line
        end
      end
      passed = log.count { |line| line.end_with?("OK") }
      errors = log.select { |line| line.include?("ERROR") }
      report.check("completes", complete?(log), "#{program} never reported its tests complete")
      report.check("all-ok", passed == TESTS && errors.empty?,
                   "#{passed} of #{TESTS} tests OK, #{errors.length} errors, the first: #{errors.first}")
    end

    def complete?(log) = log.any? { |line| line.upcase.include?("TESTS COMPLETE") }

    # A C128 in C128 mode with the image attached, run until CP/M shows its
    # A> prompt.
    def boot(dir)
      path = File.join(dir, "cpm3.d81")
      File.binwrite(path, File.binread(IMAGE))
      machine = Badline::C128.new(mode: :c128)
      machine.vic.render = false
      Badline::Media.attach(machine, path)
      machine.run_cycles(1_000_000) until prompt?(screen(machine)) || machine.cycles > 60_000_000
      machine
    end

    def prompt?(lines) = lines.any? { |line| line.start_with?("A>") }

    # Presses each key for 60,000 cycles, with as long between them.
    def type(machine, text)
      text.each_char do |char|
        key = KEYS.fetch(char)
        machine.keyboard.press(key)
        machine.run_cycles(60_000)
        machine.keyboard.release(key)
        machine.run_cycles(60_000)
      end
    end

    # The VIC-IIe's text screen, a line per row, trailing spaces dropped.
    def screen(machine)
      ram = machine.address_bus.ram
      base = ((3 - (machine.cia2.port_a_lines & 0x03)) * 0x4000) + (machine.mmu.vic_bank << 16) +
             ((machine.vic.peek(0xd018) >> 4) * 0x400)
      Array.new(25) { |row| screen_line(ram, base + (row * 40)) }
    end

    def screen_line(ram, address)
      line = +""
      40.times do |column|
        code = ram.peek(address + column) & 0x7f
        line << (code < 32 ? code + 64 : code).chr
      end
      line.rstrip
    end
  end
end
