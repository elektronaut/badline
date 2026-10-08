# frozen_string_literal: true

module Badline
  module Frontend
    # The emulator's pause menu, which F9 opens over the frozen picture.
    # The machine stands still while it's open. Its sections follow the
    # machine's hardware: the drive, the datasette, the expansion port, the
    # control ports, the sound and the power. It's drawn in colours outside
    # the C64's palette, so it reads as the emulator's and not the
    # machine's, and F9 or Esc closes it again.
    #
    # INSERT on a page opens the file browser for that device. Quick open
    # starts a file as the command line does, in a new machine, and it and
    # a cartridge going in or out ask first, as each power cycles the
    # machine.
    class PauseMenu
      SECTIONS = ["SNAPSHOTS", "DRIVE 8", "DATASETTE", "EXPANSION PORT", "PORTS", "SOUND", "POWER"].freeze
      PAGES = %i[snapshots drive datasette expansion ports sound power].freeze

      PANEL = 0x1d2230
      EDGE = 0x3a4256
      TEXT = 0xc9d1e0
      BRIGHT = 0xffc66d
      DIM = 0x6b7489
      FILL = 0x343c50

      MARGIN = 16
      WIDTH = 352
      HEIGHT = 240
      BODY = 138

      ESCAPE = 41
      RETURN = 40
      SPACE = 44
      SNAPSHOT_ACTIONS = %i[quicksave_now save_as load_save].freeze
      ARROWS = { 79 => :right, 80 => :left, 81 => :down, 82 => :up }.freeze
      MOUSEWHEEL = 0x403

      # Takes the media, the REU and whether disks are writable from Options.
      def initialize(painter, options, snapshots)
        media_path = options.media_path.to_s
        @painter = painter
        @buttons = Buttons.new(painter, [TEXT, BRIGHT, PANEL, FILL])
        @pages = MenuPages.new(painter, @buttons, media_path, options, snapshots)
        @snapshots = snapshots
        @dialogs = MenuDialogs.new(painter, @buttons, @pages.media, options, snapshots)
        @open = false
        @section = 0
        @left = MARGIN
        @top = MARGIN
      end

      def open? = @open

      # The index in PAGES of the page #show opens on.
      attr_writer :section

      # The machine Quick open started, which the app runs in place of the
      # one before once #frame returns :swap.
      def computer = @dialogs.computer

      def show(computer, controls, sound)
        @open = true
        @buttons.focus = PAGES[@section]
        @pages.machine(computer, controls, sound)
        SDL.SDL_SetRelativeMouseMode(0)
        draw
      end

      def close
        @open = false
      end

      # Opens on the file the SDL event says was dropped on the window,
      # and says whether the menu stays open to ask about it: a disk or tape
      # goes straight in, and anything else asks first.
      def drop(computer, controls, sound)
        show(computer, controls, sound)
        file = SDL.event_file(SDL.event)
        asks = @dialogs.drop(LibC.strstr(file, ""))
        LibC.free(file)
        asks
      end

      # Handles a key pressed while the menu is open: the arrows move
      # between the buttons, and a section opens as they reach it, Return
      # or Space presses the button, and F9 or Esc closes the menu. While
      # the file browser or a question is open, the keys go to it, and Esc
      # goes back to the page. Returns the action the app has to take on,
      # as #click does.
      def key(scancode)
        return :resume if scancode == Keys::F9
        return @dialogs.key(scancode) if @dialogs.open?
        return :resume if scancode == ESCAPE
        return choose(@buttons.focus) if [RETURN, SPACE].include?(scancode)

        direction = ARROWS[scancode]
        move(direction) unless direction.nil?
        nil
      end

      # Handles a click, and returns the action the app has to take on, if
      # any: :resume, :quit, :freeze or :swap.
      def click(left, top)
        action = @buttons.action_at(left, top)
        return @dialogs.click(action, top) if %i[browse confirm cancel].include?(action)

        choose(action)
      end

      # Handles the events that came in, draws the menu over the frozen
      # picture, dimmed, for the app to present, and returns the action the
      # app has to take on, if any, leaving the events after one for the
      # machine. Key releases still reach the machine, so no key stays held
      # down while it stands still.
      def frame(renderer, texture, controls)
        action = nil
        action = event(SDL.event_type(SDL.event), controls) while action.nil? && SDL.SDL_PollEvent(SDL.event) != 0
        SDL.SDL_SetTextureColorMod(texture, 96, 96, 96)
        SDL.SDL_RenderClear(renderer)
        SDL.SDL_RenderCopy(renderer, texture, nil, nil)
        SDL.SDL_SetTextureColorMod(texture, 255, 255, 255)
        draw
        SDL.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255)
        action
      end

      # Centres the menu on a screen `width` by `height`.
      def center(width, height)
        @left = (width - WIDTH) / 2
        @top = (height - HEIGHT) / 2
      end

      def draw
        painter = @painter
        @buttons.forget
        painter.box(@left, @top, WIDTH, HEIGHT, PANEL)
        painter.box(@left, @top + 24, WIDTH, 1, EDGE)
        painter.text(@left + 8, @top + 9, "PAUSED", BRIGHT)
        resume = "RESUME"
        @buttons.plain(@left + WIDTH - 8 - Painter.width(resume) - (Buttons::PAD * 2), @top + 7, resume, :resume)
        return @dialogs.draw(@left + 8, @top + 34, WIDTH - 16) if @dialogs.open?

        painter.box(@left + BODY - 8, @top + 32, 1, HEIGHT - 56, EDGE)
        draw_sections
        @buttons.plain(@left + 6, @top + HEIGHT - 28, "QUICK OPEN...", :quick_open)
        painter.text(@left + 8, @top + HEIGHT - 12, "F9/ESC: RESUME", DIM)
        @pages.draw(PAGES[@section], @left + BODY, @top + 34)
      end

      private

      def choose(pressed)
        return nil if pressed.nil?

        action = @buttons.resolve(pressed)
        index = PAGES.index(action)
        unless index.nil?
          @section = index
          return nil
        end
        return action if %i[resume quit freeze].include?(action)

        menu_action(action)
      end

      def menu_action(action)
        return snapshot_action(action) if SNAPSHOT_ACTIONS.include?(action) || MenuPages::RECENT.include?(action)

        case action
        when :insert_disk then @dialogs.browse(:disk)
        when :insert_tape then @dialogs.browse(:tape)
        when :insert_cartridge then @dialogs.browse(:cartridge)
        when :quick_open then @dialogs.browse(:program)
        when :remove_cartridge then @dialogs.ask_remove
        else @pages.perform(action)
        end
        nil
      end

      # Saves now, asks for a name to save under, opens the saves folder,
      # or loads one of the page's quicksaves and autosaves, returning
      # :swap once a save has loaded.
      def snapshot_action(action)
        case action
        when :quicksave_now then @snapshots.quicksave
        when :save_as then @dialogs.ask_name(@snapshots.free_name(@pages.media.game_name))
        when :load_save then @dialogs.browse(:snapshot)
        else return @dialogs.load(@pages.recent(action))
        end
        nil
      end

      # Moves the focus: down from RESUME to the sections, through them,
      # where each opens as it's reached, on to Quick open, right into a
      # page, up and down it, and left out of it again.
      def move(direction)
        focus = @buttons.focus
        section = focus == :quick_open ? PAGES.size : PAGES.index(focus)
        if focus == :resume
          @buttons.focus = PAGES[@section] if %i[down left].include?(direction)
        elsif section.nil?
          move_in_page(direction)
        else
          move_in_sections(section, direction)
        end
      end

      # Up and down go through the page's rows, and left goes back to its
      # section.
      def move_in_page(direction)
        case direction
        when :up, :down then @buttons.shift(direction == :up ? -1 : 1, PAGES.size + 2)
        when :left then @buttons.focus = PAGES[@section]
        end
      end

      def move_in_sections(section, direction)
        case direction
        when :up then section.zero? ? @buttons.focus = :resume : open_section(section - 1)
        when :down then section < PAGES.size - 1 ? open_section(section + 1) : @buttons.focus = :quick_open
        when :right then @buttons.focus = @buttons.action(PAGES.size + 2) || @buttons.focus if section < PAGES.size
        end
      end

      # Opens a section, laid out at once, so keys that come before the next
      # frame find its rows.
      def open_section(index)
        @section = index
        @buttons.focus = PAGES[index]
        draw
      end

      def event(type, controls)
        event = SDL.event
        case type
        when SDL::QUIT then :quit
        when SDL::KEYDOWN then key_down(SDL.event_scancode(event), SDL.event_repeat(event))
        when SDL::KEYUP then controls.key(SDL.event_scancode(event), false) && nil
        when SDL::MOUSEMOTION then @buttons.point(SDL.event_x(event), SDL.event_y(event)) && nil
        when SDL::MOUSEBUTTONDOWN
          SDL.event_button(event) == 1 ? click(SDL.event_x(event), SDL.event_y(event)) : nil
        when MOUSEWHEEL then @dialogs.scroll(-3 * SDL.event_x(event)) && nil
        end
      end

      # A key held down repeats only the arrows.
      def key_down(scancode, repeat)
        repeat.zero? || ARROWS.key?(scancode) ? key(scancode) : nil
      end

      def draw_sections
        top = @top + 32
        SECTIONS.each_with_index do |name, index|
          @buttons.plain(@left + 6, top, name.ljust(14), PAGES[index], on: index == @section)
          top += Buttons::HEIGHT + 2
        end
      end
    end
  end
end
