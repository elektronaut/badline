# frozen_string_literal: true

module Badline
  class Options
    # The checks Options#parse makes once every argument has been read:
    # the options fit the mode, the numbers are positive and the files
    # exist.
    module Validation
      private

      def validate
        validate_mode
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

      # `sid` takes directories as well as tunes.
      def validate_tune(path)
        return if !File.exist?(path) || File.extname(path).casecmp?(".sid")
        return if @sid_command && File.directory?(path)

        raise Error, "not a .sid tune: #{path}"
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
