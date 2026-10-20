# frozen_string_literal: true

require "zlib"
require "badline/snapshot/container"
require "badline/snapshot/c64_setup"
require "badline/snapshot/machine_state"
require "badline/snapshot/keyed"
require "badline/snapshot/vice"
require "badline/snapshot/image"

module Badline
  # Saves and restores the whole machine in VICE's .vsf snapshot format.
  #
  # A snapshot badline writes holds the machine as BL-* modules, one per
  # unit, each a list of keyed records (Snapshot::Keyed), which later
  # badlines read: doc/snapshot-format.md lists them. VICE skips modules it
  # doesn't know. An export for VICE puts VICE's own modules for the C64
  # ahead of them. A snapshot from VICE restores through its modules, as
  # far as they map, and reports the modules badline doesn't take.
  module Snapshot
    module_function

    def save(computer, path)
      File.binwrite(path, dump(computer))
      path
    end

    # Saves the machine's snapshot with VICE's modules ahead of its own, so
    # x64sc, xvic, xpet, xcbm2 or xcbm5x0 opens it too (Image.exported).
    def export(computer, path)
      File.binwrite(path, Image.exported(computer).to_s)
      path
    end

    # The machine's snapshot file. Saving first runs the machine on to the
    # end of the instruction its CPU is in, and of an REU transfer under
    # way (Machine::Settling), so a save advances it by a few cycles, and a
    # second save straight after runs none. A VIC-20's, a C128's, a
    # Plus/4's, a PET's or a CBM-II's snapshot is in a container named as
    # xvic, x128, xplus4, xpet or xcbm2 names its machine.
    def dump(computer) = Image.of(computer).to_s

    def read(path) = Image.new(Container.parse(File.binread(path)), name: File.basename(path))

    # A new machine, built as the snapshot's was and restored from it.
    # Yields a line for each thing it leaves out.
    def load(path, &) = read(path).load(&)

    # Restores `computer` from the snapshot at `path`, and returns what it
    # applied and left out, yielding a line for each thing left out. A
    # snapshot that fails leaves the machine as it was.
    def restore(computer, path, &) = read(path).restore(computer, &)

    # A machine's snapshots, as .vsf files and in memory. C64, Vic20, C128,
    # Plus4, PET, CBM2 and CBM2::P500 each include it.
    module Files
      def save_snapshot(path) = Snapshot.save(self, path)

      # Saves the snapshot with VICE's modules too, so VICE's emulator for
      # the machine opens it as well as badline (Image.exported).
      def export_snapshot(path) = Snapshot.export(self, path)

      def restore_snapshot(path, &) = Snapshot.restore(self, path, &)

      # The machine's snapshot in memory (Image.of), which settles it as a
      # save does.
      def snapshot = Image.of(self)

      # Takes the machine back to an Image from #snapshot. The machine keeps
      # its chips, its traps and its callbacks, and puts in the cartridge,
      # drives and tape the image has, taking out any it hasn't. Raises
      # Snapshot::FormatError for an image of a machine built another way.
      # The image goes into a new machine first, so one that fails leaves
      # this machine as it was. What it leaves out goes unsaid:
      # Image#restore returns it in a Report.
      def restore(image)
        image.restore(self) { nil }
        self
      end
    end
  end

  class C64
    include Snapshot::Files
  end

  class Vic20
    include Snapshot::Files
  end

  class C128
    include Snapshot::Files
  end

  class Plus4
    include Snapshot::Files
  end

  class PET
    include Snapshot::Files
  end

  class KIM1
    include Snapshot::Files
  end

  class CBM2
    include Snapshot::Files

    class P500
      include Snapshot::Files
    end
  end
end
