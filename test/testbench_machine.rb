# frozen_string_literal: true

# The machine-driving half of the VICE testbench runner: attaching a test's
# media, running it until it reports or its budget runs out, and reading
# back the display and the text screen. It stays inside the Ruby subset
# Spinel compiles, so bin/testbench on CRuby and spinel/testbench.rb on a
# Spinel build run each test the same way.
module Testbench
  # Boot + RUN typing overhead on top of the testlist cycle budgets, which
  # assume VICE's own autostart.
  BOOT_ALLOWANCE = 3_000_000

  # The VICE PAL viewport crop of the VIC display, matching the 384x272
  # reference screenshots (the window's Frontend::Screen crops 4 lines lower).
  WIDTH = 384
  HEIGHT = 272
  COL_OFFSET = 96
  ROW_OFFSET = 16

  # VICE's NTSC view is 247 lines from line 28, and runs on past the last
  # line of the frame into the first lines of the next.
  NTSC_HEIGHT = 247
  NTSC_ROW_OFFSET = 28

  # A power-on machine for a test with a cartridge, which starts it the way
  # VICE does, and otherwise one booted up to the cycle where an attached
  # program loads (see test/forked_boot.rb), with the CIAs and the VIC-II
  # the test asks for. expansion is the testlist option naming a memory
  # expansion fitted before power-on, a GEO-RAM, a RAM expansion or an
  # REU, or nil for none, and region names the video standard, :pal,
  # :ntsc or :ntscold.
  def self.machine(cartridge, cia_model = :mos6526, vic_model = :mos6569, expansion = nil, region: :pal)
    computer = Badline::Computer.new(cia_model:, vic_model:, ram_expansion: ram_expansion(expansion),
                                     reu: reu_size(expansion), region: region_profile(region))
    computer.attach_cartridge(Badline::Cartridge::GeoRAM.new(size: 512)) if expansion == "geo512k"
    Badline::Computer::INIT_THRESHOLD.times { computer.cycle! } unless cartridge
    computer
  end

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

  # The RAM expansion an expansion option fits, if it names one.
  def self.ram_expansion(expansion)
    case expansion
    when "plus60k" then :plus60k
    when "plus256k" then :plus256k
    end
  end

  # The size in K of the REU an expansion option plugs in, reu128k to
  # reu16m, if it names one.
  def self.reu_size(expansion)
    return unless expansion&.start_with?("reu")

    size = expansion[3, expansion.length - 4].to_i
    expansion.end_with?("m") ? size * 1024 : size
  end

  # The region profile a video standard names.
  def self.region_profile(region)
    case region
    when :ntsc then Badline::Region::NTSC
    when :ntscold then Badline::Region::NTSC_OLD
    else Badline::Region::PAL
    end
  end

  # The display cropped to the reference screenshots, as rows of palette
  # indices.
  def self.screenshot(vic)
    display = vic.display
    width = vic.width
    lines = vic.height
    top = vic.region.name == :pal ? ROW_OFFSET : NTSC_ROW_OFFSET
    height = vic.region.name == :pal ? HEIGHT : NTSC_HEIGHT
    Array.new(height) { |row| display[(((row + top) % lines) * width) + COL_OFFSET, WIDTH] }
  end

  # The text screen at $0400, 25 lines of 40 characters.
  def self.screen_text(ram)
    Array.new(25) { |row| screen_line(ram, 0x0400 + (row * 40)) }
  end

  def self.screen_line(ram, address)
    line = +""
    40.times { |col| line << screen_ascii(ram.peek(address + col)) }
    line
  end

  def self.screen_ascii(code)
    code &= 0x7f
    case code
    when 0x01..0x1a then (code + 0x60).chr
    when 0x00, 0x1b..0x1f then (code + 0x40).chr
    when 0x20..0x3f, 0x41..0x5a then code.chr
    else " "
    end
  end

  # Runs one test on a machine from Testbench.machine: attaches the
  # cartridge, if any, and the program, if any, from the test's directory
  # mounted as device 8, then runs until the test writes $D7FF or the
  # budget runs out. With mount false the program loads without the
  # directory mounted, which leaves device 8 to a true drive. With a
  # load_name it isn't injected at all: LOAD"NAME",8 and RUN go into the
  # keyboard buffer, and the true drive loads it from its disk. As VICE's
  # debug cartridge does, the run ends on the cycle of the write, so a
  # screenshot shows the display as drawn up to there. Only a screenshot
  # test reads the display, so the others run with the VIC's colours
  # unpainted.
  class Execution
    attr_reader :exit_code

    def initialize(computer, mount: true, load_name: "")
      @computer = computer
      @mount = mount
      @load_name = load_name
      @exit_code = nil
      computer.install_debug_register { |value| @exit_code = value }
    end

    def run(render, cartridge, directory, prg, budget)
      @computer.vic.render = render
      Badline::Media.attach(@computer, cartridge) if cartridge
      if @load_name.empty?
        inject(directory, prg) unless prg.empty?
      else
        @computer.type_text("load\"#{@load_name}\",8\rrun\r")
      end
      @computer.cycle! until @exit_code || @computer.cycles > budget
      @exit_code
    end

    private

    def inject(directory, prg)
      @computer.mount(Badline::Storage::HostDirectory.new(directory)) if @mount
      Badline::Media.attach(@computer, File.join(directory, prg))
    end
  end
end
