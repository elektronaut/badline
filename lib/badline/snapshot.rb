# frozen_string_literal: true

require "zlib"
require "badline/snapshot/state"
require "badline/snapshot/setup"
require "badline/snapshot/container"
require "badline/snapshot/fields"
require "badline/snapshot/machine_state"
require "badline/snapshot/vice"
require "badline/snapshot/image"

module Badline
  # Saves and restores the whole machine in VICE's .vsf snapshot format.
  #
  # A snapshot badline writes carries VICE's modules for what both
  # emulators model, and a BADLINE module holding the State
  # Computer#snapshot takes, with everything badline needs to carry on
  # exactly where it stopped. VICE skips modules it doesn't know. Restoring
  # a badline snapshot uses the BADLINE module alone; a snapshot from VICE
  # restores through its modules, as far as they map, and reports the
  # modules badline doesn't take.
  module Snapshot
    module_function

    def save(computer, path)
      File.binwrite(path, dump(computer))
      path
    end

    def dump(computer)
      state = computer.snapshot
      Container.new(Vice.export(state) + [MachineState.section(state)]).to_s
    end

    def read(path) = Image.new(Container.parse(File.binread(path)))

    # A new machine, built as the snapshot's was and restored from it.
    # Yields a line for each thing it leaves out.
    def load(path, &) = read(path).load(&)

    # Restores `computer` from the snapshot at `path`, and returns what it
    # applied and left out, yielding a line for each thing left out. A
    # snapshot that fails leaves the machine as it was.
    def restore(computer, path, &) = read(path).restore(computer, &)
  end

  class Computer
    def save_snapshot(path) = Snapshot.save(self, path)

    def restore_snapshot(path, &) = Snapshot.restore(self, path, &)
  end
end
