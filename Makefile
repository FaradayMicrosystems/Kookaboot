PREFIX ?= /usr/local
LIBDIR  = $(PREFIX)/lib/kookaboot
BINDIR  = $(PREFIX)/bin
SCRIPTS = bin/kookaboot bin/kookaboot-menu lib/*.sh tests/*.sh iso/build.sh

.PHONY: install uninstall lint test iso

install:
	install -d $(DESTDIR)$(LIBDIR) $(DESTDIR)$(BINDIR)
	install -m 0644 lib/*.sh $(DESTDIR)$(LIBDIR)/
	install -m 0755 bin/kookaboot $(DESTDIR)$(BINDIR)/kookaboot

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/kookaboot
	rm -rf $(DESTDIR)$(LIBDIR)

# Lint is skipped with a warning when shellcheck is not installed.
lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -x -s bash $(SCRIPTS) && echo "lint: OK"; \
	else \
		echo "lint: SKIPPED - shellcheck not installed (apt/pacman: shellcheck, dnf: ShellCheck)"; \
	fi

test: lint
	tests/unit.sh

# Build the live installer ISO (root, Ubuntu/Debian host). Output in iso/out/.
iso:
	iso/build.sh
