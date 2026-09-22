# frozen_string_literal: true

module Badline
  module Storage
    # HVSC's song length database. Each tune gets a comment naming its path
    # and a line keyed by the MD5 of the whole `.sid` file, holding one
    # `m:ss` time per song, optionally down to milliseconds:
    #
    #   ; /DEMOS/0-9/12th_Sector_Music.sid
    #   c7c299ce06ec5ccffb2261fb11b42a73=4:33.108
    #
    # The file runs to well over a hundred thousand entries, so a lookup
    # scans for its one key rather than building a table.
    class SongLengths
      class << self
        # The database lives in the DOCUMENTS directory of an HVSC
        # collection, so look for one above the tune, then wherever
        # `$HVSC_BASE` points.
        def locate(tune_path)
          candidates(tune_path).find { |path| File.file?(path) }
        end

        private

        def candidates(tune_path)
          ancestors(File.dirname(File.expand_path(tune_path)))
            .push(ENV.fetch("HVSC_BASE", nil))
            .compact
            .map { |dir| File.join(dir, "DOCUMENTS", "Songlengths.md5") }
        end

        def ancestors(dir)
          dirs = []
          until dirs.last == dir
            dirs << dir
            dir = File.dirname(dir)
          end
          dirs
        end
      end

      def initialize(path)
        @path = path
      end

      # The tune's per-song lengths in seconds, or nil when it isn't listed.
      def lengths(md5)
        prefix = "#{md5.downcase}="
        File.foreach(@path) do |line|
          next unless line.start_with?(prefix)

          return line[prefix.length..].split.map { |time| seconds(time) }
        end
        nil
      end

      private

      def seconds(time)
        minutes, rest = time.split(":", 2)
        rest ? (minutes.to_i * 60) + rest.to_f : minutes.to_f
      end
    end
  end
end
