# frozen_string_literal: true

# Machines for the snapshot specs, and a comparison of two machines' whole
# state.
module SnapshotScenarios
  # bin/machine_diff's demo: a raster IRQ that changes the background
  # colour, eight sprites, a sounding SID voice and CIA 2 timer A, with a
  # main loop that counts in screen RAM. The code starts at $080D.
  DEMO_PRG = [
    0x01, 0x08, # load address
    0x0b, 0x08, 0x0a, 0x00, 0x9e, 0x32, 0x30, 0x36, 0x31, 0x00, 0x00, 0x00,
    0x78,                   # sei
    0xa9, 0x7f,             # lda #$7f
    0x8d, 0x0d, 0xdc,       # sta $dc0d
    0xad, 0x0d, 0xdc,       # lda $dc0d
    0xa9, 0x01,             # lda #$01
    0x8d, 0x1a, 0xd0,       # sta $d01a
    0xa9, 0x1b,             # lda #$1b
    0x8d, 0x11, 0xd0,       # sta $d011
    0xa9, 0x80,             # lda #$80
    0x8d, 0x12, 0xd0,       # sta $d012
    0xa9, 0x85,             # lda #<irq
    0x8d, 0x14, 0x03,       # sta $0314
    0xa9, 0x08,             # lda #>irq
    0x8d, 0x15, 0x03,       # sta $0315
    0xa2, 0x3f,             # ldx #$3f
    0x8a,                   # txa
    0x9d, 0x40, 0x03,       # sta $0340,x
    0xca,                   # dex
    0x10, 0xf9,             # bpl $0831
    0xa2, 0x0f,             # ldx #$0f
    0x8a,                   # txa
    0x0a, 0x0a, 0x0a, 0x0a, # asl x4
    0x69, 0x30,             # adc #$30
    0x9d, 0x00, 0xd0,       # sta $d000,x
    0xca,                   # dex
    0x10, 0xf3,             # bpl $083a
    0xa2, 0x07,             # ldx #$07
    0xa9, 0x0d,             # lda #$0d
    0x9d, 0xf8, 0x07,       # sta $07f8,x
    0x8a,                   # txa
    0x9d, 0x27, 0xd0,       # sta $d027,x
    0xca,                   # dex
    0x10, 0xf4,             # bpl $0849
    0xa9, 0xff,             # lda #$ff
    0x8d, 0x15, 0xd0,       # sta $d015
    0x8d, 0x1c, 0xd0,       # sta $d01c
    0xa9, 0x0f,             # lda #$0f
    0x8d, 0x18, 0xd4,       # sta $d418
    0xa9, 0x10,             # lda #$10
    0x8d, 0x01, 0xd4,       # sta $d401
    0xa9, 0x09,             # lda #$09
    0x8d, 0x05, 0xd4,       # sta $d405
    0xa9, 0x21,             # lda #$21
    0x8d, 0x04, 0xd4,       # sta $d404
    0xa9, 0xff,             # lda #$ff
    0x8d, 0x04, 0xdd,       # sta $dd04
    0x8d, 0x05, 0xdd,       # sta $dd05
    0xa9, 0x11,             # lda #$11
    0x8d, 0x0e, 0xdd,       # sta $dd0e
    0x58,                   # cli
    0xee, 0x00, 0x04,       # inc $0400
    0x4c, 0x7f, 0x08,       # jmp $087f
    0xee, 0x19, 0xd0,       # irq: inc $d019
    0xee, 0x21, 0xd0,       # inc $d021
    0xe6, 0xfb,             # inc $fb
    0xa5, 0xfb,             # lda $fb
    0x8d, 0x01, 0xd4,       # sta $d401
    0xad, 0x12, 0xd0,       # lda $d012
    0x49, 0x40,             # eor #$40
    0x8d, 0x12, 0xd0,       # sta $d012
    0x4c, 0x81, 0xea        # jmp $ea81
  ].freeze
  DEMO_START = 0x080d

  # The demo, started straight after power-on without booting: it sets
  # its own vectors, and its IRQ handler leaves through the KERNAL.
  def demo_machine(**models)
    Badline::Computer.new(**models).tap do |computer|
      computer.load_prg(DEMO_PRG)
      computer.cpu.program_counter = DEMO_START
    end
  end

  # Cycles the demo runs before a snapshot: mid-frame, past its first
  # raster IRQ, and mid-instruction.
  DEMO_CYCLES = 10_001

  # The demo run to DEMO_CYCLES and its State there, taken once for every
  # spec that restores it. Restoring is exact, which the Computer#snapshot
  # specs check against a machine run the whole way.
  def self.demo_state
    @demo_state ||= begin
      computer = Badline::Computer.new
      computer.load_prg(DEMO_PRG)
      computer.cpu.program_counter = DEMO_START
      DEMO_CYCLES.times { computer.cycle! }
      computer.snapshot
    end
  end

  # A new demo machine at DEMO_CYCLES, restored from the shared State.
  def saved_demo
    state = SnapshotScenarios.demo_state
    Badline::Computer.setup(state).build.restore(state)
  end

  def run(computer, cycles)
    cycles.times { computer.cycle! }
    computer
  end

  def snapshot_path
    @snapshot_path ||= File.join(Dir.mktmpdir, "machine.vsf")
  end

  # Where the state of two machines differs, from their roots: every
  # object reachable through instance variables, compared field by field.
  # What the host holds, and what a machine works out again, is left out
  # (StateDiff::HOST). nil and false read the same, as a restored flag
  # that was never set comes back false.
  # `host` adds instance variables to leave out, by class name.
  def state_differences(ours, theirs, host: {})
    StateDiff.new(ours, theirs, host:).differences
  end

  # A copy of `object` made through its save_state and load_state, into
  # `target`, a fresh object of the same kind.
  def round_trip(object, target)
    out = Badline::Snapshot::StateWriter.new
    object.save_state(out)
    input = Badline::Snapshot::StateReader.new(out.state)
    target.load_state(input)
    raise "load_state left part of the state unread" unless input.finished?

    target
  end

  # Walks two machines side by side.
  class StateDiff
    # Instance variables that belong to the host, not the machine, by
    # class name, and classes that belong to the host whole. The drive's
    # idle-skip bookkeeping is empty once it has settled, as saving it
    # does, and a disk image's directory is read again when it's next
    # needed.
    HOST = {
      "Badline::Computer" => %i[@init_handlers @capture_output @init_handlers_lost],
      "Badline::CPU" => %i[@traps @debug],
      "Badline::AddressBus" => %i[@debug_register @keyboard @joystick1 @joystick2 @control_ports],
      "Badline::VIC" => %i[@dirty_lines @render @open_bus @loop @debug],
      "Badline::VIC::Sequencer" => %i[@render],
      "Badline::SID" => %i[@synthesizing @decimator @samples @filter_chunk @pots],
      "Badline::CIA" => %i[@peripheral],
      "Badline::Drive1541" => %i[@owed @budget @slept @wake_at @pass_cycles @pass_instructions @record_state
                                 @record_cycles @record_instructions @record_quiet @asleep @recording
                                 @orbit_instructions],
      "Badline::Drive1541::CPU" => %i[@traps @debug],
      "Badline::Drive1541::Bus" => %i[@touched @volatile @watching],
      "Badline::Storage::D64Image" => %i[@entries], "Badline::Storage::D71Image" => %i[@entries],
      "Badline::Storage::D81Image" => %i[@entries], "Badline::Storage::T64" => %i[@entries]
    }.freeze
    HOST_CLASSES = %w[Badline::Keyboard Badline::Joystick Badline::ControlPorts Badline::ChroutTrap
                      Badline::DebugRegister Badline::Input::Mouse1351 Badline::Input::Paddles].freeze
    LIMIT = 20

    def initialize(first, second, host: {})
      @host = HOST.merge(host) { |_name, ours, theirs| ours + theirs }
      @first = first
      @second = second
      @seen = {}.compare_by_identity
      @out = []
    end

    def differences
      stack = [[@first, @second, "computer"]]
      until stack.empty? || @out.length >= LIMIT
        ours, theirs, path = stack.pop
        compare(ours, theirs, path) { |pair| stack << pair }
      end
      @out
    end

    private

    def compare(ours, theirs, path, &)
      return if same_plain?(ours, theirs)

      mismatch = mismatch(ours, theirs, path)
      return @out << mismatch if mismatch
      return if skipped?(ours) || visited?(ours, theirs)
      return children(ours, theirs, path, &) unless table?(ours)

      @out << "#{path}: tables differ" unless ours == theirs
    end

    def mismatch(ours, theirs, path)
      return "#{path}: #{brief(ours)} against #{brief(theirs)}" if plain?(ours) || plain?(theirs)

      "#{path}: #{ours.class} against #{theirs.class}" unless ours.instance_of?(theirs.class)
    end

    def children(ours, theirs, path, &)
      case ours
      when Array then array(ours, theirs, path, &)
      when Hash then hash(ours, theirs, path, &)
      when String, Data then @out << "#{path}: #{ours.class} differs" unless ours == theirs
      else
        (ivars(ours) | ivars(theirs)).sort.each do |name|
          yield [ours.instance_variable_get(name), theirs.instance_variable_get(name), "#{path}.#{name}"]
        end
      end
    end

    def array(ours, theirs, path)
      return @out << "#{path}: #{ours.length} items against #{theirs.length}" unless ours.length == theirs.length
      return if ours == theirs
      return @out << "#{path}: #{first_difference(ours, theirs)}" if ours.all? { |item| plain?(item) } &&
                                                                     ours != theirs

      ours.each_index { |i| yield [ours[i], theirs[i], "#{path}[#{i}]"] }
    end

    def hash(ours, theirs, path)
      return @out << "#{path}: keys #{ours.keys.inspect[0, 60]} against #{theirs.keys.inspect[0, 60]}" \
        unless ours.keys == theirs.keys

      ours.each_key { |key| yield [ours[key], theirs[key], "#{path}{#{key.inspect}}"] }
    end

    def first_difference(ours, theirs)
      i = ours.each_index.find { |index| ours[index] != theirs[index] }
      "differs from [#{i}]: #{ours[i].inspect} against #{theirs[i].inspect}"
    end

    # A frozen table, compared as a whole.
    def table?(object) = object.frozen? && (object.is_a?(Array) || object.is_a?(Hash))

    def ivars(object) = object.instance_variables - @host.fetch(object.class.name, [])

    def skipped?(object)
      object.is_a?(Proc) || object.is_a?(Method) || object.is_a?(Fiber) || object.is_a?(Module) ||
        HOST_CLASSES.include?(object.class.name)
    end

    def visited?(ours, theirs)
      return true if @seen[ours].equal?(theirs)

      @seen[ours] = theirs
      false
    end

    def plain?(value)
      value.nil? || value == true || value == false || value.is_a?(Numeric) || value.is_a?(Symbol) ||
        value.is_a?(Range)
    end

    def same_plain?(ours, theirs)
      return true if (ours.nil? || ours == false) && (theirs.nil? || theirs == false)

      plain?(ours) && plain?(theirs) && ours == theirs && ours.instance_of?(theirs.class)
    end

    def brief(value) = value.inspect[0, 60]
  end
end
