PREFIX ?= /usr/local

install: bin/be
	mkdir -p "$(PREFIX)/bin"
	cp bin/be "$(PREFIX)/bin/be"

uninstall:
	rm -f "$(PREFIX)/bin/be"

.PHONY: install uninstall
