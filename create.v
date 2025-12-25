import vatar
import os
import compress.gzip

fn create_archive(opts CliOptions) ! {
	if opts.files.len == 0 {
		return error('No files specified for archiving')
	}

	mut tar := vatar.open(opts.archive, 'w')!

	for file in opts.files {
		add_to_archive(mut tar, file, opts.verbose)!
	}

	tar.finalize()!

	// Get the archive data and write it to file
	archive_data := tar.get_archive_data()
	if opts.use_gzip {
		compressed_data := gzip.compress(archive_data, compression_level: 128) or {
			return error('Failed to compress archive data')
		}
		os.write_file(opts.archive, compressed_data.bytestr()) or {
			return error('Cannot write compressed archive file: ${opts.archive}')
		}
	} else {
		os.write_file(opts.archive, archive_data.bytestr()) or {
			return error('Cannot write archive file: ${opts.archive}')
		}
	}

	tar.close()

	if opts.verbose {
		println('Archive created: ${opts.archive}')
	}
}

fn add_to_archive(mut tar vatar.MTar, path string, verbose bool) ! {
	if !os.exists(path) {
		return error('File or directory does not exist: ${path}')
	}

	if os.is_dir(path) {
		// Add directory header
		dir_name := if path.ends_with('/') { path } else { path + '/' }
		tar.write_dir_header(dir_name)!

		if verbose {
			println('Adding directory: ${dir_name}')
		}

		// Recursively add contents
		files := os.ls(path) or { return error('Cannot list directory: ${path}') }
		for file in files {
			file_path := os.join_path(path, file)
			add_to_archive(mut tar, file_path, verbose)!
		}
	} else {
		// Add file
		content := os.read_file(path) or { return error('Cannot read file: ${path}') }
		size := u32(content.len)

		tar.write_file_header(path, size)!
		if size > 0 {
			tar.write_data(content.bytes(), size)!
		}

		if verbose {
			println('Adding file: ${path} (${size} bytes)')
		}
	}
}
