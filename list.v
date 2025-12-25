import vatar
import os
import time
import compress.gzip

fn list_archive(opts CliOptions) ! {
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

	// Heh, create a temporary file with the tar data for now
	temp_dir := os.temp_dir()
	temp_file := '${temp_dir}/vatar_list_${os.getpid()}_${time.now().unix()}.tmp'
	defer { os.rm(temp_file) or {} }

	os.write_file(temp_file, tar_data.bytestr()) or {
		return error('Cannot write temporary tar file')
	}

	mut tar := vatar.open(temp_file, 'r')!
	defer { tar.close() }

	mut total_files := 0
	mut total_size := u32(0)

	for {
		mut header := vatar.MtarHeader{}
		tar.read_header(mut header) or {
			if err.code() == int(vatar.MtarError.null_record) {
				break // End of archive
			}
			return err
		}

		if header.typ == u8(vatar.MtarType.tdir) {
			println(header.name)
		} else if header.typ == u8(vatar.MtarType.treg) {
			println(header.name)
			total_files++
			total_size += header.size
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
		println('')
		println('${total_files} files, ${total_size} bytes total')
	}
}
