# frozen_string_literal: true

require "badline/storage/stil/credit"

module Badline
  module Storage
    # HVSC's SID Tune Information List, `DOCUMENTS/STIL.txt`: covers,
    # subtune names and composers' comments, keyed by each tune's HVSC path.
    # An entry holds fields for the whole file, then a block per subtune
    # that has any:
    #
    #   /MUSICIANS/C/Crowther_Anthony/From_Ratt_To_You.sid
    #   COMMENT: The tune names are listed, if they were given a name, the
    #            remaining tunes were just called Tune 35, Tune 27 etc.
    #   (#16)
    #      NAME: G-Bust
    #     TITLE: Ghostbusters [from the movie]
    #    ARTIST: Ray Parker, Jr.
    #
    # A comment runs on over lines indented by nine spaces, and a blank line
    # ends the entry. The file is ISO-8859-1.
    class STIL
      # One of NAME, AUTHOR, TITLE, ARTIST or COMMENT, with its lines of
      # text joined by newlines.
      class Field
        attr_reader :name, :text

        def initialize(name, text)
          @name = name
          @text = text
        end

        def continue(line)
          @text = "#{@text}\n#{line}"
        end

        # The field laid out as STIL.txt does.
        def lines
          @text.split("\n").each_with_index.map do |line, index|
            label = index.zero? ? "#{@name}:" : ""
            "#{label.rjust(8)} #{line}"
          end
        end
      end

      # A tune's fields for the whole file, and for each subtune by number.
      class Entry
        attr_reader :fields

        def initialize
          @fields = []
          @subtunes = {}
          @subtune = 0
        end

        def subtune(number) = @subtunes.fetch(number, [])

        # Starts the block for a subtune, which the fields read after it
        # go to.
        def open_subtune(subtune)
          @subtune = subtune
          @subtunes[subtune] = []
        end

        def add(field)
          if @subtune.zero?
            @fields << field
          else
            @subtunes[@subtune] << field
          end
        end

        # Adds a line to the last field read.
        def continue(line)
          last = @subtune.zero? ? @fields.last : @subtunes[@subtune].last
          last&.continue(line)
        end
      end

      # The list lives in the DOCUMENTS directory of an HVSC collection.
      def self.locate(tune_path) = HVSC.document(tune_path, "STIL.txt")

      def initialize(path)
        @path = path
      end

      # The entry for a tune's HVSC path, or nil when the list has none. The
      # first lookup reads the whole list.
      def entry(hvsc_path) = entries[hvsc_path]

      def entries
        @entries ||= parse(Storage.latin1(File.binread(@path).bytes))
      end

      private

      def parse(text)
        entries = {}
        entry = nil
        text.split("\n").each do |line|
          line = line.chomp
          if line.start_with?("/")
            entry = Entry.new
            entries[line] = entry
          elsif entry.nil? || line.empty? || line.start_with?("#")
            entry = nil
          else
            read(entry, line)
          end
        end
        entries
      end

      def read(entry, line)
        if line.start_with?("(#")
          entry.open_subtune(line[2..].to_i)
        elsif line.start_with?("         ")
          entry.continue(line[9..])
        else
          name, text = line.lstrip.split(": ", 2)
          entry.add(Field.new(name, text.to_s)) if %w[NAME AUTHOR TITLE ARTIST COMMENT].include?(name)
        end
      end
    end
  end
end
