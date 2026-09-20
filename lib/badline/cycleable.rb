# frozen_string_literal: true

module Badline
  class Cycleable
    attr_reader :cycles

    def initialize
      @loop = Fiber.new { loop { main_loop } }
      @cycles = 0
      @pending_write = false
    end

    def cycle!
      @loop.resume
      nil
    end

    def pending_write? = @pending_write

    private

    def cycle(write: false)
      @pending_write = write
      Fiber.yield
      poll
      result = yield if block_given?
      @cycles += 1
      @pending_write = false
      result
    end

    def poll; end

    def main_loop
      Fiber.yield
    end
  end
end
