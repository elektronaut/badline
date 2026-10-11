# frozen_string_literal: true

module Badline
  class Drive1581
    class WD1772
      # The type II commands and read address, which find an ID field on
      # the track under the head:
      #
      #   100mhE00  read sector    the data field after the ID that carries
      #                            the track and sector registers
      #   101mhEPa  write sector   a data field after that ID, deleted with a
      #   11000hE00 read address   the next ID field's six bytes, the track
      #                            going into the sector register
      #
      # The search reads each ID field as it passes. One that matches but
      # whose CRC doesn't read back sets CRC_ERROR and the search goes on;
      # after five index pulses it gives up with NOT_FOUND. Each byte of a
      # field passes in BYTE cycles and sets DRQ as it lands in the data
      # register, and LOST_DATA where the last one was still unread. With m
      # the command goes on to the next sector until one isn't found. E
      # lets the head settle first. SectorWrites writes the data field.
      module Sectors
        private

        def start_type2
          start_search(@command < 0xa0 ? READ : WRITE)
        end

        def start_read_address
          start_search(ADDRESS)
        end

        def start_search(mode)
          @type1 = false
          @status = 0
          @drq = false
          @mode = mode
          resume_type2 unless spinning_up?(SEARCH)
        end

        def resume_type2
          if @mode == WRITE && @mechanism.write_protected?
            @status |= PROTECTED
            return finish
          end
          return begin_search if @command.nobits?(SETTLE_DELAY)

          @phase = SETTLE_SEARCH
          @due = @now + SETTLE
        end

        # Searches for five index pulses from now.
        def begin_search
          index = next_index
          @deadline = index == NEVER ? NEVER : index + (4 * Mechanism::REVOLUTION)
          search
        end

        # Waits for the next ID field to pass under the head.
        def search
          @phase = SEARCH
          track = @mechanism.track
          sector = track&.next_id((@mechanism.angle(@now) / BYTE) + 1)
          @found = sector ? track.sectors.index(sector) : -1
          @id_at = sector ? byte_end(sector.id.mark) : NEVER
          @due = [@id_at, @deadline].min
        end

        def found = @mechanism.track&.sectors&.[](@found)

        def id_passed
          return not_found unless @now == @id_at

          sector = found
          return search if sector.nil?

          id = sector.id
          return id_read(id) if @mode == ADDRESS
          return search unless matches?(id.bytes)
          return crc_mismatch unless id.good

          @status &= ~CRC_ERROR
          @mode == VERIFY_TRACK ? finish : sector_found(sector)
        end

        def matches?(id)
          id[0] == @track && (@mode == VERIFY_TRACK || id[2] == @sector)
        end

        def crc_mismatch
          @status |= CRC_ERROR
          search
        end

        def not_found
          @status |= NOT_FOUND
          finish
        end

        def sector_found(sector)
          return write_sector(sector) if @mode == WRITE

          data = sector.data
          return search if data.nil? || data.mark > sector.id.mark + 7 + Track::DATA_MARK_WINDOW

          @status |= DELETED if data.deleted
          transfer(data.bytes, data.mark, READ_DATA)
          @crc_good = data.good
        end

        # Read address: the ID's bytes and its CRC.
        def id_read(id)
          @status |= CRC_ERROR unless id.good
          transfer(id.bytes + Track.field_crc(Track::ID_MARK, id.bytes), id.mark, READ_ADDRESS)
        end

        def transfer(bytes, mark, phase)
          @bytes = bytes
          @index = 0
          @phase = phase
          @due = byte_end(mark + 1)
        end

        # A byte of the field lands in the data register. After the last,
        # the CRC passes.
        def byte_read
          return field_read if @index == @bytes.length

          @status |= LOST_DATA if @drq
          @data = @bytes[@index]
          @drq = true
          @index += 1
          @due += @index == @bytes.length && @phase == READ_DATA ? 2 * BYTE : BYTE
        end

        def field_read
          if @phase == READ_ADDRESS
            @sector = @bytes[0]
          elsif !@crc_good
            @status |= CRC_ERROR
          elsif @command.anybits?(MULTIPLE)
            @sector = (@sector + 1) & 0xff
            return begin_search
          end
          finish
        end
      end
    end
  end
end
