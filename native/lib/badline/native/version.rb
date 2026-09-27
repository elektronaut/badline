# frozen_string_literal: true

module Badline
  module Native
    # The `--version` line: the badline version, the revision it was built
    # from, and the Spinel compiler that built it.
    def self.version(revision: REVISION, spinel: SPINEL)
      line = "badline #{Badline::VERSION}"
      line += " (#{revision})" unless revision.empty?
      line + " built with #{spinel.empty? ? 'an unknown Spinel' : spinel}"
    end
  end
end
