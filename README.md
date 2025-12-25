# VAtar

VAtar (V Atto tar) is a barebone `tar` utility written in VLang.

> This program exists for the sole purpose of making a minimal OS distribution
> whose userland is composed exclusively of VLang programs. It is deliberately
> feature-incomplete: any missing convenience is intentional. See this as
> a friendly nudge toward a cleaner, better reimplementation. Bugs may be fixed
> and some basic features may (not) be added.

The original library by RXI was translated using C2V and then extensively
modified by hand.

## Building

Ensure you have [V installed](https://vlang.io/) on your system.

```bash
$ make build
```

## Usage

```bash
$ vatar [OPTIONS] [FILES...]
```

### Operations

- `-c, --create`: Create a new archive
- `-x, --extract`: Extract files from an archive
- `-t, --list`: List the contents of an archive

### Options

- `-f, --file <ARCHIVE>`: Archive file name (required)
- `-v, --verbose`: Verbose output
- `-z, --gzip`: Compress/decompress archive with gzip
- `-C, --directory <DIR>`: Change to directory before performing operations

### Examples

Create a tar archive:
```bash
$ vatar -c -f archive.tar file1.txt file2.txt
```

Create a compressed tar archive:
```bash
$ vatar -c -z -f archive.tar.gz file1.txt file2.txt
```

Extract a tar archive:
```bash
$ vatar -x -f archive.tar
```

List contents of a tar archive:
```bash
$ vatar -t -f archive.tar
```

Extract to a specific directory:
```bash
$ vatar -x -C /tmp -f archive.tar
```

## Tests

You can run tests against the BSD version of the tar utility:

```bash
$ make test
```

## License

I would like to thank RXI for their implementation of Tar, which greatly
accelerated the development of this utility without reinventing the wheel.

Original MIT implementation is available here: https://github.com/rxi/microtar

MIT License, see `LICENSE` for more details.
