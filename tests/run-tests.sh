#!/bin/bash

set -o nounset -o errexit -o pipefail
set -o xtrace

debug() { :; }

error() { echo "[ERROR] $*" >&2 || true; }

trap 'echo got sigint in run-tests.sh; trap - INT; kill -s INT "$$"' INT

trap 'exit_code=$?; error "run-tests.sh: exit code $exit_code"; exit $exit_code' ERR

if [ $# -ne 2 ]; then
    error "Usage: $0 <target_dir> speed|mini|big"
    exit 1
fi

TARGET_DIR="$1"
GUEST_ARCH="$(cat "$TARGET_DIR/arch.txt")"
TESTSET="$2"

if ! [ "$TESTSET" = "speed" ] && ! [ "$TESTSET" = "mini" ] && ! [ "$TESTSET" = "big" ]; then
    error "Usage: $0 <target_dir> speed|mini|big"
    exit 1
fi

export XTRACE=0

SPINRUN_MEM=500

SPINRUN_CMD=(./spinrun --target "$TARGET_DIR" --qemu-args -m "$SPINRUN_MEM" -- )

# Function to run spinrun with target directory and forward all other arguments
spinrun() (
    { set +x; } 2>/dev/null
    "${SPINRUN_CMD[@]}" "$@"
)

if [ "$TESTSET" = "speed" ]; then
    echo "test start speed"
    timeout 100 "${SPINRUN_CMD[@]}" uname
    echo "TEST SET: speed - SUCCESS"
    exit 0
fi

test_mini() {
    echo "test mini checks"
    tmpdir="$(mktemp -d)"
    cat > "$tmpdir/test.sh" <<'EOF'
#!/bin/sh
set -o pipefail -o errexit -o nounset
[ "${XTRACE:-0}" = "1" ] && set -o xtrace

ping -c 1 10.0.2.2 >/dev/null
echo "ping ok"
echo "stdout test"
echo "stderr test1" >&2
echo "stderr test2" >/dev/stderr
echo "PATH=$PATH"
echo "exit code test"
exit 123
EOF
    chmod +x "$tmpdir/test.sh"

    fn="$(mktemp)"
    fn_out="$(mktemp)"
    ret=0
    XTRACE=1 spinrun --qemu-args -virtfs "local,path=$tmpdir,mount_tag=share,security_model=none" -- 'echo "$(( 2 + $(echo "$(( 12345 + 1 ))") ))" && mount -t 9p share /mnt && /mnt/test.sh' 2>"$fn" >"$fn_out" || ret=$?

    test "$ret" = "123"
    grep -qF "debug 'io_mode: separate_output'" "$fn"
    grep -qF "[    0.000000] Linux version" "$fn"
    grep -qF "+ /usr/local/bin/spinrun-stage1" "$fn"
    grep -qF "+ modprobe virtio_pci" "$fn"
    grep -qF "+ mount --move . /" "$fn"
    grep -qF "12345" "$fn"
    grep -qF "12346" "$fn"
    grep -qF "12348" "$fn"
    grep -qF "reboot: Power down" "$fn"
    grep -qF "debug 'exitcode: 123'" "$fn"
    test "$(cat "$fn_out")" = '12348
ping ok
stdout test
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
exit code test'

    rm "$fn" "$fn_out"
    rm -rf "$tmpdir"
}

if [ "$TESTSET" = "mini" ]; then
    test_mini
    echo "TEST SET: mini - SUCCESS"
    exit 0
fi


echo "test simple command 'uname'"
test "$(spinrun uname 2>&1)" = "Linux"

echo "test exit code"
test "$(spinrun exit 123 ; echo $?)" = "123"

echo "test network is working"
test "$(spinrun 'ping -c 1 10.0.2.2 >/dev/null && echo ok' )" = "ok"

echo "test echo to stderr with 2>&1"
test "$(spinrun "echo 111 >&2" 2>&1)" = "111"

echo "test PATH"
test "$(spinrun 'echo $PATH')" = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

echo "test output with XTRACE=1"
fn="$(mktemp)"

XTRACE=1 spinrun 'echo "$(( 2 + $(echo "$(( 12345 + 1 ))") ))"' 2>"$fn" >/dev/null

grep -qF "debug 'io_mode: separate_output'" "$fn"
grep -qF "[    0.000000] Linux version" "$fn"
grep -qF "+ /usr/local/bin/spinrun-stage1" "$fn"
grep -qF "+ modprobe virtio_pci" "$fn"
grep -qF "+ mount --move . /" "$fn"
grep -qF "12345" "$fn"
grep -qF "12346" "$fn"
grep -qF "12348" "$fn"
grep -qF "reboot: Power down" "$fn"
grep -qF "debug 'exitcode: 0'" "$fn"

# exit 0
rm "$fn"


case "$GUEST_ARCH" in
    aarch64)
        echo "simple test with raw qemu command - aarch64"
        test "$(qemu-system-aarch64 -M virt -cpu cortex-a72 -m "$SPINRUN_MEM" -nographic -kernel "$TARGET_DIR/vmlinuz" -initrd "$TARGET_DIR/initramfs" -append 'loglevel=0 CMD=uname')" = "Linux"
        ;;
    x86_64)
        echo "simple test with raw qemu command - x86_64"
        test "$(qemu-system-x86_64 -cpu max -m "$SPINRUN_MEM" -display none -serial stdio -kernel "$TARGET_DIR/vmlinuz" -initrd "$TARGET_DIR/initramfs" -append 'loglevel=0 console=ttyS0 CMD=uname')" = "Linux"
        ;;
    *)
        echo "unsupported GUEST_ARCH: $GUEST_ARCH"
        exit 1
        ;;
esac

echo "test running script from 9p shared folder"

tmpdir="$(mktemp -d)"
cat > "$tmpdir/test.sh" <<'EOF'
#!/bin/sh
echo "hello $(uname)" > /mnt/test.txt
EOF
chmod +x "$tmpdir/test.sh"

spinrun --qemu-args -virtfs "local,path=$tmpdir,mount_tag=share,security_model=none" -- 'mount -t 9p share /mnt && /mnt/test.sh'
test "$(cat "$tmpdir/test.txt")" = "hello Linux"

rm -rf "$tmpdir"

echo "test interrupting with timeout 0.5 gives exit code 130"
test "$(timeout --signal INT 0.5 bash -c 'trap " " INT; "${@}" sleep 10; echo $?' _ "${SPINRUN_CMD[@]}" )" = "130"


# ------------------------------------------------------------

echo "test echo cmd as single argument"
test "$(spinrun "echo 111")" = "111"

echo "test echo to stderr with 2>/dev/null"
test "$(spinrun "echo 111 >&2" 2>/dev/null)" = ""

echo "test echo cmd as multiple arguments"
test "$(spinrun echo 111)" = "111"

echo "test echo cmd with 2>&1"
test "$(spinrun "echo 111" 2>&1)" = "111"

echo "test sort with 2>&1"
test "$(echo -en "123\n012\n" | spinrun sort 2>&1)" = $'012\n123'

echo "test HOME"
test "$(spinrun 'echo $HOME')" = "/root"

echo "test TERM"
test "$(spinrun 'echo $TERM')" = "xterm-256color"

echo "test pwd"
test "$(spinrun pwd)" = "/root"

echo "test /dev/fd is a symlink to /proc/self/fd"
test "$(spinrun 'readlink /dev/fd')" = "/proc/self/fd"

echo "test /dev/random exists"
test "$(spinrun 'ls /dev/random')" = "/dev/random"


echo "test multiple echo commands"
test "$(spinrun 'echo hello; echo world')" = $'hello\nworld'

echo "test /dev/stdout and /dev/stderr working with 2>&1 - must be correct orders and no errors"
test "$(spinrun 'echo 1 >/dev/stdout; echo 2 >/dev/stderr' 2>&1)" = $'1\n2'

echo "test /dev/stdout and /dev/stderr with 2>&1 1>/dev/null" 
test "$(spinrun 'echo 1 >/dev/stdout; echo 2 >/dev/stderr' 2>&1 1>/dev/null)" = "2"

echo "test /dev/stdout and /dev/stderr with 2>/dev/null"
test "$(spinrun 'echo 1 >/dev/stdout; echo 2 >/dev/stderr' 2>/dev/null)" = "1"

echo "test /dev/stdout and /dev/stderr with separate stdout/stderr output - order can be different"
t="$(bash -c '("${@}" | cat) 2>&1' _ "${SPINRUN_CMD[@]}" 'echo 1 >/dev/stdout; echo 2 >/dev/stderr')"
test "$t" = $'2\n1' || test "$t" = $'1\n2'

echo "test /proc/self/fd/0 is a pipe"
spinrun 'readlink /proc/self/fd/0'|grep "^pipe:"

echo "test /proc/self/fd/1 is a pipe"
spinrun 'readlink /proc/self/fd/1'|grep "^pipe:"

echo "test /proc/self/fd/2 is a pipe"
spinrun 'readlink /proc/self/fd/2'|grep "^pipe:"

echo "test /tmp is empty dir"
test "$(spinrun 'ls /tmp')" = ""

echo "test echo cmd to stdin"
test "$( echo 'echo 123' | spinrun )" = "123"

# exit 0

echo "test with empty --qemu-args"
test "$(spinrun --qemu-args -- uname)" = "Linux"

echo "test /proc/cmdline"
test "$(spinrun --qemu-args -append 'hello' -- cat /proc/cmdline)" = "hello"

echo "test with CMD in kernel args"
test "$(spinrun --qemu-args -append 'CMD=uname' --)" = "Linux"

if [ "$GUEST_ARCH" = "aarch64" ]; then
    echo "test with no network for aarch64"
    t="$(spinrun --qemu-args -nic none -- "ip a")"
    if echo "$t"|grep eth0 ; then
        echo "eth0 is present: $t"
        exit 1
    fi
fi



echo "test transfer random data from guest to host and back"

tmpdir="$(mktemp -d)"
(awk 'BEGIN{for(i=0;i<256;i++)printf "%c",i;}' && head -c 1000000 /dev/urandom) > "$tmpdir/testfile.dat"

spinrun --qemu-args -virtfs "local,path=$tmpdir,mount_tag=share,security_model=none" -- 'mount -t 9p share /mnt && cat > /mnt/to-guest.dat && cat /mnt/testfile.dat' > "$tmpdir/from-guest.dat" < "$tmpdir/testfile.dat"

diff "$tmpdir/testfile.dat" "$tmpdir/to-guest.dat"
diff "$tmpdir/testfile.dat" "$tmpdir/from-guest.dat"

rm -rf "$tmpdir"

echo "test transfer random data from guest to host using raw qemu command and terminal"

tmpdir="$(mktemp -d)"
(awk 'BEGIN{for(i=0;i<256;i++)printf "%c",i;}' && head -c 10000 /dev/urandom) > "$tmpdir/testfile.dat"

cmd_to_run="mount -t 9p share /mnt && cat /mnt/testfile.dat"
case "$GUEST_ARCH" in
    aarch64)
        echo "test transfer random data from guest to host using raw qemu command and terminal - aarch64"
        qemu-system-aarch64 -M virt -cpu cortex-a72 -m "$SPINRUN_MEM" -nographic -kernel "$TARGET_DIR/vmlinuz" -initrd "$TARGET_DIR/initramfs" -virtfs "local,path=$tmpdir,mount_tag=share,security_model=none" -append "loglevel=0 CMD=\"${cmd_to_run}\"" > "$tmpdir/from-guest.dat"
        ;;
    x86_64)
        echo "test transfer random data from guest to host using raw qemu command and terminal - x86_64"
        qemu-system-x86_64 -cpu max -m "$SPINRUN_MEM" -display none -serial stdio -kernel "$TARGET_DIR/vmlinuz" -initrd "$TARGET_DIR/initramfs" -virtfs "local,path=$tmpdir,mount_tag=share,security_model=none" -append "loglevel=0 console=ttyS0 CMD=\"${cmd_to_run}\"" > "$tmpdir/from-guest.dat"
        ;;
    *)
        echo "unsupported GUEST_ARCH: $GUEST_ARCH"
        exit 1
        ;;
esac

diff "$tmpdir/testfile.dat" "$tmpdir/from-guest.dat"

rm -rf "$tmpdir"


test_interrupt() {
    timeout="$1"
    echo "test interrupting with timeout $timeout doesn't leave qemu process running"
    tag="tag-$RANDOM$RANDOM$RANDOM-tag"
    ret=0
    timeout --preserve-status --signal INT "$timeout" "${SPINRUN_CMD[@]}" "sleep 10; echo hello $tag" || ret=$?
    ! pgrep -l -f "$tag" || (echo "qemu process is still running" && exit 1)
    test "$ret" = "130"
}

test_interrupt 0.5

for timeout in 0.0000001 0.001 0.002 0.005 0.01 0.02 0.05 0.1 0.2 0.9; do
    test_interrupt "$timeout"
done

test_streaming_output() {
    echo "test streaming output"

    fifo_in=$(mktemp -u)
    fifo_out=$(mktemp -u)
    mkfifo "$fifo_in" "$fifo_out"

    spinrun 'while read s; do echo "got $s"; done; exit 55' < "$fifo_in" > "$fifo_out" &
    pid=$!
    exec 3>"$fifo_in"
    exec 4<"$fifo_out"
    rm "$fifo_in" "$fifo_out"

    echo "qwerty1" >&3
    read resp <&4
    echo "resp: $resp"
    test "$resp" = "got qwerty1"

    echo "qwerty2" >&3
    read resp <&4
    echo "resp: $resp"
    test "$resp" = "got qwerty2"

    exec 3>&-
    exec 4<&-

    ret=0
    wait $pid || ret=$?
    echo "ret: $ret"
    test "$ret" = "55"
}

test_streaming_output

test_mini

echo "TEST SET: big - SUCCESS"





