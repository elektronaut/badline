# frozen_string_literal: true

module Badline
  module Snapshot
    # How a PET was built: its model's name, one of PET::Model::ALL, its
    # RAM below $8000 in K and its editor's frame rate, the arguments
    # PET.new takes, the ROMs it runs by file: BASIC, the editor, the
    # KERNAL and the characters, the 8296 board's jumpers, by name and
    # comma-separated, and the SuperPET's CPU and RAM switches, as
    # PET::SuperPET::Board names their positions, empty on the others.
    PETSetup = Data.define(:model, :ram_kb, :refresh_hz, :basic, :editor, :kernal, :characters, :jumpers,
                           :cpu_switch, :ram_switch)

    class PETSetup
      MODELS = PET::Model::ALL.map(&:name).freeze

      REFRESH_RATES = [50, 60].freeze

      # The setup of `machine`.
      def self.of(machine)
        model = machine.model
        refresh_hz = machine.refresh_hz
        new(model: model.name, ram_kb: machine.ram.length >> 10, refresh_hz:, basic: model.basic,
            editor: model.editor(refresh_hz), kernal: model.kernal, characters: model.characters,
            jumpers: machine.jumpers.join(","), cpu_switch: machine.superpet? ? machine.board.cpu_switch : "",
            ram_switch: machine.superpet? ? machine.board.ram_switch : "")
      end

      # The model by name, the RAM, the frame rate, the ROMs, the jumpers
      # where a board has any and the switches where it has them, in a
      # keyed snapshot module.
      def write_fields(out)
        out.text("model", model).int("ram_kb", ram_kb).int("refresh_hz", refresh_hz)
        out.text("rom.basic", basic).text("rom.editor", editor).text("rom.kernal", kernal)
        out.text("rom.characters", characters)
        out.text("jumpers", jumpers) unless jumpers.empty?
        out.text("cpu_switch", cpu_switch).text("ram_switch", ram_switch) unless cpu_switch.empty?
      end

      # A ROM the snapshot doesn't name is the model's own, a board without
      # jumpers named has none fitted, and a SuperPET without its switches
      # named has them at 6502 and R/W.
      def self.read_fields(input)
        profile = PET::Model.named(input.choice("model", MODELS, PET::Model::DEFAULT))
        ram_kb = input.int("ram_kb", profile.ram_kb)
        unless PET::Model.ram_fits?(profile, ram_kb)
          raise FormatError, "the snapshot is of a PET with #{ram_kb}K of RAM, which badline doesn't build"
        end

        refresh_hz = input.int("refresh_hz", profile.crtc? ? 50 : 60)
        unless REFRESH_RATES.include?(refresh_hz)
          raise FormatError, "the snapshot is of a PET at #{refresh_hz} Hz, which badline doesn't build"
        end

        refresh_hz = 60 unless profile.crtc?
        superpet = profile.superpet?
        new(model: profile.name, ram_kb:, refresh_hz:, basic: input.text("rom.basic", profile.basic),
            editor: input.text("rom.editor", profile.editor(refresh_hz)),
            kernal: input.text("rom.kernal", profile.kernal),
            characters: input.text("rom.characters", profile.characters), jumpers: input.text("jumpers", ""),
            cpu_switch: superpet ? input.choice("cpu_switch", PET::SuperPET::Board::CPU_SWITCH, "6502") : "",
            ram_switch: superpet ? input.choice("ram_switch", PET::SuperPET::Board::RAM_SWITCH, "rw") : "")
      end

      # A machine built this way, at power-on, with the BASIC, editor and
      # character ROMs PET::ROMSets names for its ROMs.
      def build
        version = PET::ROMSets::BASICS.find { |_, roms| roms.first == basic }&.first
        editor_name = PET::ROMSets::EDITORS.key(editor)
        unless cpu_switch.empty?
          return PET::SuperPET.new(refresh_hz:, basic: version, editor: editor_name, cpu: cpu_switch,
                                   bank_ram: ram_switch)
        end

        PET.new(model:, ram_kb:, refresh_hz:, basic: version, editor: editor_name, characters: fitted_characters,
                jumpers: jumpers.split(","))
      rescue ArgumentError => e
        raise FormatError, "the snapshot is of a #{self}, which badline doesn't build: #{e.message}"
      end

      # The ROMs are named where they aren't the model's own, and the
      # jumpers where any are fitted.
      def to_s
        text = "#{model} with #{ram_kb}K at #{refresh_hz} Hz"
        text = "#{text} jumpered #{jumpers}" unless jumpers.empty?
        text = "#{text} with its CPU switch at #{cpu_switch} and RAM switch at #{ram_switch}" unless cpu_switch.empty?
        roms = [basic, editor, kernal, characters]
        profile = PET::Model.named(model)
        stock = [profile.basic, profile.editor(refresh_hz), profile.kernal, profile.characters]
        roms == stock ? text : "#{text} running #{roms.join(', ')}"
      end

      private

      # The name of a character ROM other than the model's own, nil for its
      # own.
      def fitted_characters
        return nil if characters == PET::Model.named(model).characters

        PET::ROMSets::CHARACTERS.key(characters) || characters
      end
    end
  end
end
