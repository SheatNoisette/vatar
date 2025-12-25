import os

fn is_gzip_file(filename string) !bool {
	file_data := os.read_bytes(filename) or { return error('Cannot read file: ${filename}') }
	// Gzip files start with 0x1F 0x8B
	return file_data.len >= 2 && file_data[0] == 0x1F && file_data[1] == 0x8B
}
