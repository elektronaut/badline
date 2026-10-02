# frozen_string_literal: true

module Badline
  # libSDL2 through Spinel's FFI DSL, the one binding both builds use. The
  # native build compiles the declarations, and finds the library's
  # directory (see NativeBuild.sdl2_flags). badline-ruby loads badline/ffi
  # first, which implements them over Fiddle, so only the library itself
  # has to be present.
  module SDL
    ffi_lib "SDL2"

    ffi_func :SDL_Init, [:uint32], :int
    ffi_func :SDL_Quit, [], :void
    ffi_func :SDL_GetError, [], :str
    ffi_func :SDL_SetHint, %i[str str], :int
    ffi_func :SDL_CreateWindow, %i[str int int int int uint32], :ptr
    ffi_func :SDL_SetWindowTitle, %i[ptr str], :void
    ffi_func :SDL_SetWindowSize, %i[ptr int int], :void
    ffi_func :SDL_DestroyWindow, [:ptr], :void
    ffi_func :SDL_CreateRenderer, %i[ptr int uint32], :ptr
    ffi_func :SDL_GetWindowDisplayMode, %i[ptr ptr], :int
    ffi_func :SDL_DestroyRenderer, [:ptr], :void
    ffi_func :SDL_RenderSetLogicalSize, %i[ptr int int], :int
    ffi_func :SDL_CreateTexture, %i[ptr uint32 int int int], :ptr
    ffi_func :SDL_DestroyTexture, [:ptr], :void
    ffi_func :SDL_UpdateTexture, %i[ptr ptr int_array int], :int
    ffi_func :SDL_RenderClear, [:ptr], :int
    ffi_func :SDL_SetRenderDrawColor, %i[ptr int int int int], :int
    ffi_func :SDL_RenderFillRect, %i[ptr ptr], :int
    ffi_func :SDL_RenderDrawLine, %i[ptr int int int int], :int
    ffi_func :SDL_SetTextureBlendMode, %i[ptr int], :int
    ffi_func :SDL_SetTextureColorMod, %i[ptr int int int], :int
    ffi_func :SDL_RenderCopy, %i[ptr ptr ptr ptr], :int
    ffi_func :SDL_RenderPresent, [:ptr], :void
    ffi_func :SDL_PollEvent, [:ptr], :int
    ffi_func :SDL_SetRelativeMouseMode, [:int], :int
    ffi_func :SDL_Delay, [:uint32], :void
    ffi_func :SDL_GetRendererOutputSize, %i[ptr ptr ptr], :int
    ffi_func :SDL_RenderReadPixels, %i[ptr ptr uint32 ptr int], :int
    ffi_func :SDL_CreateRGBSurfaceWithFormatFrom, %i[ptr int int int int uint32], :ptr
    ffi_func :SDL_FreeSurface, [:ptr], :void
    ffi_func :SDL_RWFromFile, %i[str str], :ptr
    ffi_func :SDL_SaveBMP_RW, %i[ptr ptr int], :int
    ffi_func :SDL_InitSubSystem, [:uint32], :int
    ffi_func :SDL_QuitSubSystem, [:uint32], :void
    ffi_func :SDL_OpenAudioDevice, %i[ptr int ptr ptr int], :uint32
    ffi_func :SDL_CloseAudioDevice, [:uint32], :void
    ffi_func :SDL_PauseAudioDevice, %i[uint32 int], :void
    ffi_func :SDL_QueueAudio, %i[uint32 buffer_in uint32], :int
    ffi_func :SDL_GetQueuedAudioSize, [:uint32], :uint32
    ffi_func :SDL_NumJoysticks, [], :int
    ffi_func :SDL_IsGameController, [:int], :int
    ffi_func :SDL_GameControllerOpen, [:int], :ptr
    ffi_func :SDL_GameControllerClose, [:ptr], :void
    ffi_func :SDL_GameControllerName, [:ptr], :str
    ffi_func :SDL_GameControllerGetButton, %i[ptr int], :uint8
    ffi_func :SDL_GameControllerGetAxis, %i[ptr int], :int16
    ffi_func :SDL_ClearQueuedAudio, [:uint32], :void
    ffi_func :SDL_PushEvent, [:ptr], :int
    ffi_func :SDL_GetKeyName, [:int], :str

    ffi_buffer :event, 56
    ffi_read_u32 :event_type, 0
    ffi_read_u8 :event_repeat, 13
    ffi_read_i32 :event_scancode, 16
    ffi_read_i32 :event_sym, 20
    ffi_read_u16 :event_mod, 24
    # SDL_MouseMotionEvent's xrel and yrel, and SDL_MouseButtonEvent's
    # button.
    ffi_read_i32 :event_xrel, 28
    ffi_read_i32 :event_yrel, 32
    ffi_read_u8 :event_button, 16
    # Where the pointer is, in a motion or button event.
    ffi_read_i32 :event_x, 20
    ffi_read_i32 :event_y, 24

    ffi_buffer :rect, 16
    ffi_write_i32 :rect_x, 0
    ffi_write_i32 :rect_y, 4
    ffi_write_i32 :rect_w, 8
    ffi_write_i32 :rect_h, 12
    # Where the drive LED goes.
    ffi_buffer :led_rect, 16
    # A glyph's place in the SID player's font and on its window.
    ffi_buffer :glyph_rect, 16
    ffi_buffer :place_rect, 16

    # SDL_DisplayMode: Uint32 format; int w, h, refresh_rate; then a pointer.
    ffi_buffer :display_mode, 24
    ffi_read_i32 :mode_refresh, 12

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
    ffi_const :INIT_GAMECONTROLLER, 0x2000
    ffi_const :INIT_EVENTS, 0x4000
    ffi_const :WINDOWPOS_CENTERED, 0x2fff0000
    ffi_const :WINDOW_RESIZABLE, 0x20
    ffi_const :RENDERER_ACCELERATED, 0x02
    ffi_const :RENDERER_PRESENTVSYNC, 0x04
    ffi_const :PIXELFORMAT_RGB888, 0x16161804
    ffi_const :PIXELFORMAT_ARGB8888, 0x16362004
    ffi_const :BLENDMODE_BLEND, 0x01
    ffi_const :TEXTUREACCESS_STREAMING, 1
    ffi_const :QUIT, 0x100
    ffi_const :KEYDOWN, 0x300
    ffi_const :KEYUP, 0x301
    ffi_const :MOUSEMOTION, 0x400
    ffi_const :MOUSEBUTTONDOWN, 0x401
    ffi_const :MOUSEBUTTONUP, 0x402
    ffi_const :KMOD_SHIFT, 0x0003
    ffi_const :CONTROLLERDEVICEADDED, 0x653
    ffi_const :CONTROLLERDEVICEREMOVED, 0x654
    ffi_const :AUDIO_S16LSB, 0x8010
    ffi_const :ALLOW_FREQUENCY_CHANGE, 0x01
    ffi_const :KEY_TAB, 0x09
    ffi_const :KEY_F10, 0x4000_0043
  end

  # The few C library calls the native front end makes.
  module LibC
    ffi_func :malloc, [:size_t], :ptr
    ffi_func :free, [:ptr], :void
    ffi_func :poll, %i[ptr size_t int], :int

    ffi_const :POLLIN, 0x01

    # struct pollfd: int fd; short events, revents.
    ffi_buffer :pollfd, 8
    ffi_write_i32 :pollfd_fd, 0
    ffi_write_i16 :pollfd_events, 4
  end
end
