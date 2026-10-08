# frozen_string_literal: true

module Badline
  class C128
    # The C128's two 1K colour RAM banks, and the colour RAM and character
    # ROM it pushes into the VIC's bank. In C128 mode the 8502's port picks
    # them: P0 the colour RAM bank the CPU sees, P1 the one the VIC sees,
    # and P2 low shows the VIC the character ROM's C128 set. In C64 mode
    # both see colour RAM bank 1, and the VIC the C64 set.
    class ColorLines
      def initialize(vic, cia2, c64_characters, c128_characters)
        @vic_bank = vic.vic_bank
        @cia2 = cia2
        @c64_characters = c64_characters
        @c128_characters = c128_characters
        @bank0 = ColorMemory.new(vic)
        @bank1 = ColorMemory.new(vic)
      end

      # Colour RAM bank +number+, 0 or 1.
      def color_ram(number) = number.zero? ? @bank0 : @bank1

      # The colour RAM bank the CPU sees.
      def cpu_color_ram(c64_mode, port) = c64_mode ? @bank1 : color_ram(port & 0x01)

      # Pushes the colour RAM and the character ROM the VIC sees into its
      # bank.
      def push(c64_mode, port)
        if c64_mode
          @vic_bank.connect(cia2: @cia2, color_ram: @bank1)
          @vic_bank.map_character_rom(@c64_characters)
        else
          @vic_bank.connect(cia2: @cia2, color_ram: color_ram((port >> 1) & 0x01))
          @vic_bank.map_character_rom(@c128_characters, shadow: port.nobits?(0x04))
        end
      end
    end
  end
end
