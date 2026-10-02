# frozen_string_literal: true

module Badline
  module Storage
    class STIL
      # A TITLE in a STIL entry, the tune a subtune covers, with the ARTIST
      # after it, and the stretch of the subtune it covers when the title
      # ends in one, such as `(0:53)` or `(1:16-1:32)`. A credit without an
      # end lasts until the next one takes over.
      class Credit
        TIMES = /\s*\((\d+):(\d\d)(?:\.\d+)?(?:-(\d+):(\d\d)(?:\.\d+)?)?\)\s*\z/

        attr_reader :text, :start, :finish

        def initialize(title, artist)
          match = TIMES.match(title)
          @start = match ? (match[1].to_i * 60) + match[2].to_i : 0
          @finish = match && match[3] ? (match[3].to_i * 60) + match[4].to_i : -1
          name = match ? title[0, match.begin(0)] : title
          @text = artist.empty? ? name : "#{name} - #{artist}"
        end

        # The credits in the fields, in the order STIL lists them.
        def self.list(fields)
          credits = []
          fields.each_with_index do |field, index|
            next unless field.name == "TITLE"

            following = fields[index + 1]
            artist = following && following.name == "ARTIST" ? following.text : ""
            credits << new(field.text.tr("\n", " "), artist.tr("\n", " "))
          end
          credits
        end

        # The text of the credit covering `seconds` into the subtune, or ""
        # when none does: the last one started by then that hasn't ended.
        def self.at(credits, seconds)
          text = ""
          credits.each do |credit|
            text = credit.text if credit.covers?(seconds)
          end
          text
        end

        def covers?(seconds) = seconds >= @start && (@finish.negative? || seconds <= @finish)
      end
    end
  end
end
