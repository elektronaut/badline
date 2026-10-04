# frozen_string_literal: true

module Badline
  module Frontend
    # The pause menu's prompt for a name, typed with the keys by their
    # place on a US keyboard: letters, with Shift for capitals, digits,
    # space, - and _ and the full stop. Backspace deletes, Return takes the
    # name and Esc leaves it.
    class NameField
      COLUMNS = 30
      LETTERS = "abcdefghijklmnopqrstuvwxyz"
      DIGITS = "1234567890"
      OTHERS = { 44 => [" ", " "], 45 => ["-", "_"], 55 => [".", "."] }.freeze

      RETURN = 40
      ESCAPE = 41
      BACKSPACE = 42

      attr_reader :text

      def initialize(painter)
        @painter = painter
        @open = false
        @title = ""
        @text = ""
        @problem = ""
      end

      def open? = @open

      def open(title, text)
        @open = true
        @title = title
        @text = text
        @problem = ""
      end

      def close
        @open = false
      end

      # Says why the name won't do, under the field.
      def refuse(problem)
        @problem = problem
      end

      # Handles a key, and returns :done for Return, :cancel for Esc, or
      # nil.
      def key(scancode, shift)
        return :done if scancode == RETURN
        return :cancel if scancode == ESCAPE

        @problem = ""
        if scancode == BACKSPACE
          @text = @text[0, @text.length - 1].to_s
        else
          char = character(scancode, shift)
          @text += char unless char.empty? || @text.length >= COLUMNS
        end
        nil
      end

      def draw(left, top, width)
        painter = @painter
        painter.text(left, top, @title, PauseMenu::BRIGHT)
        painter.box(left, top + 18, width, Buttons::HEIGHT + 4, PauseMenu::FILL)
        painter.text(left + 4, top + 22, "#{@text}_", PauseMenu::TEXT)
        painter.text(left, top + 42, @problem, MenuPages::WARNING) unless @problem.empty?
        painter.text(left, top + 60, "RETURN: SAVE  ESC: CANCEL", PauseMenu::DIM)
      end

      private

      def character(scancode, shift)
        if scancode.between?(4, 29)
          letter = LETTERS[scancode - 4]
          shift ? letter.upcase : letter
        elsif scancode.between?(30, 39)
          DIGITS[scancode - 30]
        elsif OTHERS.key?(scancode)
          OTHERS[scancode][shift ? 1 : 0]
        else
          ""
        end
      end
    end
  end
end
