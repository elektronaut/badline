# frozen_string_literal: true

module Badline
  class PET
    # The BASIC and editor ROMs each model's board takes: its own, and the
    # upgrades Commodore sold for it, BASIC 2 for the 2001 and BASIC 4 for
    # the 3032s, and the 8296's character ROMs and board jumpers. Options
    # reads it to check --basic, --editor, --characters and --jumpers, so
    # it loads nothing else.
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
        "4-80-b-50hz-0283" => "pet/editor4-80-b-50hz-0283.rom", "4-80-b-60hz" => "pet/editor4-80-b-60hz.rom",
        "4-80-b-50hz-8296" => "pet/editor4-80-b-50hz-8296.rom"
      }.freeze

      # The BASICs each model takes, its own first, and the editors that
      # fit each, the 50 Hz one first and the 60 Hz one last on a CRTC
      # board. The 8032's other 50 Hz editor, 901474-04 dated 0283, sits
      # between them, and the 8296 takes the 8032's as well as its own.
      FITS = {
        "2001" => { "1" => %w[1], "2" => %w[2-n] },
        "3032" => { "2" => %w[2-n], "4" => %w[4-n] },
        "3032b" => { "2" => %w[2-b], "4" => %w[4-b] },
        "4032" => { "4" => %w[4-40-n-50hz 4-40-n-60hz] },
        "8032" => { "4" => %w[4-80-b-50hz 4-80-b-50hz-0283 4-80-b-60hz] },
        "8096" => { "4" => %w[4-80-b-50hz 4-80-b-50hz-0283 4-80-b-60hz] },
        "8296" => { "4" => %w[4-80-b-50hz-8296 4-80-b-50hz 4-80-b-50hz-0283 4-80-b-60hz] }
      }.freeze

      # The character ROMs by the names --characters takes, and the ones
      # each model's board takes, its own first: the 8296's socket takes
      # 901447-10, its ASCII one, or the 4K 324242-01, which holds a DIN set
      # in its first half and 901447-10 in its second.
      CHARACTERS = { "ascii" => "pet/characters2.rom", "din" => "pet/characters-din.rom" }.freeze

      CHARACTER_FITS = { "8296" => %w[ascii din] }.freeze

      # The jumpers each model's board takes, by the names --jumpers takes
      # (Bus::Expansion), none on a board not named.
      JUMPERS = { "8296" => %w[ram9 rama userport] }.freeze

      # The cycles a line and the lines a frame the CRTC editors set up
      # where they differ from 50-cycle lines, 400 a frame at 50 Hz and 333
      # at 60 Hz, by the editor's ROM.
      CRTC_FRAMES = {
        "pet/editor4-80-b-50hz-0283.rom" => [64, 313], "pet/editor4-80-b-50hz-8296.rom" => [59, 339]
      }.freeze

      # The cycles a line and the lines a frame the CRTC editor in the ROM
      # named sets up at +refresh_hz+.
      def self.crtc_frame(editor, refresh_hz) = CRTC_FRAMES[editor] || [50, refresh_hz == 50 ? 400 : 333]

      # The BASIC the model has, without --basic.
      def self.stock_basic(model) = FITS.fetch(model).keys.first

      # The editors that fit the model with the BASIC, or an empty list for
      # a BASIC it doesn't take.
      def self.editors(model, basic) = FITS.fetch(model).fetch(basic, [])

      # The character ROMs the model takes, by name, none for one that takes
      # only its own.
      def self.characters(model) = CHARACTER_FITS.fetch(model, [])

      # The jumpers the model's board takes.
      def self.jumpers(model) = JUMPERS.fetch(model, [])

      # The editor that fits the model with the BASIC at +refresh_hz+.
      def self.editor(model, basic, refresh_hz)
        fitting = editors(model, basic)
        refresh_hz == 60 ? fitting.last : fitting.first
      end
    end
  end
end
