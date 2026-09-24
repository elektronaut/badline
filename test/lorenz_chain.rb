# frozen_string_literal: true

# The machine-driving half of the Wolfgang Lorenz runner: mounting the
# suite's disks, injecting keys and telling when the chain has ended. It
# stays inside the Ruby subset Spinel compiles, so bin/lorenz on CRuby and
# spinel/lorenz.rb on a Spinel build drive the chain the same way.
# Lorenz::Run in test/lorenz_run.rb turns what it records into rows.
module Lorenz
  GETIN_LIMIT = 100
  GETIN_GRACE = -200
  HANG_CYCLES = 90_000_000
  BATCH = 10_000

  AUTOSTART = %(lO"*",8,1\rrun\r)
  COMPLETION = "test suite 2.15+ completed - ok"
  NEXT_DISK = "Disk4.d64"

  def self.open_image(path)
    case File.extname(path).downcase
    when ".d64" then Badline::Storage::D64Image.new(path)
    when ".d71" then Badline::Storage::D71Image.new(path)
    when ".d81" then Badline::Storage::D81Image.new(path)
    else raise "#{path} is not a mountable disk image"
    end
  end

  # Mounts the image, with the disk the chain carries on from once it runs
  # out as a spare, and types the LOAD that starts the chain, or resumes it
  # at start_test.
  def self.mount(computer, path, capture, start_test)
    disk = Disk.new(open_image(path), capture)
    spare = spare_path(path)
    disk.spare(spare, open_image(spare)) if spare
    computer.mount(disk)
    computer.type_text(start_test ? %(lO"#{start_test}",8\rrun\r) : AUTOSTART)
    disk
  end

  # The disk the chain carries on from once the image runs out, if it is
  # beside the image.
  def self.spare_path(path)
    spare = File.join(File.dirname(path), NEXT_DISK)
    spare if File.exist?(spare) && File.expand_path(spare) != File.expand_path(path)
  end

  # The mounted disk image, noting which program the suite loads next and
  # how much transcript had been printed by then. A program the image
  # lacks is looked for on the spare, which replaces the image before the
  # LOAD is served when it holds it.
  class Disk
    attr_reader :names, :offsets

    def initialize(image, capture)
      @image = image
      @capture = capture
      @names = []
      @offsets = []
      @spare_path = nil
      @spare = nil
    end

    def spare(path, image)
      @spare_path = path
      @spare = image
    end

    def read_file(name, type: :prg)
      @names << name.downcase
      @offsets << @capture.output.length
      @image.read_file(name, type:) || swap_for(name)
    end

    def read_error(name, type: :prg) = @image.read_error(name, type:)
    def first_block(name, type: :prg) = @image.first_block(name, type:)
    def last_block(name, type: :prg) = @image.last_block(name, type:)
    def read_file_at(track, sector) = @image.read_file_at(track, sector)
    def read_block(track, sector) = @image.read_block(track, sector)
    def block_error(track, sector) = @image.block_error(track, sector)
    def header_block = @image.header_block
    def new_entry_block = @image.new_entry_block

    private

    def swap_for(name)
      spare = @spare
      return unless spare&.read_file(name)

      warn "#{name.downcase} is not on the mounted image, swapping in #{@spare_path}"
      @image = spare
      @spare = nil
      spare.read_file(name)
    end
  end

  # Drives the machine a batch of cycles at a time until the suite
  # finishes, hangs or drops to BASIC. When a failed test halts waiting for
  # a keypress (detected by GETIN polling), a space is injected to
  # continue: STOP would exit some tests to BASIC and kill the chain.
  class Chain
    attr_reader :result, :key_offsets

    def initialize(computer, capture, disk, max_cycles, stop_after = nil)
      @computer = computer
      @capture = capture
      @disk = disk
      @max_cycles = max_cycles
      @stop_after = stop_after&.downcase
      @result = nil
      @printed = 0
      @last_progress = 0
      @getin_hits = 0
      @key_offsets = []
      computer.cpu.install_trap(0xffe4) { @getin_hits += 1 }
    end

    def keys_sent = @key_offsets.length

    # Runs a batch and returns what the machine printed in it.
    def step
      BATCH.times { @computer.cycle! }
      text = take_output
      classify
      send_key if @getin_hits > GETIN_LIMIT
      text
    end

    private

    def take_output
      out = @capture.output
      return "" unless out.length > @printed

      text = out[@printed, out.length - @printed]
      @printed = out.length
      @last_progress = @computer.cycles
      @getin_hits = 0
      text
    end

    def classify
      out = @capture.output
      @result = "completed" if out.include?(COMPLETION)
      if @computer.cycles - @last_progress > HANG_CYCLES
        @result = out.rstrip.end_with?("ready.") ? "ready-prompt" : "hung"
      end
      @result = "timeout" if @computer.cycles > @max_cycles
      @result = "stopped" if @result.nil? && moved_past_stop?
    end

    def moved_past_stop?
      stop_after = @stop_after
      return false unless stop_after

      index = @disk.names.index(stop_after)
      !index.nil? && index < @disk.names.length - 1
    end

    # The offset the injection lands at is what attributes it to a segment:
    # the resumed chain prints on past it, so the test that stopped is the
    # one whose slice still covers it.
    def send_key
      @key_offsets << @capture.output.length
      warn "[#{@computer.cycles}] test halted waiting for key, sending space (##{keys_sent})"
      @computer.type_text(" ")
      @getin_hits = GETIN_GRACE
    end
  end
end
