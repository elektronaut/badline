# frozen_string_literal: true

module Badline
  module Drives
    # The true drives the PET's and the CBM-II's IEEE-488 bus takes, by the
    # names --drive-type gives them, xpet's drive types, and the disk images
    # each reads. Options reads it to check --drive-type, and
    # Media::TrueDrive to pick the drive an image goes in, so it loads
    # nothing else. Machine::IEEEDrives builds each.
    module IEEEModels
      # The images each model reads, by extension.
      MEDIA = { "2031" => %w[.d64 .g64], "8050" => %w[.d80], "8250" => %w[.d82] }.freeze

      # The model --true-drive plugs in without --drive-type.
      DEFAULT = "2031"

      # The model an image goes in when neither the drive on device 8 nor
      # the machine's own model reads it.
      FOR_IMAGES = { ".d64" => "2031", ".g64" => "2031", ".d80" => "8050", ".d82" => "8250" }.freeze

      NAMES = MEDIA.keys.freeze

      module_function

      # Whether the model reads the image at path.
      def reads?(model, path) = MEDIA.fetch(model, []).include?(File.extname(path).downcase)

      # The model the image at path goes in: the drive's on device 8,
      # `present`, if it reads it, or else the machine's own, `chosen`, or
      # else the image's own, or nil for an image none reads.
      def taking(path, present, chosen)
        return present if present && reads?(present, path)
        return chosen if reads?(chosen, path)

        FOR_IMAGES[File.extname(path).downcase]
      end
    end
  end
end
