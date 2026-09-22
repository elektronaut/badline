# frozen_string_literal: true

module Badline
  module Audio
    # Runs a tune on the whole machine, for the RSID tunes that install their
    # own interrupts and expect a booted C64 underneath. The tune goes in
    # through the same stub `Media` uses and BASIC SYSes it; rendering starts
    # when the CPU reaches that stub.
    class MachinePlayer
      FRAME_CYCLES = BarePlayer::FRAME_CYCLES

      # Boot, plus room for the keyboard buffer to type the SYS.
      START_LIMIT = 15_000_000

      def initialize(tune, song: nil, sid_model: tune.sid_model)
        @tune = tune
        @song = song || tune.start_song
        @computer = Computer.new(sid_model:)
        @injected = false
        @started = false
      end

      def start
        @computer.on_init { inject }
        @computer.cpu.install_trap(@tune.driver_address) { begin_playing }
        @computer.cycle! until @started || @computer.cycles > START_LIMIT
      end

      def sid = @computer.sid

      # Advances one PAL frame, or `budget` cycles if that is shorter, then
      # yields whatever the SID recorded over it. Returns the cycles advanced.
      def frame(budget, &)
        cycles = [budget, FRAME_CYCLES].min
        cycles.times { @computer.cycle! }
        sid.drain_samples.each(&)
        cycles
      end

      private

      def inject
        @computer.ram.write(@tune.load_address, @tune.data)
        @computer.ram.write(@tune.driver_address, @tune.driver(song: @song))
        @computer.type_text("sys#{@tune.driver_address}\r")
        @injected = true
      end

      def begin_playing
        return unless @injected

        @computer.sid.synthesize!
        @started = true
      end
    end
  end
end
