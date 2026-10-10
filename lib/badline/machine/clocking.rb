# frozen_string_literal: true

module Badline
  module Machine
    # Running a machine from outside its own #cycle!, and the handlers that
    # wait for its KERNAL to boot. Computer, Vic20 and C128 each include it
    # and answer #cycle!, #cycles and #init_threshold, the cycle at which
    # #on_init's handlers run, and keep the handlers in @init_handlers.
    module Clocking
      # Runs `count` cycles, one #cycle! after another.
      def run_cycles(count)
        i = 0
        while i < count
          cycle!
          i += 1
        end
      end

      # Runs cycles until the block returns true or the cycle count passes
      # `limit`, checking before each cycle.
      def run_until(limit)
        cycle! until yield || @cycles > limit
      end

      # Runs the block once the KERNAL has booted (see init_threshold), or
      # now if it has.
      def on_init(&block)
        if booting?
          @init_handlers << block
        else
          block.call
        end
      end

      def inspect
        "#<#{self.class.name} cycles=#{@cycles} cpu=(#{@cpu.inspect})>"
      end

      private

      def booting?
        @cycles < init_threshold
      end

      def handle_init
        @init_handlers.each(&:call)
      end
    end
  end
end
