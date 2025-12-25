.PHONY: build test clean

build:
	v -prod -Wimpure-v . -o vatar

build_fast:
	v . -o vatar

test: build_fast
	v -stats test .

clean:
	rm -f vatar
