# frozen_string_literal: true

# A playable window for the Spinel build: boots the machine (or attaches
# and autostarts the media given), shows the screen in an SDL2 window at
# 50 Hz and feeds it the host keyboard. SDL2 is reached through Spinel's
# FFI, since a Spinel binary can't load ruby-sdl2, so this builds with
# Spinel only:
#
#   spinel -I lib --no-line-map --rbs spinel/sig spinel/window.rb -o tmp/spinel/window
#   tmp/spinel/window [media] [frames] [paced|unpaced] [sound] [screenshot.bmp]
#
# Tab switches the arrow keys and space, and WASD and left shift, between
# the keyboard and the joysticks: the arrows drive joystick 2 and WASD
# joystick 1, and F9 swaps them. With frames it quits after that many, and
# unpaced runs as fast as the display allows instead of holding 50 Hz.
# `sound` plays the SID, and F10 mutes it. A screenshot path saves the last
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
    ffi_func :SDL_InitSubSystem, [:uint32], :int
    ffi_func :SDL_OpenAudioDevice, %i[ptr int ptr ptr int], :uint32
    ffi_func :SDL_CloseAudioDevice, [:uint32], :void
    ffi_func :SDL_PauseAudioDevice, %i[uint32 int], :void
    ffi_func :SDL_QueueAudio, %i[uint32 int_array uint32], :int
    ffi_func :SDL_GetQueuedAudioSize, [:uint32], :uint32
    ffi_func :SDL_ClearQueuedAudio, [:uint32], :void

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

    # SDL_AudioSpec: int freq; Uint16 format; Uint8 channels, silence;
    # Uint16 samples, padding; Uint32 size; then two pointers.
    ffi_buffer :wanted, 32
    ffi_buffer :obtained, 32
    ffi_write_i32 :spec_freq, 0
    ffi_write_u16 :spec_format, 4
    ffi_write_u8 :spec_channels, 6
    ffi_write_u16 :spec_samples, 8

    ffi_const :INIT_AUDIO, 0x10
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
    ffi_const :AUDIO_S16LSB, 0x8010
    ffi_const :ALLOW_FREQUENCY_CHANGE, 0x01
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

  # The SID's output on SDL's audio queue, as mono signed 16-bit samples.
  # Once the device plays, it is the clock: #wait holds each frame until
  # the queue is down to `AHEAD`, so the machine runs at the device's pace.
  #
  # The device starts once the queue holds AHEAD. Below real time the
  # queue runs dry, and the device then stops until it holds AHEAD again,
  # so the sound stutters with silent gaps rather than slowing down. A
  # frame that would take the queue past LIMIT is dropped whole, which
  # only happens unpaced.
  #
  # Spinel hands an Array of Integers to C as 64-bit words, so each word
  # carries four samples, the first in the low quarter. A frame's samples
  # rarely come in fours, and the rest wait for the next frame.
  class Sound
    RATE = 44_100
    AHEAD = 0.08
    LIMIT = 0.25

    attr_reader :rate, :underruns, :dropped, :queued, :low, :high

    def initialize(sid, wanted)
      @sid = sid
      @device = 0
      @rate = RATE
      @started = false
      @muted = false
      @underruns = 0
      @dropped = 0
      @queued = 0
      @carry = []
      @words = Array.new(256, 0)
      reset_levels
      open_device if wanted
    end

    def on? = @device != 0

    def muted? = @muted

    def playing? = @started

    def feed
      return unless on?

      samples = @sid.drain_samples
      return if @muted || samples.empty?

      level = queued_seconds
      if level + (samples.size.to_f / @rate) > LIMIT
        @dropped += samples.size
      else
        play(samples, level)
      end
    end

    def wait
      SDL.SDL_Delay(1) while queued_seconds > AHEAD
    end

    def toggle_mute
      @muted = !@muted
      return unless @muted

      halt
      SDL.SDL_ClearQueuedAudio(@device)
    end

    def reset_levels
      @low = LIMIT
      @high = 0.0
    end

    def close
      SDL.SDL_CloseAudioDevice(@device) if on?
    end

    private

    def open_device
      unless SDL.SDL_InitSubSystem(SDL::INIT_AUDIO).zero?
        puts "No sound: #{SDL.SDL_GetError}"
        return
      end

      SDL.spec_freq(SDL.wanted, RATE)
      SDL.spec_format(SDL.wanted, SDL::AUDIO_S16LSB)
      SDL.spec_channels(SDL.wanted, 1)
      SDL.spec_samples(SDL.wanted, 512)
      @device = SDL.SDL_OpenAudioDevice(nil, 0, SDL.wanted, SDL.obtained, SDL::ALLOW_FREQUENCY_CHANGE)
      return puts "No sound: #{SDL.SDL_GetError}" unless on?

      @rate = SDL.read_i32(SDL.obtained)
      @sid.record(rate: @rate)
      puts "Sound at #{@rate} Hz"
    end

    def queued_seconds = SDL.SDL_GetQueuedAudioSize(@device) / (2.0 * @rate)

    def play(samples, level)
      @low = level if level < @low
      underrun! if @started && level.zero?
      queue(samples)
      level = queued_seconds
      @high = level if level > @high
      start if level >= AHEAD
    end

    def queue(samples)
      carry = @carry + samples
      count = carry.size / 4
      @words = Array.new(count, 0) if count > @words.size
      words = @words
      i = 0
      while i < count
        at = i * 4
        words[i] = (carry[at] & 0xffff) | ((carry[at + 1] & 0xffff) << 16) |
                   ((carry[at + 2] & 0xffff) << 32) | (carry[at + 3] * 0x1_0000_0000_0000)
        i += 1
      end
      @carry = carry[count * 4, carry.size - (count * 4)]
      SDL.SDL_QueueAudio(@device, words, count * 8)
      @queued += count * 4
    end

    def start
      return if @started

      @started = true
      SDL.SDL_PauseAudioDevice(@device, 0)
    end

    def halt
      @started = false
      SDL.SDL_PauseAudioDevice(@device, 1)
    end

    def underrun!
      @underruns += 1
      puts "Running below real time, so the sound will stutter." if @underruns == 1
      halt
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

    F9 = 66
    F10 = 67

    ARROWS = { 44 => :fire, 228 => :fire, 79 => :right, 80 => :left, 81 => :down, 82 => :up }.freeze
    WASD = { 225 => :fire, 7 => :right, 4 => :left, 22 => :down, 26 => :up }.freeze

    def self.c64_key(scancode)
      if scancode.between?(4, 29)
        LETTERS[scancode - 4]
      elsif scancode.between?(30, 39)
        DIGITS[scancode - 30]
      else
        OTHERS[scancode] || :none
      end
    end

    def self.arrows(scancode) = ARROWS[scancode] || :none

    def self.wasd(scancode) = WASD[scancode] || :none

    def self.joystick?(scancode) = ARROWS.key?(scancode) || WASD.key?(scancode)
  end

  # Routes host keys to the C64 keyboard or, in joystick mode, the arrow
  # cluster and WASD to the two joysticks. The arrows start on joystick 2.
  class Controls
    attr_reader :joystick_mode, :arrows_port

    def initialize(computer)
      @computer = computer
      @joystick_mode = false
      @arrows_port = 2
    end

    def key(scancode, down)
      if @joystick_mode && Keys.joystick?(scancode)
        joystick_key(scancode, down)
      else
        key = Keys.c64_key(scancode)
        down ? @computer.keyboard.press(key) : @computer.keyboard.release(key)
      end
    end

    def toggle_joystick_mode
      @joystick_mode = !@joystick_mode
      release_all
    end

    def swap_ports
      @arrows_port = 3 - @arrows_port
      release_all
    end

    private

    def joystick_key(scancode, down)
      direction = Keys.arrows(scancode)
      if direction == :none
        move(joystick(3 - @arrows_port), Keys.wasd(scancode), down)
      else
        move(joystick(@arrows_port), direction, down)
      end
    end

    def joystick(port) = port == 1 ? @computer.joystick1 : @computer.joystick2

    def move(joystick, direction, down)
      down ? joystick.press(direction) : joystick.release(direction)
    end

    def release_all
      Keys::ARROWS.each_key { |scancode| @computer.keyboard.release(Keys.c64_key(scancode)) }
      Keys::WASD.each_key { |scancode| @computer.keyboard.release(Keys.c64_key(scancode)) }
      Keys::ARROWS.each_value do |direction|
        @computer.joystick1.release(direction)
        @computer.joystick2.release(direction)
      end
    end
  end

  # Opens the window, then runs the machine a PAL frame at a time: poll
  # events, clock 312 lines of 63 cycles, queue the SID's samples, upload
  # the changed lines, present and wait. With sound playing, the wait lasts
  # until the audio queue is down to Sound::AHEAD; otherwise it waits out
  # the rest of the 20 ms.
  class App
    FRAME_CYCLES = 312 * 63
    FRAME_SECONDS = 0.02
    SCALE = 2
    TITLE = "Badline (Spinel)"
    STAGES = %w[events emulate audio blit present wait].freeze

    def initialize(computer, frame_limit:, paced:, screenshot:, sound:)
      @computer = computer
      @frame_limit = frame_limit
      @paced = paced
      @screenshot = screenshot
      @screen = Screen.new(computer.vic)
      @controls = Controls.new(computer)
      @spent = Array.new(STAGES.size, 0.0)
      @slowest = 0.0
      open_window
      @sound = Sound.new(computer.sid, sound)
    end

    def run
      @frames = 0
      @running = true
      @deadline = @reported = now
      @reported_samples = 0
      frame while @running
      @sound.close
      close_window
    end

    private

    def frame
      stamps = [now]
      handle_events
      stamps << now
      emulate
      stamps << now
      @sound.feed
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
      took = stamps[-2] - stamps.first
      @slowest = took if took > @slowest
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
      if [Keys::TAB, Keys::F9, Keys::F10].include?(scancode)
        handle_toggle(scancode) if down
      else
        @controls.key(scancode, down)
      end
    end

    def handle_toggle(scancode)
      if scancode == Keys::TAB
        @controls.toggle_joystick_mode
      elsif scancode == Keys::F9
        @controls.swap_ports
      else
        @sound.toggle_mute
      end
      update_title
    end

    def update_title
      title = TITLE
      title += " [JOY #{@controls.arrows_port}]" if @controls.joystick_mode
      title += " [MUTED]" if @sound.muted?
      SDL.SDL_SetWindowTitle(@window, title)
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
      return @sound.wait if @sound.playing?

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
      puts "#{fps.round(1)} fps, per frame ms: #{stages.join(' ')}, slowest work #{(@slowest * 1000).round(2)}"
      report_sound(at) if @sound.on?
      @spent = Array.new(STAGES.size, 0.0)
      @slowest = 0.0
      @reported = at
    end

    def report_sound(at)
      sound = @sound
      rate = (sound.queued - @reported_samples) / (at - @reported)
      queue = sound.high.zero? ? "empty" : "#{(sound.low * 1000).round(1)}-#{(sound.high * 1000).round(1)} ms"
      puts "  sound #{rate.round} samples/s, queue #{queue}, #{sound.underruns} underruns, #{sound.dropped} dropped"
      sound.reset_levels
      @reported_samples = sound.queued
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

media = ""
frames = 0
paced = true
screenshot = ""
sound = false
ARGV.each do |arg|
  if arg == "unpaced"
    paced = false
  elsif arg == "sound"
    sound = true
  elsif arg.end_with?(".bmp")
    screenshot = arg
  elsif arg.to_i.to_s == arg
    frames = arg.to_i
  elsif arg != "paced"
    media = arg
  end
end

computer = Badline::Computer.new
puts Badline::Media.attach(computer, media) unless media.empty?
SpinelWindow::App.new(computer, frame_limit: frames, paced:, screenshot:, sound:).run
