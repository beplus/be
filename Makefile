BE_PREFIX ?= /usr/local

install: bin/be
	mkdir -p "$(BE_PREFIX)/bin"
	cp bin/be "$(BE_PREFIX)/bin/be"

uninstall:
	rm -f "$(BE_PREFIX)/bin/be"

.PHONY: install uninstall
