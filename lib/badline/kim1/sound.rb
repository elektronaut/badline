# frozen_string_literal: true

module Badline
  class KIM1
    # The KIM-1's sound: U2's PB7, the tape output, which programs such as
    # the First Book of KIM's music player toggle, or with the speaker
    # wired, U3's PA0, where the User Manual's chapter 5 puts a speaker.
    # Machine::LineSound turns it into samples.
    class Sound
      include Machine::LineSound

      # Whether the speaker on U3's PA0 is wired, and plays in place of PB7.
      attr_accessor :speaker

      def initialize(monitor, user)
        @monitor = monitor
        @user = user
        @speaker = false
        init_line_sound
      end

      def model = :pb7

      private

      def line_high? = @speaker ? @user.port_a_output.anybits?(0x01) : @monitor.port_b_output.anybits?(0x80)
    end
  end
end
