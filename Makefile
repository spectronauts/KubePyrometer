PREFIX   ?= /usr/local
VERSION  := $(shell cat VERSION)
NAME     := kubepyrometer
TAR_NAME := $(NAME)-$(VERSION)

LIBEXEC  := $(PREFIX)/libexec/$(NAME)

# Data directories to install under libexec/
DATA_DIRS := scripts workloads templates manifests configs images

.PHONY: install uninstall dist clean

install:
	install -d $(PREFIX)/bin
	install -m 755 kubepyrometer $(PREFIX)/bin/kubepyrometer
	install -d $(LIBEXEC)
	install -m 755 v0/run.sh $(LIBEXEC)/run.sh
	install -m 644 v0/config.yaml $(LIBEXEC)/config.yaml
	cp VERSION $(LIBEXEC)/VERSION
	@for dir in $(DATA_DIRS); do \
		if [ -d "v0/$$dir" ]; then \
			cp -R "v0/$$dir" "$(LIBEXEC)/"; \
		fi; \
	done
	chmod +x $(LIBEXEC)/scripts/*.sh

uninstall:
	rm -f $(PREFIX)/bin/kubepyrometer
	rm -rf $(LIBEXEC)

dist:
	@echo "Building $(TAR_NAME).tar.gz"
	$(eval TMPDIR := $(shell mktemp -d))
	mkdir -p $(TMPDIR)/$(TAR_NAME)
	cp -R kubepyrometer VERSION LICENSE NOTICE README.md v0 $(TMPDIR)/$(TAR_NAME)/
	rm -rf $(TMPDIR)/$(TAR_NAME)/v0/bin $(TMPDIR)/$(TAR_NAME)/v0/runs
	tar -czf $(TAR_NAME).tar.gz -C $(TMPDIR) $(TAR_NAME)
	shasum -a 256 $(TAR_NAME).tar.gz > $(TAR_NAME).tar.gz.sha256
	rm -rf $(TMPDIR)
	@echo "Created $(TAR_NAME).tar.gz"
	@cat $(TAR_NAME).tar.gz.sha256

clean:
	rm -f $(NAME)-*.tar.gz $(NAME)-*.tar.gz.sha256
