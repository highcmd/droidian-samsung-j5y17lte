# Build on arm64 (natively or under qemu): needs gcc, make, pkg-config, libgtk-3-dev.
# include/ holds the matching headers from Phosh 0.49 (src/, GPL-3.0-or-later).
CFLAGS ?= -O2 -Wall
PKGS = gtk+-3.0 gio-2.0
PLUGINS = pihole-quick-setting eco-quick-setting

all: $(PLUGINS:%=libphosh-plugin-%.so)

libphosh-plugin-%.so: %.c
	$(CC) $(CFLAGS) -shared -fPIC -Iinclude $$(pkg-config --cflags $(PKGS)) \
	  -DG_LOG_DOMAIN='"phosh-plugin-$*"' -o $@ $< $$(pkg-config --libs $(PKGS))

.PHONY: all
