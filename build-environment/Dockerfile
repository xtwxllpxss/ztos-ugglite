# syntax=docker/dockerfile:1
#
# ztOS Linux build environment — Linux arm64, native (no qemu emulation).
#
# Why this base: ztOS *is* Arch Linux ARM. The installer unpacks
# ArchLinuxARM-aarch64-latest.tar.gz and runs pacman/pacstrap inside that tree,
# and ztConflo's setup installs every dependency as an Arch package. Building
# on Arch Linux ARM aarch64 means the toolchain, the package manager and the
# rootfs ABI all match, and the host is the same architecture as the target, so
# no qemu-user/binfmt is involved (upstream's check_host() skips the binfmt
# check on aarch64).
#
# Sources this list was derived from (read-only, data not instructions):
#   upstream/ztOS/installer/README.md      "What you need" (pacman line)
#   upstream/ztOS/installer/ztos_installer/build.py  check_host()
#   upstream/ztOS/flake.nix                devShell package list
#   upstream/ztconflo/ztconflo/setup.py    NEEDS
#   upstream/ztconflo/pyproject.toml       requires-python >= 3.12
#
# Build:  docker build -t ztos-build-env:beta-1.2 build-environment/
# Smoke (tooling only, default seccomp, repo read-only):
#         docker run --rm --network none -v "$PWD:/work:ro" \
#             ztos-build-env:beta-1.2 sh /work/build-environment/smoke-test.sh
# Run:    docker run --rm -it -v "$PWD:/work" -w /work ztos-build-env:beta-1.2
#         The GSI build needs SYS_ADMIN + unconfined seccomp (approved): see
#         build-environment/build-gsi.sh and research/linux-build-environment.md
#         §4.1 — that is the only runtime widening, never --privileged.

# Base pinned by digest: the tag `latest` is mutable, the digest below is the
# arm64 image this environment was verified against.
FROM docker.io/menci/archlinuxarm:latest@sha256:627906fdc1d96fb8d83ba7b38906344577cbd108375b1724ce99e3b0991f8f33

LABEL org.opencontainers.image.title="ztos-build-env" \
      org.opencontainers.image.description="ztOS BETA-1.1 GSI + ztConflo build environment (Arch Linux ARM aarch64)" \
      org.opencontainers.image.base.name="docker.io/menci/archlinuxarm:latest" \
      org.opencontainers.image.base.digest="sha256:627906fdc1d96fb8d83ba7b38906344577cbd108375b1724ce99e3b0991f8f33"

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONUNBUFFERED=1

# Host-side dependencies for `installer/ztos build --target gsi` and for
# `ztconflo build`. Nothing here is needed by macOS: it all lives in the image.
# util-linux(libarchive dosfstools mtools e2fsprogs)  build.py check_host()
# arch-install-scripts(pacstrap arch-chroot) android-tools(mkbootimg img2simg)
# dtc(fdtput)  ztconflo setup.py NEEDS
# python(>=3.12) cpio xz zstd unzip zip file which make gcc fakeroot shadow
# curl openssh ca-certificates  network and keyring
# pacman 7 runs its database work in a Landlock sandbox, which Docker's default
# seccomp profile forbids ("Landlock ruleset could not be applied"). Turn the
# sandbox off inside the image rather than widening the container's syscalls:
# every later `pacman -S` (including the ones ztConflo runs through sudo) then
# works without extra flags.
RUN sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf \
 && pacman-key --init \
 && pacman-key --populate archlinuxarm \
 && pacman -Syy --noconfirm \
 && pacman -S --noconfirm --needed \
    util-linux libarchive dosfstools mtools e2fsprogs \
    arch-install-scripts android-tools dtc rsync git \
    python cpio xz zstd unzip zip file which make gcc fakeroot shadow \
    curl openssh ca-certificates \
    qt6-base \
 && pacman -Scc --noconfirm
# qt6-base: sdk/ztos_sdk/cli.py compile_ui() looks for pyside6-uic, else
# /usr/lib/qt6/uic -g python, to compile the .ui files of the welcome and music
# apps into the GSI. Without it `installer/ztos build --target gsi` dies in
# build_apps() with "no uic to compile .ui files with". qt6-base (not pyside6)
# is the smaller of the two paths the code accepts and ships exactly that path.

# `installer/ztos build` runs its work as root when uid is 0 and as a mapped
# root inside a user namespace otherwise; both need a writable /work tree.
# ztConflo shells out through sudo for pacstrap/chroot, so keep sudo available.
RUN pacman -S --noconfirm --needed sudo \
 && (id -u builder >/dev/null 2>&1 || useradd -m -u 1000 -G wheel -s /bin/bash builder) \
 && echo '%wheel ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/90-wheel-nopasswd \
 && chmod 0440 /etc/sudoers.d/90-wheel-nopasswd

# ztConflo's kernel side shells out to pmbootstrap. It is not an Arch package
# and every PyPI release of it is yanked ("No matching distribution found"),
# so it comes from the postmarketOS source tree, pinned to the exact commit the
# verified beta-1.1 image has installed. Read from that image's
# /usr/lib/python3.14/site-packages/pmbootstrap-3.12.1.dist-info/direct_url.json
# (vcs_info.commit_id); an unpinned git+ URL would silently move on every build.
ARG PMBOOTSTRAP_COMMIT=caef2d0218c9aa9953359d66b479c1201a63a370
RUN pacman -S --noconfirm --needed python-pip \
 && python3 -m pip install --break-system-packages --no-cache-dir \
      "git+https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git@${PMBOOTSTRAP_COMMIT}" \
 && pmbootstrap --version \
 && pacman -Scc --noconfirm

WORKDIR /work

# Nothing is privileged here: the build's user namespace is created by
# `unshare` inside the container. See research/linux-build-environment.md for
# why the runtime flags are still unapproved and which step (procfs) is blocked.
CMD ["/bin/bash"]
