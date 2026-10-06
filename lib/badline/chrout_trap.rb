# frozen_string_literal: true

module Badline
  # Observe-only PC trap on the KERNAL CHROUT routine ($FFD2). Records each
  # character written while the layout finds the KERNAL mapped in, then lets execution fall
  # through to the ROM, so the screen output is unaffected. Used for headless
  # capture of program output.
  class ChroutTrap
    ADDRESS = 0xffd2

    attr_reader :output

    def initialize(cpu:, bus:, layout:)
      @cpu = cpu
      @bus = bus
      @layout = layout
      @output = +""
    end

    def call
      @output << ascii(@cpu.a) if @layout.kernal_mapped?(@bus)
    end

    def inspect
      "#<#{self.class.name} output=#{@output.inspect}>"
    end

    private

    def ascii(byte)
      case byte
      when 0x0d then "\n"
      when 0x41..0x5a then (byte + 0x20).chr
      when 0xc1..0xda then (byte - 0x80).chr
      when 0x20..0x7e then byte.chr
      else ""
      end
    end
  end
end
