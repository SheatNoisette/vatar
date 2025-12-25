import os
import flag
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
