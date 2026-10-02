# frozen_string_literal: true

module Badline
  module Audio
    # A .sid tune in the player's Media::Queue, read only once the queue or
    # the player first asks about it, so a queue of a whole collection
    # starts at once. Its subtunes, SID model and lengths follow the options:
    # --subtune picks the subtune to start on, --sid the model and --seconds the
    # length, and without them the tune's own header and HVSC's database
    # decide.
    #
    # A file that won't read as a tune, or lacks the subtune asked for, gets
    # an #error and a single subtune.
    class QueuedTune < Media::Queue::Entry
      def initialize(path, options, subtune: nil)
        super(path)
        @options = options
        @subtune = subtune
        @tune = nil
        @read = false
        @error = ""
        @lengths = nil
        @lengths_read = false
      end

      def part
        read
        @part
      end

      def parts
        read
        @parts
      end

      # Why the tune can't play, or "" when it can.
      def error
        read
        @error
      end

      def tune = @tune ||= Storage::SIDFile.new(path)

      # Lets go of the tune's data, which #tune reads again if asked.
      def release = @tune = nil

      # Each SID's model, SID 1's first: the one --sid names for all of
      # them, or each one's own.
      def sid_models
        forced = @options.sid_model
        forced ? Array.new(tune.sids, forced) : tune.sid_models
      end

      def model_name = sid_models.map { |model| model.to_s.delete_prefix("mos") }.join(" + ")

      def length(subtune) = @options.seconds || songlengths&.at(subtune - 1) || @options.fallback_seconds

      # How long the subtune may stay silent before it ends, or nil when its
      # length is known rather than the fallback.
      def silence(subtune) = @options.seconds || songlengths&.at(subtune - 1) ? nil : @options.silence_seconds

      # The header's name, author and release, those it fills in.
      def header = [tune.name, tune.author, tune.released].reject(&:empty?)

      private

      def read
        return if @read

        @read = true
        @parts = tune.subtunes
        @part = @subtune || tune.start_subtune
        @error = "no subtune #{@part}: the tune has #{@parts}" if @part > @parts
      rescue Storage::SIDFile::FormatError => e
        @error = e.message
      end

      # HVSC's database is keyed by the tune's MD5 and lists one length per
      # subtune.
      def songlengths
        return @lengths if @lengths_read

        @lengths_read = true
        database = @options.songlengths || Storage::SongLengths.locate(path)
        @lengths = database && Storage::SongLengths.new(database).lengths(tune.md5)
      end
    end
  end
end
