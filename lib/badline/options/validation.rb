# frozen_string_literal: true

module Badline
  class Options
    # The checks Options#parse makes: that each value reads as its option
    # takes it, and once every argument has been read, that the options
    # fit the mode, the numbers are positive and the files exist.
    module Validation
      private

      def sid_card_for(value)
        raise Error, "invalid argument: --sid-card #{value}" unless SID_MODELS.key?(value)

        SID_MODELS[value]
      end

      def sid_card_address_for(value)
        raise Error, "invalid argument: --sid-card-address #{value}" unless SID_CARD_ADDRESSES.key?(value.downcase)

        SID_CARD_ADDRESSES[value.downcase]
      end

      def sid_model_for(value)
        return if value == "auto"
        raise Error, "invalid argument: --sid #{value}" unless SID_MODELS.key?(value)

        SID_MODELS[value]
      end

      def ram_configuration(value)
        raise Error, "invalid argument: --ram #{value}" unless RAM_CONFIGURATIONS.key?(value)

        RAM_CONFIGURATIONS[value]
      end

      def plus4_ram(value)
        raise Error, "invalid argument: --ram #{value}" unless PLUS4_RAM.key?(value)

        PLUS4_RAM[value]
      end

      def pet_ram(value)
        raise Error, "invalid argument: --ram #{value}" unless PET_RAM.key?(value)

        PET_RAM[value]
      end

      def plus4_ram_expansion(value)
        raise Error, "invalid argument: --ram-expansion #{value}" unless PLUS4_RAM_EXPANSIONS.key?(value)

        PLUS4_RAM_EXPANSIONS[value]
      end

      def drive_type_for(value)
        unless (PLUS4_DRIVE_TYPES + Drives::IEEEModels::NAMES).include?(value)
          raise Error, "invalid argument: --drive-type #{value}"
        end

        value
      end

      def kernal_for(value)
        raise Error, "invalid argument: --kernal #{value}" unless (CBM2_KERNALS + P500_KERNALS).include?(value)

        value
      end

      def baud_for(value)
        raise Error, "invalid argument: --baud #{value}" unless KIM1_BAUDS.include?(value)

        value.to_i
      end

      def reu_size(value)
        raise Error, "invalid argument: --reu #{value}" unless REU_SIZES.include?(value)

        value.to_i
      end

      def number(flag, value)
        raise Error, "invalid argument: #{flag} #{value}" unless value.match?(/\A\d+\z/)

        value.to_i
      end

      def decimal(flag, value)
        raise Error, "invalid argument: #{flag} #{value}" unless value.match?(DECIMAL)

        value.to_f
      end

      def validate
        validate_family
        validate_drive_type

        validate_mode
        validate_models
        validate_numbers
        validate_paths
      end

      def validate_drive_type
        return if @drive_type.nil?

        types = @family == :plus4 ? PLUS4_DRIVE_TYPES : Drives::IEEEModels::NAMES
        return if %i[plus4 pet cbm2].include?(@family) && types.include?(@drive_type)

        raise Error, "--drive-type needs #{PLUS4_DRIVE_TYPES.include?(@drive_type) ? 'plus4' : 'pet or cbm2'}"
      end

      def validate_mode
        if headless?
          raise Error, "#{@window_only.first} needs the window" unless @window_only.empty?
          raise Error, "#{@any_window_only.first} needs the window" unless player_window? || @any_window_only.empty?
          return if @family == :kim1
          raise Error, "no tune given" if tune_paths.empty? && !player_window?

          tune_paths.each { |path| validate_tune(path) }
        elsif !@headless_only.empty?
          raise Error, "#{@headless_only.first} needs --headless or --audio-out"
        end
      end

      def validate_family
        ram_option
        @family == :kim1 ? validate_kim1 : refuse_kim1_options
        validate_vic20 if @family == :vic20
        @family == :plus4 ? validate_plus4 : refuse_plus4_options
        @family == :pet ? validate_pet : refuse_pet_options
        @family == :cbm2 ? validate_cbm2 : refuse_cbm2_options
        if @family == :c128
          validate_c128
        elsif @c64_mode
          raise Error, "--c64 needs c128"
        end
      end

      # --ram names the VIC-20's RAM expansion, or the Plus/4's or the PET's
      # RAM.
      def ram_option
        return if @ram_name.nil?

        case @family
        when :vic20 then @ram = ram_configuration(@ram_name)
        when :plus4 then @ram_kb = plus4_ram(@ram_name)
        when :pet then @ram_kb = pet_ram(@ram_name)
        when :kim1 then @ram = kim1_ram(@ram_name)
        else raise Error, "--ram needs vic20, plus4, pet or kim1"
        end
      end

      # The C128 runs in the window, without an REU, and its NTSC models
      # have names of their own.
      def validate_c128
        raise Error, "--ntsc needs the C64; the NTSC C128 is --model c128ntsc" if @models.include?("ntsc")
        raise Error, "--reu needs the C64" unless @reu.nil?
        raise Error, "the C128 needs the window" if headless?
      end

      # The VIC-20 runs in the window, without the C64's SID and REU.
      def validate_vic20
        raise Error, "--sid needs the C64" unless @sid_model.nil?
        raise Error, "--reu needs the C64" unless @reu.nil?
        raise Error, "the VIC-20 needs the window" if headless?
      end

      # Only the Plus/4 has cartridge slots for raw ROM images and takes a
      # SID card and a RAM expansion.
      def refuse_plus4_options
        raise Error, "--#{@cartridges.keys.first} needs plus4" unless @cartridges.empty?
        raise Error, "--sid-card needs plus4" unless @sid_card.nil?
        raise Error, "--sid-card-address needs plus4" unless @sid_card_address.nil?
        raise Error, "--ram-expansion needs plus4" unless @ram_expansion.nil?
      end

      # The Plus/4 runs in the window, without the C64's SID and REU but
      # with a SID card if asked, its NTSC models have names of their own,
      # and its cartridge slots take raw ROM images.
      def validate_plus4
        raise Error, "--ntsc needs the C64; the NTSC Plus/4 is --model plus4ntsc" if @models.include?("ntsc")
        raise Error, "--sid needs the C64; the Plus/4's is --sid-card" unless @sid_model.nil?
        raise Error, "--reu needs the C64" unless @reu.nil?
        raise Error, "the Plus/4 needs the window" if headless?

        validate_plus4_expansions
        image = @cartridges.values.find { |path| !File.extname(path).casecmp?(".bin") }
        raise Error, "not a .bin ROM image: #{image}" unless image.nil?
      end

      # A RAM expansion goes over 64K, and a SID card's address needs a
      # card.
      def validate_plus4_expansions
        raise Error, "--ram-expansion needs 64k" unless @ram_expansion.nil? || [nil, 64].include?(@ram_kb)
        raise Error, "--sid-card-address needs --sid-card" unless @sid_card_address.nil? || @sid_card
      end

      # Only the PET has BASIC and editor ROMs to fit, and only it and the
      # CBM-II a frame rate to pick.
      def refuse_pet_options
        raise Error, "--60hz needs pet or cbm2" unless @refresh_hz.nil? || @family == :cbm2
        raise Error, "--basic needs pet" unless @basic.nil?
        raise Error, "--editor needs pet" unless @editor.nil?
        raise Error, "--characters needs pet" unless @characters.nil?
        raise Error, "--jumpers needs pet" unless @jumpers.empty?
        raise Error, "--cpu needs pet --model superpet" unless @cpu.nil?
        raise Error, "--bank-ram needs pet --model superpet" unless @bank_ram.nil?
      end

      # The PET runs in the window, without the C64's SID and REU, at the
      # frame rate its editor sets.
      def validate_pet
        raise Error, "--ntsc needs the C64; a CRTC PET's 60 Hz editor is --60hz" if @models.include?("ntsc")
        raise Error, "--sid needs the C64" unless @sid_model.nil?
        raise Error, "--reu needs the C64" unless @reu.nil?
        raise Error, "the PET needs the window" if headless?

        return unless PET_MODELS.include?(model)

        validate_pet_roms
        validate_pet_board
      end

      # --characters names a character ROM the board takes, --jumpers the
      # 8296 board's jumpers, and the 8296 has all of its RAM soldered on,
      # as the SuperPET has besides its bank RAM.
      def validate_pet_board
        unless @characters.nil? || PET::ROMSets.characters(model).include?(@characters)
          raise Error, "the #{model} takes no character ROM #{@characters}"
        end

        unknown = @jumpers.find { |jumper| !PET::ROMSets.jumpers(model).include?(jumper) }
        raise Error, "the #{model} has no jumper #{unknown}" unless unknown.nil?
        raise Error, "the 8296 has 32k of RAM" if model == "8296" && ![nil, 32].include?(@ram_kb)
        raise Error, "--ram doesn't fit the superpet" if model == "superpet" && !@ram_kb.nil?

        validate_cpu_switch
      end

      # --cpu and --bank-ram set the SuperPET's switches, which no other
      # PET has.
      def validate_cpu_switch
        validate_switch("--cpu", @cpu, PET::SuperPET::Board::CPU_SWITCH)
        validate_switch("--bank-ram", @bank_ram, PET::SuperPET::Board::RAM_SWITCH)
      end

      def validate_switch(flag, value, positions)
        return if value.nil?
        raise Error, "#{flag} needs pet --model superpet" unless model == "superpet"
        raise Error, "invalid argument: #{flag} #{value}" unless positions.include?(value)
      end

      # --basic and --editor name ROMs the model's board takes
      # (PET::ROMSets), and an editor named sets the frame rate.
      def validate_pet_roms
        raise Error, "invalid argument: --basic #{@basic}" unless @basic.nil? || PET::ROMSets::BASICS.key?(@basic)
        raise Error, "invalid argument: --editor #{@editor}" unless @editor.nil? || PET::ROMSets::EDITORS.key?(@editor)

        basic = @basic || PET::ROMSets.stock_basic(model)
        fitting = PET::ROMSets.editors(model, basic)
        raise Error, "the #{model} takes no BASIC #{basic}" if fitting.empty?
        return if @editor.nil?
        raise Error, "the #{model} with BASIC #{basic} takes no editor #{@editor}" unless fitting.include?(@editor)

        editor_rate(fitting)
      end

      # The frame rate of the editor named, on a CRTC board, which has a 50
      # Hz and a 60 Hz one.
      def editor_rate(fitting)
        return if fitting.size == 1

        editor_hz = @editor == fitting.last ? 60 : 50
        raise Error, "--60hz takes a 60 Hz editor, not #{@editor}" if @refresh_hz == 60 && editor_hz == 50

        @refresh_hz = editor_hz
      end

      # Only the CBM-II has a KERNAL to pick.
      def refuse_cbm2_options
        raise Error, "--kernal needs cbm2" unless @kernal.nil?
      end

      # The CBM-II runs in the window, without the C64's SID and REU, and
      # its model takes the KERNAL named.
      def validate_cbm2
        raise Error, "--ntsc needs the C64; a CBM-II on 60 Hz mains is --60hz" if @models.include?("ntsc")
        raise Error, "--sid needs the C64" unless @sid_model.nil?
        raise Error, "--reu needs the C64" unless @reu.nil?
        raise Error, "the CBM-II needs the window" if headless?

        kernals = p500? ? P500_KERNALS : CBM2_KERNALS
        raise Error, "the #{model} takes KERNAL #{kernals.join(' or ')}" unless kernals.include?(kernal)
      end

      # `sid` takes directories as well as tunes.
      def validate_tune(path)
        return if !File.exist?(path) || File.extname(path).casecmp?(".sid")
        return if @sid_command && File.directory?(path)

        raise Error, "not a .sid tune: #{path}"
      end

      # --model and --ntsc may be given more than once, but only for one
      # model.
      def validate_models
        names = family_models
        unknown = @models.find { |name| !names.include?(name) }
        raise Error, "invalid argument: --model #{unknown}" unless unknown.nil?
        raise Error, "conflicting models: #{@models.uniq.join(' and ')}" unless @models.uniq.size <= 1
      end

      def validate_numbers
        positive("--subtune", @subtune)
        positive("--seconds", @seconds)
        positive("--rate", @rate)
        positive("--filter-chunk", @filter_chunk)
      end

      def positive(name, value)
        raise Error, "invalid argument: #{name} #{value}" if !value.nil? && value <= 0
      end

      def validate_paths
        missing = (tune_paths + @cartridges.values).find { |path| !File.exist?(path) }
        raise Error, "no such file or directory: #{missing}" unless missing.nil?
        raise Error, "no such file or directory: #{@songlengths}" unless @songlengths.nil? || File.exist?(@songlengths)
      end
    end
  end
end
