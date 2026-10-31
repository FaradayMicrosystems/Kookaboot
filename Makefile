PREFIX ?= /usr/local
LIBDIR  = $(PREFIX)/lib/kookaboot
BINDIR  = $(PREFIX)/bin
SCRIPTS = bin/kookaboot lib/*.sh tests/*.sh

.PHONY: install uninstall lint test

install:
	install -d $(DESTDIR)$(LIBDIR) $(DESTDIR)$(BINDIR)
	install -m 0644 lib/*.sh $(DESTDIR)$(LIBDIR)/
	install -m 0755 bin/kookaboot $(DESTDIR)$(BINDIR)/kookaboot

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/kookaboot
	rm -rf $(DESTDIR)$(LIBDIR)

lint:
	shellcheck -x -s bash $(SCRIPTS)

test: lint
	tests/unit.sh
