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
          raise Error, "no tune given" if @media_path.nil?
          raise Error, "not a .sid tune: #{@media_path}" unless File.extname(@media_path).casecmp?(".sid")
        elsif !@headless_only.empty?
          raise Error, "#{@headless_only.first} needs --headless or --audio-out"
        end
      end

      def validate_numbers
        positive("--song", @song)
        positive("--seconds", @seconds)
        positive("--rate", @rate)
        positive("--filter-chunk", @filter_chunk)
      end

      def positive(name, value)
        raise Error, "invalid argument: #{name} #{value}" if !value.nil? && value <= 0
      end

      def validate_paths
        raise Error, "no such file or directory: #{@media_path}" unless @media_path.nil? || File.exist?(@media_path)
        raise Error, "no such file or directory: #{@songlengths}" unless @songlengths.nil? || File.exist?(@songlengths)
      end
    end
  end
end
