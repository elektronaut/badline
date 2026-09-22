# frozen_string_literal: true

module Badline
  module Audio
    # Runs a PSID tune on a bare rig: a CPU and RAM with the SID clocked
    # alongside it. The VIC and the CIAs still decode their registers, so a
    # tune writing to them lands somewhere sane, but neither is ever cycled,
    # which is what makes this path about three times faster than the whole
    # machine.
    #
    # Calls go through a six-byte stub whose JSR operand the dispatch trap
    # rewrites:
    #
    #   stub: jsr target
    #   idle: jmp idle
    #
    # The CPU spins in the idle loop between calls, so a dispatch always
    # lands on an instruction boundary and a play routine that overruns its
    # frame is never re-entered.
    class BarePlayer
      include IntegerHelper

      # 312 raster lines of 63 cycles.
      FRAME_CYCLES = 19_656

      # A tune's init routine is free to unpack itself, but not forever.
      INIT_LIMIT = 10_000_000

      def initialize(tune, song: nil)
        @tune = tune
        @song = (song || tune.start_song).clamp(1, tune.songs) - 1
        @bus = AddressBus.new
        @cpu = CPU.new(@bus)
        @sid = @bus.sid
        @idle = false
      end

      def start
        @bus.ram.write(@tune.load_address, @tune.data)
        @bus.ram.write(stub_address, stub)
        @sid.synthesize!
        @cpu.status.interrupt = true
        @cpu.program_counter = idle_address
        install_dispatch
        call(@tune.init_address, @song)
        settle
      end

      # Advances one PAL frame, or `budget` cycles if that is shorter,
      # yielding the SID's output every cycle. Returns the cycles advanced.
      def frame(budget)
        call(@tune.play_address)
        cycles = [budget, FRAME_CYCLES].min
        cycles.times { yield step }
        cycles
      end

      private

      def stub_address = @stub_address ||= @tune.driver_address

      def idle_address = stub_address + 3

      def stub
        [0x20, 0x00, 0x00, 0x4c,
         low_byte(idle_address), high_byte(idle_address)]
      end

      def call(address, argument = 0)
        @pending = address
        @argument = argument
      end

      # A tune that never returns from init gets cut off and plays with
      # whatever it managed to set up.
      def settle
        limit = @cpu.cycles + INIT_LIMIT
        step until @idle || @cpu.cycles > limit
      end

      def step
        @sid.cycle!
        @cpu.cycle!
        @sid.sample
      end

      def install_dispatch
        @cpu.install_trap(idle_address) do
          @idle = true
          dispatch if @pending
        end
      end

      def dispatch
        @bus.poke(0x01, bank_for(@pending))
        @bus.ram.write(stub_address + 1,
                       [low_byte(@pending), high_byte(@pending)])
        @cpu.a = @argument
        @cpu.stack_pointer = 0xff
        @cpu.program_counter = stub_address
        @pending = nil
        @idle = false
      end

      # Tunes live under the ROMs as often as not, so $01 has to bank out
      # whatever covers the routine about to run. libsidplayfp's map: RAM
      # under BASIC from $a000, RAM under both ROMs and no I/O for a routine
      # in the I/O window itself, RAM under the KERNAL from $e000.
      def bank_for(address)
        return 0x37 if address < 0xa000
        return 0x36 if address < 0xd000
        return 0x34 if address < 0xe000

        0x35
      end
    end
  end
end
