.PHONY: install uninstall test

PREFIX ?= $(HOME)/.local
BINDIR = $(PREFIX)/bin
DATADIR = $(PREFIX)/share/asimov

install:
	mkdir -p $(BINDIR) $(DATADIR)/protocols $(DATADIR)/hooks
	cp bin/asimov $(BINDIR)/asimov
	chmod +x $(BINDIR)/asimov
	cp protocols/*.json $(DATADIR)/protocols/
	cp hooks/pre-commit $(DATADIR)/hooks/
	chmod +x $(DATADIR)/hooks/pre-commit
	@echo ""
	@echo "Installed asimov to $(BINDIR)/asimov"
	@echo "Data files in $(DATADIR)/"
	@echo ""
	@echo "Make sure $(BINDIR) is in your PATH"

uninstall:
	rm -f $(BINDIR)/asimov
	rm -rf $(DATADIR)
	@echo "Uninstalled asimov"

test:
	bats test/
