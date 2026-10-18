# frozen_string_literal: true

module Badline
  module Drives
    class Model8050
      # Sleeping through the two processors' idle loops, exactly.
      #
      # With nothing to do, the IP goes round DOS 2.7's idle loop from
      # IP_LOOP, and the FDC round its job loop from FDC_LOOP, each pass
      # finding the job queue empty, until ATN interrupts the IP or the
      # 6530's timer the FDC, every 5 ms. A pass puts back what it found,
      # so each processor comes back to its loop's start as it left it, and
      # only the chips' counters and the cycle counts move.
      #
      # Each time a processor comes to its loop's start, the unit compares
      # what that processor sees with what it saw last time round: the CPU
      # (Engine::IdleCPU#idle_state), its chips but for their counters, its
      # RAM and the common RAM, and on the FDC's side the drives. The same,
      # with no read of a counter or an interrupt flag between (the buses'
      # volatile), makes the pass repeatable. Once both processors have a
      # repeatable pass, with the motors off, no head stepping, no disk
      # going in or out and no interrupt pulled, the unit sleeps:
      # host_cycle! only counts the cycles it owes, until one of the chips'
      # counters is due to pull IRQ (quiet_cycles), the controller moves a
      # line of the bus, or something outside reads or changes the unit
      # (settle!).
      #
      # Waking runs the counters on in bulk, counts off each processor's
      # whole passes, and runs the rest of a pass on that processor alone.
      # Its passes touch nothing the other one or the counters move, so the
      # order the two run in doesn't matter. Then the unit runs cycle by
      # cycle again. Woken by a counter, it keeps the passes it found, and
      # sleeps again as soon as both repeat: the IP's, which the timer's
      # interrupt doesn't reach, at once, and the FDC's a pass after its
      # interrupt. Woken from outside, it finds both afresh.
      module Idle
        IP_LOOP = 0xc5a1
        FDC_LOOP = 0xfc17

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
          @fdc_mark = nil
          @ip_pass = nil
          @fdc_pass = nil
        end

        # A cycle owed while asleep, which wakes the unit once the budget
        # is spent.
        def owe_cycle
          @owed += 1
          wake! if @owed >= @budget
        end

        # Looks for the loops' starts after a cycle run awake. An interrupt
        # pulled breaks the processor's pass.
        def watch_loops
          ip = @ip_cpu
          @ip_pass = nil if ip.irq
          @fdc_pass = nil if @fdc_cpu.irq
          ip_pass_found if ip.program_counter == IP_LOOP && ip.boundary?
          fdc = @fdc_cpu
          fdc_pass_found if fdc.program_counter == FDC_LOOP && fdc.boundary?
        end

        def ip_pass_found
          state = ip_state
          @ip_pass = repeated(@ip_mark, state, @ip_cpu, @ip_bus.volatile)
          @ip_mark = [state, @ip_cpu.cycles, @ip_cpu.instructions]
          @ip_bus.volatile = false
          fall_asleep if @ip_pass && @fdc_pass
        end

        def fdc_pass_found
          state = fdc_state
          @fdc_pass = repeated(@fdc_mark, state, @fdc_cpu, @fdc_bus.volatile)
          @fdc_mark = [state, @fdc_cpu.cycles, @fdc_cpu.instructions]
          @fdc_bus.volatile = false
          fall_asleep if @ip_pass && @fdc_pass
        end

        # The pass since +mark+ as [cycles, instructions] if it left the
        # processor as it found it, or nil.
        def repeated(mark, state, cpu, volatile)
          return nil if mark.nil? || volatile || mark[0] != state

          [cpu.cycles - mark[1], cpu.instructions - mark[2]]
        end

        def fall_asleep
          return unless @mechanism.quiet? && !@ip_cpu.irq && !@fdc_cpu.irq

          budget = quiet_cycles
          return if budget < 2

          @asleep = true
          @owed = 0
          @budget = budget
        end

        # How many cycles the chips can run with no counter pulling IRQ.
        def quiet_cycles
          [@data_riot.quiet_cycles, @control_riot.quiet_cycles, @rriot.quiet_cycles, @via.quiet_cycles].min
        end

        # Runs the cycles owed: the counters in bulk, then each processor's
        # whole passes and the rest of a pass.
        def wake!
          owed = @owed
          @asleep = false
          @owed = 0
          return if owed.zero?

          @data_riot.fast_forward(owed)
          @control_riot.fast_forward(owed)
          @rriot.fast_forward(owed)
          @via.fast_forward(owed)
          skip(@ip_cpu, @ip_pass, @ip_mark, owed)
          skip(@fdc_cpu, @fdc_pass, @fdc_mark, owed)
          @cycles += owed
        end

        # Counts off the processor's whole passes, moving its mark on with
        # them, and runs the rest on the processor alone.
        def skip(cpu, pass, mark, owed)
          passes = owed / pass[0]
          cpu.fast_forward(passes * pass[0], passes * pass[1])
          mark[1] += passes * pass[0]
          mark[2] += passes * pass[1]
          (owed - (passes * pass[0])).times { cpu.cycle! }
        end

        # What the IP sees: its CPU, its RIOTs but for their counters, its
        # bus's last byte and the common RAM.
        def ip_state
          [*@ip_cpu.idle_state, *@data_riot.idle_state, *@control_riot.idle_state, @ip_bus.data,
           *@common.snapshot]
        end

        # What the FDC sees: its CPU, the VIA and the 6530 but for their
        # counters, its bus's last byte, the drives and the common RAM.
        def fdc_state
          [*@fdc_cpu.idle_state, *@via.idle_state, *@rriot.idle_state, @fdc_bus.data, *@mechanism.idle_state,
           *@common.snapshot]
        end
      end
    end
  end
end
