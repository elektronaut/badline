# frozen_string_literal: true

module Badline
  module Drives
    class Model9060
      # Sleeping through the two processors' idle loops, exactly, as
      # Model8050::Idle does.
      #
      # With nothing to do, the IP goes round DOS 3.0's idle loop from
      # IP_LOOP, and the SASI host round its job loop from SASI_LOOP, each
      # pass finding the job queue empty, until ATN interrupts the IP. The
      # host has no interrupt of its own. A pass puts back what it found, so
      # each processor comes back to its loop's start as it left it.
      #
      # Each time a processor comes to its loop's start, the unit compares
      # what that processor sees with what it saw last time round: the CPU,
      # its chips but for their counters, its RAM and the common RAM. The
      # same, with no read of a counter or an interrupt flag between, makes
      # the pass repeatable. Once both are, with the hard disk's controller
      # idle and no interrupt pulled, the unit sleeps until a counter is due
      # to pull IRQ, the IEEE-488 controller moves a line, or something
      # outside reads or changes the unit (settle!).
      module Idle
        IP_LOOP = 0xc131
        SASI_LOOP = 0xf8f1

        # Whether the unit may sleep through its idle loops.
        attr_reader :idle_skip

        def idle_skip=(on)
          settle!
          @idle_skip = on
        end

        def asleep? = @asleep

        # Brings the unit up to the present, cycle for cycle, and drops the
        # passes it found, since whoever called may change it.
        def settle!
          wake! if @asleep
          forget_passes
        end

        private

        def init_idle
          @idle_skip = true
          @asleep = false
          @owed = 0
          @budget = 0
          forget_passes
        end

        def forget_passes
          @ip_mark = nil
          @sasi_mark = nil
          @ip_pass = nil
          @sasi_pass = nil
        end

        def owe_cycle
          @owed += 1
          wake! if @owed >= @budget
        end

        def watch_loops
          ip = @ip_cpu
          @ip_pass = nil if ip.irq
          @sasi_pass = nil if @sasi_cpu.irq
          ip_pass_found if ip.program_counter == IP_LOOP && ip.boundary?
          host = @sasi_cpu
          sasi_pass_found if host.program_counter == SASI_LOOP && host.boundary?
        end

        def ip_pass_found
          state = ip_state
          @ip_pass = repeated(@ip_mark, state, @ip_cpu, @ip_bus.volatile)
          @ip_mark = [state, @ip_cpu.cycles, @ip_cpu.instructions]
          @ip_bus.volatile = false
          fall_asleep if @ip_pass && @sasi_pass
        end

        def sasi_pass_found
          state = sasi_state
          @sasi_pass = repeated(@sasi_mark, state, @sasi_cpu, @sasi_bus.volatile)
          @sasi_mark = [state, @sasi_cpu.cycles, @sasi_cpu.instructions]
          @sasi_bus.volatile = false
          fall_asleep if @ip_pass && @sasi_pass
        end

        def repeated(mark, state, cpu, volatile)
          return nil if mark.nil? || volatile || mark[0] != state

          [cpu.cycles - mark[1], cpu.instructions - mark[2]]
        end

        def fall_asleep
          target = @target
          return unless target.quiet? && !target.busy? && !@ip_cpu.irq && !@sasi_cpu.irq

          budget = quiet_cycles
          return if budget < 2

          @asleep = true
          @owed = 0
          @budget = budget
        end

        def quiet_cycles
          [@data_riot.quiet_cycles, @control_riot.quiet_cycles, @via.quiet_cycles].min
        end

        def wake!
          owed = @owed
          @asleep = false
          @owed = 0
          return if owed.zero?

          @data_riot.fast_forward(owed)
          @control_riot.fast_forward(owed)
          @via.fast_forward(owed)
          @target.fast_forward(owed)
          skip(@ip_cpu, @ip_pass, @ip_mark, owed)
          skip(@sasi_cpu, @sasi_pass, @sasi_mark, owed)
          @cycles += owed
        end

        def skip(cpu, pass, mark, owed)
          passes = owed / pass[0]
          cpu.fast_forward(passes * pass[0], passes * pass[1])
          mark[1] += passes * pass[0]
          mark[2] += passes * pass[1]
          (owed - (passes * pass[0])).times { cpu.cycle! }
        end

        def ip_state
          [*@ip_cpu.idle_state, *@data_riot.idle_state, *@control_riot.idle_state, @ip_bus.data, common_changes]
        end

        def sasi_state
          [*@sasi_cpu.idle_state, *@via.idle_state, *@lines.state, *@sasi_bus.ram.read(0, 0x80), @sasi_bus.data,
           common_changes]
        end

        def common_changes = @ip_bus.common_changes + @sasi_bus.common_changes
      end
    end
  end
end
