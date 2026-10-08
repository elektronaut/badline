# frozen_string_literal: true

module Badline
  class Options
    # The checks Options#parse makes: that each value reads as its option
    # takes it, and once every argument has been read, that the options
    # fit the mode, the numbers are positive and the files exist.
    module Validation
      private

      def sid_model_for(value)
        return if value == "auto"
        raise Error, "invalid argument: --sid #{value}" unless SID_MODELS.key?(value)

        SID_MODELS[value]
      end

      def ram_configuration(value)
        raise Error, "invalid argument: --ram #{value}" unless RAM_CONFIGURATIONS.key?(value)

        RAM_CONFIGURATIONS[value]
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
        validate_mode
        validate_models
        validate_numbers
        validate_paths
      end

      def validate_mode
        if headless?
          raise Error, "#{@window_only.first} needs the window" unless @window_only.empty?
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
          raise Error, "--ram needs vic20"
        end
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
        missing = tune_paths.find { |path| !File.exist?(path) }
        raise Error, "no such file or directory: #{missing}" unless missing.nil?
        raise Error, "no such file or directory: #{@songlengths}" unless @songlengths.nil? || File.exist?(@songlengths)
      end
    end
  end
end
