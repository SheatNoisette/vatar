module vatar

/*
 * Copyright (c) 2017 rxi, 2025 SheatNoisette
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to
 * deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 * sell copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 * IN THE SOFTWARE.
 */
import os

// Raw structure offsets
const header_name_size = 100
const header_mode_size = 8
const header_owner_size = 8
const header_group_size = 8
const header_size_size = 12
const header_mtime_size = 12
const header_checksum_size = 8
const header_linkname_size = 100
const header_padding_size = 255

// Error codes
pub enum MtarError {
	success      = 0
	failure      = -1
	open_fail    = -2
	read_fail    = -3
	write_fail   = -4
	seek_fail    = -5
	bad_checksum = -6
	null_record  = -7
	not_found    = -8
}

// Type flags
pub enum MtarType {
	treg  = 48 // '0'
	tlnk  = 49 // '1'
	tsym  = 50 // '2'
	tchr  = 51 // '3'
	tblk  = 52 // '4'
	tdir  = 53 // '5'
	tfifo = 54 // '6'
}

pub struct MtarHeader {
pub mut:
	mode     u32
	owner    u32
	size     u32
	mtime    u32
	typ      u8
	name     string
	linkname string
}

struct MtarRawHeader {
mut:
	name     [header_name_size]u8
	mode     [header_mode_size]u8
	owner    [header_owner_size]u8
	group    [header_group_size]u8
	size     [header_size_size]u8
	mtime    [header_mtime_size]u8
	checksum [header_checksum_size]u8
	typ      u8
	linkname [header_linkname_size]u8
	padding  [header_padding_size]u8
}

pub struct MTar {
pub mut:
	file           os.File
	buffer         []u8
	pos            u32
	remaining_data u32
	last_header    u32
	is_read_mode   bool
}

// Error to string conversion
pub fn (err MtarError) str() string {
	return match err {
		.success { 'success' }
		.failure { 'failure' }
		.open_fail { 'could not open' }
		.read_fail { 'could not read' }
		.write_fail { 'could not write' }
		.seek_fail { 'could not seek' }
		.bad_checksum { 'bad checksum' }
		.null_record { 'null record' }
		.not_found { 'file not found' }
	}
}

// Line 44: @TODO: Remplace with built-in
fn round_up(n u32, incr u32) u32 {
	return n + (incr - n % incr) % incr
}

fn checksum(rh &MtarRawHeader) u32 {
	// vfmt off
	mut res := u32(256)
	// Sum bytes before checksum field
	for b in rh.name { res += b }
	for b in rh.mode { res += b }
	for b in rh.owner { res += b }
	for b in rh.group { res += b }
	for b in rh.size { res += b }
	for b in rh.mtime { res += b }
	// Skip checksum field
	// Sum bytes after checksum field
	res += rh.typ
	for b in rh.linkname { res += b }
	for b in rh.padding { res += b }
	// vfmt on
	return res
}

// @TODO: Use V built-in or refactor it completely instead of this boilerplate
fn cstring_to_string(arr []u8) string {
	mut i := 0
	for i < arr.len && arr[i] != 0 {
		i++
	}
	return arr[0..i].bytestr()
}

fn raw_to_header(rh &MtarRawHeader) !MtarHeader {
	// Check if record is null
	if rh.checksum[0] == 0 {
		return error_with_code(MtarError.null_record.str(), int(MtarError.null_record))
	}

	// Calculate and verify checksum
	chksum1 := checksum(rh)
	chksum_str := cstring_to_string(rh.checksum[..])
	chksum2 := chksum_str.parse_uint(8, 32) or { 0 }
	if chksum1 != chksum2 {
		return error_with_code(MtarError.bad_checksum.str(), int(MtarError.bad_checksum))
	}

	// Parse header fields
	mode_str := cstring_to_string(rh.mode[..])
	owner_str := cstring_to_string(rh.owner[..])
	size_str := cstring_to_string(rh.size[..]).trim_space()
	mtime_str := cstring_to_string(rh.mtime[..])

	return MtarHeader{
		mode:     u32(mode_str.parse_uint(8, 32) or { 0 })
		owner:    u32(owner_str.parse_uint(8, 32) or { 0 })
		size:     u32(size_str.parse_uint(8, 32) or { 0 })
		mtime:    u32(mtime_str.parse_uint(8, 32) or { 0 })
		typ:      rh.typ
		name:     cstring_to_string(rh.name[..])
		linkname: cstring_to_string(rh.linkname[..])
	}
}

fn header_to_raw(h &MtarHeader) MtarRawHeader {
	mut rh := MtarRawHeader{}

	// Convert header to raw format
	// vfmt off
	for i, b in '${h.mode:o}'.bytes() { rh.mode[i] = b }
	for i, b in '${h.owner:o}'.bytes() { rh.owner[i] = b }
	for i, b in '${h.size:o}'.bytes() { rh.size[i] = b }
	for i, b in '${h.mtime:o}'.bytes() { rh.mtime[i] = b }

	rh.typ = if h.typ != 0 { h.typ } else { u8(MtarType.treg) }

	for i, b in h.name.bytes() { rh.name[i] = b }
	for i, b in h.linkname.bytes() { rh.linkname[i] = b }

	chksum := checksum(&rh)
	chksum_str := '${chksum:06o}'
	for i in 0 .. 6 { rh.checksum[i] = chksum_str[i] }
	rh.checksum[6] = 0
	rh.checksum[7] = ` `

	return rh
	// vfmt on
}

// Public API
pub fn open(filename string, mode string) !MTar {
	mut tar := MTar{}

	// Determine read/write mode
	tar.is_read_mode = mode.contains('r')

	// Open file (only for reading)
	if tar.is_read_mode {
		tar.file = os.open(filename) or {
			return error_with_code(MtarError.open_fail.str(), int(MtarError.open_fail))
		}
	} else if mode.contains('w') {
		// For writing, initialize buffer instead of file
		tar.buffer = []u8{}
	} else {
		// Append mode not supported for memory-based writing
		return error_with_code(MtarError.open_fail.str(), int(MtarError.open_fail))
	}

	// Verify archive if in read mode
	if tar.is_read_mode {
		mut h := MtarHeader{}
		tar.read_header(mut h) or {
			tar.close()
			return err
		}
	}

	return tar
}

pub fn (mut tar MTar) close() {
	if tar.is_read_mode {
		tar.file.close()
	}
	// For write mode, buffer is kept in memory
}

pub fn (mut tar MTar) seek(pos u32) ! {
	if tar.is_read_mode {
		tar.file.seek(i64(pos), .start) or {
			return error_with_code(MtarError.seek_fail.str(), int(MtarError.seek_fail))
		}
	}
	// For write mode, seeking doesn't apply to buffer
	tar.pos = pos
}

pub fn (mut tar MTar) rewind() ! {
	tar.remaining_data = 0
	tar.last_header = 0
	tar.seek(0)!
}

pub fn (mut tar MTar) next() ! {
	// Load header
	mut h := MtarHeader{}
	tar.read_header(mut h)!

	// Seek to next record
	n := round_up(h.size, 512) + u32(sizeof(MtarRawHeader))
	tar.seek(tar.pos + n)!
}

pub fn (mut tar MTar) find(name string, mut h MtarHeader) ! {
	// Start at beginning
	tar.rewind()!

	// Iterate all files until we find the target
	mut header := MtarHeader{}
	for {
		tar.read_header(mut header) or {
			if err.code() == int(MtarError.null_record) {
				return error_with_code(MtarError.not_found.str(), int(MtarError.not_found))
			}
			return err
		}

		if header.name == name {
			h = header
			return
		}
		tar.next()!
	}
}

pub fn (mut tar MTar) read_header(mut h MtarHeader) ! {
	// Save header position
	tar.last_header = tar.pos

	// Read raw header
	mut rh := MtarRawHeader{}
	mut rh_bytes := []u8{len: int(sizeof(MtarRawHeader))}
	bytes_read := tar.file.read(mut rh_bytes) or {
		return error_with_code(MtarError.read_fail.str(), int(MtarError.read_fail))
	}

	if bytes_read != int(sizeof(MtarRawHeader)) {
		return error_with_code(MtarError.read_fail.str(), int(MtarError.read_fail))
	}

	// Manually copy bytes to struct fields, for a pure, but really pure V
	// without struct packing (@[packed]), which is not portable in other
	// backends.

	// If you have a better way to handle this, please let me know !
	// vfmt off
	// {
	mut offset := 0

	for i in 0 .. header_name_size  { rh.name[i] = rh_bytes[offset + i]        }
	offset += header_name_size

	for i in 0 .. header_mode_size  { rh.mode[i] = rh_bytes[offset + i]        }
	offset += header_mode_size

	for i in 0 .. header_owner_size { rh.owner[i] = rh_bytes[offset + i]       }
	offset += header_owner_size

	for i in 0 .. header_group_size { rh.group[i] = rh_bytes[offset + i]       }
	offset += header_group_size

	for i in 0 .. header_size_size 	{ rh.size[i] = rh_bytes[offset + i]        }
	offset += header_size_size

	for i in 0 .. header_mtime_size { rh.mtime[i] = rh_bytes[offset + i]       }
	offset += header_mtime_size

	for i in 0 .. header_checksum_size { rh.checksum[i] = rh_bytes[offset + i] }
	offset += header_checksum_size

	rh.typ = rh_bytes[offset]
	offset += 1

	for i in 0 .. header_linkname_size { rh.linkname[i] = rh_bytes[offset + i] }
	offset += header_linkname_size

	for i in 0 .. header_padding_size { rh.padding[i] = rh_bytes[offset + i]   }
	// vfmt on
	// }

	tar.pos += u32(bytes_read)

	// Seek back to start of header
	tar.seek(tar.last_header)!

	// Parse raw header
	h = raw_to_header(&rh)!
}

pub fn (mut tar MTar) read_data(ptr &u8, size u32) ! {
	// First read: get size and seek to data
	if tar.remaining_data == 0 {
		mut h := MtarHeader{}
		tar.read_header(mut h)!
		tar.seek(tar.pos + u32(sizeof(MtarRawHeader)))!
		tar.remaining_data = h.size
	}

	// Read data
	mut data_buf := unsafe { ptr.vbytes(int(size)) }
	bytes_read := tar.file.read(mut data_buf) or {
		return error_with_code(MtarError.read_fail.str(), int(MtarError.read_fail))
	}

	if bytes_read != int(size) {
		return error_with_code(MtarError.read_fail.str(), int(MtarError.read_fail))
	}

	tar.pos += size
	tar.remaining_data -= size

	// If finished reading, seek back to header
	if tar.remaining_data == 0 {
		tar.seek(tar.last_header)!
	}
}

pub fn (mut tar MTar) write_header(h &MtarHeader) ! {
	// Build raw header
	rh := header_to_raw(h)
	tar.remaining_data = h.size

	// Write header to buffer
	mut rh_bytes := []u8{len: int(sizeof(MtarRawHeader))}
	unsafe { C.memcpy(rh_bytes.data, &rh, rh_bytes.len) }
	tar.buffer << rh_bytes
	tar.pos += u32(rh_bytes.len)
}

pub fn (mut tar MTar) write_file_header(name string, size u32) ! {
	h := MtarHeader{
		name: name
		size: size
		typ:  u8(MtarType.treg)
		mode: 0o664
	}
	tar.write_header(&h)!
}

pub fn (mut tar MTar) write_dir_header(name string) ! {
	h := MtarHeader{
		name: name
		typ:  u8(MtarType.tdir)
		mode: 0o775
	}
	tar.write_header(&h)!
}

pub fn (mut tar MTar) write_data(data &u8, size u32) ! {
	// Write data to buffer
	data_buf := unsafe { data.vbytes(int(size)) }
	tar.buffer << data_buf
	tar.pos += size
	tar.remaining_data -= size

	// Write padding if finished writing all data
	if tar.remaining_data == 0 {
		tar.write_null_bytes(int(round_up(tar.pos, 512) - tar.pos))!
	}
}

pub fn (mut tar MTar) finalize() ! {
	// Write two NULL records
	tar.write_null_bytes(int(sizeof(MtarRawHeader)) * 2)!
}

pub fn (tar MTar) get_archive_data() []u8 {
	return tar.buffer.clone()
}

fn (mut tar MTar) write_null_bytes(n int) ! {
	nul := u8(0)
	for _ in 0 .. n {
		tar.buffer << nul
		tar.pos++
	}
}
