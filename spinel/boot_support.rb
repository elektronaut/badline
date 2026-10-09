# frozen_string_literal: true

# What spinel/boot.rb, spinel/c128_boot.rb and spinel/vic20_boot.rb share:
# running the machine in stretches between the checkpoints they print,
# and the trailer of the text screen, the counts, the registers and the
# speed. Builds with Spinel as well as running on CRuby.
module BootSupport
  # Runs the machine to +cycles+ in stretches, stopping at every multiple
  # of +interval+, at +timed_from+ and, with +frame+ above zero, at every
  # multiple of it, and yields the cycle count at each stop. Returns the
  # seconds the run took from timed_from on.
  def self.run(machine, cycles, timed_from, interval, frame = 0)
    started = 0.0
    i = 0
    while i < cycles
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC) if i == timed_from
      stop = ((i / interval) + 1) * interval
      if frame.positive?
        frame_end = ((i / frame) + 1) * frame
        stop = frame_end if frame_end < stop
      end
      stop = timed_from if i < timed_from && timed_from < stop
      stop = cycles if cycles < stop
      machine.run_cycles(stop - i)
      i = stop
      yield i
    end
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end

  # Prints the text screen at +base+ in RAM, +rows+ lines of +columns+
  # characters, with trailing spaces trimmed.
  def self.print_screen(ram, base, rows, columns)
    row = 0
    while row < rows
      line = +""
      col = 0
      while col < columns
        line << screen_char(ram.peek(base + (row * columns) + col))
        col += 1
      end
      puts line.rstrip
      row += 1
    end
  end

  def self.screen_char(code)
    code &= 0x7f
    if code.zero?
      "@"
    elsif code < 27
      (code + 96).chr
    elsif code < 64
      code.chr
    else
      "."
    end
  end

  # Prints the cycle and instruction counts and the registers.
  def self.print_state(machine)
    cpu = machine.cpu
    puts "cycles #{machine.cycles} instructions #{cpu.instructions}"
    puts "pc #{cpu.program_counter} a #{cpu.a} x #{cpu.x} y #{cpu.y} p #{cpu.p}"
  end

  # Prints the speed: +timed+ cycles in +elapsed+ seconds, against the
  # machine's clock.
  def self.print_speed(timed, elapsed, clock_hz)
    puts "timed #{timed} cycles in #{(elapsed * 1000).round} ms, #{(timed / elapsed / clock_hz).round(3)}x real time"
  end
end
