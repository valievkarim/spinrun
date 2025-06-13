# spinrun

**spinrun** boots a clean, disposable Alpine Linux VM using QEMU in < 1s

Get interactive shell or run a command, pass stdin/stdout/stderr & exit code back.

Single command, no daemon, no config, no disk images, runs in RAM.

MacOS and Linux hosts supported.

## Quick Start

Clone the repository:
```sh
git clone https://github.com/valievkarim/spinrun
cd spinrun
```

Install dependencies:

macOS:
```sh
brew install qemu squashfs zstd
```

Ubuntu 24.04+:
```sh
sudo apt install qemu-system make squashfs-tools zstd cpio curl
```

Ubuntu 22.04 (qemu >= 8.1 needed):
```sh
sudo apt install software-properties-common
sudo add-apt-repository ppa:canonical-server/server-backports
sudo apt install qemu-system make squashfs-tools zstd cpio curl
```

Build and run:
```sh
make
./spinrun
```

Optional: install to `/usr/local/libexec/spinrun` and `/usr/local/bin/spinrun*`:
```sh
sudo make install   # sudo make uninstall - to remove
```


## Usage

```sh
./spinrun [--target x86|arm] [--qemu-args <args> --] <command> [args...]
./spinrun [--target x86|arm] [--qemu-args <args> --] "<shell-command>"
```

Options:
- `--target <x86|arm>` — Select target architecture (default is native host architecture)
- `--qemu-args <args> --` — Start a list of arguments passed directly to QEMU (must end with `--`)

Shortcuts:
- `./spinrun-x86` = same as `./spinrun --target x86`
- `./spinrun-arm` = same as `./spinrun --target arm`

## Examples

```sh
./spinrun                                  # Interactive shell (native target)
./spinrun --target arm uname -a            # Run command on ARM guest
./spinrun --qemu-args -m 8G -- free -m     # Start command with extra QEMU args
./spinrun "echo hello && whoami"           # Run shell command
./spinrun-x86 ping 8.8.8.8                 # Shortcut for x86 target
XTRACE=1 ./spinrun ls -la /                # Enable full debug tracing
```

### Share host directory

```sh
./spinrun --qemu-args -virtfs local,path=./,mount_tag=share,security_model=none --
```

Inside guest:

```sh
mount -t 9p share /mnt
```

### Install Alpine packages inside guest

```sh
apk add htop
apk add bash coreutils    # Useful shell tools
apk add build-base        # gcc, make, etc.
```

### Run containers inside guest

```sh
apk add podman
podman run --rm -it ubuntu bash
```

### Access external ext4 HDD on macOS

First find your disk device on macOS host:
```sh
diskutil list
diskutil unmountDisk /dev/...
```

Then run spinrun with disk access:
```sh
sudo ./spinrun --qemu-args -drive file=/dev/disk4,format=raw,if=virtio,readonly=on --
```

Inside the guest, install utils and mount:
```sh
apk add util-linux         # full-featured fdisk, mount etc
fdisk -l
mount /dev/vda... /mnt/
```

## Performance

Measured by `time ./spinrun uname -a` on a MacBook Pro M1, I get real time ~0.4s.

Measured by `time sudo ./spinrun uname -a` on Xeon E3-1270 v5, I get real time ~1.0s

This can be optimized down to 0.3 and 0.8s respectively by keeping only needed kernel modules in the initramfs, see comments in [buildinitramfs.sh](buildinitramfs.sh)

Hardware acceleration is enabled automatically on macOS (HVF) and Linux (KVM) when possible.
It works when guest architecture is the same as host architecture.
For KVM to work on Linux, you need to run `spinrun` as root or add your user to `kvm` group:

```sh
sudo usermod -aG kvm $USER # Then log out and back in, or start a new terminal session
```

`time ./spinrun-x86 uname`, without hardware acceleration, gives me 4.5s on M1 Macbook.


## Manual QEMU Run

You can also run the built image directly with QEMU:

```sh
qemu-system-aarch64 -serial mon:stdio -display none -M virt -cpu cortex-a72 \
  -kernel arm/vmlinuz -initrd arm/initramfs -m 2048

qemu-system-x86_64 -serial mon:stdio -display none -kernel x86/vmlinuz \
  -initrd x86/initramfs -append console=ttyS0 -m 2048
```

Add `-accel hvf` on macOS or `-accel kvm` on Linux for hardware acceleration.
When launching with `./spinrun` it is enabled automatically.
For KVM to work on Linux, you need to run as root or add your user to `kvm` group

## How It Works

- [download.sh](download.sh) - Downloads the kernel, initramfs, modloop (kernel modules archive), and minirootfs from [alpine release](https://dl-cdn.alpinelinux.org/alpine/)
- [buildinitramfs.sh](buildinitramfs.sh) - Merges initramfs, modloop, minirootfs, and the `overlay/` directory into a single initramfs image
- [spinrun](spinrun) - Launches QEMU with the built initramfs, handles stdin/stdout/stderr, sends the command to be run, and receives the exit code back

Inside the guest (overlay/ directory):
- [/init](overlay/init): kernel runs this first. Calls `spinrun-stage1`
- [/usr/local/bin/spinrun-stage1](overlay/usr/local/bin/spinrun-stage1): mounts `/proc`, loads kernel modules, sets up networking, and execs `spinrun-stage2`
- [/usr/local/bin/spinrun-stage2](overlay/usr/local/bin/spinrun-stage2): runs the command sent from the host and returns the exit code

When running non-interactively, stdin, stdout, and stderr are passed via **virtio-ports** for reliable, stream-safe I/O

- [tests/run-tests.sh](tests/run-tests.sh) - Test suite
- [Makefile](Makefile) - build commands
- [Makefile.test.mk](Makefile.test.mk) - various test setups


