# frozen_string_literal: true

module Badline
  module Snapshot
    # How a C128 was built: its model's name, its SID's model and the
    # mode it resets into, the arguments C128.new takes.
    C128Setup = Data.define(:model, :sid_model, :mode)

    class C128Setup
      MARKER = "C128"
      SID_MODELS = %i[mos6581 mos8580].freeze
      MODES = %i[c64 c128].freeze

      # The setup a C128's State starts with.
      def self.from(state)
        input = StateReader.new(state)
        input.marker(MARKER)
        input.check_stamp
        read(input)
      end

      def self.read(input)
        model = input.string
        known = C128::Model::ALL.any? { |candidate| candidate.name == model }
        raise FormatError, "the state names a C128 model badline doesn't know" unless known

        sid_model = SID_MODELS.fetch(input.int)
        new(model:, sid_model:, mode: MODES.fetch(input.int))
      rescue IndexError
        raise FormatError, "the state names a SID or a mode badline doesn't know"
      end

      def write(out)
        out.string(model).int(SID_MODELS.index(sid_model)).int(MODES.index(mode))
      end

      # A machine built this way, at power-on.
      def build = C128.new(model:, sid_model:, mode:)

      def to_s = [model, sid_model, mode].join(" with a ")
    end
  end
end
