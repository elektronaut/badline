# frozen_string_literal: true

module Badline
  module Frontend
    # What the pause menu puts in the machine and takes out: disks, tapes
    # and cartridges, whether disks are writable, which carries over from
    # one disk to the next, and the set of the disk in device 8, which
    # PREVIOUS and NEXT step through: the .m3u or .vfl list it came from,
    # while that lists it, or the set DiskSet finds. It keeps what last went
    # wrong for the page to show.
    class MenuMedia
      attr_reader :problem

      # Takes the disk set from the command line's `media_path` when it's a
      # list, and the names of the cartridges it and `cartridges`, the
      # Plus/4's ROM images by slot (Options#cartridges), put in the first
      # machine.
      def initialize(media_path, writable, cartridges)
        @list = Media::DiskList.list?(media_path) ? media_path : ""
        @writable = writable
        @set_path = ""
        @set = []
        @problem = ""
        @computer = nil
        @command_line = cartridges.map { |slot, path| [slot, path] } + [["", media_path]]
        @names = {}
        @named = nil
      end

      def computer=(computer)
        @computer = computer
        return unless @named.nil?

        @command_line.each { |slot, path| note_cartridge(computer, path.dup, slot) }
        @named = computer
      end

      def writable? = @writable

      def disk_path = MediaSlots.disk_path(@computer)

      def inserted? = MediaSlots.disk?(@computer)

      # Puts a disk in device 8 or a tape in the datasette, `kind` :disk or
      # :tape, and says whether it went in. A list puts its first disk in.
      def insert(kind, path)
        succeeds? do
          if kind == :disk
            disk = Media::DiskList.disk(path)
            Media.insert_disk(@computer, disk, read_only: !@writable)
            list(path)
          else
            @computer.datasette.insert(Storage::TAP.new(path))
          end
        end
      end

      # Does what the Drive page's :eject_disk, :previous_disk, :next_disk,
      # :protect or :unprotect asks.
      def drive(action)
        case action
        when :eject_disk then eject_disk
        when :previous_disk then step_disk(-1)
        when :next_disk then step_disk(1)
        else writable(action == :unprotect)
        end
      end

      def eject_disk = MediaSlots.eject_disk(@computer)

      # Sets whether disks are writable, for the disk in the drive too,
      # which goes in again as the notch now says.
      def writable(writable)
        @writable = writable
        path = disk_path
        insert(:disk, path) if inserted? && !path.empty?
      end

      # The disks of the set the disk in the drive belongs to.
      def disk_set
        path = disk_path
        return [] if path.empty?

        unless @set_path == path
          listed = @list.empty? ? [] : expanded(Media::DiskList.disks(@list))
          @set = listed.include?(path) ? listed : expanded(Media::DiskSet.around(path))
          @set_path = path
        end
        @set
      end

      # Puts the disk `step` before or after this one in its set in the
      # drive, if there is one.
      def step_disk(step)
        set = disk_set
        index = set.index(disk_path)
        return if index.nil? || !(index + step).between?(0, set.size - 1)

        insert(:disk, set[index + step])
      end

      # The extensions of the cartridges the machine takes: .crt, on the
      # Plus/4 raw .bin ROM images too, and none on the PET.
      def cartridge_extensions
        extensions = Media::Extensions.of(@computer.family == :pet ? %i[none] : %i[cartridge])
        @computer.family == :plus4 ? extensions + [Media::Plus4Media::ROM_IMAGE] : extensions
      end

      # The extensions of what goes in device 8: on the PET the 8050's and
      # 8250's disk images besides the others, and no raw GCR, which only
      # a serial true drive reads.
      def disk_extensions
        return Media::Extensions.of(%i[disk ieee_disk archive disk_list]) if @computer.family == :pet

        Media::Extensions::DEVICE8
      end

      # Swaps the cartridge for the one at `path`, which power cycles the
      # machine, and says whether it went in.
      def attach_cartridge(path)
        attached = cartridge_succeeds? { Media.attach(@computer, path) }
        note_cartridge(@computer, path, "") if attached
        attached
      end

      # What a save of the machine is named after: the cartridge, the disk,
      # the tape, or BASIC, without the bracketed parts of a file's name. A
      # VIC-20's are named after its disk, or else the machine, and a
      # Plus/4's or a PET's after its disk or tape.
      def game_name
        vic20 = @computer.family == :vic20
        name = vic20 || %i[plus4 pet].include?(@computer.family) ? "" : cartridge_name
        disk = disk_path
        name = File.basename(disk, File.extname(disk)) if name.empty? && !disk.empty?
        name = tape_name if name.empty? && !vic20
        name = name.sub(/\s*[(\[].*\z/, "").strip
        return name unless name.empty?

        vic20 ? "VIC-20" : "BASIC"
      end

      def tape_name
        tape = @computer.datasette.tape
        tape.nil? ? "" : File.basename(tape.path, File.extname(tape.path))
      end

      # The name the cartridge in the expansion port gives itself, or an
      # empty one. A VIC-20 keeps its own (Vic20#cartridge_name). A Plus/4's
      # is the name of the file it came from: a .crt's own, or else the
      # file's. It names each of its
      # cartridges with a ROM in, and a slot filled from elsewhere, such as
      # a snapshot, by the slot.
      def cartridge_name
        case @computer.family
        when :plus4 then @computer.cartridge_slots.map { |slot| slot_name(slot) }.uniq.join(", ")
        when :vic20 then @computer.cartridge_name
        when :pet then ""
        else
          cartridge = @computer.address_bus.cartridge
          cartridge.nil? ? "" : cartridge.name
        end
      end

      # Takes the cartridge out with the power off.
      def remove_cartridge
        @names = {}
        MediaSlots.remove_cartridge(@computer)
      end

      # A new machine started on `path`, as the command line would, or nil
      # when it won't start.
      def start(options, path)
        computer = nil
        if Media.kind(@computer, path) == :cartridge
          cartridge_succeeds? { computer = started(options, path) }
        else
          succeeds? { computer = started(options, path) }
        end
        @problem.empty? ? computer : nil
      end

      private

      # Runs the block, keeps the media error it raised as the problem, and
      # says whether there was none.
      def succeeds?(&)
        @problem = Frontend.media_problem(&)
        @problem.empty?
      end

      # Runs the block as #succeeds? does, keeping a cartridge's chip in a
      # bank or slot the machine doesn't map as the problem too.
      def cartridge_succeeds?(&)
        @problem = Frontend.cartridge_problem(&)
        @problem.empty?
      end

      # The machine Frontend.start started on `path`, with the names of
      # the cartridges in it noted.
      def started(options, path)
        computer = Frontend.start(options, path, @writable)
        list(path)
        @names = {}
        options.cartridges.each { |slot, image| note_cartridge(computer, image.dup, slot) }
        note_cartridge(computer, path, "")
        @named = computer
        computer
      end

      def named? = @computer.equal?(@named)

      def slot_name(slot) = named? ? @names.fetch(slot, slot.upcase) : slot.upcase

      # Keeps the name of the cartridge at `path` in a Plus/4 by the slots
      # it fills, by xplus4's names, a raw image's in `slot` if it names
      # one. Other media, and other machines' cartridges, leave the names
      # alone.
      def note_cartridge(computer, path, slot)
        return unless computer.family == :plus4 && Media.kind(computer, path) == :cartridge

        name = file_name(path)
        Media::Plus4Media.cartridge_chips(path, slot: slot.empty? ? nil : slot).each do |chip|
          @names["c#{chip.bank + 1}#{chip.address < 0xc000 ? 'lo' : 'hi'}"] = name
        end
      end

      # A .crt's own name, or else the file's, without its extension.
      def file_name(path)
        name = Media::Extensions.kind(path) == :cartridge ? Storage::CRTFile.new(path, machine: nil).name : ""
        name.empty? ? File.basename(path, File.extname(path)) : name
      end

      # Keeps `path` as the list the set comes from, if it's a list.
      def list(path)
        return unless Media::DiskList.list?(path)

        @list = path
        @set_path = ""
      end

      def expanded(paths) = paths.map { |path| File.expand_path(path) }
    end
  end
end
