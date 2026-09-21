# frozen_string_literal: true

module Badline
  # SID (Sound Interface Device) chip.
  #
  # $D400-$D418 - Voices, filter and volume   - write only
  # $D419-$D41A - POTX/POTY paddle inputs     - read only
  # $D41B-$D41C - Voice 3 oscillator/envelope - read only
  # $D41D-$D41F - Unconnected, reads as $FF
  #
  # The register file mirrors every 32 bytes up to $D7FF.
  #
  # Reading a write-only register returns the last byte the SID saw on the
  # data bus. Paddles and the 1351 mouse attach as a pots source
  # responding to #pot_x and #pot_y; with none attached the lines read $FF.
  class SID
    include Addressable

    attr_accessor :pots, :osc3, :env3

    def initialize(pots: nil)
      addressable_at(0xd400, length: 2**10)
      @registers = Memory.new(length: 2**5)
      @pots = pots
      @osc3 = 0x00
      @env3 = 0x00
      @bus_value = 0x00
    end

    def peek(addr)
      case index(addr) % (2**5)
      when 0x19 then latch(pots ? pots.pot_x : 0xff)
      when 0x1a then latch(pots ? pots.pot_y : 0xff)
      when 0x1b then latch(osc3)
      when 0x1c then latch(env3)
      when 0x1d..0x1f then 0xff
      else @bus_value
      end
    end

    def poke(addr, value)
      reg = index(addr) % (2**5)
      @registers.poke(reg, value) if reg <= 0x18
      @bus_value = value
    end

    # Register contents as written, for a synthesis layer to read back.
    def register(reg) = @registers.peek(reg)

    private

    def latch(value)
      @bus_value = value
    end
  end
end
