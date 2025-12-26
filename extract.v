import vatar
import os
import compress.gzip
import time

fn extract_archive(opts CliOptions) ! {
	// Read the archive file
	archive_data := os.read_bytes(opts.archive) or {
		return error('Cannot read archive file: ${opts.archive}')
	}

	// Check if file is gzip compressed (either by flag or auto-detection)
	is_gzip := if opts.use_gzip {
		true
	} else {
		is_gzip_file(opts.archive) or { false }
	}

	mut tar_data := archive_data.clone()
	if is_gzip {
		tar_data = gzip.decompress(archive_data) or {
			return error('Failed to decompress archive data')
		}
	}

	// Change to extraction directory if specified
	if opts.directory != '' {
		os.chdir(opts.directory) or { return error('Error changing directory: ${err}') }
	}

	// Create a temporary file with the tar data
	temp_dir := os.temp_dir()
	temp_file := '${temp_dir}/vatar_extract_${os.getpid()}_${time.now().unix()}.tmp'
	defer { os.rm(temp_file) or { eprintln('Warning: Could not delet the temporary file!') } }

	os.write_file(temp_file, tar_data.bytestr()) or {
		return error('Cannot write temporary tar file')
	}

	mut tar := vatar.open(temp_file, 'r')!
	defer { tar.close() }

	for {
		mut header := vatar.MtarHeader{}
		tar.read_header(mut header) or {
			if err.code() == int(vatar.MtarError.null_record) {
				// End of archive, goodbye!
				break
			}
			return err
		}

		if header.typ == u8(vatar.MtarType.tdir) {
			// Create directory
			os.mkdir_all(header.name.trim_right('/')) or {
				return error('Cannot create directory: ${header.name}')
			}
			if opts.verbose {
				println('Extracting directory: ${header.name}')
			}
		} else if header.typ == u8(vatar.MtarType.treg) {
			// Seek to data position
			tar.seek(tar.pos + u32(sizeof(vatar.MtarRawHeader)))!
			tar.remaining_data = header.size

			// Extract file
			mut data := []u8{len: int(header.size)}
			if header.size > 0 {
				tar.read_data(mut data, header.size)!
			}

			// Ensure parent directory exists
			parent_dir := os.dir(header.name)
			if parent_dir != '' && parent_dir != '.' {
				os.mkdir_all(parent_dir) or {
					return error('Cannot create parent directory: ${parent_dir}')
				}
			}

			os.write_file(header.name, data.bytestr()) or {
				return error('Cannot write file: ${header.name}')
			}

			if opts.verbose {
				println('Extracting file: ${header.name} (${header.size} bytes)')
			}
		}

		// Move to next entry
		tar.next() or {
			if err.code() == int(vatar.MtarError.null_record) {
				break
			}
			return err
		}
	}

	if opts.verbose {
		println('Archive extracted: ${opts.archive}')
	}
}
