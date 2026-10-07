# frozen_string_literal: true

module Badline
  module Media
    # A program loading into a VIC-20 once it has booted (Vic20Media).
    module Vic20Basic
      # Where BASIC starts with each RAM expansion it can start in, as
      # TXTTAB holds it.
      BASIC_STARTS = { 0x1001 => :unexpanded, 0x0401 => :"3k", 0x1201 => :"8k" }.freeze

      class << self
        # A BASIC program, one that loads at a start of BASIC or a byte
        # ahead of it, goes to this machine's start of BASIC. Anything else
        # goes where it says, and doesn't RUN.
        def load_program(machine, data, autostart:)
          load_addr = data[0] | (data[1] << 8)
          basic_start = machine.basic_start
          ahead = [0, 1].find { |offset| BASIC_STARTS.key?(load_addr + offset) || load_addr + offset == basic_start }
          return machine.load_prg(data) unless ahead

          load_basic(machine, data, basic_start - ahead, load_addr)
          machine.type_text("run\r") if autostart
        end

        private

        # Puts a BASIC program at `address`, relinking its lines when that
        # isn't where it was saved from, as BASIC's LOAD does, and sets the
        # end of the program, where BASIC's variables start, and the end
        # address the KERNAL's LOAD leaves.
        def load_basic(machine, data, address, saved_at)
          ram = machine.ram
          ram.write(address, data[2..])
          end_addr = address + data.length - 2
          relink(ram, machine.basic_start, end_addr) unless address == saved_at
          [0x2d, 0xae].each { |pointer| ram.write(pointer, [end_addr & 0xff, end_addr >> 8]) }
        end

        # Points each line's link at the line after it, as BASIC's LINKPRG
        # does: past the zero that ends the line's text. A link with a zero
        # high byte ends the program.
        def relink(ram, line, end_addr)
          while line + 4 < end_addr && ram.peek(line + 1).positive?
            following = line + 4
            following += 1 while following < end_addr && ram.peek(following).positive?
            following += 1
            ram.write(line, [following & 0xff, following >> 8])
            line = following
          end
        end
      end
    end
  end
end
