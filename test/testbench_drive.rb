# frozen_string_literal: true

# The true drive for bin/testbench's --drive rows. The Spinel build has no
# drive, so spinel/testbench.rb leaves this file out.
module Testbench
  DOS_ROM = "dos1541.rom"

  # The true drive's rows, which run only under --drive, except for
  # drive/1541-testsuite's, which run only under --1541-testsuite.
  DRIVE_DIR = %r{\A\.\./drive/(1541-testsuite\z)?}

  # A machine booted as Testbench.machine boots one, with a true 1541 on
  # the serial bus that boots alongside it.
  def self.drive_machine(cia_model, vic_model)
    computer = Badline::Computer.new(cia_model:, vic_model:)
    computer.attach_drive1541(Badline::Drive1541.new)
    Badline::Computer::INIT_THRESHOLD.times { computer.cycle! }
    computer
  end

  # Puts a .d64 in the true drive, formatted as the DOS would have, or a
  # .g64 as its tracks are. The drive writes back to the image at +path+.
  def self.insert_disk(computer, path)
    computer.drive1541.insert(Badline::Drive1541::Disk.open(path))
  end

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
