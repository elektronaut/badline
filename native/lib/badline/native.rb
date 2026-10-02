# frozen_string_literal: true

# The native badline: the emulator core and the front end both builds
# share, and the native side of each seam where the builds differ: the
# terminal of --headless and the --version line.
require "badline"
require "io/buffer"
require "badline/frontend"

require "badline/native/build_info"
require "badline/native/version"
require "badline/native/console"

module Badline
  module Native
    # The factories Audio::CLI calls for --headless.
    SINK = ->(rate:, exact_rate:) { Frontend::AudioSink.new(rate:, exact_rate:) }

    CONSOLE = ->(input:, output:) { Console.new(input:, output:) }

    # The factory for `sid` without --headless: the SID player's window.
    PLAYER = ->(input:, output:) { Frontend::PlayerWindow.new(input:, output:) }
  end
end
