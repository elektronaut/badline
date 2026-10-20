# frozen_string_literal: true

require "badline/core"
require "badline/kim1"

# The KIM-1's scenarios, the kim1-scenarios suite: its monitor on the
# keypad and display entering bytes (User Manual, figure 5.5), stepping a
# program with SST (figure 5.6) and stopping it with ST (section 4.1), on a
# teletype at 9600 and 110 baud (section 2.6), loading a papertape through
# the monitor's L command (appendix F), loading and starting a program
# straight into RAM, and U3's timer interrupting through PB7 wired to IRQ.
# Each takes under two million cycles. They run only when a filter names
# them, as bin/drive_scenarios kim1 does.
module DriveScenarios
  module KIM1Runs
    CHECKS = {
      "kim1-tty-110" => %w[prompt],
      "kim1-papertape" => %w[loads prompts-after],
      "kim1-tty" => %w[prompt opens-address],
      "kim1-sst" => %w[steps],
      "kim1-keypad" => %w[shows-address-and-byte stores-bytes],
      "kim1-stop" => %w[saves-registers shows-pc],
      "kim1-autostart" => %w[runs],
      "kim1-timer" => %w[interrupts]
    }.freeze

    # The sample program of figure 5.4, at $0200.
    SAMPLE = [0xa9, 0x01, 0x8d, 0x01, 0x17, 0xee, 0x00, 0x17, 0xad, 0x00,
              0x17, 0x49, 0xff, 0x4a, 0xaa, 0xca, 0x10, 0xfd, 0x30, 0xf1].freeze

    # LDA #$12, LDX #$34, LDY #$56, then a JMP to itself at $0206.
    LOOP = [0xa9, 0x12, 0xa2, 0x34, 0xa0, 0x56, 0x4c, 0x06, 0x02].freeze

    # INC $10, then a JMP back to it.
    COUNTER = [0xe6, 0x10, 0x4c, 0x00, 0x02].freeze

    # LDA #$40, STA $170D: U3's timer at ÷8 with its interrupt on, then CLI
    # and a loop, and at $0210 the handler, which counts at $11 and starts
    # the timer again: an interrupt every (64 + 1) x 8 cycles and the 16 or
    # 18 the CPU takes to answer one and get back.
    TIMER = [0xa9, 0x40, 0x8d, 0x0d, 0x17, 0x58, 0xe6, 0x10, 0x4c, 0x06, 0x02].freeze
    HANDLER = [0xe6, 0x11, 0xa9, 0x40, 0x8d, 0x0d, 0x17, 0x40].freeze

    # The keys and what the display shows after each, figure 5.6's first
    # steps.
    SST_STEPS = [%w[AD-0200 0200-A9], %w[GO 0202-8D], %w[GO 0205-EE], %w[GO 0208-AD], %w[GO 020B-49]].freeze

    # The bytes that go in through L: two records, at $0300 and $0318.
    LOADED = Array.new(30) { |index| (index * 7) & 0xff }.freeze

    module_function

    def run(report, name, dir)
      case name
      when "kim1-keypad" then keypad(report)
      when "kim1-sst" then sst(report)
      when "kim1-stop" then stop(report)
      when "kim1-tty" then tty(report)
      when "kim1-tty-110" then slow_tty(report)
      when "kim1-papertape" then papertape(report)
      when "kim1-autostart" then autostart(report, dir)
      else timer(report)
      end
    end

    # A KIM-1 past its reset, with the monitor scanning the display.
    def booted(tty: false, baud: 9600)
      machine = Badline::KIM1.new(tty:, baud:)
      machine.run_cycles(Badline::KIM1::BOOT_CYCLES)
      machine
    end

    # Presses the keys and runs on until the monitor has taken them.
    def keys(machine, text)
      machine.type_keys(text)
      machine.run_cycles(1_000) while machine.typing?
      machine.display_text
    end

    def deposit(machine, address, bytes)
      bytes.each_with_index { |byte, offset| machine.poke(address + offset, byte) }
    end

    def bytes_at(machine, address, count) = Array.new(count) { |offset| machine.peek(address + offset) }

    def keypad(report)
      machine = booted
      shown = keys(machine, "AD 0200 DA A9 + 01")
      report.check("shows-address-and-byte", shown == "0201 01", "showed #{shown}")
      stored = bytes_at(machine, 0x0200, 2)
      report.check("stores-bytes", stored == [0xa9, 0x01], "stored #{stored}")
    end

    def sst(report)
      machine = booted
      deposit(machine, 0x0200, SAMPLE)
      deposit(machine, 0x17fa, [0x00, 0x1c])
      machine.sst = true
      shown = SST_STEPS.map { |step| keys(machine, step[0].tr("-", " ")) }
      wanted = SST_STEPS.map { |step| step[1].tr("-", " ") }
      report.check("steps", shown == wanted, "showed #{shown.join(', ')}")
    end

    def stop(report)
      machine = booted
      deposit(machine, 0x0200, LOOP)
      deposit(machine, 0x17fa, [0x00, 0x1c])
      keys(machine, "AD 0200 GO")
      machine.press_stop
      machine.run_cycles(20_000)
      saved = bytes_at(machine, 0xef, 7)
      report.check("saves-registers", saved == [0x06, 0x02, 0x20, 0xff, 0x12, 0x56, 0x34], "saved #{saved}")
      report.check("shows-pc", machine.display_text == "0206 4C", "showed #{machine.display_text}")
    end

    # The teletype's output, without the NULs the monitor pads lines with,
    # once it ends with `ending` or `limit` cycles have run.
    def printed(machine, ending, limit)
      teletype = machine.teletype
      machine.run_cycles(10_000) until teletype.output.delete("\x00").end_with?(ending) || machine.cycles > limit
      teletype.output.delete("\x00")
    end

    def tty(report)
      machine = booted(tty: true)
      machine.type_text("0200 ")
      output = printed(machine, "0200 00 ", 400_000)
      report.check("prompt", output.start_with?("\x7f\r\nKIM\r\n0000 00 "), "printed #{output.inspect}")
      report.check("opens-address", output.end_with?("0200 \r\n0200 00 "), "printed #{output.inspect}")
    end

    def slow_tty(report)
      machine = booted(tty: true, baud: 110)
      output = printed(machine, "KIM\r\n", 2_000_000)
      report.check("prompt", output == "\x7f\r\nKIM\r\n", "printed #{output.inspect}")
    end

    # A papertape of LOADED: a full record and a short one, then the last,
    # up to its end, as Storage::Papertape#text gives it. The monitor prints
    # XOFF once it has read the last.
    def tape_text
      first = record(0x0300, LOADED.take(24))
      "#{first}\n#{record(0x0318, LOADED.drop(24))}\n#{record(2, [])}"
    end

    def record(address, bytes)
      fields = [bytes.length, address >> 8, address & 0xff] + bytes
      sum = fields.sum
      ";#{(fields + [sum >> 8, sum & 0xff]).map { |byte| byte.to_s(16).upcase.rjust(2, '0') }.join}"
    end

    def papertape(report)
      machine = booted(tty: true)
      machine.type_text("L#{tape_text}")
      output = printed(machine, "0002\x13 KIM\r\n", 2_000_000)
      loaded = bytes_at(machine, 0x0300, LOADED.length)
      report.check("loads", loaded == LOADED, "loaded #{loaded}")
      report.check("prompts-after", output.end_with?(";0000020002\x13 KIM\r\n"), "printed #{output.inspect}")
    end

    # The counter as a .bin, which Media.attach loads at $0200 and the
    # monitor starts there with AD and GO.
    def autostart(report, dir)
      path = File.join(dir, "counter.bin")
      File.binwrite(path, COUNTER.pack("C*"))
      machine = Badline::KIM1.new
      Badline::Media.attach(machine, path, kim1: Badline::Media::KIM1Media::Loading.new(load_address: 0x0200))
      machine.run_cycles(200_000)
      counting = machine.peek(0x10).positive? && machine.cpu.program_counter.between?(0x0200, 0x0204)
      report.check("runs", counting, "counted #{machine.peek(0x10)} at #{machine.cpu.program_counter}")
    end

    def timer(report)
      machine = booted
      machine.irq_wired = true
      deposit(machine, 0x0200, TIMER)
      deposit(machine, 0x0210, HANDLER)
      deposit(machine, 0x17fe, [0x10, 0x02])
      keys(machine, "AD 0200 GO")
      intervals = handler_intervals(machine, 65)
      steady = intervals.all? { |interval| [536, 538].include?(interval) } && intervals.sum == 64 * 537
      report.check("interrupts", steady, "took #{intervals.uniq.sort} cycles apart")
    end

    # The cycles between `count` entries into the handler at $0210.
    def handler_intervals(machine, count)
      entries = []
      while entries.length < count && machine.cycles < 1_000_000
        machine.cycle!
        entries << machine.cycles if machine.cpu.boundary? && machine.cpu.program_counter == 0x0210
      end
      Array.new(entries.length - 1) { |index| entries[index + 1] - entries[index] }
    end
  end
end
