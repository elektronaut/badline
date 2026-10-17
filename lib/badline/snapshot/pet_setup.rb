# frozen_string_literal: true

module Badline
  module Snapshot
    # How a PET was built: its model's name, one of PET::Model::ALL, its
    # RAM below $8000 in K and its editor's frame rate, the arguments
    # PET.new takes, and the ROMs it runs by file: BASIC, the editor, the
    # KERNAL and the characters.
    PETSetup = Data.define(:model, :ram_kb, :refresh_hz, :basic, :editor, :kernal, :characters)

    class PETSetup
      MODELS = PET::Model::ALL.map(&:name).freeze

      REFRESH_RATES = [50, 60].freeze

      # The setup of `machine`.
      def self.of(machine)
        model = machine.model
        refresh_hz = machine.refresh_hz
        new(model: model.name, ram_kb: machine.ram.length >> 10, refresh_hz:, basic: model.basic,
            editor: model.editor(refresh_hz), kernal: model.kernal, characters: model.characters)
      end

      # The model by name, the RAM, the frame rate and the ROMs, in a keyed
      # snapshot module.
      def write_fields(out)
        out.text("model", model).int("ram_kb", ram_kb).int("refresh_hz", refresh_hz)
        out.text("rom.basic", basic).text("rom.editor", editor).text("rom.kernal", kernal)
        out.text("rom.characters", characters)
      end

      # A ROM the snapshot doesn't name is the model's own.
      def self.read_fields(input)
        profile = PET::Model.named(input.choice("model", MODELS, PET::Model::DEFAULT))
        ram_kb = input.int("ram_kb", profile.ram_kb)
        unless PET::Model::RAM_SIZES.include?(ram_kb)
          raise FormatError, "the snapshot is of a PET with #{ram_kb}K of RAM, which badline doesn't build"
        end

        refresh_hz = input.int("refresh_hz", profile.crtc? ? 50 : 60)
        unless REFRESH_RATES.include?(refresh_hz)
          raise FormatError, "the snapshot is of a PET at #{refresh_hz} Hz, which badline doesn't build"
        end

        refresh_hz = 60 unless profile.crtc?
        new(model: profile.name, ram_kb:, refresh_hz:, basic: input.text("rom.basic", profile.basic),
            editor: input.text("rom.editor", profile.editor(refresh_hz)),
            kernal: input.text("rom.kernal", profile.kernal),
            characters: input.text("rom.characters", profile.characters))
      end

      # A machine built this way, at power-on.
      def build = PET.new(model:, ram_kb:, refresh_hz:)

      # The ROMs are named where they aren't the model's own.
      def to_s
        text = "#{model} with #{ram_kb}K at #{refresh_hz} Hz"
        roms = [basic, editor, kernal, characters]
        profile = PET::Model.named(model)
        stock = [profile.basic, profile.editor(refresh_hz), profile.kernal, profile.characters]
        roms == stock ? text : "#{text} running #{roms.join(', ')}"
      end
    end
  end
end
