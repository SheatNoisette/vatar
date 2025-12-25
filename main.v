import os
import flag
import compress.gzip
import time
import vatar
import v.vmod

struct CliOptions {
mut:
	command   string
	archive   string
	files     []string
	verbose   bool
	use_gzip  bool
	directory string
}

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

fn is_gzip_file(filename string) !bool {
	file_data := os.read_bytes(filename) or { return error('Cannot read file: ${filename}') }
	// Gzip files start with 0x1F 0x8B
	return file_data.len >= 2 && file_data[0] == 0x1F && file_data[1] == 0x8B
}

fn extract_archive(opts CliOptions) ! {
	// Read the archive file
	archive_data := os.read_bytes(opts.archive) or {
		return error('Cannot read archive file: ${opts.archive}')
	}

	// Change to extraction directory if specified
	if opts.directory != '' {
		os.chdir(opts.directory) or { return error('Error changing directory: ${err}') }
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

fn main() {
	vm := vmod.decode(@VMOD_FILE) or { panic(err) }
	mut fp := flag.new_flag_parser(os.args)
	fp.version('v${vm.version}')
	fp.application('${vm.name}')
	fp.description('${vm.description}')
	fp.skip_executable()

	// Tar-style flags
	create := fp.bool('create', `c`, false, 'create a new archive')
	extract := fp.bool('extract', `x`, false, 'extract files from an archive')
	list := fp.bool('list', `t`, false, '(tell) list the contents of an archive')
	verbose := fp.bool('verbose', `v`, false, 'verbosely list files processed')
	use_gzip := fp.bool('gzip', `z`, false, 'compress/decompress archive with gzip')
	file := fp.string('file', `f`, '', 'archive file name')
	directory := fp.string('directory', `C`, '', 'change to directory DIR')

	args := fp.finalize() or {
		eprintln('Error: ${err}')
		println(fp.usage())
		return
	}

	// Validate operation flags
	mut operation_count := 0
	if create {
		operation_count++
	}
	if extract {
		operation_count++
	}
	if list {
		operation_count++
	}

	if operation_count != 1 {
		println('Error: You must specify exactly one of -c (create), -x (extract), or -t (list)')
		println(fp.usage())
		return
	}

	if file == '' {
		println('Error: Archive file must be specified with -f')
		println(fp.usage())
		return
	}

	if create {
		files := args
		if files.len == 0 {
			println('Error: No files specified for archiving')
			println('Usage: vatar -c -f <archive> [files...]')
			return
		}
		opts := CliOptions{
			command:  'create'
			archive:  file
			files:    files
			verbose:  verbose
			use_gzip: use_gzip
		}
		create_archive(opts) or { println('Error: ${err}') }
	} else if extract {
		if args.len > 0 {
			println('Error: Unexpected arguments for extract operation')
			println('Usage: vatar -x -f <archive>')
			return
		}
		opts := CliOptions{
			command:   'extract'
			archive:   file
			files:     []
			verbose:   verbose
			use_gzip:  use_gzip
			directory: directory
		}
		extract_archive(opts) or { println('Error: ${err}') }
	} else if list {
		if args.len > 0 {
			println('Error: Unexpected argumnts for list operation')
			println('Usage: vatar -t -f <archive>')
			return
		}
		opts := CliOptions{
			command:   'list'
			archive:   file
			files:     []
			verbose:   verbose
			use_gzip:  use_gzip
			directory: directory
		}
		list_archive(opts) or { println('Error: ${err}') }
	}
}
