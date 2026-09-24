# frozen_string_literal: true

# Spinel mishandles a block passed on with an anonymous &: into a
# constructor it arrives as nil, and through a method that passes it on a
# block that reads a local is refused. Computer#install_debug_register
# does both, so the Spinel harnesses that use the debug register require
# this to hand the handler on as a value and set it after
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
