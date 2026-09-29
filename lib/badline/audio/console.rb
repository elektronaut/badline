# frozen_string_literal: true

require "io/console"
require "io/wait"

module Badline
  module Audio
    # The terminal of `badline-ruby --headless`, put in raw mode with
    # io/console.
    class Console < Terminal
      private

      # Ctrl-C still raises Interrupt.
      def raw!
        mode = @input.console_mode
        @input.raw!(intr: true)
        mode
      end

      def restore(mode)
        @input.console_mode = mode
      end

      def readable?(seconds)
        !@input.wait_readable(seconds).nil?
      end
    end
  end
end
