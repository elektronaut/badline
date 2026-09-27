# frozen_string_literal: true

require "badline/snapshot/container"
require "badline/snapshot/value"
require "badline/snapshot/registry"
require "badline/snapshot/state_writer"
require "badline/snapshot/state_reader"
require "badline/snapshot/state_restorer"
require "badline/snapshot/machine_state"
require "badline/snapshot/fields"
require "badline/snapshot/vice"
require "badline/snapshot/image"

module Badline
  # Saves and restores the whole machine in VICE's .vsf snapshot format.
  #
  # A snapshot badline writes carries VICE's modules for what both
  # emulators model (MAINCPU, C64MEM, CIA1, CIA2, SID and VIC-II), and a
  # BADLINE module with everything else badline needs to carry on exactly
  # where it stopped. VICE skips modules it doesn't know. Restoring a
  # badline snapshot uses the BADLINE module alone; a snapshot from VICE
  # restores through its modules, as far as they map, and reports the
  # modules badline doesn't take.
  #
  # Snapshots stay out of the native build: they reflect on the machine's
  # objects, which Spinel doesn't compile.
  module Snapshot
    module_function

    def save(computer, path)
      File.binwrite(path, dump(computer))
      path
    end

    def dump(computer)
      state = MachineState.section(computer)
      Container.new(Vice.export(state) + [state]).to_s
    end

    def read(path) = Image.new(Container.parse(File.binread(path)))

    # A new machine, built with the snapshot's chip models and restored
    # from it. Yields a line for each module it leaves out.
    def load(path, &)
      image = read(path)
      image.to_computer.tap { |computer| image.restore(computer, &) }
    end

    # Restores `computer` from the snapshot at `path`, and returns what it
    # applied and left out, yielding a line for each module left out.
    def restore(computer, path, &) = read(path).restore(computer, &)
  end

  class Computer
    def save_snapshot(path) = Snapshot.save(self, path)

    def restore_snapshot(path, &) = Snapshot.restore(self, path, &)
  end
end
