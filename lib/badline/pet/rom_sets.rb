# frozen_string_literal: true

module Badline
  class PET
    # The BASIC and editor ROMs each model's board takes: its own, and the
    # upgrades Commodore sold for it, BASIC 2 for the 2001 and BASIC 4 for
    # the 3032s. Options reads it to check --basic and --editor, so it
    # loads nothing else.
    #
    # An editor ROM goes with one BASIC, scans one keyboard and drives one
    # board's video, so a model and a BASIC fit one editor, and on a CRTC
    # board its 50 Hz and its 60 Hz versions.
    module ROMSets
      # BASIC's ROM and its KERNAL's, by version.
      BASICS = {
        "1" => %w[pet/basic1.rom pet/kernal1.rom], "2" => %w[pet/basic2.rom pet/kernal2.rom],
        "4" => %w[pet/basic4.rom pet/kernal4.rom]
      }.freeze

      # The editors by the names --editor takes: the BASIC, the keyboard,
      # N or B, and on a CRTC board the columns and the frame rate.
      EDITORS = {
        "1" => "pet/editor1.rom", "2-n" => "pet/editor2-n.rom", "2-b" => "pet/editor2-b.rom",
        "4-n" => "pet/editor4-n.rom", "4-b" => "pet/editor4-b.rom", "4-40-n-50hz" => "pet/editor4-40-n-50hz.rom",
        "4-40-n-60hz" => "pet/editor4-40-n-60hz.rom", "4-80-b-50hz" => "pet/editor4-80-b-50hz.rom",
        "4-80-b-50hz-0283" => "pet/editor4-80-b-50hz-0283.rom", "4-80-b-60hz" => "pet/editor4-80-b-60hz.rom"
      }.freeze

      # The BASICs each model takes, its own first, and the editors that
      # fit each, the 50 Hz one first and the 60 Hz one last on a CRTC
      # board. The 8032's other 50 Hz editor, 901474-04 dated 0283, sits
      # between them.
      FITS = {
        "2001" => { "1" => %w[1], "2" => %w[2-n] },
        "3032" => { "2" => %w[2-n], "4" => %w[4-n] },
        "3032b" => { "2" => %w[2-b], "4" => %w[4-b] },
        "4032" => { "4" => %w[4-40-n-50hz 4-40-n-60hz] },
        "8032" => { "4" => %w[4-80-b-50hz 4-80-b-50hz-0283 4-80-b-60hz] },
        "8096" => { "4" => %w[4-80-b-50hz 4-80-b-50hz-0283 4-80-b-60hz] }
      }.freeze

      # The BASIC the model has, without --basic.
      def self.stock_basic(model) = FITS.fetch(model).keys.first

      # The editors that fit the model with the BASIC, or an empty list for
      # a BASIC it doesn't take.
      def self.editors(model, basic) = FITS.fetch(model).fetch(basic, [])

      # The editor that fits the model with the BASIC at +refresh_hz+.
      def self.editor(model, basic, refresh_hz)
        fitting = editors(model, basic)
        refresh_hz == 60 ? fitting.last : fitting.first
      end
    end
  end
end
