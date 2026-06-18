PREFIX ?= /usr/local
EXEC_PREFIX ?= $(PREFIX)
LIBEXECDIR ?= $(EXEC_PREFIX)/lib/jool-netns
SYSCONFDIR ?= /etc
UNITDIR ?= $(SYSCONFDIR)/systemd/system
ENV_DIR ?= $(SYSCONFDIR)/jool-netns
DESTDIR ?=

INSTALL ?= install
SED ?= sed

SCRIPTS = common.sh up.sh down.sh

.PHONY: all install install-scripts install-service install-examples clean

all:

install: install-scripts install-service install-examples

install-scripts:
	$(INSTALL) -d "$(DESTDIR)$(LIBEXECDIR)"
	$(INSTALL) -m0644 common.sh "$(DESTDIR)$(LIBEXECDIR)/common.sh"
	$(INSTALL) -m0755 up.sh "$(DESTDIR)$(LIBEXECDIR)/up.sh"
	$(INSTALL) -m0755 down.sh "$(DESTDIR)$(LIBEXECDIR)/down.sh"

install-service:
	$(INSTALL) -d "$(DESTDIR)$(UNITDIR)"
	$(SED) \
		-e 's|@libexecdir@|$(LIBEXECDIR)|g' \
		-e 's|@sysconfdir@|$(SYSCONFDIR)|g' \
		jool-netns@.service.in > "$(DESTDIR)$(UNITDIR)/jool-netns@.service"
	chmod 0644 "$(DESTDIR)$(UNITDIR)/jool-netns@.service"

install-examples:
	$(INSTALL) -d "$(DESTDIR)$(ENV_DIR)"
	$(INSTALL) -m0644 jool-netns.env.example "$(DESTDIR)$(ENV_DIR)/example.env"

clean:
