# frozen_string_literal: true

require_relative "booting"

# A machine booted to BASIC's prompt, for specs that start from there.
module BootedMachine
  # The booted machine's snapshot, taken once for every spec that restores
  # it.
  def self.image
    @image ||= Booting.boot(Badline::C64.new, past: 100_000).snapshot
  end

  # A new machine at BASIC's prompt, restored from the shared snapshot.
  def booted = BootedMachine.image.load
end
