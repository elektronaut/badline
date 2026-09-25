# frozen_string_literal: true

# Spinel refuses a block that reads a local when it is passed on with an
# anonymous & into a constructor, and loses the block's writes to one.
# Computer#install_debug_register passes its block on that way, and
# SIDTests.exit_code hands it one that reads a local, so sidtests.rb
# requires this to hand the handler on as a value and set it after
# DebugRegister.new instead.
module Badline
  class DebugRegister
    attr_writer :handler
  end

  class AddressBus
    def install_debug_handler(handler)
      register = DebugRegister.new(@sid)
      register.handler = handler
      @debug_register = register
      update_overlays!
    end
  end

  class Computer
    def install_debug_register(&handler)
      address_bus.install_debug_handler(handler)
    end
  end
end
