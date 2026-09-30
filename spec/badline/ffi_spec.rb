# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"

describe Badline::FFI do
  # Declarations against the C library, which every process has loaded.
  let(:libc) do
    Module.new do
      ffi_func :strlen, [:str], :size_t
      ffi_func :abs, [:int], :int
      ffi_func :getenv, [:str], :str
      ffi_func :memset, %i[ptr int size_t], :ptr
      ffi_func :memcpy, %i[ptr buffer_in size_t], :ptr
      ffi_func :strchr, %i[ptr int], :ptr
      ffi_func :free, [:ptr], :void
      ffi_func :isdigit, [:int], :bool
      ffi_const :ANSWER, 42
      ffi_buffer :scratch, 16
      ffi_read_u8 :byte1, 1
      ffi_read_i16 :short2, 2
      ffi_read_u32 :word4, 4
      ffi_read_i64 :quad8, 8
      ffi_read_ptr :pointer8, 8
      ffi_write_u8 :set_byte1, 1
      ffi_write_i16 :set_short2, 2
      ffi_write_u32 :set_word4, 4
      ffi_write_i64 :set_quad8, 8
      ffi_write_ptr :set_pointer8, 8
    end
  end

  describe "ffi_func" do
    it "calls the C function" do
      expect(libc.strlen("hello")).to eq(5)
    end

    it "passes signed integers" do
      expect(libc.abs(-7)).to eq(7)
    end

    it "returns a string" do
      expect(libc.getenv("PATH")).to eq(ENV.fetch("PATH"))
    end

    it "returns nil for a null string" do
      expect(libc.getenv("BADLINE_FFI_SPEC_UNSET")).to be_nil
    end

    it "returns a pointer" do
      expect(libc.strchr("abc", "c".ord)).to be_a(Fiddle::Pointer)
    end

    it "returns nil for a null pointer" do
      expect(libc.strchr("abc", "z".ord)).to be_nil
    end

    it "returns a bool as true or false" do
      expect([libc.isdigit("7".ord), libc.isdigit("x".ord)]).to eq([true, false])
    end

    it "passes nil as a null pointer" do
      expect { libc.free(nil) }.not_to raise_error
    end

    it "lets C write into a String" do
      bytes = "abcd".b
      libc.memset(bytes, "z".ord, 2)
      expect(bytes).to eq("zzcd")
    end

    it "copies what C wrote into an IO::Buffer back" do
      buffer = IO::Buffer.new(4)
      libc.memset(buffer, 0x41, 4)
      expect(buffer.get_string).to eq("AAAA")
    end

    it "hands C an IO::Buffer's contents" do
      source = IO::Buffer.for("wxyz")
      libc.memcpy(libc.scratch, source, 4)
      expect(libc.scratch[0, 4]).to eq("wxyz")
    end

    it "passes an empty IO::Buffer as a null pointer" do
      expect { libc.free(IO::Buffer.new(0)) }.not_to raise_error
    end

    it "is a method of the module" do
      expect(libc).to respond_to(:strlen)
    end
  end

  describe "ffi_const" do
    it "sets a constant" do
      expect(libc::ANSWER).to eq(42)
    end
  end

  describe "ffi_buffer" do
    it "starts zeroed" do
      expect(libc.scratch[0, 16]).to eq("\0" * 16)
    end

    it "is the same buffer every time" do
      address = libc.scratch.to_i
      expect(libc.scratch.to_i).to eq(address)
    end
  end

  describe "the accessors" do
    it "read back what they wrote at each width" do
      writes = { set_byte1: 0xfe, set_short2: -2, set_word4: 0xdead_beef, set_quad8: -3 }
      writes.each { |writer, value| libc.public_send(writer, libc.scratch, value) }
      expect(%i[byte1 short2 word4 quad8].map { |reader| libc.public_send(reader, libc.scratch) })
        .to eq(writes.values)
    end

    it "write only their own width" do
      libc.set_word4(libc.scratch, 0)
      libc.set_byte1(libc.scratch, 0x1ff)
      expect(libc.scratch[0, 4].bytes).to eq([0, 0xff, 0, 0])
    end

    it "read and write pointers" do
      libc.set_pointer8(libc.scratch, libc.scratch)
      expect(libc.pointer8(libc.scratch).to_i).to eq(libc.scratch.to_i)
    end

    it "read a null pointer as nil" do
      libc.set_pointer8(libc.scratch, nil)
      expect(libc.pointer8(libc.scratch)).to be_nil
    end
  end

  describe "ffi_lib" do
    it "raises for a library it can't find" do
      expect { Module.new { ffi_lib "badline-no-such-library" } }
        .to raise_error(described_class::Error, /can't find libbadline-no-such-library/)
    end

    it "finds functions in the library" do
      sdl = Module.new do
        ffi_lib "SDL2"
        ffi_func :SDL_GetKeyName, [:int], :str
      end
      expect(sdl.SDL_GetKeyName(0x09)).to eq("Tab")
    end
  end

  describe ".library_candidates" do
    it "looks in Homebrew's directory too" do
      expect(described_class.library_candidates("SDL2")).to include("/opt/homebrew/lib/libSDL2.dylib")
    end

    it "tries the versioned name a runtime package installs" do
      expect(described_class.library_candidates("SDL2")).to include("libSDL2-2.0.so.0")
    end
  end
end
