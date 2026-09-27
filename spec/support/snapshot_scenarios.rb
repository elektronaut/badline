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

  def run(computer, cycles)
    cycles.times { computer.cycle! }
    computer
  end

  def snapshot_path
    @snapshot_path ||= File.join(Dir.mktmpdir, "machine.vsf")
  end

  # Where the state of two machines differs, from their roots. A
  # variable one machine hasn't set and the other holds nil reads the same.
  def state_differences(ours, theirs)
    StateDiff.new(ours, theirs).differences
  end

  # Walks two machines' state records side by side.
  class StateDiff
    Records = Badline::Snapshot::StateReader
    Ref = Badline::Snapshot::Value::Ref

    def initialize(first, second)
      @first = Records.decode(Badline::Snapshot::StateWriter.encode(first))
      @second = Records.decode(Badline::Snapshot::StateWriter.encode(second))
      @seen = {}
      @out = []
    end

    def differences
      stack = [[0, 0, "computer"]]
      until stack.empty? || @out.length > 10
        ours, theirs, path = stack.pop
        next if @seen[[ours, theirs]]

        @seen[[ours, theirs]] = true
        compare(@first[ours], @second[theirs], path) { |refs, child| stack << [*refs.map(&:id), child] }
      end
      @out
    end

    private

    def compare(ours, theirs, path, &)
      return @out << "#{path}: #{ours.class} against #{theirs.class}" unless ours.instance_of?(theirs.class)
      return if plain?(ours) && ours == theirs

      mine = entries(ours)
      other = entries(theirs)
      return @out << "#{path}: #{mine.keys - other.keys} against #{other.keys - mine.keys}" if mine.keys != other.keys

      mine.each { |name, value| value(value, other[name], "#{path}#{name}", &) }
    end

    # An array of plain values, such as memory, compares as a whole.
    def plain?(record) = record.is_a?(Records::ArrayRecord) && record.items.none?(Ref)

    # An object's variables in name order, leaving out those that are nil.
    def entries(record)
      case record
      when Records::ArrayRecord then record.items.each_with_index.to_h { |item, i| ["[#{i}]", item] }
      when Records::HashRecord then record.pairs.to_h { |key, item| ["{#{key.inspect}}", item] }
      when Records::ProcRecord then { ".receiver" => record.receiver }.merge(named(record.locals))
      when Records::StringRecord then { "" => record.bytes }
      when Records::MethodRecord then { ".receiver" => record.receiver }
      else named(record.respond_to?(:ivars) ? record.ivars : record.fields)
      end
    end

    def named(pairs) = pairs.to_h.compact.sort_by(&:first).to_h { |name, value| [".#{name}", value] }

    def value(ours, theirs, path)
      if ours.is_a?(Ref) && theirs.is_a?(Ref)
        yield [ours, theirs], path
      elsif ours != theirs
        @out << "#{path}: #{ours.inspect[0, 60]} against #{theirs.inspect[0, 60]}"
      end
    end
  end
end
