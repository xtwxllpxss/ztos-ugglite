#!/bin/sh
# Shared kernel finalization for ugglite (ugglite == pmOS device qcom-msm89x7).
#
# Runs INSIDE the ztos-build-env container. Two callers:
#   * build/kernel/run-inner.sh right after `pmbootstrap build --force` (normal run)
#   * the parent, as an export-only recovery step in the already-built container:
#       docker cp build-environment/finalize-kernel.sh <ctr>:/tmp/  (only if /src
#       is not mounted), then `docker start` a container whose run-inner.sh is
#       just `sh /src/build-environment/finalize-kernel.sh`.
#
# It never builds and never forces: it locates the already built apk under
# /linux-work/work/packages, runs `install --no-image` ONLY if the chroot has no
# initramfs yet, then verifies and exports. Safe to re-run: it rewrites the same
# artifacts and hashes. Every check is fail-closed (non-zero == fatal).
#
# Scope: proves the kernel/modules/initramfs module tree are from the locally
# built, signed apk, and that installed vmlinuz is byte-identical to it. It also
# exports the busybox binary that the verified initramfs contains, every applet
# that binary reports via `busybox --list` (as explicit relative symlinks; this
# initramfs ships none because its /init runs `busybox --install -s` at boot)
# and, if dynamic, its loader/libs, then executes the export in a chroot to prove
# /bin/sh starts. The build environment itself ships no busybox. It does NOT
# claim that this pmOS kernel/initramfs boots ztOS/Arch: pmOS's /init has to be
# adapted for ztOS separately. No image, no disk, no device, no flasher, no
# rootfs export.
set -eu

SRC=${SRC:-/src}
OUT=${OUT:-/out}
LW=${LW:-/linux-work}
DEVICE=${DEVICE:-qcom-msm89x7}
KERNEL_PKG=${KERNEL_PKG:-linux-postmarketos-qcom-msm89x7}
# Exact literal from upstream-lock.json clones.pmaports.head (read with
# `git -C upstream/pmaports rev-parse HEAD`, not copied from any report).
APORTS_HEAD=39fe8995ea485a798ac8f1eff091b3962352e791
PMB_CFG=$LW/pmbootstrap.cfg
CHROOT=$LW/work/chroot_rootfs_$DEVICE
# Disposable chroot only: this is never a bootable-image credential and SSH is
# off inside it. No password is published or defaulted; the caller must set one.
: "${BOOTSTRAP_PW:?BOOTSTRAP_PW must be set (throwaway chroot account, never a bootable-image credential)}"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }
fail() { log "FAILED: $*"; exit 1; }

# --- ELF dependency resolution for the initramfs busybox export --------------
# dep_path <tree> <name>: resolve one PT_INTERP path or DT_NEEDED name against
# an unpacked rootfs tree and print the matching path *tree-relative* (e.g.
# lib/libc.musl-aarch64.so.1), or nothing when there is none. A name with a
# slash is an exact root-relative path; a bare name is looked up in the dynamic
# loader's default directories, the way the runtime resolves it (musl: /lib,
# /usr/lib, /usr/local/lib). Existence is tested with -e, which follows
# symlinks on purpose: musl ships libc as the symlink
# lib/libc.musl-<arch>.so.1 -> ld-musl-<arch>.so.1, and `find -type f` (or
# `-f`, which does not follow) misses it.
# '..' components and paths that stay absolute after stripping the leading '/'
# are rejected: a dependency name must never select something outside the tree.
dep_path() {
    dp_tree=$1
    dp_name=$2
    case $dp_name in
        ''|*..*) return 0 ;;
    esac
    case $dp_name in
        /*) dp_rel=${dp_name#/} ;;
        */*) dp_rel=$dp_name ;;
        *) dp_rel= ;;
    esac
    if [ -n "$dp_rel" ]; then
        case $dp_rel in /*) return 0 ;; esac
        [ -e "$dp_tree/$dp_rel" ] && printf '%s\n' "$dp_rel"
        return 0
    fi
    for dp_dir in lib usr/lib usr/local/lib; do
        if [ -e "$dp_tree/$dp_dir/$dp_name" ]; then
            printf '%s\n' "$dp_dir/$dp_name"
            return 0
        fi
    done
    return 0
}

# norm <root-relative path>: collapse '.', '//' and '..' textually. Prints the
# normalised path, or nothing with a non-zero status when '..' would climb above
# the root (an escape). Purely textual: nothing outside the tree is consulted.
norm() {
    nm_in=$1
    nm_out=
    while [ -n "$nm_in" ]; do
        case $nm_in in
            */*) nm_c=${nm_in%%/*}; nm_in=${nm_in#*/} ;;
            *) nm_c=$nm_in; nm_in= ;;
        esac
        case $nm_c in
            ''|.) ;;
            ..) case $nm_out in
                    '') return 1 ;;
                    */*) nm_out=${nm_out%/*} ;;
                    *) nm_out= ;;
                esac ;;
            *) nm_out=${nm_out:+$nm_out/}$nm_c ;;
        esac
    done
    printf '%s\n' "$nm_out"
}

# tree_real <tree> <path-in-tree>: canonical path of a member of an unpacked
# rootfs, with symlinks resolved *inside that tree*: an absolute target
# ('/bin/busybox', '/usr/lib/libfoo.so') is tree-relative, which is what it
# means once the tree is the root, and never the host's file of that name.
# readlink -f must not be used here for that reason. Prints nothing for a
# dangling link, a link chain that leaves the tree (via '..'), more than 32
# hops, or a target that is not a regular file.
tree_real() {
    tr_tree=$1
    tr_p=${2#/}
    tr_i=0
    while [ "$tr_i" -lt 32 ]; do
        tr_i=$((tr_i + 1))
        tr_p=$(norm "$tr_p") || return 0
        [ -n "$tr_p" ] || return 0
        if [ -L "$tr_tree/$tr_p" ]; then
            tr_t=$(readlink "$tr_tree/$tr_p") || return 0
            case $tr_t in
                /*) tr_p=${tr_t#/} ;;
                *) tr_p=$(dirname "$tr_p")/$tr_t ;;
            esac
            continue
        fi
        if [ -f "$tr_tree/$tr_p" ]; then
            printf '%s\n' "$tr_tree/$tr_p"
        fi
        return 0
    done
    return 0
}

# dep_real <tree> <path-in-tree>: tree_real, kept as the name the dependency
# loop reads better with.
dep_real() {
    tree_real "$1" "$2"
}

# relpath <dir> <target>: relative path that reaches <target> from <dir>, both
# root-relative (e.g. relpath sbin bin/busybox -> ../bin/busybox). Used so an
# exported symlink never becomes absolute and never points outside the export.
relpath() {
    rp_up=
    rp_rest=${1#./}
    case $rp_rest in ''|.) rp_rest= ;; esac
    while [ -n "$rp_rest" ]; do
        rp_up=$rp_up../
        case $rp_rest in
            */*) rp_rest=${rp_rest#*/} ;;
            *) rp_rest= ;;
        esac
    done
    printf '%s\n' "$rp_up$2"
}

log "kernel finalize start (export-only, no build): $(uname -a)"
[ "$(id -u)" = 0 ] || fail "must run as root in the container"
[ -d "$LW/work" ] || fail "no pmbootstrap work tree at $LW/work (nothing was built there)"
[ -f "$PMB_CFG" ] || fail "no pmbootstrap config at $PMB_CFG"
[ -d "$LW/aports/.git" ] || fail "no git checkout at $LW/aports"

free_kb() { df -Pk "$1" | awk 'NR==2 {print $4}'; }
for d in / "$OUT"; do
    f=$(free_kb "$d")
    log "free on $d: $((f / 1024 / 1024)) GiB"
    [ "$f" -ge 3145728 ] || fail "less than 3 GiB free on $d"
done

# 1. pmaports pin + no local APKBUILD edits. HEAD is the literal from
#    upstream-lock.json; the kernel tag/sha512 are pinned by the APKBUILD of
#    the correct checkout (v7.1.3-r1), so a clean checkout is the source proof.
HEAD=$(git -C "$LW/aports" rev-parse HEAD) || fail "cannot read pmaports HEAD"
log "pmaports HEAD: $HEAD"
[ "$HEAD" = "$APORTS_HEAD" ] || fail "pmaports HEAD $HEAD != pinned $APORTS_HEAD"
DIRTY=$(git -C "$LW/aports" status --porcelain -- '*APKBUILD' 2>&1) || fail "git status failed in $LW/aports"
[ -z "$DIRTY" ] || fail "APKBUILD files are modified/untracked in the pmaports copy: $DIRTY"

# 2. Locate the locally built apk BEFORE any install, so a missing build fails
#    instead of quietly installing the mirror package. Only work/packages is
#    accepted; work/cache_apk_aarch64 is the remote binary.
APK=$(python3 - "$LW/work" "$KERNEL_PKG" <<'PY'
import os, sys
root, pkg = sys.argv[1], sys.argv[2]
hits = []
for d, _, fs in os.walk(root):
    if os.sep + "packages" + os.sep not in d + os.sep:
        continue
    for f in fs:
        if f.startswith(pkg + "-") and f.endswith(".apk"):
            hits.append(os.path.join(d, f))
print(sorted(hits)[-1] if hits else "")
PY
) || fail "search for a locally built apk under $LW/work/packages failed"
[ -n "$APK" ] || fail "no locally built $KERNEL_PKG apk under $LW/work/packages (remote binary is not accepted)"
case "$APK" in
    "$LW/work/packages/"*) ;;
    *) fail "apk is not a local build: $APK" ;;
esac
APK_BASE=$(basename "$APK")
log "built apk: $APK ($(stat -c %s "$APK") bytes)"

# 3. Rootfs chroot + mkinitfs, only when it has not produced an initramfs yet.
if [ ! -f "$CHROOT/boot/initramfs" ]; then
    log "no initramfs at $CHROOT yet; running install --no-image (no build, no force)"
    command -v kpartx >/dev/null 2>&1 || {
        log "installing kpartx (multipath-tools) into the container"
        pacman -S --noconfirm --needed multipath-tools >/dev/null || fail "cannot install kpartx"
    }
    pmbootstrap -c "$PMB_CFG" --work "$LW/work" --aports "$LW/aports" \
        --as-root --details-to-stdout -y \
        install --no-image --password "$BOOTSTRAP_PW" --no-sshd \
        || fail "install --no-image failed"
fi
[ -d "$CHROOT" ] || fail "no rootfs chroot at $CHROOT"
[ -f "$CHROOT/boot/initramfs" ] || fail "no initramfs at $CHROOT/boot/initramfs"
log "initramfs: $(stat -c %s "$CHROOT/boot/initramfs") bytes"

# 4. Unpack the apk. Exactly one modules dir, no guessing.
TREE=$LW/tree
rm -rf "$TREE"
mkdir -p "$TREE"
bsdtar -xpf "$APK" -C "$TREE" || fail "bsdtar cannot unpack $APK"
KERNEL=$TREE/boot/vmlinuz
DTB=$TREE/boot/dtbs/qcom/msm8917-xiaomi-ugglite.dtb
[ -f "$KERNEL" ] || fail "no boot/vmlinuz (legacy gzip image) in the apk; *.efi is not accepted"
[ -f "$DTB" ] || fail "no msm8917-xiaomi-ugglite.dtb in the apk"
# Legacy gzip vmlinuz only. An EFI stub starts with 'MZ' and is not a ztOS
# kernel image, so its magic is rejected instead of being exported.
MAGIC=$(od -An -tx1 -N2 "$KERNEL" | tr -d ' \n')
[ "$MAGIC" = 1f8b ] || fail "boot/vmlinuz is not gzip (magic=$MAGIC); *.efi / EFI stub is not accepted"
set -- "$TREE"/usr/lib/modules/*
[ "$#" -eq 1 ] || fail "expected exactly one modules dir in the apk, found $#"
[ -d "$1" ] || fail "modules path is not a directory: $1"
MODDIR=$1
KV=$(basename "$MODDIR")
log "kernel: boot/vmlinuz (gzip), modules: usr/lib/modules/$KV, dtb: $(basename "$DTB")"

# 5. Signature: signed member, its key in the chroot keyring, apk verify rc=0.
#    Verification is never disabled; the mirror apk is not an input. apk signer
#    names are .SIGN.RSA[<bits>].<key>.rsa.pub, so the bit count is optional.
SIGNER=$(bsdtar -tf "$APK" | grep -m1 '^\.SIGN\.RSA[0-9]*\.' || true)
[ -n "$SIGNER" ] || fail "built apk carries no .SIGN.RSA[0-9]* signature member"
log "apk signer member: $SIGNER"
KEY=$(printf '%s\n' "$SIGNER" | sed 's/^\.SIGN\.RSA[0-9]*\.//; s/\.rsa\.pub$//')
[ -n "$KEY" ] || fail "cannot derive signer key name from $SIGNER"
# The trusted keyring is pmbootstrap's own ($LW/work/config_apk_keys), which it
# bind-mounts onto the chroot's /etc/apk/keys for its runs. Reading it from the
# work tree keeps the check meaningful in an export-only recovery, where no
# pmbootstrap process is running and the chroot's /etc/apk/keys is a plain,
# empty directory instead of that mount.
KEYS=$LW/work/config_apk_keys
[ -d "$KEYS" ] || fail "no pmbootstrap apk keyring at $KEYS"
[ -f "$KEYS/$KEY.rsa.pub" ] || fail "signer key $KEY is not in $KEYS (untrusted signer)"
log "signer key present in the pmbootstrap keyring: $KEYS/$KEY.rsa.pub"
# `apk verify` still has to run inside the chroot, so the same trusted key is
# staged into the chroot's keyring dir when it is not already there (with the
# bind mount in place this is the identical file). Verification itself is never
# disabled or relaxed: its exit status below is fatal.
KCH=$CHROOT/etc/apk/keys
mkdir -p "$KCH" || fail "cannot create $KCH"
SRC_KEY_SHA=$(sha256sum "$KEYS/$KEY.rsa.pub" | awk '{print $1}')
[ -n "$SRC_KEY_SHA" ] || fail "cannot hash $KEYS/$KEY.rsa.pub"
KCH_KEY_SHA=$(sha256sum "$KCH/$KEY.rsa.pub" 2>/dev/null | awk '{print $1}')
[ -n "$KCH_KEY_SHA" ] || KCH_KEY_SHA=-
if [ "$KCH_KEY_SHA" != "$SRC_KEY_SHA" ]; then
    cp "$KEYS/$KEY.rsa.pub" "$KCH/$KEY.rsa.pub" || fail "cannot stage the signer key into the chroot keyring"
    KCH_KEY_SHA=$(sha256sum "$KCH/$KEY.rsa.pub" | awk '{print $1}')
fi
[ "$KCH_KEY_SHA" = "$SRC_KEY_SHA" ] || fail "the chroot keyring copy of $KEY differs from the pmbootstrap keyring"
cp "$APK" "$CHROOT/tmp/kernel.apk" || fail "cannot stage apk for verify"
if ! APKVERIFY=$(chroot "$CHROOT" apk verify /tmp/kernel.apk 2>&1); then
    rm -f "$CHROOT/tmp/kernel.apk"
    fail "apk verify failed for the built kernel apk: $APKVERIFY"
fi
rm -f "$CHROOT/tmp/kernel.apk"
log "apk verify: $APKVERIFY"

# 6. The installed kernel must be the locally built one, byte for byte.
chroot_kernel=$(sha256sum "$CHROOT/boot/vmlinuz" | awk '{print $1}') || fail "cannot hash installed vmlinuz"
local_kernel=$(sha256sum "$KERNEL" | awk '{print $1}') || fail "cannot hash apk vmlinuz"
log "installed kernel sha256: $chroot_kernel"
log "built apk kernel sha256: $local_kernel"
[ "$chroot_kernel" = "$local_kernel" ] || fail "install used a different kernel than the local build"

# 7. Export. The modules tar is written as an uncompressed temp file in Linux
#    storage, never in /out and never through a pipe, so tar's exit status is
#    visible; only a successful tar is compressed, then the temp file is removed.
mkdir -p "$OUT/artifacts/kernel" "$OUT/artifacts/dtb" "$OUT/artifacts/initramfs"
cp -a "$KERNEL" "$OUT/artifacts/kernel/vmlinuz" || fail "cannot export vmlinuz"
cp -a "$DTB" "$OUT/artifacts/dtb/" || fail "cannot export dtb"
cp -a "$CHROOT/boot/initramfs" "$OUT/artifacts/initramfs/initramfs" || fail "cannot export initramfs"
cp -a "$APK" "$OUT/artifacts/$APK_BASE" || fail "cannot export apk"
MODSTZ="$OUT/artifacts/modules-$KV.tar.zst"
MODTAR=$LW/modules.tar
rm -f "$MODTAR" "$MODSTZ"
tar -C "$TREE/usr/lib/modules" -cf "$MODTAR" "$KV" || { rm -f "$MODTAR"; fail "tar failed for usr/lib/modules/$KV"; }
zstd -q -T0 -19 -f "$MODTAR" -o "$MODSTZ" || { rm -f "$MODTAR" "$MODSTZ"; fail "zstd failed for $MODTAR"; }
rm -f "$MODTAR"
log "modules: $(du -sh "$MODDIR" | cut -f1) packed -> $(stat -c %s "$MODSTZ") bytes"

# 8. Matching proof against the initramfs, read with bsdtar (cpio is not
#    installed in the image) and stored as a list: /init exists, at least one
#    real .ko(.zst|.gz|.xz) lives under lib/modules/$KV or usr/lib/modules/$KV,
#    and no module for any other kernel version is present.
INIT_LIST=$LW/initramfs.list
bsdtar -tf "$OUT/artifacts/initramfs/initramfs" >"$INIT_LIST" || fail "bsdtar cannot list the initramfs"
ENTRIES=$(wc -l <"$INIT_LIST" | tr -d ' ')
[ "$ENTRIES" -gt 0 ] || fail "initramfs listing is empty"
grep -Eq '^\.?/?init$' "$INIT_LIST" || fail "initramfs has no /init"
MODS=$(awk '
{
    p = $0
    sub(/^\.?\//, "", p)
    if (p !~ /^(usr\/)?lib\/modules\/[^\/]+\//) next
    sub(/^(usr\/)?lib\/modules\//, "", p)
    i = index(p, "/")
    v = substr(p, 1, i - 1)
    rest = substr(p, i + 1)
    if (rest ~ /\.ko(\.(zst|gz|xz))?$/) print v "|" rest
}' "$INIT_LIST")
COUNT_KV=$(printf '%s\n' "$MODS" | awk -F'|' -v kv="$KV" 'NF && $1 == kv' | wc -l | tr -d ' ')
COUNT_OTHER=$(printf '%s\n' "$MODS" | awk -F'|' -v kv="$KV" 'NF && $1 != kv' | wc -l | tr -d ' ')
OTHER_VERS=$(printf '%s\n' "$MODS" | awk -F'|' -v kv="$KV" 'NF && $1 != kv {print $1}' | sort -u | tr '\n' ' ')
log "initramfs: $ENTRIES entries, $COUNT_KV module(s) for $KV, $COUNT_OTHER for other versions"
[ "$COUNT_KV" -ge 1 ] || fail "initramfs carries no .ko for modules $KV (lib/modules or usr/lib/modules)"
[ "$COUNT_OTHER" -eq 0 ] || fail "initramfs carries modules for other kernels: $OTHER_VERS"

# 8b. BusyBox from the verified initramfs, for the ztOS packager. The build
#     environment has no busybox, so the only trusted copy is the one mkinitfs
#     put into this initramfs. Exported: bin/busybox, every applet it reports as
#     a relative symlink in bin/, and - only if it is dynamically linked - its
#     PT_INTERP and NEEDED libraries. Nothing else from the initramfs is
#     exported (no rootfs copy). Fail-closed: no busybox, a non-ELF busybox, an
#     applet name that is not a plain file name, an unresolvable dynamic
#     dependency, an exported link that would dangle, or a chroot of the export
#     that cannot execute /bin/sh stops the finalize.
BBTREE=$LW/initramfs-tree
rm -rf "$BBTREE"
mkdir -p "$BBTREE"
bsdtar -xpf "$OUT/artifacts/initramfs/initramfs" -C "$BBTREE" || fail "bsdtar cannot unpack the exported initramfs into $BBTREE"
BBMEMBER=$(cd "$BBTREE" && find . -type f \( -name busybox -o -name 'busybox.*' \) | sed 's|^\./||' | grep -E '^(usr/)?(s?bin)/busybox(\.|$)' | sort | head -1)
[ -n "$BBMEMBER" ] || fail "no bin/busybox (or sbin/usr-bin variant) inside the initramfs"
BB="$BBTREE/$BBMEMBER"
[ "$(od -An -tx1 -N4 "$BB" | tr -d ' \n')" = 7f454c46 ] || fail "initramfs $BBMEMBER is not an ELF binary"
# readelf is the only way to tell static from dynamic and to read PT_INTERP and
# DT_NEEDED, so a missing readelf is fatal instead of quietly exporting a
# dynamic busybox without its loader/libs.
command -v readelf >/dev/null 2>&1 || fail "readelf is not available in the container; cannot inspect $BBMEMBER"
BB_PHDR=$(readelf -l "$BB" 2>/dev/null) || fail "readelf -l cannot read the program headers of $BBMEMBER"
BB_DYN=$(readelf -d "$BB" 2>/dev/null) || fail "readelf -d cannot read the dynamic section of $BBMEMBER"
BB_SHA=$(sha256sum "$BB" | awk '{print $1}')
BB_SIZE=$(stat -c %s "$BB")
EXP=$OUT/artifacts/initramfs
# A re-run must not leave applets or libs from an earlier attempt behind: the
# export subtrees are rebuilt. The initramfs file itself lives in the same
# directory and is kept.
rm -rf "$EXP/bin" "$EXP/sbin" "$EXP/usr" "$EXP/lib"
rm -f "$EXP/applets.txt"
mkdir -p "$EXP/bin"
cp -a "$BB" "$EXP/bin/busybox" || fail "cannot export busybox"
chmod 0755 "$EXP/bin/busybox"
EXP_SHA=$(sha256sum "$EXP/bin/busybox" | awk '{print $1}') || fail "cannot hash the exported busybox"
[ "$EXP_SHA" = "$BB_SHA" ] || fail "exported bin/busybox sha256 $EXP_SHA != initramfs $BBMEMBER sha256 $BB_SHA"
BB_INTERP=$(printf '%s\n' "$BB_PHDR" | sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p' | head -1)
if [ -n "$BB_INTERP" ]; then
    BB_LINKAGE=dynamic
else
    BB_LINKAGE=static
fi
BB_LIBS=
INTERP_DEST=
if [ "$BB_LINKAGE" = dynamic ]; then
    # Interpreter first, then every DT_NEEDED. Runtime paths are kept: the
    # interpreter goes to its own path, a bare library name goes into the search
    # directory that matched it (lib/, usr/lib/, ...) and never to '/', which is
    # not on the loader's search path - that placement is what made a bare
    # libc.musl-aarch64.so.1 unresolvable at runtime.
    NEEDED=$(printf '%s\n' "$BB_DYN" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p')
    BB_SEEN=
    for dep in "$BB_INTERP" $NEEDED; do
        case " $BB_SEEN " in
            *" $dep "*) continue ;;
        esac
        BB_SEEN="$BB_SEEN $dep"
        SRC=$(dep_path "$BBTREE" "$dep")
        REAL=
        if [ -n "$SRC" ]; then
            REAL=$(dep_real "$BBTREE" "$SRC")
        fi
        case $dep in
            /*|*/*) DEST=${dep#/} ;;
            *) if [ -n "$SRC" ]; then DEST=$(dirname "$SRC")/${dep##*/}; else DEST=lib/${dep##*/}; fi ;;
        esac
        if [ -n "$REAL" ]; then
            mkdir -p "$EXP/$(dirname "$DEST")"
            # Symlinks are resolved first, so the export holds a real file and
            # nothing can dangle (lib/libc.musl-*.so.1 -> ld-musl-*.so.1 is a
            # link in musl's own tree).
            cp -a "$REAL" "$EXP/$DEST" || fail "cannot export $dep as $DEST"
            log "busybox dep $dep -> $DEST (from ${REAL#"$BBTREE"/})"
        else
            # Absent from the initramfs. The one satisfiable case is a libc
            # name: musl and glibc ship libc inside the loader file, so the
            # name is a link to the interpreter that is exported anyway.
            case $dep in
                libc.*|libc.so*|libc-*.so*) ;;
                *) fail "dynamic busybox needs $dep, which is not in the initramfs" ;;
            esac
            [ -n "$INTERP_DEST" ] || fail "dynamic busybox needs $dep, but the interpreter $BB_INTERP could not be resolved"
            mkdir -p "$EXP/$(dirname "$DEST")"
            if [ "$(dirname "$DEST")" = "$(dirname "$INTERP_DEST")" ]; then
                LINK_TARGET=${INTERP_DEST##*/}
            else
                LINK_TARGET=$(relpath "$(dirname "$DEST")" "$INTERP_DEST")
            fi
            ln -sfn "$LINK_TARGET" "$EXP/$DEST" || fail "cannot link $dep to the exported interpreter"
            log "busybox dep $dep is not in the initramfs; linked to the interpreter $INTERP_DEST"
        fi
        if [ "$dep" = "$BB_INTERP" ]; then
            INTERP_DEST=$DEST
        fi
        BB_LIBS="$BB_LIBS $DEST"
    done
    # No exported library may be dangling or point outside the export.
    for rel in $BB_LIBS; do
        LIB_REAL=$(readlink -f "$EXP/$rel" 2>/dev/null) || LIB_REAL=
        [ -n "$LIB_REAL" ] && [ -f "$LIB_REAL" ] || fail "exported $rel does not resolve to a file"
        case $LIB_REAL in
            "$EXP"/*) ;;
            *) fail "exported $rel resolves outside the export: $LIB_REAL" ;;
        esac
    done
fi
# Applet inventory. Two independent sources, unioned:
#   (a) applet links already in the initramfs: symlinks whose target basename is
#       busybox*, and files that share the busybox inode (hardlinked applets);
#   (b) the applet list the binary itself reports (`busybox --list`).
# (b) is authoritative, and it is what this initramfs actually relies on: its
# /init begins with '#!/bin/busybox ash' and runs `/bin/busybox --install -s` at
# boot, so an initramfs that ships no applet links at all is correct, not a
# defect - the links are created in the initramfs's writable tmpfs root at boot.
# Requiring upstream links (the previous behaviour) made a usable busybox
# unexportable. Executing the binary here is also the only way to prove the
# export is runnable, so the export is executed in a chroot again below.
# Exported names get explicit *relative* symlinks in bin/, never absolute
# (/bin/busybox would dangle in the packager's tree) and never 300 hardlinks.
APPLETS=$LW/initramfs-applets.txt
DECLARED=$LW/initramfs-declared-applets.txt
BB_LIST=$LW/busybox-applets-list.txt
rm -f "$APPLETS" "$DECLARED" "$BB_LIST"
BB_REAL=$(tree_real "$BBTREE" "$BBMEMBER") || fail "cannot resolve $BBMEMBER inside the initramfs tree"
[ -n "$BB_REAL" ] || fail "cannot resolve $BBMEMBER inside the initramfs tree"

# (a) applets already declared by the initramfs.
(cd "$BBTREE" && find . -type l -exec sh -c 'for l; do t=$(readlink "$l"); case "${t##*/}" in busybox|busybox.*) printf "%s\n" "${l#./}";; esac; done' sh {} +) | sort >"$DECLARED" \
    || fail "cannot enumerate busybox applet symlinks"
BB_DEVINO=$(stat -c '%d:%i' "$BB") || fail "cannot stat $BBMEMBER"
(cd "$BBTREE" && find . -type f -links +1) | sed 's|^\./||' | while IFS= read -r cand; do
    if [ "$cand" != "$BBMEMBER" ] && [ "$(stat -c '%d:%i' "$BBTREE/$cand")" = "$BB_DEVINO" ]; then
        printf '%s\n' "$cand"
    fi
done | sort >>"$DECLARED" || fail "cannot enumerate busybox hardlinks"
sort -u -o "$DECLARED" "$DECLARED"
while IFS= read -r link; do
    [ -n "$link" ] || continue
    APP_REAL=$(tree_real "$BBTREE" "$link") || fail "cannot resolve applet $link inside the initramfs tree"
    [ "$APP_REAL" = "$BB_REAL" ] || fail "applet $link resolves to '${APP_REAL:-nothing}', not to $BBMEMBER"
done <"$DECLARED"
BB_DECLARED=$(wc -l <"$DECLARED" | tr -d ' ')
log "applet links already in the initramfs: $BB_DECLARED"

# (b) the binary's own applet list, obtained by executing it in a chroot of the
#     unpacked initramfs. That chroot has the merged-usr layout (bin -> usr/bin,
#     lib -> usr/lib) and this busybox's interpreter, so it needs nothing else.
chroot "$BBTREE" "/$BBMEMBER" --list >"$BB_LIST.raw" 2>"$LW/busybox-applets-list.err" \
    || fail "cannot execute \`/$BBMEMBER --list\` in a chroot of the initramfs ($(tail -n 1 "$LW/busybox-applets-list.err" 2>/dev/null)); the binary cannot be run in this container"
grep -v '^[[:space:]]*$' "$BB_LIST.raw" | LC_ALL=C sort -u >"$BB_LIST" || fail "cannot normalise the busybox applet list"
rm -f "$BB_LIST.raw"
BB_REPORTED=$(wc -l <"$BB_LIST" | tr -d ' ')
[ "$BB_REPORTED" -ge 1 ] || fail "busybox --list reported no applets"
# An applet name must be one plain file name: no path separator, no traversal,
# no whitespace. '[' and '[[' are real applets, so the set is not narrowed to
# alphanumerics.
while IFS= read -r a; do
    case $a in
        ''|.|..|*/*|*[[:space:]]*) fail "busybox --list reported an unusable applet name: '$a'" ;;
    esac
done <"$BB_LIST"
# /init is a shell script, so sh is not optional.
grep -qx sh "$BB_LIST" || fail "busybox --list has no 'sh' applet; /init cannot run"
# A name the initramfs links but the binary does not implement is an
# inconsistency: exporting it would only produce "applet not found".
while IFS= read -r link; do
    [ -n "$link" ] || continue
    grep -qx "${link##*/}" "$BB_LIST" || fail "the initramfs links $link as a busybox applet, but \`busybox --list\` does not report that name"
done <"$DECLARED"
log "busybox --list: $BB_REPORTED applet name(s) ($BB_DECLARED already linked by the initramfs)"

awk '{printf "bin/%s|busybox\n", $0}' "$BB_LIST" >"$APPLETS" || fail "cannot build the applet export list"
BB_APPLETS=$(wc -l <"$APPLETS" | tr -d ' ')
[ "$BB_APPLETS" -ge 1 ] || fail "no applets to export for the busybox in the initramfs"
while IFS='|' read -r link target; do
    [ -n "$link" ] || continue
    case $link in
        */*) LINKDIR=${link%/*} ;;
        *) LINKDIR=. ;;
    esac
    if [ "$LINKDIR" = bin ]; then
        NEWTARGET=busybox
    else
        NEWTARGET=$(relpath "$LINKDIR" bin/busybox)
    fi
    mkdir -p "$EXP/$(dirname "$link")"
    ln -sfn "$NEWTARGET" "$EXP/$link" || fail "cannot export applet link $link"
done <"$APPLETS"
# Read the export back: every applet link is relative and resolves to exactly
# the exported busybox.
EXP_BB_REAL=$(readlink -f "$EXP/bin/busybox") || fail "cannot resolve the exported busybox"
while IFS='|' read -r link target; do
    [ -n "$link" ] || continue
    EXP_TARGET=$(readlink "$EXP/$link" 2>/dev/null) || EXP_TARGET=
    case $EXP_TARGET in
        '') fail "exported applet $link is missing" ;;
        /*) fail "exported applet $link has an absolute target: $EXP_TARGET" ;;
    esac
    EXP_LINK_REAL=$(readlink -f "$EXP/$link" 2>/dev/null) || EXP_LINK_REAL=
    [ "$EXP_LINK_REAL" = "$EXP_BB_REAL" ] || fail "exported applet $link does not resolve to the exported busybox (${EXP_LINK_REAL:-dangling})"
done <"$APPLETS"
# Functional proof: the export alone, chrooted, must execute /bin/sh and
# reproduce the same applet list. A missing loader/lib, a dangling applet or a
# busybox that cannot start fails here - the export is not taken on inspection.
CHOUT=$(chroot "$EXP" /bin/sh -c 'echo ztos-busybox-ok' 2>&1) || fail "a chroot of the export cannot execute /bin/sh: $CHOUT"
[ "$CHOUT" = ztos-busybox-ok ] || fail "a chrooted exported /bin/sh printed '$CHOUT', expected ztos-busybox-ok"
chroot "$EXP" /bin/busybox --list 2>/dev/null | LC_ALL=C sort -u >"$LW/export-applets-list.txt" \
    || fail "a chroot of the export cannot run /bin/busybox --list"
LIST_SHA_A=$(sha256sum "$LW/export-applets-list.txt" | awk '{print $1}')
LIST_SHA_B=$(sha256sum "$BB_LIST" | awk '{print $1}')
[ -n "$LIST_SHA_A" ] && [ "$LIST_SHA_A" = "$LIST_SHA_B" ] || fail "the exported busybox reports a different applet list than the busybox in the initramfs"
cp "$APPLETS" "$EXP/applets.txt" || fail "cannot write applets.txt"
rm -rf "$BBTREE"
log "busybox: $BBMEMBER -> artifacts/initramfs/bin/busybox ($BB_SIZE bytes, $BB_LINKAGE, sha256 verified in the export, $BB_APPLETS applet name(s) from busybox --list, relative symlinks, /bin/sh and --list re-executed in a chroot of the export)"
[ "$BB_LINKAGE" = static ] || log "busybox libs exported:$BB_LIBS"

# 9. Manifests. Record what was actually asserted, including the counts.
cd "$OUT"
{
    echo "device=$DEVICE"
    echo "kernel_pkg=$KERNEL_PKG"
    echo "kernel_version=$KV"
    echo "kernel_image=boot/vmlinuz (legacy gzip; EFI stub / *.efi rejected)"
    echo "kernel_magic=$MAGIC"
    echo "dtb=qcom/msm8917-xiaomi-ugglite.dtb"
    echo "source=built from pinned pmaports APKBUILD (linux-postmarketos-qcom-msm89x7 7.1.3-r1, tag v7.1.3-r1, sha512 pinned in APKBUILD)"
    echo "apk=$APK"
    echo "apk_file=$APK_BASE"
    echo "apk_signer_member=$SIGNER"
    echo "apk_verify=rc=0 $APKVERIFY"
    echo "installed_kernel_sha256=$chroot_kernel"
    echo "apk_kernel_sha256=$local_kernel"
    echo "modules_dir=usr/lib/modules/$KV"
    echo "modulesdir_count=1"
    echo "initramfs_entries=$ENTRIES"
    echo "initramfs_has_init=yes"
    echo "initramfs_kernel_modules=$COUNT_KV"
    echo "initramfs_other_kernel_modules=$COUNT_OTHER"
    echo "initramfs_busybox=initramfs/bin/busybox"
    echo "initramfs_busybox_member=$BBMEMBER"
    echo "initramfs_busybox_size=$BB_SIZE"
    echo "initramfs_busybox_sha256=$BB_SHA"
    echo "initramfs_busybox_linkage=$BB_LINKAGE"
    if [ "$BB_LINKAGE" = dynamic ]; then
        echo "initramfs_busybox_interp=$BB_INTERP"
        echo "initramfs_busybox_libs=${BB_LIBS# }"
    fi
    echo "initramfs_busybox_applets_source=busybox --list in a chroot of the unpacked initramfs ($BB_REPORTED name(s)); the initramfs itself ships $BB_DECLARED applet link(s) (its /init runs busybox --install -s at boot)"
    echo "initramfs_busybox_applet_links=$BB_APPLETS (initramfs/applets.txt: bin/<applet>|busybox; explicit relative symlinks in initramfs/bin/, each verified to resolve to initramfs/bin/busybox)"
    echo "initramfs_busybox_chroot_test=ok (chroot of initramfs/: /bin/sh -c printed the expected string and /bin/busybox --list matched the initramfs busybox)"
    echo "pmaports_head=$HEAD"
    echo "pmbootstrap=$(pmbootstrap --version)"
    echo "scope=kernel+modules+initramfs module tree+apk signature only; NOT a ztOS/Arch boot claim (pmOS /init must be adapted for ztOS)"
    echo "built_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >artifacts/manifest.txt || fail "cannot write manifest"
cp "$PMB_CFG" artifacts/pmbootstrap.cfg || fail "cannot copy pmbootstrap config"
# SHA256SUMS covers the kernel, dtb, initramfs, modules, apk and every file
# exported from the initramfs for the packager (busybox, its libs, applets.txt).
BB_SUMFILES=$(cd "$OUT/artifacts" && find initramfs -type f ! -path initramfs/initramfs | sort)
( cd artifacts && sha256sum kernel/vmlinuz dtb/msm8917-xiaomi-ugglite.dtb initramfs/initramfs \
    "modules-$KV.tar.zst" "$APK_BASE" $BB_SUMFILES >SHA256SUMS ) || fail "cannot write SHA256SUMS"
( cd artifacts && sha1sum kernel/vmlinuz dtb/msm8917-xiaomi-ugglite.dtb initramfs/initramfs >SHA1SUMS ) \
    || fail "cannot write SHA1SUMS"
log "done: $OUT/artifacts (kernel, dtb, initramfs, modules-$KV.tar.zst, $APK_BASE, initramfs/bin/busybox)"
