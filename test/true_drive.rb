# frozen_string_literal: true

# The true 1541 bin/machine_diff plugs in with --true-drive, and the
# drive's part in its checkpoint lines.
module TrueDrive
  DIRECTORY = "load\"$\",8\rlist\r"

  module_function

  # A Computer, with a true drive plugged in if the options ask.
  def computer(options)
    computer = Badline::Computer.new
    return computer unless options[:true_drive]

    drive = Badline::Drive1541.new
    drive.idle_skip = options[:idle_skip] if drive.respond_to?(:idle_skip=)
    computer.attach_drive1541(drive)
    computer
  end

  # Puts a D64 in the true drive, and types the directory load. Returns
  # nil for other media, or without a true drive.
  def insert(computer, path, options)
    return unless options[:true_drive] && path.downcase.end_with?(".d64")

    computer.drive1541.insert(Badline::Drive1541::Disk.from_d64(Badline::Storage::D64Image.new(path)))
    text = options[:text] == "print 6*7\r" ? DIRECTORY : options[:text]
    computer.on_init { computer.type_text(text) }
    true
  end

  # The true drive's CPU, cycle counts, VIAs, head and RAM, or nil without
  # one.
  def digest(computer)
    drive = computer.respond_to?(:drive1541) && computer.drive1541
    return unless drive

    cpu = drive.cpu
    values = [drive.cycles, cpu.program_counter, cpu.a, cpu.x, cpu.y, cpu.stack_pointer, cpu.p, cpu.cycles,
              cpu.instructions, drive.mechanism.half_track, drive.mechanism.motor_on? ? 1 : 0]
    [drive.via1, drive.via2].each do |via|
      values.push(via.timer1, via.timer1_latch, via.timer2, via.interrupt_flags, via.interrupt_enable, via.acr,
                  via.pcr, via.port_a_output, via.port_b_output)
    end
    Badline::Checkpoint.fnv1a(values + drive.ram.read(0, 0x0800))
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
