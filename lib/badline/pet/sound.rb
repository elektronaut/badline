# frozen_string_literal: true

module Badline
  class PET
    # The PET's sound: the level the VIA drives on CB2, which the 4000 and
    # 8000 series take to their internal speaker and every model to the
    # user port's pin M, where the 2001 and 3000 series had their speaker
    # added. CB2 carries the shift register's bits in its shift-out modes,
    # mode 4's free-running square wave under timer 2 for the bell and most
    # PET music, and the PCR's CB2 output otherwise, held high or low by
    # hand or floating high as an input. Machine::LineSound turns it into
    # samples.
    class Sound
      include Machine::LineSound

      def initialize(via)
        @via = via
        init_line_sound
      end

      def model = :cb2

      private

      def line_high? = @via.cb2_output
    end
  end
end
