# frozen_string_literal: true

require "fileutils"
require "net/http"

# reyco2000/6809_6309_code_tester's self-checking 6809 programs, run on a
# bare 6809 with the test device they expect at $FF00-$FF0F. The
# programs are GPL-3.0, so they are fetched, at COMMIT, and never
# committed.
module M6809CodeTester
  REPO = "reyco2000/6809_6309_code_tester"
  COMMIT = "f445da35665991ec00a7bfc3ab4ce36f4482687e"
  DIR = "vendor/m6809-code-tester"
  PROGRAMS = %w[6809_functional_test 6809_interrupt_test 6809_cycle_test].freeze

  # 64K of RAM, and the test device: the interrupt lines at $FF00 (bit 0
  # IRQ, bit 1 FIRQ, bit 2 NMI, 1 asserted), levels at $FF01 that load
  # into $FF00 once the count written to $FF02 and $FF03 has run out, a
  # cycle counter latched by writes to $FF04 and $FF05 and read back as
  # their difference at $FF06 and $FF07, a console at $FF08 and the exit
  # code at $FF0F.
  class Bus
    attr_reader :ram, :console, :exit_code, :lines
    attr_writer :cpu

    def initialize
      @ram = Array.new(0x10000, 0)
      @console = +""
      @exit_code = nil
      @lines = 0
      @delayed = 0
      @countdown = nil
      @start = @end = 0
    end

    def load_s19(text)
      start = nil
      text.each_line do |line|
        bytes = [line[2..].strip].pack("H*").bytes
        case line[0, 2]
        when "S1" then bytes[3...-1].each_with_index { |byte, i| @ram[((bytes[1] << 8) | bytes[2]) + i] = byte }
        when "S9" then start = (bytes[1] << 8) | bytes[2]
        end
      end
      start
    end

    def read(address)
      return @ram[address] unless (address & 0xfff0) == 0xff00

      case address & 0x0f
      when 0x0 then @lines
      when 0x6 then ((@end - @start) >> 8) & 0xff
      when 0x7 then (@end - @start) & 0xff
      else @ram[address]
      end
    end

    def write(address, value)
      @ram[address] = value
      return unless (address & 0xfff0) == 0xff00

      device_write(address & 0x0f, value)
    end

    # Counts down a delayed line change. Called once a cycle, before the
    # CPU's.
    def tick
      return unless @countdown

      @countdown -= 1
      return unless @countdown <= 0

      @lines = @delayed
      @countdown = nil
    end

    private

    def device_write(register, value)
      case register
      when 0x0 then @lines = value & 0x07
      when 0x1 then @delayed = value & 0x07
      when 0x3 then @countdown = (@ram[0xff02] << 8) | value
      when 0x4 then @start = @cpu.cycles
      when 0x5 then @end = @cpu.cycles
      when 0x8 then @console << value.chr
      when 0xf then @exit_code = value
      end
    end
  end

  module_function

  def fetch(dir = DIR)
    FileUtils.mkdir_p(dir)
    Net::HTTP.start("raw.githubusercontent.com", 443, use_ssl: true) do |http|
      PROGRAMS.product(%w[s19 lst]).each do |name, extension|
        path = "/#{REPO}/#{COMMIT}/bin/#{name}.#{extension}"
        response = http.get(path)
        raise "#{path}: HTTP #{response.code}" unless response.code == "200"

        File.binwrite(File.join(dir, "#{name}.#{extension}"), response.body)
      end
    end
  end

  # Runs a program until it writes its exit code, or for +limit+ cycles.
  # Returns the exit code (nil if it never wrote one), the console's text,
  # the PC it stopped at and the cycles it took.
  def run(cpu_class, name, dir: DIR, limit: 20_000_000)
    bus = Bus.new
    start = bus.load_s19(File.read(File.join(dir, "#{name}.s19")))
    cpu = cpu_class.new(bus)
    bus.cpu = cpu
    cpu.pc = start
    cpu.resume(0)
    until bus.exit_code || cpu.cycles >= limit
      bus.tick
      cpu.irq = bus.lines[0] == 1
      cpu.firq = bus.lines[1] == 1
      cpu.nmi = bus.lines[2] == 1
      cpu.cycle!
    end
    [bus.exit_code, bus.console, cpu.pc, cpu.cycles]
  end
end
