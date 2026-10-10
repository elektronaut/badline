# frozen_string_literal: true

module Badline
  module Media
    # A .sid tune on a machine with a SID (Media.attach): its data and the
    # player the tune boots with go in RAM once the KERNAL has booted, and
    # the autostart types what starts it.
    module Tune
      class << self
        # Plays `subtune`, or the tune's own start subtune, and says what
        # plays. A tune for more than one SID raises FormatError.
        def attach(computer, path, autostart:, subtune:)
          tune = Storage::SIDFile.new(path)
          if tune.sids > 1
            raise Storage::SIDFile::FormatError, "Written for #{tune.sids} SIDs, which only the SID player plays"
          end

          subtune = (subtune || tune.start_subtune).clamp(1, tune.subtunes)
          computer.on_init { start(computer, tune, autostart:, subtune:) }
          title = tune.name.empty? ? path : tune.name
          title += " (subtune #{subtune})" if tune.subtunes > 1
          autostart ? "Playing #{title}" : "Loaded #{title}"
        end

        private

        def start(computer, tune, autostart:, subtune:)
          computer.ram.write(tune.load_address, tune.data)
          tune.boot_memory(subtune:).each { |address, bytes| computer.ram.write(address, bytes) }
          computer.type_text(tune.boot_command) if autostart
        end
      end
    end
  end
end
