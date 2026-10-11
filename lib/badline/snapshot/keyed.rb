# frozen_string_literal: true

require "zlib"
require "badline/snapshot/container"

module Badline
  module Snapshot
    # A snapshot module as keyed, typed records, which a later badline
    # reads by name: one it doesn't know is skipped, and one that isn't
    # there leaves the value a freshly built machine has.
    #
    # The payload is deflated. Inside, each record is the key's length and
    # the key (ASCII, lower snake case with dots between sub-units), a
    # one-byte type tag, then the value's length and the value. Lengths are
    # BER-compressed (Ruby's pack "w"), and so are integers, each folded to
    # a natural number (0, -1, 1, -2 ... as 0, 1, 2, 3 ...). The value's
    # length lets a reader skip a tag it doesn't know.
    #
    # A module's header version is MAJOR.MINOR. The major number is this
    # record encoding, and a reader refuses another one. Fields carry no
    # version: a changed meaning gets a new key.
    module Keyed
      MAJOR = 1
      MINOR = 0

      INT = 0x01
      BOOL = 0x02
      BYTES = 0x03
      INTS = 0x04
      TEXT = 0x05

      KEY = /\A[a-z0-9_]+(\.[a-z0-9_]+)*\z/

      # The values an int record holds: what a 64-bit integer holds once
      # zigzag doubles it, which a native build's integers can't exceed.
      VALUES = (-(1 << 62))..((1 << 62) - 1)

      module_function

      def ber(number) = [number].pack("w")

      # Folds an Integer in VALUES to a natural number, as a
      # native build's 64-bit integers hold it.
      def zigzag(value) = value.negative? ? ((-value - 1) << 1) | 1 : value << 1

      def unzigzag(folded) = folded.odd? ? -(folded >> 1) - 1 : folded >> 1

      # The module `name`, with the records the block writes to the Writer
      # it yields.
      def section(name)
        out = Writer.new
        yield out
        out.section(name)
      end
    end
  end
end

require "badline/snapshot/keyed/cursor"
require "badline/snapshot/keyed/writer"
require "badline/snapshot/keyed/report"
require "badline/snapshot/keyed/reader"
require "badline/snapshot/keyed/recorder"
require "badline/snapshot/keyed/modules"
