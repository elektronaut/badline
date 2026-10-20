# frozen_string_literal: true

module Badline
  module Drives
    class Model8050
      # Sleeping through the two processors' idle loops, exactly.
      #
      # With nothing to do, the IP goes round its DOS's idle loop from
      # @ip_loop, and the FDC round its job loop from @fdc_loop (IP_LOOP and
      # FDC_LOOP on the 8050), each pass finding the job queue empty, until
      # ATN interrupts the IP or the 6530's timer the FDC, every 5 ms on the
      # 8050. A pass puts back what it found,
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
      # host_cycle! only counts host cycles, until the one in which a chip's
      # counter is due to pull IRQ (quiet_cycles), until the controller
      # moves a line of the bus (host_written!), or until something outside
      # reads or changes the unit (settle!).
      #
      # Waking runs the counters on in bulk, counts off each processor's
      # whole passes, and runs the rest of a pass on that processor alone.
      # Its passes touch nothing the other one or the counters move, so the
      # order the two run in doesn't matter. Then the unit runs cycle by
      # cycle again. Woken by a counter, it keeps the passes it found, and
      # sleeps again as soon as both repeat: the IP's, which the timer's
      # interrupt doesn't reach, at once, and the FDC's once it is back at
      # its loop's start where its last pass proved to repeat but for the
      # bytes the interrupt changed (fdc_pass_found). Woken from outside, it
      # finds both afresh.
      #
      # Woken by a counter on the FDC's side, as the 6530's timer wakes the
      # controller every 5 ms, the unit wakes only the FDC's side, as the
      # board does: the FDC with its VIA, its 6530 and the drives run cycle
      # by cycle (fdc_step) through the interrupt, and the IP owes its
      # cycles. The two sides meet only in the common RAM, and the IP's
      # pass reads none of the FDC's chips, so while no write changes the
      # common RAM, the IP's pass runs on as it did. The IP catches up on its
      # passes as the unit falls asleep again, as soon as a write changes
      # the common RAM, before a counter on its side is due to pull its IRQ,
      # and when something outside reads or changes the unit.
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

        # Whether the unit, or the IP's side of it, owes cycles.
        def dozing? = @asleep || @fdc_alone

        # Brings the unit up to the present, cycle for cycle, and drops the
        # passes it found, since whoever called may change it.
        def settle!
          if @asleep
            wake!
            @asleep = false
          end
          join_ip if @fdc_alone
          forget_passes
        end

        # The controller pushed its lines into the bus. A line it moved
        # wakes a unit that owes cycles, which saw the lines as they stood.
        def host_written!
          settle! if dozing? && @ieee_port.lines_moved?
        end

        private

        # The unit's loops start at +ip_loop+ and +fdc_loop+.
        def init_idle(ip_loop, fdc_loop)
          @ip_loop = ip_loop
          @fdc_loop = fdc_loop
          @idle_skip = true
          @asleep = false
          @owed = 0
          @budget = 0
          @fdc_alone = false
          @ip_owed = 0
          @ip_budget = 0
          @alone_changes = 0
          @planned = false
          @slept = 0
          @wake_at = 0
          forget_passes
        end

        def forget_passes
          @ip_mark = nil
          @fdc_mark = nil
          @ip_pass = nil
          @fdc_pass = nil
          @fdc_proof = nil
        end

        # A cycle owed while asleep, which wakes the unit once the budget
        # is spent: the FDC's side alone if the IP's counters leave it
        # room.
        def owe_cycle
          @owed += 1
          return if @owed < @budget

          wake!
          wake_fdc unless @asleep
        end

        # The FDC's side runs on alone while the IP owes its cycles.
        def wake_fdc
          budget = [@data_riot.quiet_cycles, @control_riot.quiet_cycles].min
          return if budget < 2 || @ip_pass.nil? || @fdc_alone

          @fdc_alone = true
          @ip_owed = 0
          @ip_budget = budget
          @alone_changes = common_changes
        end

        # A cycle of the FDC's side alone, the IP owing it. A write that
        # changed the common RAM, or the IP's counters coming due, has the
        # IP catch up and the unit run whole again.
        def fdc_alone_cycle
          fdc_step
          @ip_owed += 1
          return join_ip if common_changes != @alone_changes || @ip_owed >= @ip_budget

          fdc = @fdc_cpu
          @fdc_pass = nil if fdc.irq
          fdc_pass_found if fdc.program_counter == @fdc_loop && fdc.boundary?
        end

        # Runs the IP's side over the cycles it owes, its counters in bulk
        # and its passes, and the unit whole from then on.
        def join_ip
          owed = @ip_owed
          @fdc_alone = false
          @ip_owed = 0
          @data_riot.fast_forward(owed)
          @control_riot.fast_forward(owed)
          skip(@ip_cpu, @ip_pass, @ip_mark, owed)
        end

        # Looks for the loops' starts after a cycle run awake. An interrupt
        # pulled breaks the processor's pass.
        def watch_loops
          ip = @ip_cpu
          @ip_pass = nil if ip.irq
          @fdc_pass = nil if @fdc_cpu.irq
          ip_pass_found if ip.program_counter == @ip_loop && ip.boundary?
          fdc = @fdc_cpu
          fdc_pass_found if fdc.program_counter == @fdc_loop && fdc.boundary?
        end

        def ip_pass_found
          state = ip_state
          @ip_pass = repeated(@ip_mark, state, @ip_cpu, @ip_bus.volatile)
          @ip_mark = [state, @ip_cpu.cycles, @ip_cpu.instructions]
          @ip_bus.volatile = false
          fall_asleep if @ip_pass && @fdc_pass
        end

        # The FDC is at its loop's start. A pass that repeated is kept as a
        # proof with the bytes of the 6530's RAM it touched: from a state
        # that differs from the proof's only in other bytes, as the timer's
        # interrupt leaves it, the pass runs the same way and repeats too.
        def fdc_pass_found
          registers = fdc_state
          ram = @rriot.ram.dup
          state = [registers, ram]
          bus = @fdc_bus
          touched = bus.ram_touched
          pass = repeated(@fdc_mark, state, @fdc_cpu, bus.volatile)
          if pass
            @fdc_proof = [registers, ram, touched, pass]
          elsif proven?(registers, ram)
            pass = @fdc_proof[3]
          end
          @fdc_pass = pass
          @fdc_mark = [state, @fdc_cpu.cycles, @fdc_cpu.instructions]
          bus.volatile = false
          bus.ram_touched = 0
          fall_asleep if @ip_pass && pass
        end

        # Whether the FDC stands where the proof's pass started, but for
        # bytes of the 6530's RAM the pass didn't touch.
        def proven?(registers, ram)
          proof = @fdc_proof
          return false if proof.nil? || proof[0] != registers

          start = proof[1]
          touched = proof[2]
          index = 0
          while index < 64
            return false if touched.anybits?(1 << (index >> 1)) && start[index] != ram[index]

            index += 1
          end
          true
        end

        # The pass since +mark+ as [cycles, instructions] if it left the
        # processor as it found it, or nil.
        def repeated(mark, state, cpu, volatile)
          return nil if mark.nil? || volatile || mark[0] != state

          [cpu.cycles - mark[1], cpu.instructions - mark[2]]
        end

        def fall_asleep
          join_ip if @fdc_alone
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
          owe_slept
          owed = @owed
          @asleep = false
          @owed = 0
          quiet = [owed, @budget].min
          skip_passes(quiet) if quiet.positive?
          (owed - quiet).times { @asleep ? owe_cycle : run_cycle }
        end

        def skip_passes(cycles)
          @data_riot.fast_forward(cycles)
          @control_riot.fast_forward(cycles)
          @rriot.fast_forward(cycles)
          @via.fast_forward(cycles)
          skip(@ip_cpu, @ip_pass, @ip_mark, cycles)
          skip(@fdc_cpu, @fdc_pass, @fdc_mark, cycles)
          @cycles += cycles
        end

        # Asleep, a host cycle only counts towards the one planned to wake
        # the unit (plan_sleep). Returns whether it did.
        def slept_through?
          return false unless @planned

          @slept += 1
          doze if @slept == @wake_at
          true
        end

        # Plans the host cycle that brings the cycles owed up to the budget,
        # once the unit has fallen asleep and the host cycle it fell asleep
        # in is over.
        def plan_sleep
          return if @planned

          @planned = true
          @slept = 0
          needed = ((@budget - @owed) * @host_clock_hz) - @phase
          @wake_at = needed.positive? ? (needed + CLOCK_HZ - 1) / CLOCK_HZ : 1
        end

        # The budget is spent: the unit wakes, its FDC's side alone if it
        # can.
        def doze
          wake!
          wake_fdc unless @asleep
        end

        # Turns the host cycles slept into cycles owed, through the phase
        # accumulator.
        def owe_slept
          return unless @planned

          @planned = false
          phase = @phase + (@slept * CLOCK_HZ)
          @owed += phase / @host_clock_hz
          @phase = phase % @host_clock_hz
          @slept = 0
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
        # bus's last byte and the common RAM, as the count of the writes
        # that changed it.
        def ip_state
          [*@ip_cpu.idle_state, *@data_riot.idle_state, *@control_riot.idle_state, @ip_bus.data, common_changes]
        end

        # What the FDC sees but the 6530's RAM: its CPU, the VIA and the
        # 6530's ports and timer but for their counters, its bus's last
        # byte, the drives and the common RAM.
        def fdc_state
          [*@fdc_cpu.idle_state, *@via.idle_state, *@rriot.port_state, @fdc_bus.data, *@mechanism.idle_state,
           common_changes]
        end

        def common_changes = @ip_bus.common_changes + @fdc_bus.common_changes
      end
    end
  end
end
