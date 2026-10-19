# frozen_string_literal: true

module Badline
  module Snapshot
    # How a VIC-20 was built: its RAM expansion, a key of
    # Vic20::Bus::RAM_CONFIGURATIONS, and its model, one of Vic20::MODELS,
    # the arguments Vic20.new takes.
    Vic20Setup = Data.define(:ram, :model)

    class Vic20Setup
      RAM_CONFIGURATIONS = Vic20::Bus::RAM_CONFIGURATIONS.keys.freeze

      # The RAM expansion and the model by name, in a keyed snapshot module.
      # A snapshot without a model is of a PAL machine, the only one badline
      # built before the NTSC one.
      def write_fields(out)
        out.text("ram", ram.to_s).text("model", model)
      end

      def self.read_fields(input)
        text = input.choice("ram", RAM_CONFIGURATIONS.map(&:to_s), "unexpanded")
        new(ram: RAM_CONFIGURATIONS.find { |name| name.to_s == text } || :unexpanded,
            model: input.choice("model", Vic20::MODELS, "pal"))
      end

      # A machine built this way, at power-on.
      def build = Vic20.new(ram:, model:)

      def to_s = model == "pal" ? ram.to_s : "#{ram} #{model}"
    end
  end
end
