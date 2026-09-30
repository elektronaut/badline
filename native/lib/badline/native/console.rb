# frozen_string_literal: true

module Badline
  module Native
    # The terminal of `badline --headless`, the native side of the console
    # seam: badline-ruby's is Audio::Console. stty puts the terminal in raw
    # mode, keeping Ctrl-C's signal as badline-ruby's `raw!(intr: true)`
    # does, and restores it afterwards, and poll(2) waits for keys.
    class Console < Audio::Terminal
      private

      def raw!
        mode = `stty -g`.strip
        system("stty raw -echo isig")
        mode
      end

      def restore(mode)
        system("stty #{mode}") unless mode.empty?
      end

      def readable?(seconds)
        LibC.pollfd_fd(LibC.pollfd, @input.fileno)
        LibC.pollfd_events(LibC.pollfd, LibC::POLLIN)
        LibC.poll(LibC.pollfd, 1, (seconds * 1000).round).positive?
      end
    end
  end
end
