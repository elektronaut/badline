# frozen_string_literal: true

module Badline
  class Drive1581
    class WD1772
      # The disk turning under the head: the index pulses a phase waits
      # for or counts, and the cycle the head comes to a place round the
      # track.
      module Turn
        # The disk began or stopped turning: a phase waiting on the turn
        # starts its wait again.
        def spin_changed
          case @phase
          when SPIN_UP, MOTOR_IDLE, INDEX_INTERRUPT then count_index
          when SEARCH then begin_search
          when TRACK_INDEX, WRITE_TRACK_START then wait_index(@phase)
          end
        end

        private

        # The motor starts: with h clear and the motor off, the command waits
        # out six index pulses first, and the phase comes after them.
        def spinning_up?(phase)
          spin_up = !@motor_on && @command.nobits?(NO_SPIN_UP)
          @motor_on = true
          return false unless spin_up

          @after_spin_up = phase
          @phase = SPIN_UP
          @count = 6
          count_index
          true
        end

        # Waits for @count index pulses, or for the disk to turn.
        def count_index
          @due = next_index
        end

        def index_counted
          @count -= 1
          return @due += Mechanism::REVOLUTION if @count.positive?

          case @phase
          when SPIN_UP then spun_up
          when MOTOR_IDLE
            @motor_on = false
            idle
          else
            @intrq = true
            idle
          end
        end

        # The cycle the next index pulse starts, or NEVER while no disk turns.
        def next_index = at_angle(0)

        # The cycle the head next comes to +angle+, from the index.
        def at_angle(angle)
          return NEVER unless @mechanism.spinning?

          delta = (angle - @mechanism.angle(@now)) % Mechanism::REVOLUTION
          @now + (delta.zero? ? Mechanism::REVOLUTION : delta)
        end

        # The cycle the byte at +position+ round the track has passed under
        # the head.
        def byte_end(position) = at_angle(((position + 1) % Track::LENGTH) * BYTE)
      end
    end
  end
end
