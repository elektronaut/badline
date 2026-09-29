# frozen_string_literal: true

module Badline
  module Snapshot
    # A file that isn't a snapshot badline reads, is cut short, or holds a
    # state that doesn't line up with the machine reading it.
    class FormatError < StandardError; end

    # A machine's state, held in memory: the Integers each chip writes in
    # turn, and the byte strings for memories, names and paths. Booleans
    # are written as 0 and 1. Computer#snapshot takes one and
    # Computer#restore puts it back.
    class State
      attr_reader :values, :strings

      def initialize(values, strings)
        @values = values
        @strings = strings
      end

      def ==(other)
        other.is_a?(State) && values == other.values && strings == other.strings
      end
    end

    # Writes a State. Each chip's save_state writes its fields through one
    # of these, and its load_state reads them back from a StateReader in
    # the same order.
    class StateWriter
      attr_reader :state

      def initialize
        @values = []
        @strings = []
        @state = State.new(@values, @strings)
      end

      def int(value)
        raise TypeError, "not an Integer: #{value.inspect}" unless value.is_a?(Integer)

        @values << value.to_i
        self
      end

      def boolean(value)
        @values << (value ? 1 : 0)
        self
      end

      def optional_int(value)
        return boolean(false) if value.nil?

        boolean(true).int(value)
      end

      def ints(values)
        int(values.length)
        values.each { |value| int(value) }
        self
      end

      def booleans(values)
        int(values.length)
        values.each { |value| boolean(value) }
        self
      end

      # Bytes, 0 to 255 each, kept as one string.
      def blob(values)
        @strings << values.pack("C*")
        self
      end

      def string(value)
        @strings << value.to_s.b
        self
      end

      def optional_string(value)
        return boolean(false) if value.nil?

        boolean(true).string(value)
      end

      # A name a reader checks for, so a state that has gone out of step
      # fails there instead of loading the wrong fields.
      def marker(name) = string(name)
    end

    # Reads a State back in the order a StateWriter wrote it.
    class StateReader
      def initialize(state)
        @values = state.values
        @strings = state.strings
        @value = 0
        @string = 0
      end

      def int
        raise FormatError, "the state ends early, at value #{@value}" if @value >= @values.length

        value = @values[@value]
        @value += 1
        value
      end

      def boolean?
        value = int
        raise FormatError, "expected a boolean in the state, found #{value}" unless value.between?(0, 1)

        value == 1
      end

      def optional_int = boolean? ? int : nil

      def ints = Array.new(int) { int }

      def booleans = Array.new(int) { boolean? }

      # Reads into an existing array, in place, so whatever else holds it
      # sees the values.
      def ints_into(array) = array.replace(ints)

      def booleans_into(array) = array.replace(booleans)

      def blob = string.bytes

      def blob_into(array) = array.replace(blob)

      def string
        raise FormatError, "the state ends early, at string #{@string}" if @string >= @strings.length

        value = @strings[@string]
        @string += 1
        value
      end

      def optional_string = boolean? ? string : nil

      def marker(name)
        found = string
        raise FormatError, "expected #{name} in the state, found #{found[0, 20].inspect}" unless found == name
      end

      # Whether every value and string has been read.
      def finished? = @value == @values.length && @string == @strings.length
    end
  end
end
