# frozen_string_literal: true

# A playable window for the Spinel build: boots the machine (or attaches
# and autostarts the media given), shows the screen in an SDL2 window at
# 50 Hz and feeds it the host keyboard. SDL2 is reached through Spinel's
# FFI, since a Spinel binary can't load ruby-sdl2, so this builds with
# Spinel only:
#
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/window.rb -o tmp/spinel/window
#   tmp/spinel/window [media] [frames] [paced|unpaced] [screenshot.bmp]
#
# Tab switches the arrow keys and space between the keyboard and joystick 2.
# With frames it quits after that many, and unpaced runs as fast as the
# display allows instead of holding 50 Hz. A screenshot path saves the last
# frame as the renderer drew it. Every 50 frames it prints the frame rate
# and where the frame time went.

require "badline/version"
require "badline/integer_helper"
require "badline/addressable"
require "badline/memory"
require "badline/color_memory"
require "badline/rom"
require "badline/address_bus"
require "badline/instruction"
require "badline/instruction_set"
require "badline/status"
require "badline/keyboard"
require "badline/joystick"
require "badline/control_ports"
require "badline/input"
require "badline/cycleable"
require "badline/datasette"
require "badline/time_of_day"
require "badline/cia"
require "badline/sid"
require "badline/debug_register"
require "badline/interrupts"
require "badline/traps"
require "badline/cpu"
require "badline/vic"
require "badline/keyboard_buffer"
require "badline/computer"
require "badline/storage"
require "badline/cartridge"
require "badline/kernal_trap"
require "badline/chrout_trap"
require "badline/media"

module SpinelWindow
  module SDL
    ffi_lib "SDL2"
    ffi_cflags "-L/opt/homebrew/lib"
    ffi_cflags "-L/usr/local/lib"

    ffi_func :SDL_Init, [:uint32], :int
    ffi_func :SDL_Quit, [], :void
    ffi_func :SDL_GetError, [], :str
    ffi_func :SDL_SetHint, %i[str str], :int
    ffi_func :SDL_CreateWindow, %i[str int int int int uint32], :ptr
    ffi_func :SDL_SetWindowTitle, %i[ptr str], :void
    ffi_func :SDL_DestroyWindow, [:ptr], :void
    ffi_func :SDL_CreateRenderer, %i[ptr int uint32], :ptr
    ffi_func :SDL_DestroyRenderer, [:ptr], :void
    ffi_func :SDL_RenderSetLogicalSize, %i[ptr int int], :int
    ffi_func :SDL_CreateTexture, %i[ptr uint32 int int int], :ptr
    ffi_func :SDL_DestroyTexture, [:ptr], :void
    ffi_func :SDL_UpdateTexture, %i[ptr ptr int_array int], :int
    ffi_func :SDL_RenderClear, [:ptr], :int
    ffi_func :SDL_RenderCopy, %i[ptr ptr ptr ptr], :int
    ffi_func :SDL_RenderPresent, [:ptr], :void
    ffi_func :SDL_PollEvent, [:ptr], :int
    ffi_func :SDL_Delay, [:uint32], :void
    ffi_func :SDL_GetRendererOutputSize, %i[ptr ptr ptr], :int
    ffi_func :SDL_RenderReadPixels, %i[ptr ptr uint32 ptr int], :int
    ffi_func :SDL_CreateRGBSurfaceWithFormatFrom, %i[ptr int int int int uint32], :ptr
    ffi_func :SDL_FreeSurface, [:ptr], :void
    ffi_func :SDL_RWFromFile, %i[str str], :ptr
    ffi_func :SDL_SaveBMP_RW, %i[ptr ptr int], :int

    ffi_buffer :event, 56
    ffi_read_u32 :event_type, 0
    ffi_read_u8 :event_repeat, 13
    ffi_read_i32 :event_scancode, 16

    ffi_buffer :rect, 16
    ffi_write_i32 :rect_w, 8
    ffi_write_i32 :rect_h, 12

    ffi_buffer :output_w, 4
    ffi_buffer :output_h, 4
    ffi_read_i32 :read_i32, 0

    ffi_const :INIT_VIDEO, 0x20
    ffi_const :INIT_EVENTS, 0x4000
    ffi_const :WINDOWPOS_CENTERED, 0x2fff0000
    ffi_const :WINDOW_RESIZABLE, 0x20
    ffi_const :RENDERER_ACCELERATED, 0x02
    ffi_const :PIXELFORMAT_RGB888, 0x16161804
    ffi_const :TEXTUREACCESS_STREAMING, 1
    ffi_const :QUIT, 0x100
    ffi_const :KEYDOWN, 0x300
    ffi_const :KEYUP, 0x301
  end

  module LibC
    ffi_func :malloc, [:size_t], :ptr
    ffi_func :free, [:ptr], :void
  end

  # The visible part of the VIC's display, as GUI::ScreenPane crops it,
  # repacked for an SDL texture in XRGB8888. Spinel hands an Array of
  # Integers to C as 64-bit words, so each word carries two neighbouring
  # pixels, the left one in the low half.
  class Screen
    WIDTH = 384
    HEIGHT = 272
    COL_OFFSET = 96
    ROW_OFFSET = 20
    ROW_BYTES = WIDTH * 4
    ROW_WORDS = WIDTH / 2

    COLORS = [
      0x000000, 0xffffff, 0x924a40, 0x84c5cc,
      0x9351b6, 0x72b14b, 0x483aaa, 0xd5df7c,
      0x675200, 0xc33d00, 0xc18178, 0x606060,
      0x8a8a8a, 0xb3ec91, 0x867ade, 0xb3b3b3
    ].freeze

    PAIRS = Array.new(256) { |pair| COLORS[pair & 0x0f] | (COLORS[pair >> 4] << 32) }.freeze

    attr_reader :pixels

    def initialize(vic)
      @vic = vic
      @pixels = Array.new(HEIGHT * ROW_WORDS, 0)
    end

    # Repacks only the lines the VIC has changed since the last frame.
    def update
      dirty = @vic.dirty_lines
      row = 0
      while row < HEIGHT
        pack_row(row) if dirty[row + ROW_OFFSET]
        row += 1
      end
      @vic.clear_dirty_lines!
    end

    private

    def pack_row(row)
      display = @vic.display
      pixels = @pixels
      from = ((row + ROW_OFFSET) * @vic.width) + COL_OFFSET
      to = row * ROW_WORDS
      last = to + ROW_WORDS
      while to < last
        pixels[to] = PAIRS[(display[from] & 0x0f) | ((display[from + 1] & 0x0f) << 4)]
        from += 2
        to += 1
      end
    end
  end

  # SDL scancodes follow key positions on a US layout. They map onto the C64
  # keys GUI::KeyMap and GUI::JoyMap give the same keys by name.
  module Keys
    TAB = 43

    LETTERS = %i[a b c d e f g h i j k l m n o p q r s t u v w x y z].freeze
    DIGITS = %i[1 2 3 4 5 6 7 8 9 0].freeze

    OTHERS = {
      40 => :return, 41 => :run_stop, 42 => :delete, 44 => :space,
      45 => :-, 46 => :"=", 49 => :"@", 51 => :";", 52 => :":",
      54 => :",", 55 => :".", 56 => :/,
      58 => :f1, 60 => :f3, 62 => :f5, 64 => :f7,
      74 => :clr_home, 77 => :£, 79 => :cursor_h, 80 => :left,
      81 => :cursor_v, 82 => :up, 85 => :*, 87 => :+,
      224 => :control, 225 => :lshift, 226 => :cbm, 229 => :rshift
    }.freeze

    JOYSTICK = { 44 => :fire, 228 => :fire, 79 => :right, 80 => :left, 81 => :down, 82 => :up }.freeze

    def self.c64_key(scancode)
      if scancode.between?(4, 29)
        LETTERS[scancode - 4]
      elsif scancode.between?(30, 39)
        DIGITS[scancode - 30]
      else
        OTHERS[scancode] || :none
      end
    end

    def self.direction(scancode) = JOYSTICK[scancode] || :none
  end

  # Opens the window, then runs the machine a PAL frame at a time: poll
  # events, clock 312 lines of 63 cycles, upload the changed lines, present
  # and wait out the rest of the 20 ms.
  class App
    FRAME_CYCLES = 312 * 63
    FRAME_SECONDS = 0.02
    SCALE = 2
    TITLE = "Badline (Spinel)"
    STAGES = %w[events emulate blit present wait].freeze

    def initialize(computer, frame_limit:, paced:, screenshot:)
      @computer = computer
      @frame_limit = frame_limit
      @paced = paced
      @screenshot = screenshot
      @screen = Screen.new(computer.vic)
      @joystick_mode = false
      @spent = Array.new(STAGES.size, 0.0)
      open_window
    end

    def run
      @frames = 0
      @running = true
      @deadline = @reported = now
      frame while @running
      close_window
    end

    private

    def frame
      stamps = [now]
      handle_events
      stamps << now
      emulate
      stamps << now
      upload
      stamps << now
      draw
      stamps << now
      pace
      stamps << now
      finish_frame(stamps)
    end

    def finish_frame(stamps)
      STAGES.size.times { |stage| @spent[stage] += stamps[stage + 1] - stamps[stage] }
      @frames += 1
      @running = false if @frames == @frame_limit
      report(stamps.last) if (@frames % 50).zero?
    end

    def open_window
      abort "SDL_Init: #{SDL.SDL_GetError}" unless SDL.SDL_Init(SDL::INIT_VIDEO | SDL::INIT_EVENTS).zero?

      SDL.SDL_SetHint("SDL_RENDER_SCALE_QUALITY", "0")
      @window = SDL.SDL_CreateWindow(
        TITLE, SDL::WINDOWPOS_CENTERED, SDL::WINDOWPOS_CENTERED,
        Screen::WIDTH * SCALE, Screen::HEIGHT * SCALE, SDL::WINDOW_RESIZABLE
      )
      @renderer = SDL.SDL_CreateRenderer(@window, -1, SDL::RENDERER_ACCELERATED)
      SDL.SDL_RenderSetLogicalSize(@renderer, Screen::WIDTH, Screen::HEIGHT)
      create_texture
    end

    def create_texture
      @texture = SDL.SDL_CreateTexture(
        @renderer, SDL::PIXELFORMAT_RGB888, SDL::TEXTUREACCESS_STREAMING, Screen::WIDTH, Screen::HEIGHT
      )
      SDL.rect_w(SDL.rect, Screen::WIDTH)
      SDL.rect_h(SDL.rect, Screen::HEIGHT)
    end

    def close_window
      SDL.SDL_DestroyTexture(@texture)
      SDL.SDL_DestroyRenderer(@renderer)
      SDL.SDL_DestroyWindow(@window)
      SDL.SDL_Quit
    end

    def handle_events
      while SDL.SDL_PollEvent(SDL.event) != 0
        type = SDL.event_type(SDL.event)
        if type == SDL::QUIT
          @running = false
        elsif [SDL::KEYDOWN, SDL::KEYUP].include?(type) && SDL.event_repeat(SDL.event).zero?
          handle_key(SDL.event_scancode(SDL.event), type == SDL::KEYDOWN)
        end
      end
    end

    def handle_key(scancode, down)
      if scancode == Keys::TAB
        toggle_joystick if down
        return
      end

      direction = @joystick_mode ? Keys.direction(scancode) : :none
      if direction == :none
        key = Keys.c64_key(scancode)
        down ? @computer.keyboard.press(key) : @computer.keyboard.release(key)
      else
        down ? @computer.joystick2.press(direction) : @computer.joystick2.release(direction)
      end
    end

    def toggle_joystick
      @joystick_mode = !@joystick_mode
      Keys::JOYSTICK.each_value { |direction| @computer.joystick2.release(direction) }
      Keys::JOYSTICK.each_key { |scancode| @computer.keyboard.release(Keys.c64_key(scancode)) }
      SDL.SDL_SetWindowTitle(@window, @joystick_mode ? "#{TITLE} [JOY]" : TITLE)
    end

    def emulate
      computer = @computer
      i = 0
      while i < FRAME_CYCLES
        computer.cycle!
        i += 1
      end
    end

    def upload
      @screen.update
      SDL.SDL_UpdateTexture(@texture, SDL.rect, @screen.pixels, Screen::ROW_BYTES)
    end

    def draw
      SDL.SDL_RenderClear(@renderer)
      SDL.SDL_RenderCopy(@renderer, @texture, SDL.rect, SDL.rect)
      write_screenshot if @screenshot != "" && @frames + 1 == @frame_limit
      SDL.SDL_RenderPresent(@renderer)
    end

    def pace
      return unless @paced

      @deadline += FRAME_SECONDS
      started = now
      @deadline = started if @deadline < started - FRAME_SECONDS
      left = @deadline - started
      SDL.SDL_Delay((left * 1000).to_i) if left > 0.001
      nil while now < @deadline
    end

    def report(at)
      fps = 50 / (at - @reported)
      stages = STAGES.each_with_index.map { |name, stage| "#{name} #{(@spent[stage] * 20).round(2)}" }
      puts "#{fps.round(1)} fps, per frame ms: #{stages.join(' ')}"
      @spent = Array.new(STAGES.size, 0.0)
      @reported = at
    end

    # Reads back what the renderer drew, before it is presented, and saves
    # it as a BMP.
    def write_screenshot
      SDL.SDL_GetRendererOutputSize(@renderer, SDL.output_w, SDL.output_h)
      width = SDL.read_i32(SDL.output_w)
      height = SDL.read_i32(SDL.output_h)
      data = LibC.malloc(width * height * 4)
      SDL.SDL_RenderReadPixels(@renderer, nil, SDL::PIXELFORMAT_RGB888, data, width * 4)
      surface = SDL.SDL_CreateRGBSurfaceWithFormatFrom(data, width, height, 32, width * 4, SDL::PIXELFORMAT_RGB888)
      SDL.SDL_SaveBMP_RW(surface, SDL.SDL_RWFromFile(@screenshot, "wb"), 1)
      SDL.SDL_FreeSurface(surface)
      LibC.free(data)
      puts "wrote #{@screenshot}, #{width}x#{height}"
    end

    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end

computer = Badline::Computer.new
media = ARGV[0] || ""
puts Badline::Media.attach(computer, media) unless media.empty?
SpinelWindow::App.new(
  computer,
  frame_limit: ARGV[1] ? ARGV[1].to_i : 0,
  paced: ARGV[2] != "unpaced",
  screenshot: ARGV[3] || ""
).run
