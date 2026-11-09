#!/usr/bin/env python3
"""ugglite touch-key -> navigation mapper (evdev -> uinput, non-grabbing).

Physical keys (proven by a real user capture, see REPORT.md):
    left    KEY_LEFTMETA (125)
    centre  KEY_F1       (59)
    right   KEY_F2       (60)

Nav codes ztmetro understands (hwkey_nav(), ztmetro.c):
    KEY_APPSELECT 580 -> NAV_SEARCH   (left)
    KEY_HOMEPAGE  172 -> NAV_START    (centre)
    KEY_BACK      158 -> NAV_BACK     (right)

Short/long press is NOT timed here. The mapper forwards the whole press - both
edges, with the real duration - and ztmetro's own hardware-key timer does the
rest (ztmetro.c, keyboard_handle_key/hwkey_held_fired/nav_hold/nav_activate):

    press            -> hwkey_held = nav, timer = LONG_PRESS_MS (450 ms)
    held 450 ms      -> nav_hold():  left = keyboard toggle, centre = switcher,
                                     right = next app   (same as on-screen long)
    release < 450 ms -> nav_activate(): exactly the on-screen tap
    release > 450 ms -> nothing; there is no short action after a long one

So the mapper must never synthesise a tap of its own: one physical press is one
action, short or long, never both. The old release-edge-only version could not
produce a long press at all; emitting a tap on release would give the double.

Physical Super leak: event3 is registered as a keyboard (/proc/bus/input/
devices: H: Handlers=kbd), so its KEY_LEFTMETA reaches the seat as the Super
modifier before this process can see it. Emitting only on the release edge
dodged that but lost the duration. Instead the mapper remaps keycode 125 to
KEY_UNKNOWN (240) in the kernel evdev keycode table for the lifetime of the
process (EVIOCSKEYCODE_V2, index-based): no grab, no other key touched,
restored on exit, nothing persisted across reboot. The seat then never sees
Super; this mapper reads 240 and still sends APPSELECT. If the kernel refuses
the remap the mapper logs it and keeps working - navigation stays correct
because hwkey_nav() ignores modifiers, only the Super leak is left.

Fallback everywhere: no EVIOCGRAB, the touchscreen node stays ztmetro's; if this
process dies the physical keys are harmless again, the on-screen nav bar stays
visible, and the unit restarts the mapper.

The virtual device advertises KEY_BACK + KEY_HOMEPAGE, which is what ztmetro's
hardware_nav_keys() looks for, and that hides the on-screen nav bar on the NEXT
ztmetro start. install.sh pins `nav_bar = on` in the user config, which
load_config() applies after that check, so the bar stays as the fallback path.
Do not install the unit without that line.

Run as root (needs /dev/uinput, 0600 root:root, and CAP_SYS_ADMIN for the
keymap ioctl). PID goes to /run/ugglite-touchkey-nav.pid (NAVD_PIDFILE).
"""
import errno
import fcntl
import os
import select
import signal
import struct
import time

SRC = os.environ.get("NAVD_SRC", "/dev/input/event3")
PIDFILE = os.environ.get("NAVD_PIDFILE", "/run/ugglite-touchkey-nav.pid")
# NAVD_SILENCE_SUPER=0 keeps the physical Super (diagnostics only).
SILENCE_SUPER = os.environ.get("NAVD_SILENCE_SUPER", "1") != "0"

EVENT_SIZE = 24
EV_FMT = "<qqHHi"
UI_SET_EVBIT, UI_SET_KEYBIT, UI_DEV_CREATE, UI_DEV_DESTROY = (
    0x40045564, 0x40045565, 0x5501, 0x5502)
EV_SYN, EV_KEY = 0, 1
KEY_PRESS, KEY_RELEASE, KEY_REPEAT = 1, 0, 2

LONG_PRESS_MS = 450          # ztmetro.c: #define LONG_PRESS_MS 450 (log only)
SILENCED = 240               # KEY_UNKNOWN: no keysym, hwkey_nav() -> -1
SOURCE_LEFT = 125            # KEY_LEFTMETA

# evdev code -> nav code. 240 is the left key once Super is silenced.
MAP = {
    SOURCE_LEFT: 580,        # KEY_LEFTMETA -> KEY_APPSELECT
    59: 172,                 # KEY_F1       -> KEY_HOMEPAGE
    60: 158,                 # KEY_F2       -> KEY_BACK
    SILENCED: 580,           # silenced left -> KEY_APPSELECT
}
NAMES = {125: "LEFTMETA", 59: "F1", 60: "F2", 240: "UNKNOWN",
         580: "APPSELECT", 172: "HOMEPAGE", 158: "BACK"}

# struct input_keymap_entry {u8 flags; u8 len; u16 index; u32 keycode; u8 scancode[32];}
KEYMAP_FMT = "<BBHI32s"
INPUT_KEYMAP_BY_INDEX = 1
EVIOCGKEYCODE_V2 = 0x80284504
EVIOCSKEYCODE_V2 = 0x40284504

_stop = False


def _term(signum, frame):
    global _stop
    _stop = True


def log(msg):
    print("navd: " + msg, flush=True)


def emit(ui, typ, code, val):
    os.write(ui, struct.pack(EV_FMT, 0, 0, typ, code, val))
    if typ != EV_SYN:
        os.write(ui, struct.pack(EV_FMT, 0, 0, EV_SYN, 0, 0))


def make_uinput():
    fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
    # legacy struct uinput_user_dev (1116 bytes) - accepted on every kernel
    legacy = (b"ugglite-touchkeys".ljust(80, b"\0")
              + struct.pack("<HHHH", 0x19, 0, 1, 1)
              + struct.pack("<I", 0)
              + b"\0" * (64 * 4 * 4))
    os.write(fd, legacy)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    for code in sorted(set(MAP.values())):
        fcntl.ioctl(fd, UI_SET_KEYBIT, code)
    fcntl.ioctl(fd, UI_DEV_CREATE)
    return fd


def _keymap(fd, req, index, keycode=0):
    buf = struct.pack(KEYMAP_FMT, INPUT_KEYMAP_BY_INDEX, 0, index, keycode,
                      b"\0" * 32)
    out = fcntl.ioctl(fd, req, buf)
    flags, _len, _idx, got, _sc = struct.unpack(KEYMAP_FMT, out)
    return got


def _why(err):
    return errno.errorcode.get(err.errno, str(err))


def silence_super(src):
    """Remap KEY_LEFTMETA -> KEY_UNKNOWN on this device. True if it took."""
    try:
        was = _keymap(src, EVIOCGKEYCODE_V2, SOURCE_LEFT)
    except OSError as err:
        log("super: cannot read keymap slot %d (%s); Super will leak, "
            "navigation unaffected" % (SOURCE_LEFT, _why(err)))
        return False
    if was == SILENCED:
        log("super: keycode %d already maps to %d" % (SOURCE_LEFT, SILENCED))
        return True
    if was != SOURCE_LEFT:
        log("super: slot %d holds keycode %d, not %d; leaving it alone"
            % (SOURCE_LEFT, was, SOURCE_LEFT))
        return False
    try:
        _keymap(src, EVIOCSKEYCODE_V2, SOURCE_LEFT, SILENCED)
        back = _keymap(src, EVIOCGKEYCODE_V2, SOURCE_LEFT)
    except OSError as err:
        log("super: remap refused (%s); the seat still sees Super for the left "
            "key, navigation unaffected" % _why(err))
        return False
    if back != SILENCED:
        log("super: remap did not stick (slot reads %d), rolled back" % back)
        try:
            _keymap(src, EVIOCSKEYCODE_V2, SOURCE_LEFT, SOURCE_LEFT)
        except OSError:
            pass
        return False
    log("super: keycode %d -> %d on %s; the seat no longer sees Super"
        % (SOURCE_LEFT, SILENCED, SRC))
    return True


def restore_super(src):
    try:
        if _keymap(src, EVIOCGKEYCODE_V2, SOURCE_LEFT) == SILENCED:
            _keymap(src, EVIOCSKEYCODE_V2, SOURCE_LEFT, SOURCE_LEFT)
            log("super: keycode %d restored" % SOURCE_LEFT)
    except OSError as err:
        log("super: restore failed (%s); a reboot clears it" % _why(err))


def write_pidfile():
    try:
        with open(PIDFILE + ".tmp", "w") as f:
            f.write("%d\n" % os.getpid())
        os.rename(PIDFILE + ".tmp", PIDFILE)
    except OSError as err:
        log("pidfile %s: %s" % (PIDFILE, err))


def drop_pidfile():
    try:
        with open(PIDFILE) as f:
            if f.read().strip() == str(os.getpid()):
                os.unlink(PIDFILE)
    except OSError:
        pass


def press(ui, out):
    emit(ui, EV_KEY, out, KEY_PRESS)


def release(ui, code, out, held_ms):
    emit(ui, EV_KEY, out, KEY_RELEASE)
    log("%s(%d) -> %s(%d) held %d ms%s" % (
        NAMES.get(code, "?"), code, NAMES.get(out, "?"), out, held_ms,
        " (long)" if held_ms >= LONG_PRESS_MS else ""))


def main():
    signal.signal(signal.SIGTERM, _term)
    signal.signal(signal.SIGINT, _term)
    ui = make_uinput()
    src = os.open(SRC, os.O_RDONLY | os.O_NONBLOCK)
    silenced = silence_super(src) if SILENCE_SUPER else False
    if not SILENCE_SUPER:
        log("super: silencing disabled by NAVD_SILENCE_SUPER=0")
    write_pidfile()
    log("virtual device created (pid %d), reading %s (no grab); map=%s" % (
        os.getpid(), SRC, {NAMES.get(k, k): NAMES.get(v, v) for k, v in MAP.items()}))
    down = {}           # source code -> monotonic seconds of the press edge
    carry = b""         # an evdev read should end on an event boundary
    try:
        while not _stop:
            r, _, _ = select.select([src], [], [], 1.0)
            if _stop:
                break
            if not r:
                continue
            chunk = os.read(src, EVENT_SIZE * 64)
            if not chunk:
                continue
            buf = carry + chunk
            whole = len(buf) - len(buf) % EVENT_SIZE
            carry = buf[whole:]
            for off in range(0, whole, EVENT_SIZE):
                _, _, typ, code, val = struct.unpack(EV_FMT, buf[off:off + EVENT_SIZE])
                if typ != EV_KEY or code not in MAP:
                    continue
                out = MAP[code]
                if val == KEY_REPEAT:
                    continue        # a repeat would re-arm ztmetro's 450 ms timer
                if val == KEY_PRESS:
                    if code in down:
                        continue    # duplicate press: keep the first edge
                    down[code] = time.monotonic()
                    press(ui, out)
                else:
                    started = down.pop(code, None)
                    if started is None:
                        # pressed before we started: never lose the key, tap it
                        press(ui, out)
                        time.sleep(0.04)
                        release(ui, code, out, 40)
                        continue
                    release(ui, code, out,
                            int((time.monotonic() - started) * 1000))
    finally:
        for code in list(down):     # a key held at exit must not stay latched
            try:
                emit(ui, EV_KEY, MAP[code], KEY_RELEASE)
            except OSError:
                break
        if silenced:
            restore_super(src)
        os.close(src)
        fcntl.ioctl(ui, UI_DEV_DESTROY)
        os.close(ui)
        drop_pidfile()
        log("destroyed virtual device, pid %d exiting" % os.getpid())


if __name__ == "__main__":
    main()
