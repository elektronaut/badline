# frozen_string_literal: true

module Badline
  module Frontend
    # The pause menu's question before something power cycles the machine
    # or replaces a file: a cartridge going in or out, Quick open starting a
    # file, or a save overwriting one of the same name. CANCEL has the
    # focus, so Return alone changes nothing.
    class Confirmation
      TITLES = { cartridge: "INSERT A CARTRIDGE", remove: "REMOVE THE CARTRIDGE", start: "QUICK OPEN",
                 overwrite: "SAVE AS" }.freeze
      LOST = "ANYTHING NOT SAVED IS LOST."
      WARNINGS = { cartridge: ["INSERTING IT POWER CYCLES THE MACHINE.", LOST],
                   remove: ["REMOVING IT POWER CYCLES THE MACHINE.", LOST],
                   start: ["THIS STARTS A NEW MACHINE.", LOST],
                   overwrite: ["OVERWRITE EXISTING SAVE?", ""] }.freeze
      ANSWERS = { cartridge: "INSERT", remove: "REMOVE", start: "START", overwrite: "OVERWRITE" }.freeze

      def initialize(painter, buttons)
        @painter = painter
        @buttons = buttons
        @kind = :start
        @path = ""
        @open = false
      end

      def open? = @open

      # Asks about `kind`, :cartridge, :remove, :start or :overwrite, for the
      # file at `path`, or the save named so.
      def ask(kind, path)
        @kind = kind
        @path = path
        @open = true
        @buttons.focus = :cancel
      end

      # Puts the question away, and returns its kind and path.
      def close
        @open = false
        [@kind, @path]
      end

      def draw(left, top)
        painter = @painter
        painter.text(left, top, TITLES.fetch(@kind), MenuTheme::BRIGHT)
        painter.text(left, top + 20, Painter.fit(File.basename(@path), 40), MenuTheme::TEXT) unless @path.empty?
        warning = WARNINGS.fetch(@kind)
        painter.text(left, top + 44, warning[0], MenuTheme::TEXT)
        painter.text(left, top + 56, warning[1], MenuTheme::TEXT) unless warning[1].empty?
        @buttons.row([left, top + 80, MenuPages::ROW_WIDTH], "CANCEL", :cancel)
        @buttons.row([left, top + 80 + Buttons::HEIGHT + 2, MenuPages::ROW_WIDTH], ANSWERS.fetch(@kind), :confirm)
      end
    end
  end
end
