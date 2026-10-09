# frozen_string_literal: true

module Badline
  class C128
    # Following the MMU between C128 and C64 mode: the KERNAL traps and
    # typed keys go to the KERNAL the machine runs, C= held from power-on
    # starts it in C64 mode through the C128 KERNAL, and #active_screen
    # tells a front end which screen the mode's editor prints to.
    module Modes
      # Holds C= down from power-on until the C128 KERNAL has taken the
      # machine to C64 mode, as a user does to start a C128 in C64 mode.
      # #on_init's handlers then wait for the C64 KERNAL's boot.
      def hold_commodore_key
        keyboard.press(:cbm)
        @holding_commodore = true
      end

      # The screen the machine prints to: in C128 mode the screen editor's,
      # :vdc while bit 7 of its 40/80 flag at $D7 is set, as GRAPHIC 5,
      # ESC X and a reset with 40/80 DISPLAY down leave it, or :vic. C64
      # mode has the VIC-IIe's alone.
      def active_screen = mode == :c128 && ram.peek(0xd7).anybits?(0x80) ? :vdc : :vic

      private

      # The KERNAL the traps stand in for: the C128's in C128 mode, the C64's
      # in C64 mode.
      def trap_layout = mode == :c128 ? KernalTrap::C128_LAYOUT : KernalTrap::C64_LAYOUT

      # The machine went to C64 mode or came back: the traps move to the
      # KERNAL it now runs. C= held from power-on lets go, and #on_init's
      # handlers wait for the C64 KERNAL to boot.
      def mode_changed
        layout = trap_layout
        @capture_output&.layout = layout
        if @drive
          remove_kernal_traps
          install_kernal_traps(layout)
        end
        return unless @holding_commodore && mode == :c64

        keyboard.release(:cbm)
        @holding_commodore = false
        @init_threshold = @cycles + Computer::INIT_THRESHOLD if @cycles < @init_threshold
      end

      # The keyboard buffer of the KERNAL the machine runs: the C64's, or in
      # C128 mode BASIC 7.0's.
      def feed_keyboard
        c64 = mode == :c64
        count = c64 ? KeyboardBuffer::COUNT : C128_KEYBOARD_COUNT
        return unless ram.peek(count).zero?

        chunk = @pending_keys.shift(KeyboardBuffer::CAPACITY)
        ram.write(c64 ? KeyboardBuffer::ADDRESS : C128_KEYBOARD_BUFFER, chunk)
        ram.poke(count, chunk.length)
        @pending_keys = nil if @pending_keys.empty?
      end
    end
  end
end
