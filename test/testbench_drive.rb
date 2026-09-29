# frozen_string_literal: true

# Which of bin/testbench's rows run on the true drive, and with which disk.
# The drive's machine is in test/testbench_machine.rb, which the Spinel
# build shares.
module Testbench
  DOS_ROM = "dos1541.rom"

  # The true drive's rows, which run only under --drive, except for
  # drive/1541-testsuite's, which run only under --1541-testsuite.
  DRIVE_DIR = %r{\A\.\./drive/(1541-testsuite\z)?}

  def self.dos_rom? = File.exist?(File.join(Badline.rom_path, DOS_ROM))

  # A TestCase's drive: the row's disk, a mountd64 image, and the true drive
  # it runs with.
  module DriveRow
    # Whether the row runs with a true drive: a drive/ row, or one that
    # mounts a disk image.
    def drive?
      !disk.nil? || dir.match?(DRIVE_DIR)
    end

    # The true drive a row asks for: :testsuite for drive/1541-testsuite's
    # rows, :drive for the other drive rows, and nil for a cartridge row or
    # one without a drive.
    def drive_kind
      return if cartridge || !drive?

      dir.match(DRIVE_DIR)&.[](1) ? :testsuite : :drive
    end

    def disk_path
      File.expand_path(disk, dir_abs)
    end
  end
end
