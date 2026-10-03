# frozen_string_literal: true

module Badline
  module Frontend
    # The pause menu's question before something power cycles the machine:
    # a cartridge going in or out, or Quick open starting a file. CANCEL
    # has the focus, so Return alone changes nothing.
    class Confirmation
      TITLES = { cartridge: "INSERT A CARTRIDGE", remove: "REMOVE THE CARTRIDGE", start: "QUICK OPEN" }.freeze
      WARNINGS = { cartridge: "INSERTING IT POWER CYCLES THE MACHINE.", remove: "REMOVING IT POWER CYCLES THE MACHINE.",
                   start: "THIS STARTS A NEW MACHINE." }.freeze
      ANSWERS = { cartridge: "INSERT", remove: "REMOVE", start: "START" }.freeze

      def initialize(painter, buttons)
        @painter = painter
        @buttons = buttons
        @kind = :start
        @path = ""
        @open = false
      end

      def open? = @open

      # Asks about `kind`, :cartridge, :remove or :start, for the file at
      # `path`.
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
        painter.text(left, top, TITLES.fetch(@kind), PauseMenu::BRIGHT)
        painter.text(left, top + 20, Painter.fit(File.basename(@path), 40), PauseMenu::TEXT) unless @path.empty?
        painter.text(left, top + 44, WARNINGS.fetch(@kind), PauseMenu::TEXT)
        painter.text(left, top + 56, "ANYTHING NOT SAVED IS LOST.", PauseMenu::TEXT)
        @buttons.row([left, top + 80, MenuPages::ROW_WIDTH], "CANCEL", :cancel)
        @buttons.row([left, top + 80 + Buttons::HEIGHT + 2, MenuPages::ROW_WIDTH], ANSWERS.fetch(@kind), :confirm)
      end
    end
  end
end
