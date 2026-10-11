# frozen_string_literal: true

module Badline
  module Media
    # A program loading into a C64, a C128 or a 264 series machine once it
    # has booted (Media.attach). The VIC-20 has its own (Vic20Basic).
    module Program
      # Where BASIC 3.5 starts on the 264 series.
      PLUS4_BASIC_START = 0x1001

      class << self
        # Loads the program where it says, and RUNs one that loads at the
        # start of BASIC.
        def load(computer, data, autostart:)
          load_addr = computer.load_prg(data)
          start, text_end, load_end = basic(computer)
          # Run only makes sense for programs at BASIC start, or a byte ahead
          # of it, where BASIC keeps the zero before its first line.
          return unless autostart && (load_addr == start || load_addr == start - 1)

          # The end of the program, where BASIC's variables start, and where
          # the KERNAL's LOAD leaves its end address.
          end_addr = load_addr + data.length - 2
          [text_end, load_end].each { |pointer| computer.ram.write(pointer, [end_addr & 0xff, end_addr >> 8]) }
          computer.type_text("run\r")
        end

        private

        # Where BASIC starts, the pointer to the end of its text and the
        # KERNAL's end address (EAL). BASIC 7.0 starts at $1C01 and keeps
        # the end of its text at $1210, and the 264 KERNAL keeps EAL at $9D.
        def basic(computer)
          return [PLUS4_BASIC_START, 0x2d, KernalTrap::PLUS4_ZERO_PAGE.end_address] if computer.family == :plus4
          return [0x1c01, 0x1210, 0xae] if computer.family == :c128 && computer.mode == :c128

          [BASIC_START, 0x2d, 0xae]
        end
      end
    end
  end
end
