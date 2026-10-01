# frozen_string_literal: true

module Badline
  module Storage
    # The layout of an HVSC collection: tunes in directories under its root,
    # and databases about them in `DOCUMENTS`. A tune's HVSC path is its path
    # from the root, as `/MUSICIANS/H/Hubbard_Rob/Commando.sid`.
    module HVSC
      class << self
        # The named file in the DOCUMENTS directory of a collection above the
        # tune, or else of the one `$HVSC_BASE` points at.
        def document(tune_path, name)
          candidates(tune_path).map { |dir| File.join(dir, "DOCUMENTS", name) }
                               .find { |path| File.file?(path) }
        end

        # The tune's HVSC path in the collection that holds the document, or
        # nil when the tune lies outside it.
        def path(tune_path, document)
          root = File.dirname(File.expand_path(document), 2)
          tune = File.expand_path(tune_path)
          tune.start_with?("#{root}/") ? tune[root.length..] : nil
        end

        private

        def candidates(tune_path)
          dirs = []
          dir = File.dirname(File.expand_path(tune_path))
          until dirs.last == dir
            dirs << dir
            dir = File.dirname(dir)
          end
          base = ENV.fetch("HVSC_BASE", nil)
          dirs << base if base
          dirs
        end
      end
    end
  end
end
