# frozen_string_literal: true

module Badline
  module Media
    # A program loading into a C64 or a C128 once it has booted
    # (Media.attach). The VIC-20 has its own (Vic20Basic).
    module Program
      class << self
        # Loads the program where it says, and RUNs one that loads at the
        # start of BASIC.
        def load(computer, data, autostart:)
          load_addr = computer.load_prg(data)
          # Run only makes sense for programs at BASIC start, or a byte ahead
          # of it, where BASIC keeps the zero before its first line. BASIC 7.0
          # starts at $1C01 and keeps the end of its text at $1210.
          start, text_end = computer.family == :c128 && computer.mode == :c128 ? [0x1c01, 0x1210] : [BASIC_START, 0x2d]
          return unless autostart && (load_addr == start || load_addr == start - 1)

          # The end of the program, where BASIC's variables start, and where
          # the KERNAL's LOAD leaves its end address.
          end_addr = load_addr + data.length - 2
          [text_end, 0xae].each { |pointer| computer.ram.write(pointer, [end_addr & 0xff, end_addr >> 8]) }
          computer.type_text("run\r")
        end
      end
    end
  end
end
