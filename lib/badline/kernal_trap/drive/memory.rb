# frozen_string_literal: true

module Badline
  module KernalTrap
    class Drive
      # The drive's 2K of RAM, as M-W and M-R reach it, with the job queue
      # that runs a read job written into it: a job code for each of five
      # buffers at $00, their track and sector pairs from $06, and the
      # buffers from $0300. A job code is replaced by its result, 1 for
      # success or an error table code: the DOS error less 18, or 15 for
      # DRIVE NOT READY.
      class Memory
        SIZE = 0x800
        JOBS = 5
        READ_JOB = 0x80
        JOB_OK = 1
        HEADER_NOT_FOUND = 20

        # The RAM itself, which buffer channels read and write in place.
        attr_reader :ram

        # The disk that read jobs read from.
        attr_writer :storage

        # Buffer n takes the page $0300 + n * $100.
        def self.buffer_address(number)
          0x300 + (number * BLOCK_SIZE)
        end

        def initialize
          @storage = nil
          @ram = Array.new(SIZE, 0)
        end

        # Writes past the RAM are dropped, since the rest of the address
        # space is I/O and ROM.
        def write(address, bytes)
          bytes.each.with_index(address) do |byte, target|
            @ram[target] = byte if target < SIZE
          end
          run_jobs
        end

        # Only the RAM reads back.
        def read(address, count)
          Array.new(count) { |i| @ram.fetch(address + i, 0) }
        end

        def clear
          @ram.fill(0)
        end

        # The first block of the file the last LOAD read, which the DOS
        # keeps at $7E and $026F, or nil while the track there is 0.
        def last_program
          [@ram[0x7e], @ram[0x26f]] unless @ram[0x7e].zero?
        end

        def last_program=(block)
          @ram[0x7e], @ram[0x26f] = block
        end

        private

        def run_jobs
          JOBS.times do |job|
            next unless @ram[job] == READ_JOB

            track, sector = @ram[6 + (job * 2), 2]
            @ram[job] = read_job(Memory.buffer_address(job), track, sector)
          end
        end

        def read_job(buffer, track, sector)
          data = @storage.respond_to?(:read_block) && @storage.read_block(track, sector)
          return job_result(HEADER_NOT_FOUND) unless data

          @ram[buffer, BLOCK_SIZE] = data
          job_result(@storage.block_error(track, sector))
        end

        def job_result(error)
          return JOB_OK unless error

          error == DRIVE_NOT_READY ? 15 : error - 18
        end
      end
    end
  end
end
