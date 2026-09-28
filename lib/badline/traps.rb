# frozen_string_literal: true

module Badline
  module Traps
    def install_trap(addr, &handler)
      (@traps ||= {})[addr] = handler
    end

    def remove_trap(addr)
      @traps&.delete(addr)
    end

    private

    def run_traps
      @traps[@program_counter]&.call if @traps
    end
  end
end
