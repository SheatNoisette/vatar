import os
import time

const vatar_exe = 'vatar'

const test_archive = 'test.tar'
const test_bin_file = 'unreal_tournament.uc'
const test_readme_file = 'readme.md'
const test_little_file = 'little_file.txt'

// -----------------------------------------------------------------------------
// Utils

fn setup_test_files(test_dir string) ! {
	// Create test text file
	os.write_file(os.join_path(test_dir, test_readme_file), '# Setup\nThis is a serious readme for serious people.\n\r\n')!

	// Create test binary file (small)
	mut binary_content := []u8{len: 64}
	for i in 0 .. 64 {
		binary_content[i] = u8(i)
	}
	os.write_file(os.join_path(test_dir, test_bin_file), binary_content.bytestr())!

	// Create subdirectory with file
	sub_dir := os.join_path(test_dir, 'subdir')
	os.mkdir(sub_dir)!
	os.write_file(os.join_path(sub_dir, test_little_file), 'Text file content\n')!
}

fn cleanup_test_dir(test_dir string) {
	os.rmdir_all(test_dir) or {}
}

fn run_vatar(vatar_path string, args []string) os.Result {
	cmd_str := vatar_path + ' ' + args.join(' ')
	return os.execute(cmd_str)
}

// -----------------------------------------------------------------------------
// TestyMcTestface

fn test_create_archive() {
	test_dir := os.join_path(os.temp_dir(), 'vatar_test_create_${time.now().unix()}')
	os.mkdir(test_dir) or { panic(err) }
	defer { cleanup_test_dir(test_dir) }

	vatar_path := os.join_path(os.getwd(), vatar_exe)

	setup_test_files(test_dir)!

	archive_path := os.join_path(test_dir, test_archive)

	// Create archive with vatar
	result := run_vatar(vatar_path, ['-c', '-f', archive_path, os.join_path(test_dir, test_readme_file),
		os.join_path(test_dir, test_bin_file), os.join_path(test_dir, 'subdir')])
	assert result.exit_code == 0, 'vatar create failed'

	// Verify archive exists
	assert os.exists(archive_path), 'Archive not created'

	// Extract with BSD tar and compare
	extract_dir := os.join_path(test_dir, 'extract_vatar')
	os.mkdir(extract_dir)!

	tar_result := os.execute('tar -xf ${archive_path} -C ${extract_dir}')
	assert tar_result.exit_code == 0, 'BSD tar extract failed'

	// Compare contents
	original_txt := os.read_file(os.join_path(test_dir, test_readme_file))!
	extracted_txt := os.read_file('${extract_dir}${os.join_path(test_dir, test_readme_file)}')!
	assert original_txt == extracted_txt, 'Text file content mismatch'

	original_bin := os.read_bytes(os.join_path(test_dir, test_bin_file))!
	extracted_bin := os.read_bytes('${extract_dir}${os.join_path(test_dir, test_bin_file)}')!
	assert original_bin == extracted_bin, 'Binary file content mismatch'

	original_sub := os.read_file(os.join_path(test_dir, 'subdir', test_little_file))!
	extracted_sub := os.read_file('${extract_dir}${os.join_path(test_dir, 'subdir', test_little_file)}')!
	assert original_sub == extracted_sub, 'Subdir file content mismatch'
}

fn test_extract_archive() {
	test_dir := os.join_path(os.temp_dir(), 'vatar_test_extract_${time.now().unix()}')
	os.mkdir(test_dir) or { panic(err) }
	defer { cleanup_test_dir(test_dir) }

	vatar_path := os.join_path(os.getwd(), vatar_exe)

	setup_test_files(test_dir)!

	// Create archive with BSD tar
	archive_path := os.join_path(test_dir, 'test_bsd.tar')
	tar_create := os.execute('tar -C ${test_dir} -cf ${archive_path} readme.md unreal_tournament.uc subdir')
	assert tar_create.exit_code == 0, 'BSD tar create failed'

	// Extract with vatar
	extract_dir := os.join_path(test_dir, 'extract_vatar')
	os.mkdir(extract_dir)!

	vatar_result := run_vatar(vatar_path, ['-x', '-f', archive_path, '-C', extract_dir])
	assert vatar_result.exit_code == 0, 'vatar extract failed'

	// Compare contents
	original_txt := os.read_file(os.join_path(test_dir, test_readme_file))!
	extracted_txt := os.read_file(os.join_path(extract_dir, test_readme_file))!
	assert original_txt == extracted_txt, 'Text file content mismatch'

	original_bin := os.read_bytes(os.join_path(test_dir, test_bin_file))!
	extracted_bin := os.read_bytes(os.join_path(extract_dir, test_bin_file))!
	assert original_bin == extracted_bin, 'Binary file content mismatch'

	original_sub := os.read_file(os.join_path(test_dir, 'subdir', test_little_file))!
	extracted_sub := os.read_file(os.join_path(extract_dir, 'subdir', test_little_file))!
	assert original_sub == extracted_sub, 'Subdir file content mismatch'
}

fn test_list_archive() {
	test_dir := os.join_path(os.temp_dir(), 'vatar_test_list_${time.now().unix()}')
	os.mkdir(test_dir) or { panic(err) }
	defer { cleanup_test_dir(test_dir) }

	vatar_path := os.join_path(os.getwd(), vatar_exe)

	setup_test_files(test_dir)!

	archive_path := os.join_path(test_dir, test_archive)

	// Create archive with vatar
	create_result := run_vatar(vatar_path, ['-c', '-f', archive_path,
		os.join_path(test_dir, test_readme_file), os.join_path(test_dir, test_bin_file),
		os.join_path(test_dir, 'subdir')])
	assert create_result.exit_code == 0, 'vatar create failed'

	// List with vatar
	vatar_list := run_vatar(vatar_path, ['-t', '-f', archive_path])
	assert vatar_list.exit_code == 0, 'vatar list failed'

	// List with BSD tar
	bsd_list := os.execute('tar -tf ${archive_path}')
	assert bsd_list.exit_code == 0, 'BSD tar list failed'

	// Compare outputs (normalize by sorting lines)
	vatar_lines := vatar_list.output.split('\n').filter(it != '').sorted()
	bsd_lines := bsd_list.output.split('\n').filter(it != '').sorted()

	assert vatar_lines.len == bsd_lines.len, 'Different number of files listed'

	for i in 0 .. vatar_lines.len {
		vatar_name := vatar_lines[i]
		bsd_name := bsd_lines[i]
		assert vatar_name == bsd_name, 'File name mismatch: ${vatar_name} vs ${bsd_name}'
	}
}

fn test_gzip_create() {
	test_dir := os.join_path(os.temp_dir(), 'vatar_test_gzip_create_${time.now().unix()}')
	os.mkdir(test_dir) or { panic(err) }
	defer { cleanup_test_dir(test_dir) }

	vatar_path := os.join_path(os.getwd(), vatar_exe)

	setup_test_files(test_dir)!

	archive_path := os.join_path(test_dir, 'test.tar.gz')

	// Create compressed archive with vatar
	result := run_vatar(vatar_path, ['-c', '-z', '-f', archive_path,
		os.join_path(test_dir, test_readme_file), os.join_path(test_dir, test_bin_file),
		os.join_path(test_dir, 'subdir')])
	assert result.exit_code == 0, 'vatar gzip create failed'

	// Verify archive exists
	assert os.exists(archive_path), 'Compressed archive not created'

	// Extract with BSD tar and compare
	extract_dir := os.join_path(test_dir, 'extract_vatar_gzip')
	os.mkdir(extract_dir)!

	tar_result := os.execute('tar -xzf ${archive_path} -C ${extract_dir}')
	assert tar_result.exit_code == 0, 'BSD tar extract gzip failed'

	// Compare contents
	original_txt := os.read_file(os.join_path(test_dir, test_readme_file))!
	extracted_txt := os.read_file('${extract_dir}${os.join_path(test_dir, test_readme_file)}')!
	assert original_txt == extracted_txt, 'Gzip text file content mismatch'
}

fn test_gzip_extract() {
	test_dir := os.join_path(os.temp_dir(), 'vatar_test_gzip_extract_${time.now().unix()}')
	os.mkdir(test_dir) or { panic(err) }
	defer { cleanup_test_dir(test_dir) }

	vatar_path := os.join_path(os.getwd(), vatar_exe)

	setup_test_files(test_dir)!

	// Create compressed archive with BSD tar
	archive_path := os.join_path(test_dir, 'test_bsd.tar.gz')
	tar_create := os.execute('tar -C ${test_dir} -czf ${archive_path} readme.md unreal_tournament.uc subdir')
	assert tar_create.exit_code == 0, 'BSD tar gzip create failed'

	// Extract with vatar
	extract_dir := os.join_path(test_dir, 'extract_vatar_gzip')
	os.mkdir(extract_dir)!

	vatar_result := run_vatar(vatar_path, ['-x', '-z', '-f', archive_path, '-C', extract_dir])
	assert vatar_result.exit_code == 0, 'vatar gzip extract failed'

	// Compare contents
	original_txt := os.read_file(os.join_path(test_dir, test_readme_file))!
	extracted_txt := os.read_file(os.join_path(extract_dir, test_readme_file))!
	assert original_txt == extracted_txt, 'Gzip extract text file content mismatch'
}

fn test_directory_archiving() {
	test_dir := os.join_path(os.temp_dir(), 'vatar_test_dir_${time.now().unix()}')
	os.mkdir(test_dir) or { panic(err) }
	defer { cleanup_test_dir(test_dir) }

	vatar_path := os.join_path(os.getwd(), vatar_exe)

	// Nested directories
	os.mkdir(os.join_path(test_dir, 'rankin'))!
	os.mkdir(os.join_path(test_dir, 'rankin', 'torlan'))!

	// Few levels of Unreal Tournament :)
	os.write_file(os.join_path(test_dir, 'root.txt'), 'root file')!
	os.write_file(os.join_path(test_dir, 'rankin', 'rankin.txt'), 'rankin file')!
	os.write_file(os.join_path(test_dir, 'rankin', 'torlan', 'torlan.txt'), 'torlan file')!

	archive_path := os.join_path(test_dir, 'dir_test.tar')

	// Archive entire directory with vatar
	result := run_vatar(vatar_path, ['-c', '-f', archive_path, os.join_path(test_dir, 'rankin')])
	assert result.exit_code == 0, 'vatar directory archive failed'

	// Extract with BSD tar
	extract_dir := os.join_path(test_dir, 'extract_dir')
	os.mkdir(extract_dir)!

	tar_result := os.execute('tar -xf ${archive_path} -C ${extract_dir}')
	assert tar_result.exit_code == 0, 'BSD tar directory extract failed'

	// Verify directory structure and files
	assert os.exists('${extract_dir}${os.join_path(test_dir, 'rankin')}'), 'rankin dir not extracted'
	assert os.exists('${extract_dir}${os.join_path(test_dir, 'rankin', 'torlan')}'), 'torlan dir not extracted'

	original_l1 := os.read_file(os.join_path(test_dir, 'rankin', 'rankin.txt'))!
	extracted_l1 := os.read_file('${extract_dir}${os.join_path(test_dir, 'rankin', 'rankin.txt')}')!
	assert original_l1 == extracted_l1, 'rankin file mismatch'

	original_l2 := os.read_file(os.join_path(test_dir, 'rankin', 'torlan', 'torlan.txt'))!
	extracted_l2 := os.read_file('${extract_dir}${os.join_path(test_dir, 'rankin', 'torlan',
		'torlan.txt')}')!
	assert original_l2 == extracted_l2, 'torlan file mismatch'
}

fn test_long_filename() {
	test_dir := os.join_path(os.temp_dir(), 'vatar_test_long_filename_${time.now().unix()}')
	os.mkdir(test_dir) or { panic(err) }
	defer { cleanup_test_dir(test_dir) }

	vatar_path := os.join_path(os.getwd(), vatar_exe)

	// Create a file with a long prefix and short filename to test prefix field usage,
	// so we'll create a deeply nested directory structure to make a long prefix
	// because we are a naughty archiver
	mut nested_dir := test_dir
	for i in 0 .. 10 {
		nested_dir = os.join_path(nested_dir, 'level${i}')
		os.mkdir(nested_dir)!
	}
	short_name := 'short.txt'
	long_name_path := os.join_path(nested_dir, short_name)
	content := 'This is content of a file with a very long path that should be preserved correctly through archiving and extraction.'
	os.write_file(long_name_path, content)!

	archive_path := os.join_path(test_dir, 'long_name_test.tar')

	old_cwd := os.getwd()
	os.chdir(test_dir) or { panic(err) }
	defer { os.chdir(old_cwd) or {} }

	archive_name := 'long_name_test.tar'
	result := run_vatar(vatar_path, ['-c', '-f', archive_name, 'level0'])
	assert result.exit_code == 0, 'vatar create with long filename failed'

	// Verify archive exists
	assert os.exists(archive_name), 'Archive with long filename not created'

	// Extract with vatar
	extract_dir_name := 'extract_long_name'
	os.mkdir(extract_dir_name)!

	vatar_result := run_vatar(vatar_path, ['-x', '-f', archive_name, '-C', extract_dir_name])
	assert vatar_result.exit_code == 0, 'vatar extract with long filename failed'

	// The archived path (relative now)
	archived_path := 'level0/level1/level2/level3/level4/level5/level6/level7/level8/level9/short.txt'

	// Verify extraction worked
	extract_dir := os.join_path(test_dir, extract_dir_name)
	extracted_file_path := os.join_path(extract_dir, archived_path)
	assert os.exists(extracted_file_path), 'Extracted file with long path not found'
	extracted_content := os.read_file(extracted_file_path)!
	assert extracted_content == content, 'Content mismtch for long path file'

	// Also verify the directory structure too...
	assert os.exists(os.join_path(extract_dir, 'level0/level1/level2/level3/level4/level5/level6/level7/level8/level9')), 'Nested directories not extracted'
}
