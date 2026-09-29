# frozen_string_literal: true

module Badline
  module GUI
    # Translates SDL key events into the emulator's key symbols.
    #
    # MAP is just the overrides, anything not covered simply falls though.
    class KeyMap
      MAP = {
        "Backspace" => :delete,
        "Return" => :return,
        "Right" => :cursor_h,
        "Down" => :cursor_v,
        "Left" => :cursor_left,
        "Up" => :cursor_up,
        "`" => :left,
        "]" => :up,
        "PageUp" => :restore,
        "Space" => :space,
        "Left Ctrl" => :control,
        "Left Alt" => :cbm,
        "Left Shift" => :lshift,
        "Right Shift" => :rshift,
        "Home" => :clr_home,
        "Escape" => :run_stop,
        "Backslash" => :"@",
        "'" => :":",
        "End" => :£,
        "Keypad +" => :+,
        "Keypad *" => :*
      }.freeze

      def self.parse(event)
        name = Event.key_name(event.sym)
        MAP[name] || name.downcase.to_sym
      end
    end
  end
end
