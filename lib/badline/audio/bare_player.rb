# frozen_string_literal: true

module Badline
  module Audio
    # Runs a PSID tune on a bare rig: a CPU and RAM with the SID clocked
    # alongside it. The VIC and the CIAs still decode their registers, so a
    # tune writing to them lands somewhere sane, but neither is ever cycled,
    # which is what makes this path about three times faster than the whole
    # machine.
    #
    # Nothing on the rig ties it to PAL, so an NTSC tune gets an NTSC
    # machine: 60 Hz frames, the NTSC KERNAL's timer and `$02a6`, and a
    # clock of 1022727 Hz for the SID's output.
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

      # 263 raster lines of 65 cycles.
      NTSC_FRAME_CYCLES = 17_095

      NTSC_CLOCK_HZ = 1_022_727

      # A tune's init routine is free to unpack itself, but not forever.
      INIT_LIMIT = 10_000_000

      # The CIA 1 timer A latch the PAL KERNAL leaves, 60 underflows a
      # second.
      KERNAL_TIMER = 0x4025

      NTSC_KERNAL_TIMER = 0x4295

      # The KERNAL's PAL/NTSC flag, 1 for PAL.
      VIDEO_STANDARD = 0x02a6

      attr_reader :sid, :stereo

      def initialize(tune, subtune: nil, sid_models: tune.sid_models)
        @tune = tune
        @subtune = (subtune || tune.start_subtune).clamp(1, tune.subtunes) - 1
        @bus = AddressBus.new(sid_model: sid_models[0])
        # The CPU port as the KERNAL leaves it, which a PSID tune expects.
        @bus.poke(0x00, 0x2f)
        @bus.poke(0x01, 0x37)
        @bus.poke(VIDEO_STANDARD, tune.ntsc? ? 0 : 1)
        @bus.cia1.timer_a_latch = tune.ntsc? ? NTSC_KERNAL_TIMER : KERNAL_TIMER
        @cpu = CPU.new(@bus)
        @sid = @bus.sid
        @stereo = Stereo.new(@bus, tune, sid_models)
        @extras = @stereo.extras
        @multi = !@extras.empty?
        @idle = false
      end

      def start
        @bus.ram.write(@tune.load_address, @tune.data)
        @bus.ram.write(stub_address, stub)
        @stereo.synthesize!
        @cpu.status.interrupt = true
        @cpu.program_counter = idle_address
        install_dispatch
        call(@tune.init_address, @subtune)
        settle
      end

      # The rig between frames: the bus and its chips, the extra SIDs, the
      # CPU, and the call waiting for the idle loop.
      def save_state(out)
        out.marker("BARE PLAYER")
        @bus.save_state(out)
        @extras.each { |sid| sid.save_state(out) }
        @cpu.save_state(out)
        out.optional_int(@pending).int(@argument).boolean(@idle)
      end

      # Takes a rig that hasn't started to where #save_state found one, in
      # place of #start.
      def load_state(input)
        input.marker("BARE PLAYER")
        @bus.load_state(input)
        @extras.each { |sid| sid.load_state(input) }
        @cpu.load_state(input)
        @pending = input.optional_int
        @argument = input.int
        @idle = input.boolean?
        @stereo.synthesize!
        install_dispatch
      end

      # Advances one call of play, or `budget` cycles if that is shorter,
      # then yields whatever the SIDs recorded over it, in stereo. Returns
      # the cycles advanced.
      def frame(budget, &)
        call(@tune.play_address)
        cycles = [budget, period].min
        if @multi
          cycles.times { step }
        else
          cycles.times do
            @sid.cycle!
            @cpu.cycle!
          end
        end
        @stereo.mix(&)
        cycles
      end

      def clock_hz = @tune.ntsc? ? NTSC_CLOCK_HZ : TimeOfDay::CLOCK_HZ

      private

      # A video frame, or for a CIA-timed subtune one period of CIA 1 timer A,
      # which init and play are both free to reprogram.
      def period
        return (@tune.ntsc? ? NTSC_FRAME_CYCLES : FRAME_CYCLES) unless @tune.cia_timed?(@subtune + 1)

        @bus.cia1.timer_a_latch + 1
      end

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
        @extras.each(&:cycle!) if @multi
        @cpu.cycle!
      end

      def install_dispatch
        @cpu.install_trap(idle_address) do
          @idle = true
          dispatch if @pending
        end
      end

      # Tunes live under the ROMs as often as not, so $01 has to bank out
      # whatever covers the routine about to run. An RSID tune banks itself,
      # and `SIDFile#bank_for` hands back nil for it.
      def dispatch
        bank = @tune.bank_for(@pending)
        @bus.poke(0x01, bank) if bank
        @bus.ram.write(stub_address + 1,
                       [low_byte(@pending), high_byte(@pending)])
        @cpu.a = @argument
        @cpu.stack_pointer = 0xff
        @cpu.program_counter = stub_address
        @pending = nil
        @idle = false
      end
    end
  end
end
