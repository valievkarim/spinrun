.PHONY: all x86 arm clean clean-all build-test install uninstall

.DELETE_ON_ERROR:

all: x86 arm
	@echo "Build complete, images are in x86/ and arm/"
	@echo "Try running ./spinrun"
	@echo "Run ./spinrun --help for usage instructions"

dl/x86/initramfs-virt: download.sh
	mkdir -p dl/x86
	./download.sh x86_64 dl/x86

dl/arm/initramfs-virt: download.sh
	mkdir -p dl/arm
	./download.sh aarch64 dl/arm

x86: x86/initramfs

x86/initramfs: dl/x86/initramfs-virt buildinitramfs.sh Makefile $(shell find overlay)
	mkdir -p x86 tmp
	cp dl/x86/arch.txt x86/arch.txt
	cp dl/x86/vmlinuz-virt x86/vmlinuz
	./buildinitramfs.sh dl/x86 x86/initramfs

arm: arm/initramfs

arm/initramfs: dl/arm/initramfs-virt buildinitramfs.sh Makefile $(shell find overlay)
	mkdir -p arm tmp
	cp dl/arm/arch.txt arm/arch.txt
	cp dl/arm/vmlinuz-virt arm/vmlinuz
	./buildinitramfs.sh dl/arm arm/initramfs


PREFIX ?= /usr/local
BINDIR := $(PREFIX)/bin
LIBEXECDIR := $(PREFIX)/libexec/spinrun

install: x86 arm
	mkdir -p tmp
	install -d "$(DESTDIR)$(LIBEXECDIR)"
	install -d "$(DESTDIR)$(BINDIR)"
	install -m 755 spinrun "$(DESTDIR)$(LIBEXECDIR)/"
	ln -sf spinrun "$(DESTDIR)$(LIBEXECDIR)/spinrun-x86"
	ln -sf spinrun "$(DESTDIR)$(LIBEXECDIR)/spinrun-arm"
	install -d "$(DESTDIR)$(LIBEXECDIR)/x86" "$(DESTDIR)$(LIBEXECDIR)/arm"
	install -m 644 x86/arch.txt "$(DESTDIR)$(LIBEXECDIR)/x86/"
	install -m 644 x86/vmlinuz "$(DESTDIR)$(LIBEXECDIR)/x86/"
	install -m 644 x86/initramfs "$(DESTDIR)$(LIBEXECDIR)/x86/"
	install -m 644 arm/arch.txt "$(DESTDIR)$(LIBEXECDIR)/arm/"
	install -m 644 arm/vmlinuz "$(DESTDIR)$(LIBEXECDIR)/arm/"
	install -m 644 arm/initramfs "$(DESTDIR)$(LIBEXECDIR)/arm/"
	
	for cmd in spinrun spinrun-x86 spinrun-arm; do \
		printf '#!/bin/bash\nexec "%s/%s" "$$@"\n' "$(LIBEXECDIR)" "$$cmd" > tmp/$$cmd.tmp; \
		install -m 755 tmp/$$cmd.tmp "$(DESTDIR)$(BINDIR)/$$cmd"; \
		rm tmp/$$cmd.tmp; \
	done

uninstall:
	rm -f "$(DESTDIR)$(BINDIR)/spinrun" "$(DESTDIR)$(BINDIR)/spinrun-x86" "$(DESTDIR)$(BINDIR)/spinrun-arm"
	rm -f "$(DESTDIR)$(LIBEXECDIR)/spinrun" "$(DESTDIR)$(LIBEXECDIR)/spinrun-x86" "$(DESTDIR)$(LIBEXECDIR)/spinrun-arm"
	rm -f "$(DESTDIR)$(LIBEXECDIR)/x86/arch.txt" "$(DESTDIR)$(LIBEXECDIR)/x86/vmlinuz" "$(DESTDIR)$(LIBEXECDIR)/x86/initramfs"
	rm -f "$(DESTDIR)$(LIBEXECDIR)/arm/arch.txt" "$(DESTDIR)$(LIBEXECDIR)/arm/vmlinuz" "$(DESTDIR)$(LIBEXECDIR)/arm/initramfs"
	rmdir "$(DESTDIR)$(LIBEXECDIR)/x86" "$(DESTDIR)$(LIBEXECDIR)/arm" "$(DESTDIR)$(LIBEXECDIR)" || true

clean:
	rm -rf x86/* arm/* tmp/*

clean-all: clean
	rm -rf dl/*

include Makefile.test.mk
