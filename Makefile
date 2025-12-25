.PHONY: build test clean

build:
	v -prod -W -Wimpure-v -autofree . -o vatar

build_cross:
	v -cross -W -Wimpure-v -autofree -gc none  -os macos . -o vatar-aarch64-darwin
	v -cross -W -Wimpure-v -autofree -gc none  -os linux . -o vatar-amd64-linux

build_fast:
	v . -o vatar

test: build_fast
	v -Wimpure-v -autofree -stats test .

clean:
	rm -f vatar
