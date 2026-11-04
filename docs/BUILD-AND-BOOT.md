# Build and boot — the recipe, and its honest gaps

No image, kernel, firmware or binary is published. What follows is the source
path with every external input pinned by URL and commit, plus the exact place
where it still depends on something this repository cannot give you.

## Pinned inputs

| Input | Pin |
|---|---|
| ztOS (userspace) | `https://github.com/Zerone-Laboratories/ztOS` @ `94b35c2a1f4ceb568bc0ab60f5a1acebe7cfefaf` |
| pmaports | `https://gitlab.postmarketos.org/postmarketOS/pmaports` @ `39fe8995ea485a798ac8f1eff091b3962352e791` |
| kernel | `https://github.com/msm89x7-mainline/linux` tag `v7.1.3-r1` (pkgver 7.1.3, pkgrel 1; sha512 pinned in the pmaports APKBUILD) |
| lk2nd | `https://github.com/msm8916-mainline/lk2nd` @ `fd380ac637d1af38598e3f3c5321d4c962b96315`, subpackage `lk2nd-msm8952` |
| device package | `device-qcom-msm89x7` (pkgver 8, pkgrel 0) — ugglite is not a standalone pmOS device |
| DTB | `qcom/msm8917-xiaomi-ugglite.dtb` |

## Build environment

`build-environment/Dockerfile` builds a native **aarch64** Arch Linux ARM image
(`ztos-build-env:beta-1.2`). It is not an emulated build: ztOS *is* Arch Linux
ARM, so the toolchain, pacman and the rootfs ABI match the target and no
qemu/binfmt is involved.

```sh
git clone https://github.com/Zerone-Laboratories/ztOS.git
git -C ztOS checkout 94b35c2a1f4ceb568bc0ab60f5a1acebe7cfefaf
docker build -t ztos-build-env:beta-1.2 build-environment/
```

Docker is a **prerequisite**, not an implementation detail: `prepare-kernel.sh`
runs the kernel build in a separate container with
`--cap-add SYS_ADMIN --security-opt seccomp=unconfined` (no `--privileged`, no
docker socket, no USB), the project mounted read-only at `/src`, and the only
host write target `build/kernel`. This is what makes an aarch64 build possible
from a non-aarch64 host.

## Kernel

```sh
sh build-environment/prepare-kernel.sh           # container, pinned pmaports, no local APKBUILD edits
```

`finalize-kernel.sh` runs inside that container and is also the export-only
recovery path. It refuses to continue unless:

`BOOTSTRAP_PW` must be exported for the throwaway chroot account; the published
script has no default password and stops with an error if it is unset.

* `git -C $LW/aports rev-parse HEAD` equals the pinned pmaports commit,
* the pmaports APKBUILD files are unmodified and none are untracked,
* the package signature verifies — verification is never disabled, which is why
  the prebuilt `linux-postmarketos-qcom-msm89x7-7.1.3-r1.apk` from a third-party
  mirror is **not** used (its signer is not the pmaports key).

Kernel patches in `patches/kernel/` are applied to that tree in series order;
`patches/kernel/experimental/` is not part of the default series.

## Root filesystem and device layer

```sh
# assemble an Arch Linux ARM aarch64 root (pacstrap/arch-chroot or pmbootstrap)
sh devices/xiaomi-ugglite/layer.sh apply <root>   # copies overlay/ over an existing root
sh devices/xiaomi-ugglite/fixups.sh <root>        # idempotent: setuid, pacman sandbox
```

`layer.sh apply` only copies files into a root that already exists and already
has the pinned kernel and the ugglite DTB installed. It does not create a root,
install packages, partition anything or write `userdata`.
`device.toml` deliberately leaves `[boot].rootfs_target` unset — the carrier
choice belongs to whoever builds.

## Boot

Host-assisted, RAM-only:

```sh
# candidate image built from the pinned kernel + assembled root
fastboot boot <candidate-boot.img>     # boot, never flash
```

`build-environment/repack-boot-init.py` produces that image by replacing only the
`init` entry inside an existing boot image (same page size, same cmdline, same
dtb/second stage), which is how every display/UI candidate was made and rolled
back. lk2nd (`lk2nd-msm8952-23.1`) is the first stage: it hands over to the
candidate and stays flashed independently of it.

There is no default path that flashes a partition, no fallback to Android boot,
and no image with an unconditional `reboot -f` timer. The 120 s `reboot -f`
diagnostic image that existed during display bring-up is not published and is
not referenced by any recipe here.

## Gaps — what a stranger still cannot do end to end

1. **Root assembly is not automated.** `layer.sh` needs a pre-existing Arch
   Linux ARM root with the kernel package installed. The exact pacstrap package
   list, the ArchLinuxARM tarball revision and its checksum are **not pinned**
   anywhere in this project yet. This is the largest single gap.
2. **`prepare-kernel.sh` expects `/linux-work` inside the container** and a
   pmaports clone there (`$LW/aports`). The clone command is documented; the
   post-build verification accepts only the pinned HEAD, so a shallow clone of a
   different revision is a hard stop, not a silent drift.
3. **No hardware verification runs in this environment.** The build path is
   source-level only; nothing here was re-executed during packaging, and no
   image was produced.
4. **No installer, no recovery, no rollback image.** Publishing one is a
   separate scope (it writes `userdata`); only the architecture and parameters
   are described.
5. **`fixups.sh` correctness is unverified against a fresh 2026 Arch Linux ARM
   tree** — it was written for the tree that was assembled in October 2026.
