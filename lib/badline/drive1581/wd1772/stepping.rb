# frozen_string_literal: true

module Badline
  class Drive1581
    class WD1772
      # The type I commands, which move the head:
      #
      #   0000hVrr  restore    step out to track 0, the track register to 0
      #   0001hVrr  seek       step until the track register holds the data
      #                        register's track
      #   001uhVrr  step       one step the way the last one went
      #   010uhVrr  step in    one step towards the hub
      #   011uhVrr  step out   one step towards the rim
      #
      # Each step waits out the step rate rr picks (STEP_RATES), and u has
      # a step update the track register, as restore and seek always do.
      # With V the head settles and the command reads IDs until one carries
      # the track register's track, or sets NOT_FOUND after five turns.
      module Stepping
        private

        def start_type1
          @type1 = true
          @status = 0
          @drq = false
          @phase = STEPPED
          @steps = 0
          if @command < 0x10
            @track = 0xff
            @data = 0
          elsif @command >= 0x40
            @inward = @command < 0x60
          end
          step_done unless spinning_up?(STEPPED)
        end

        def spun_up
          @status |= SPUN_UP
          @phase = @after_spin_up
          case @after_spin_up
          when STEPPED then step_done
          when SEARCH then resume_type2
          else resume_track
          end
        end

        # The step rate has passed: the next step, or the end of the moves.
        def step_done
          return next_step if @steps.zero? || @command < 0x20

          moved
        end

        # Restore and seek step until the track register matches, restore
        # also stopping at track 0. The others step once.
        def next_step
          return single_step if @command >= 0x20
          return seek_restore if @command < 0x10 && restored?

          if @track == @data
            moved
          else
            @inward = @data > @track
            @track = (@track + (@inward ? 1 : -1)) & 0xff
            pulse
          end
        end

        def restored?
          return false unless @mechanism.track0? || @steps >= 255

          @status |= NOT_FOUND if !@mechanism.track0? && @command.anybits?(VERIFY)
          true
        end

        def seek_restore
          @track = 0 if @mechanism.track0?
          moved
        end

        def single_step
          @track = (@track + (@inward ? 1 : -1)) & 0xff if @command.anybits?(UPDATE)
          pulse
        end

        def pulse
          @steps += 1
          @mechanism.step(@inward)
          @phase = STEPPED
          @due = @now + STEP_RATES[@command & 0x03]
        end

        # The head is there: with V it settles, and the command ends
        # otherwise.
        def moved
          return finish unless @command.anybits?(VERIFY) && @status.nobits?(NOT_FOUND)

          @phase = SETTLED
          @due = @now + SETTLE
        end

        def verify_track
          @mode = VERIFY_TRACK
          begin_search
        end
      end
    end
  end
end
