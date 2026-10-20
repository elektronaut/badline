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
      MEDIA = {
        "2031" => %w[.d64 .g64], "8050" => %w[.d80], "8250" => %w[.d82], "1001" => %w[.d82], "4040" => %w[.d64 .d67],
        "3040" => %w[.d64 .d67], "2040" => %w[.d67], "9060" => %w[.d90], "9090" => %w[.d90]
      }.freeze

      # The model --true-drive plugs in without --drive-type.
      DEFAULT = "2031"

      # The model an image goes in when neither the drive on device 8 nor
      # the machine's own model reads it. A .d90 goes by its size
      # (hard_disk_model).
      FOR_IMAGES = { ".d64" => "2031", ".g64" => "2031", ".d80" => "8050", ".d82" => "8250", ".d67" => "2040" }.freeze

      NAMES = MEDIA.keys.freeze

      module_function

      # Whether the image at path is a hard disk's, which only a true drive
      # reads.
      def hard_disk?(path) = File.extname(path).casecmp?(".d90")

      # The hard disk a .d90 image belongs to, by its size: a D9090 for a
      # D9090's, and otherwise a D9060.
      def hard_disk_model(path) = Storage::D90Image.heads_for(File.size?(path).to_i) == 6 ? "9090" : "9060"

      # Whether the model reads the image at path.
      def reads?(model, path) = MEDIA.fetch(model, []).include?(File.extname(path).downcase)

      # The model the image at path goes in: the drive's on device 8,
      # `present`, if it reads it, or else the machine's own, `chosen`, or
      # else the image's own, or nil for an image none reads. A .d90 goes
      # in the machine's own model if that is a hard disk, and otherwise in
      # the one its size names.
      def taking(path, present, chosen)
        return reads?(chosen, path) ? chosen : hard_disk_model(path) if hard_disk?(path)
        return present if present && reads?(present, path)
        return chosen if reads?(chosen, path)

        FOR_IMAGES[File.extname(path).downcase]
      end
    end
  end
end
