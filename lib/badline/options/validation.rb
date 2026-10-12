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

      def plus4_ram_expansion(value)
        raise Error, "invalid argument: --ram-expansion #{value}" unless PLUS4_RAM_EXPANSIONS.key?(value)

        PLUS4_RAM_EXPANSIONS[value]
      end

      def drive_type_for(value)
        raise Error, "invalid argument: --drive-type #{value}" unless PLUS4_DRIVE_TYPES.include?(value)

        value
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
        raise Error, "--drive-type needs plus4" unless @drive_type.nil? || @family == :plus4

        validate_mode
        validate_models
        validate_numbers
        validate_paths
      end

      def validate_mode
        if headless?
          raise Error, "#{@window_only.first} needs the window" unless @window_only.empty?
          raise Error, "#{@any_window_only.first} needs the window" unless player_window? || @any_window_only.empty?
          raise Error, "no tune given" if tune_paths.empty? && !player_window?

          tune_paths.each { |path| validate_tune(path) }
        elsif !@headless_only.empty?
          raise Error, "#{@headless_only.first} needs --headless or --audio-out"
        end
      end

      def validate_family
        if @family == :vic20
          validate_vic20
        elsif !@ram.nil?
          raise Error, "--ram needs vic20 or plus4"
        end
        @family == :plus4 ? validate_plus4 : refuse_plus4_options
        if @family == :c128
          validate_c128
        elsif @c64_mode
          raise Error, "--c64 needs c128"
        end
      end

      # The C128 runs in the window, without an REU, and its NTSC models
      # have names of their own.
      def validate_c128
        raise Error, "--ntsc needs the C64; the NTSC C128 is --model c128ntsc" if @models.include?("ntsc")
        raise Error, "--reu needs the C64" unless @reu.nil?
        raise Error, "the C128 needs the window" if headless?
      end

      # The VIC-20 is a PAL one, in the window, without the C64's SID and
      # REU.
      def validate_vic20
        raise Error, "the NTSC VIC-20 isn't emulated yet" if @models.include?("ntsc")

        raise Error, "--sid needs the C64" unless @sid_model.nil?
        raise Error, "--reu needs the C64" unless @reu.nil?
        raise Error, "the VIC-20 needs the window" if headless?
      end

      # Only the Plus/4 has cartridge slots for raw ROM images and takes a
      # SID card and a RAM expansion.
      def refuse_plus4_options
        raise Error, "--#{@cartridges.keys.first} needs plus4" unless @cartridges.empty?
        raise Error, "--sid-card needs plus4" unless @sid_card.nil?
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
        raise Error, "--ram-expansion needs 64k" unless @ram_expansion.nil? || [nil, 64].include?(@ram_kb)

        image = @cartridges.values.find { |path| !File.extname(path).casecmp?(".bin") }
        raise Error, "not a .bin ROM image: #{image}" unless image.nil?
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
