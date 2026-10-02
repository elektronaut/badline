# frozen_string_literal: true

module Badline
  module Audio
    # Runs a tune on the whole machine, for the RSID tunes that install their
    # own interrupts and expect a booted C64 underneath. The tune goes in
    # the way `Media` puts it in: BASIC SYSes the driver stub, or RUNs a
    # BASIC tune. Rendering starts when the CPU gets there. The machine is
    # PAL whatever the tune asks for, and the frames and the clock follow
    # its region.
    class MachinePlayer
      FRAME_CYCLES = BarePlayer::FRAME_CYCLES

      # Boot, plus room for the keyboard buffer to type the SYS.
      START_LIMIT = 15_000_000

      def initialize(tune, subtune: nil, sid_models: tune.sid_models)
        @tune = tune
        @subtune = subtune || tune.start_subtune
        @computer = Computer.new(sid_model: sid_models[0])
        @stereo = Stereo.new(@computer.address_bus, tune, sid_models)
        @extras = @stereo.extras
        @multi = !@extras.empty?
        region = @computer.region
        @frame_cycles = region.cycles_per_line * region.lines_per_frame
        @injected = false
        @started = false
      end

      def start
        @computer.on_init { inject }
        @computer.cpu.install_trap(@tune.entry_address) { begin_playing }
        step until @started || @computer.cycles > START_LIMIT
      end

      attr_reader :stereo

      def sid = @computer.sid

      def clock_hz = @computer.region.clock_hz

      # Advances one frame of the machine, or `budget` cycles if that is
      # shorter, then yields whatever the SIDs recorded over it, in stereo.
      # Returns the cycles advanced.
      def frame(budget, &)
        cycles = [budget, @frame_cycles].min
        if @multi
          cycles.times { step }
        else
          cycles.times { @computer.cycle! }
        end
        @stereo.mix(&)
        cycles
      end

      private

      # The extra SIDs clock ahead of the CPU, as the machine's own does.
      def step
        @extras.each(&:cycle!) if @multi
        @computer.cycle!
      end

      def inject
        @computer.ram.write(@tune.load_address, @tune.data)
        @tune.boot_memory(subtune: @subtune).each { |address, bytes| @computer.ram.write(address, bytes) }
        @computer.type_text(@tune.boot_command)
        @injected = true
      end

      def begin_playing
        return if @started || !@injected

        @stereo.synthesize!
        @started = true
      end
    end
  end
end
