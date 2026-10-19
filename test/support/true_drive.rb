# frozen_string_literal: true

# The true drive bin/machine_diff plugs in with --true-drive, and the
# drive's part in its checkpoint lines.
module TrueDrive
  DIRECTORY = "load\"$\",8\rlist\r"

  module_function

  # A C64, with a true drive plugged in if the options ask.
  def computer(options)
    computer = Badline::C64.new
    return computer unless options[:true_drive]

    drive = Badline::Drives::Model1541.new
    drive.idle_skip = options[:idle_skip] if drive.respond_to?(:idle_skip=)
    computer.attach_drive1541(drive)
    computer
  end

  # The images the PET's and the CBM-II's IEEE-488 drives read.
  IEEE_IMAGES = %w[.d64 .d80 .d82].freeze

  # Puts a D64 in the true drive, or on the PET and the CBM-II a D64, D80
  # or D82 in the drive that reads it (Media::TrueDrive.insert), and
  # types the directory load. Returns nil for other media, or without a
  # true drive. The image opens with the options in options[:media][:disk].
  def insert(computer, path, options)
    return unless options[:true_drive]

    disk = options[:media].fetch(:disk, {})
    extension = File.extname(path).downcase
    if Badline::Media::TrueDrive::IEEE_FAMILIES.include?(computer.family)
      return unless IEEE_IMAGES.include?(extension)

      Badline::Media::TrueDrive.insert(computer, path, read_only: disk.fetch(:read_only, false))
    else
      return unless extension == ".d64"

      computer.drive1541.insert(Badline::Drives::Model1541::Disk.from_d64(Badline::Storage::D64Image.new(path, **disk)))
    end
    text = options[:text] == "print 6*7\r" ? DIRECTORY : options[:text]
    computer.on_init { computer.type_text(text) }
    true
  end

  # The true drive's CPU, cycle counts, head, chips and the first 2K of its
  # RAM, or nil without one, as the machine's true_drive picks it. The
  # 1541, 1571 and 2031 add their VIAs, the 1571 and 1581 their CIA, and
  # the 1551 its port and TIAs. An 8050 or 8250 gives unit_digest.
  def digest(computer)
    drive = computer.respond_to?(:true_drive) ? computer.true_drive : nil
    return unless drive
    return unit_digest(drive) if %w[8050 8250].include?(drive.model_name)

    values = [drive.cycles, *cpu_values(drive.cpu), *head_values(drive), *chip_values(drive)]
    Badline::Support::Checkpoint.fnv1a(values + drive.ram.read(0, 0x0800))
  end

  # The 8050 or 8250's processors, heads and motors, its RIOTs, VIA and
  # 6530, and its common RAM.
  def unit_digest(unit)
    mechanism = unit.mechanism
    values = [unit.cycles, *cpu_values(unit.ip_cpu), *cpu_values(unit.fdc_cpu), *mechanism.cylinders,
              mechanism.motor_on?(0) ? 1 : 0, mechanism.motor_on?(1) ? 1 : 0]
    [unit.data_riot, unit.control_riot, unit.rriot].each { |riot| values.push(riot.timer.counter, *riot.idle_state) }
    via = unit.via
    values.push(via.timer1, via.timer1_latch, via.timer2, via.interrupt_flags, via.interrupt_enable, via.acr, via.pcr,
                via.port_a_output, via.port_b_output)
    Badline::Support::Checkpoint.fnv1a(values.map { |value| value == true ? 1 : value || 0 } +
                                       unit.common.read(0, 0x1000))
  end

  def cpu_values(cpu)
    [cpu.program_counter, cpu.a, cpu.x, cpu.y, cpu.stack_pointer, cpu.p, cpu.cycles, cpu.instructions]
  end

  def head_values(drive)
    mechanism = drive.mechanism
    place = drive.model_name == "1581" ? mechanism.cylinder : mechanism.half_track
    [place, mechanism.motor_on? ? 1 : 0]
  end

  def chip_values(drive)
    return tia_values(drive) if drive.model_name == "1551"

    values = []
    unless drive.model_name == "1581"
      [drive.via1, drive.via2].each do |via|
        values.push(via.timer1, via.timer1_latch, via.timer2, via.interrupt_flags, via.interrupt_enable, via.acr,
                    via.pcr, via.port_a_output, via.port_b_output)
      end
    end
    values.concat(Badline::Support::Checkpoint.cia_state(drive.cia)) unless %w[1541 2031].include?(drive.model_name)
    values
  end

  # The 1551's port and both TIAs, the drive's and its interface's.
  def tia_values(drive)
    port = drive.port
    [port.ddr, port.data, *[drive.tia, drive.host_tia].flat_map { |tia| tia.ports + tia.directions + tia.inputs }]
  end

  # A checkpoint's line, with the drive's digest when there is one.
  def line(checkpoint, drive)
    drive ? "#{checkpoint} #{field(drive)}" : checkpoint.to_s
  end

  def field(digest) = "drive=#{digest ? digest.to_s(16).rjust(8, '0') : 'none'}"

  # The line for +checkpoint+, and our drive digest +ours+, after
  # checking the digest against the one in the other run's +line+. Exits
  # when they differ.
  def compare(checkpoint, ours, line)
    theirs = line[/ drive=(\h+)/, 1]&.to_i(16)
    return line(checkpoint, ours) if ours == theirs

    puts "  this run: #{field(ours)}", "  against:  #{field(theirs)}",
         "First difference at cycle #{checkpoint.cycle}: drive"
    exit 1
  end

  # The options that reach the run on another revision.
  def flags(options)
    [*("--true-drive" if options[:true_drive]), *("--no-idle-skip" unless options[:idle_skip])]
  end
end
