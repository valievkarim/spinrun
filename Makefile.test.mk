.PHONY: test test-arm-big test-x86-big test-arm-mini test-x86-mini test-arm-speed test-x86-speed test-podman-arm test-podman-x86 test-arm-inside-arm-vm test-x86-inside-arm-vm test-arm-inside-x86-vm test-x86-inside-x86-vm test-build-inside-arm-vm test-build-inside-x86-vm test-build-inside-native-vm-ubuntu-noble-podman test-build-inside-native-vm-ubuntu-jammy-podman test-full

test: test-arm-speed test-x86-speed test-arm-big test-x86-big

test-arm-big: arm
	./tests/run-tests.sh arm big

test-x86-big: x86
	./tests/run-tests.sh x86 big

test-arm-mini: arm
	./tests/run-tests.sh arm mini

test-x86-mini: x86
	./tests/run-tests.sh x86 mini

test-arm-speed: arm
	./tests/run-tests.sh arm speed

test-x86-speed: x86
	./tests/run-tests.sh x86 speed

test-podman-arm: arm
	./spinrun-arm "\
		apk add podman && \
		podman run ubuntu:24.04 cat /etc/issue\
		" | grep "^Ubuntu 24.04"

test-podman-x86: x86
	./spinrun-x86 "\
		apk add podman && \
		podman run ubuntu:24.04 cat /etc/issue\
		" | grep "^Ubuntu 24.04"

test-arm-inside-arm-vm: arm
	./spinrun-arm --qemu-args -m 800 -virtfs "local,path=./,mount_tag=share,security_model=none,readonly=on" -- "\
		mount -t 9p share /mnt && \
		apk add bash make coreutils qemu-system-aarch64 qemu-system-x86_64 && \
		cd /mnt && make test-arm-mini\
		"

test-x86-inside-arm-vm: arm
	./spinrun-arm --qemu-args -m 800 -virtfs "local,path=./,mount_tag=share,security_model=none,readonly=on" -- "\
		mount -t 9p share /mnt && \
		apk add bash make coreutils qemu-system-aarch64 qemu-system-x86_64 && \
		cd /mnt && make test-x86-mini\
		"

test-arm-inside-x86-vm: x86
	./spinrun-x86 --qemu-args -m 800 -virtfs "local,path=./,mount_tag=share,security_model=none,readonly=on" -- "\
		mount -t 9p share /mnt && \
		apk add bash make coreutils qemu-system-aarch64 qemu-system-x86_64 && \
		cd /mnt && make test-arm-mini\
		"

test-x86-inside-x86-vm: x86
	./spinrun-x86 --qemu-args -m 800 -virtfs "local,path=./,mount_tag=share,security_model=none,readonly=on" -- "\
		mount -t 9p share /mnt && \
		apk add bash make coreutils qemu-system-aarch64 qemu-system-x86_64 && \
		cd /mnt && make test-x86-mini\
		"

DIST_FILES := Makefile Makefile.test.mk spinrun overlay buildinitramfs.sh download.sh tests spinrun-arm spinrun-x86

test-build-inside-arm-vm: arm
	./spinrun-arm --qemu-args -m 2048 -virtfs "local,path=./,mount_tag=share,security_model=none,readonly=on" -- "\
		mount -t 9p share /mnt && \
		apk add bash make coreutils squashfs-tools zstd qemu-system-aarch64 qemu-system-x86_64 curl && \
		mkdir work && cd /mnt && \
		cp -r $(DIST_FILES) ~/work/ && \
		cd ~/work && umount /mnt && \
		make all test-arm-mini test-x86-mini\
		"

test-build-inside-x86-vm: x86
	./spinrun-x86 --qemu-args -m 2048 -virtfs "local,path=./,mount_tag=share,security_model=none,readonly=on" -- "\
		mount -t 9p share /mnt && \
		apk add bash make coreutils squashfs-tools zstd qemu-system-aarch64 qemu-system-x86_64 curl && \
		mkdir work && cd /mnt && \
		cp -r $(DIST_FILES) ~/work/ && \
		cd ~/work && umount /mnt && \
		make all test-arm-mini test-x86-mini\
		"

test-build-inside-native-vm-ubuntu-noble-podman: arm x86
	./spinrun --qemu-args -m 4000 -virtfs "local,path=./,mount_tag=share,security_model=none,readonly=on" -- "\
		mount -t 9p share /mnt && \
		apk add podman && \
		mkdir work && cd /mnt && \
		cp -r $(DIST_FILES) ~/work/ && \
		cd ~/work && umount /mnt && \
		podman run -v /root/work:/root/work ubuntu:24.04 bash -c '\
			apt-get update && \
			apt install -y qemu-system make squashfs-tools zstd cpio curl && \
			cd /root/work/ && make all test-arm-mini test-x86-mini install && spinrun uname\
		'\
		"

test-build-inside-native-vm-ubuntu-jammy-podman: arm x86
	./spinrun --qemu-args -m 4000 -virtfs "local,path=./,mount_tag=share,security_model=none,readonly=on" -- "\
		mount -t 9p share /mnt && \
		apk add podman && \
		mkdir work && cd /mnt && \
		cp -r $(DIST_FILES) ~/work/ && \
		cd ~/work && umount /mnt && \
		podman run -v /root/work:/root/work ubuntu:22.04 bash -c '\
			apt-get update && \
			apt-get install -y software-properties-common && \
			add-apt-repository ppa:canonical-server/server-backports && \
			apt install -y qemu-system make squashfs-tools zstd cpio curl && \
			cd /root/work/ && make all test-arm-mini test-x86-mini install && spinrun uname\
		'\
		"

test-full: test-arm-speed test-x86-speed test-x86-big test-arm-big test-build-inside-native-vm-ubuntu-noble-podman test-build-inside-native-vm-ubuntu-jammy-podman test-podman-arm test-podman-x86 test-arm-inside-arm-vm test-x86-inside-arm-vm test-arm-inside-x86-vm test-x86-inside-x86-vm test-build-inside-arm-vm test-build-inside-x86-vm

