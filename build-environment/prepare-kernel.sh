#!/bin/sh
# Trusted kernel + modules + matching initramfs for Xiaomi Redmi Note 5A
# (ugglite), built from the pinned pmaports kernel source with pmbootstrap.
#
#   sh build-environment/prepare-kernel.sh
#
# What it does, and what it does not do:
#   * runs a separate container (default name ztos-kernel-prep-1) from
#     ztos-build-env:beta-1.2 with exactly the approved widening:
#     --cap-add SYS_ADMIN --security-opt seccomp=unconfined. No --privileged,
#     no docker socket, no USB, no extra volumes.
#   * the project is mounted READ-ONLY at /src; the only host write target is
#     build/kernel (/out). pmaports and the pmbootstrap work tree live in the
#     container's own Linux storage (/linux-work), not on a macOS bind mount.
#   * pmbootstrap device=qcom-msm89x7 (the pmOS codename that serves ugglite),
#     builds linux-postmarketos-qcom-msm89x7 from the pinned pmaports APKBUILD
#     and the pinned upstream tag. Build + install + verification + export all
#     finish in build-environment/finalize-kernel.sh, which this script calls
#     through the read-only /src mount; that same finalizer is the export-only
#     recovery path for a container that already built the kernel.
#   * the prebuilt apk from mirror.nura.eco is NOT used: its signer
#     (pmos@local-...) is not the pinned pmaports key. Verification is never
#     disabled.
#
# The in-container steps are written to build/kernel/run-inner.sh so the exact
# commands are part of the artifacts. Outputs: build/kernel/artifacts/*,
# manifests and hashes, logs under build/kernel/logs/.
set -eu

cd "$(dirname "$0")/.."
PWD_ABS=$(pwd)
NAME=${NAME:-ztos-kernel-prep-1}
IMAGE=ztos-build-env:beta-1.2
OUT="$PWD_ABS/build/kernel"

die() { echo "prepare-kernel: $*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "docker not found"
[ -f build-environment/finalize-kernel.sh ] || die "build-environment/finalize-kernel.sh missing (it is executed from /src)"
docker image inspect "$IMAGE" >/dev/null 2>&1 || die "image $IMAGE not present"
if docker container inspect "$NAME" >/dev/null 2>&1; then
    die "container $NAME already exists; remove it explicitly or set NAME=<other>"
fi

# Host disk guard: >= 3 GiB free where the artifacts land.
kb=$(df -Pk "$PWD_ABS" | awk 'NR==2 {print $4}')
echo "== free on host: $((kb / 1024 / 1024)) GiB"
[ "$kb" -ge 3145728 ] || die "less than 3 GiB free on host"

mkdir -p "$OUT/logs" "$OUT/artifacts"

cat >"$OUT/run-inner.sh" <<'INNER'
#!/bin/sh
# In-container steps. Executed as root inside ztos-build-env:beta-1.2.
# Build only: install, signature check, kernel hash check, export and the
# initramfs matching proof live in build-environment/finalize-kernel.sh, which
# is also the export-only recovery script for this container.
set -eu
SRC=/src
OUT=/out
LW=/linux-work
PMB_CFG=$LW/pmbootstrap.cfg
DEVICE=qcom-msm89x7
KERNEL_PKG=linux-postmarketos-qcom-msm89x7
# Exact literal from upstream-lock.json clones.pmaports.head.
APORTS_HEAD=39fe8995ea485a798ac8f1eff091b3962352e791

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }
fail() { log "FAILED: $*"; exit 1; }

log "kernel prep start: $(uname -a)"
[ "$(id -u)" = 0 ] || fail "must run as root in the container"

free_kb() { df -Pk "$1" | awk 'NR==2 {print $4}'; }
for d in / "$OUT"; do
    f=$(free_kb "$d")
    log "free on $d: $((f / 1024 / 1024)) GiB"
    [ "$f" -ge 3145728 ] || fail "less than 3 GiB free on $d"
done

mkdir -p "$LW/work" "$LW/aports" "$OUT/artifacts" "$OUT/logs"
# pmaports is mounted read-only; pmbootstrap needs it writable (it runs git
# checks and installs hooks). Copy it into Linux storage instead of binding it.
if [ ! -f "$LW/aports/pmaports.cfg" ]; then
    log "copying pmaports from read-only source into $LW/aports"
    cp -a "$SRC/upstream/pmaports/." "$LW/aports/" || fail "cannot copy pmaports"
fi
HEAD=$(git -C "$LW/aports" rev-parse HEAD) || fail "cannot read pmaports HEAD"
log "pmaports HEAD: $HEAD"
[ "$HEAD" = "$APORTS_HEAD" ] || fail "pmaports HEAD $HEAD != pinned $APORTS_HEAD"

# Work-folder version: what `pmbootstrap init` would write.
WV=$(python3 -c 'import pmb.config; print(pmb.config.work_version)') || fail "cannot read pmb.config.work_version"
echo "$WV" >"$LW/work/version"
mkdir -p "$LW/work/cache_git"

cat >"$PMB_CFG" <<CFG
[pmbootstrap]
aports = $LW/aports
device = $DEVICE
work = $LW/work
ui = none
user = user
kernel =
is_default_channel = False
hostname = ugglite

[mirrors]
alpine = https://dl-cdn.alpinelinux.org/
pmaports = https://mirror.nura.eco/postmarketos/
systemd = https://mirror.nura.eco/postmarketos/extra-repos/systemd/
CFG

PMB="pmbootstrap -c $PMB_CFG --work $LW/work --aports $LW/aports --as-root --details-to-stdout -y"

# pmbootstrap 3.12.1's startup check requires kpartx; the beta-1.2 image predates
# that requirement. Install it into this container only (ephemeral layer).
if ! command -v kpartx >/dev/null 2>&1; then
    log "installing kpartx (multipath-tools) into the container"
    pacman -S --noconfirm --needed multipath-tools >/dev/null || fail "cannot install kpartx"
fi

log "pmbootstrap version: $(pmbootstrap --version)"
$PMB work_migrate || fail "work_migrate failed"
log "config: device=$DEVICE kernel=$(pmbootstrap -c $PMB_CFG -p $LW/aports config device)"

# 1. Kernel package from the pinned APKBUILD (source tag v7.1.3-r1, sha512
#    pinned by that APKBUILD in the pinned checkout). --force: without it
#    pmbootstrap treats the package in the binary mirror as "up to date" and
#    installs that instead of building.
log "building $KERNEL_PKG (source download + LLVM build; this is the long step)"
$PMB build --arch aarch64 --force "$KERNEL_PKG" || fail "pmbootstrap build failed"

# 2. Everything after the build is shared with the export-only recovery path.
log "handing over to /src/build-environment/finalize-kernel.sh (no build inside)"
KERNEL_PKG="$KERNEL_PKG" exec sh "$SRC/build-environment/finalize-kernel.sh"
INNER
chmod +x "$OUT/run-inner.sh"

echo "== starting $NAME from $IMAGE (SYS_ADMIN + seccomp=unconfined, no privileged)"
# No --rm: a failed run keeps its named container (stop state, /linux-work
# intact) for inspection. The client's exit code is the script's exit code;
# output is redirected to a file, never piped through tee (which would mask it).
# rc is pre-set and captured with `||`, otherwise `set -e` would abort on a
# failing docker run before the diagnostics below could print.
LOG="$OUT/logs/pmbootstrap-run.log"
: >"$LOG"
rc=0
docker run --name "$NAME" \
    --cap-add SYS_ADMIN --security-opt seccomp=unconfined \
    -v "$PWD_ABS:/src:ro" -v "$OUT:/out" \
    -w /linux-work "$IMAGE" sh /out/run-inner.sh >"$LOG" 2>&1 || rc=$?
{
    echo "== docker run rc=$rc"
    docker inspect -f 'container={{.Name}} status={{.State.Status}} exit={{.State.ExitCode}} started={{.State.StartedAt}} finished={{.State.FinishedAt}}' "$NAME" 2>&1
} | tee -a "$LOG"
if [ "$rc" -ne 0 ]; then
    echo "== last log lines:" >&2
    tail -n 40 "$LOG" >&2
    exit "$rc"
fi
tail -n 25 "$LOG"
