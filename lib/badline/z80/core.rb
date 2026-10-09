# frozen_string_literal: true

require "badline/z80/flags"
require "badline/z80/registers"
require "badline/z80/bus_cycles"
require "badline/z80/arithmetic"
require "badline/z80/shifts"
require "badline/z80/loads"
require "badline/z80/exchanges"
require "badline/z80/jumps"
require "badline/z80/main_page"
require "badline/z80/bit_page"
require "badline/z80/extended_page"
require "badline/z80/block_transfers"
require "badline/z80/block_io"
require "badline/z80/interrupt_acceptance"
require "badline/z80/saved_state"

module Badline
  class Z80
    # The Z80 core, on whatever bus +bus+ is. The bus answers
    # fetch(address) for an opcode fetch (M1), read(address) and
    # write(address, value) for memory, input(port) and output(port, value)
    # for I/O, and acknowledge for the byte a device puts on the data bus
    # when the CPU takes a maskable interrupt.
    #
    # #step! runs one instruction, prefixes and all, or takes an interrupt,
    # or idles one opcode fetch while halted. #cycles counts T-states, and
    # each bus call happens while it holds the T-state its machine cycle
    # starts on.
    module Core
      include Flags
      include Registers
      include BusCycles
      include Arithmetic
      include Shifts
      include Loads
      include Exchanges
      include Jumps
      include MainPage
      include BitPage
      include ExtendedPage
      include BlockTransfers
      include BlockIO
      include InterruptAcceptance
      include SavedState

      attr_reader :bus, :cycles, :nmi
      attr_accessor :int

      def initialize(bus)
        @bus = bus
        @cycles = 0
        @a = @f = 0xff
        @b = @c = @d = @e = @h = @l = 0xff
        @af_alt = @bc_alt = @de_alt = @hl_alt = 0xffff
        @ix = @iy = @sp = 0xffff
        @wz = @q = @last_q = 0
        @prefix = 0
        @int = @nmi = @nmi_pending = false
        reset!
      end

      # The RESET line: the program counter, I, R and the interrupt mode go
      # to 0, and interrupts are disabled.
      def reset!
        @pc = @i = @r = @im = 0
        @iff1 = @iff2 = false
        @halted = @after_ei = @after_ld_a_ir = false
        @nmi_pending = false
      end

      # The NMI line. Asserting it latches an interrupt, taken after the
      # current instruction, and holding it does nothing more.
      def nmi=(asserted)
        @nmi_pending = true if asserted && !@nmi
        @nmi = asserted
      end

      # The WAIT line: a bus that holds it during an access lengthens that
      # machine cycle by +states+ T-states.
      def wait(states)
        @cycles += states
      end

      def step!
        if @nmi_pending
          take_nmi
        elsif @int && @iff1 && !@after_ei
          take_int
        else
          @after_ei = @after_ld_a_ir = false
          @last_q = @q
          @q = 0
          @prefix = 0
          @halted ? idle_fetch : execute(fetch_opcode)
        end
        nil
      end

      def inspect
        "Cycles: #{@cycles}, PC: #{hex(@pc)}, SP: #{hex(@sp)}, AF: #{hex(af)}, BC: #{hex(bc)}, " \
          "DE: #{hex(de)}, HL: #{hex(hl)}, IX: #{hex(@ix)}, IY: #{hex(@iy)}"
      end

      private

      def hex(value)
        value.to_s(16).rjust(4, "0")
      end
    end
  end
end
