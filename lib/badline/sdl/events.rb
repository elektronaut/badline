# frozen_string_literal: true

module Badline
  module SDL
    KEY_TAB = 0x09
    KEY_F10 = 0x4000_0043
    KMOD_SHIFT = 0x0003

    # The events the front end handles. SDL_Event is a 56-byte union, read
    # here at the offsets its keyboard, mouse and controller members use.
    Quit = Data.define
    KeyDown = Data.define(:sym, :mod)
    KeyUp = Data.define(:sym, :mod)
    MouseMotion = Data.define(:xrel, :yrel)
    MouseButton = Data.define(:button, :pressed)
    ControllerDevice = Data.define

    EVENT_SIZE = 56

    # The next event the front end handles, skipping the others, or nil once
    # the queue is empty.
    def self.poll_event
      buffer = (@event ||= Fiddle::Pointer.malloc(EVENT_SIZE, Fiddle::RUBY_FREE))
      while PollEvent.call(buffer) == 1
        event = decode(buffer.to_str(EVENT_SIZE))
        return event if event
      end
      nil
    end

    def self.decode(bytes)
      case bytes.unpack1("L")
      when 0x100 then Quit.new
      when 0x300 then KeyDown.new(*bytes.unpack("lS", offset: 20))
      when 0x301 then KeyUp.new(*bytes.unpack("lS", offset: 20))
      when 0x400 then MouseMotion.new(*bytes.unpack("l2", offset: 28))
      when 0x401, 0x402 then MouseButton.new(bytes.getbyte(16), bytes.getbyte(17) == 1)
      when 0x653..0x655 then ControllerDevice.new
      end
    end

    def self.key_name(sym) = GetKeyName.call(sym)
  end
end
