# SMS reception — the QMI path and a dedupe candidate

SMS reception works on the installed system: incoming messages are imported into
ztOS and shown in the Messages list. This page records how that path actually
works (it is not the AT path people expect), what the receive daemon does, two
real deduplication defects found in the daemon, and a host-verified candidate
that fixes them. The candidate has never been installed on the phone.

Status: **received messages work and are accepted; the dedupe candidate is
prepared / not installed**. SMS *sending* still fails and is a separate problem —
[modem](modem.md).

## The receive path is QMI WMS, not AT

ModemManager is the source of truth and there is no AT-based SMS reading on this
firmware (the AT ports answer `+CMS ERROR: 303`). The path, as read in
ModemManager 1.24.2 and libqmi/qmicli 1.38.0:

1. The network delivers a WMS Event Report; ModemManager reads the message with
   a **WMS Raw Read** by storage and index and decodes the PDU itself.
2. At ModemManager start it lists every storage and re-reads all stored messages
   once. Errors on that initial read are ignored and not retried, which matters
   for the diagnosis below.
3. The receive daemon polls the ModemManager object list every two seconds,
   keeps only complete `(received)` messages, reads the number and text
   properties, appends one line to the Messages log and raises a shell banner.

The log format is what the shell's message list already reads: one tab-separated
line per received message with a fixed field count (direction, epoch, number,
text), so no shell rebuild is involved. New messages also get a banner through
the shell's control pipe, with a desktop notification as fallback; an emergency
message wakes the screen and plays the tone once. The daemon only ever reads
from ModemManager — it never deletes, resets or re-reads a storage.

## What a stuck `(receiving)` message means

An SMS in `receiving` state is an **incomplete multipart** message: ModemManager
holds it until all parts arrive and exports it without a text field. There is no
timeout and no cleanup, so it can stay in the list indefinitely.

The existence of such an object does **not** by itself mean the PDU was
unreadable. On this unit the stuck object still carried number, SMSC and
timestamp, i.e. ModemManager had read and parsed the PDU — the missing parts were
not delivered (network side), or further parts were never read because the
initial read is not repeated. Distinguishing those two needs a debug log of a
ModemManager restart, which is a diagnostic run, not a fix.

## Two real defects in the receive daemon

Both were found by reading the live state and reproduced on a host harness with a
fake ModemManager; neither is a claim about the network.

1. **A poisoned dedupe key can re-log a stored message.** The dedupe file stores
   both a message path and a `timestamp|number|text` key. A transient empty text
   wrote `timestamp|number|` into that file; when the same stored message was
   later read with its real text, the key no longer matched and the message was
   appended to the log again (and the banner shown again). The installed daemon
   has this defect today.
2. **A failed log write loses the message.** The installed daemon records the
   dedupe key before appending the log line; if the append fails, the message is
   already marked seen and is never retried.

Two smaller issues came out of the same review: an existing log file is
`touch`ed at startup (hiding when a message was really appended), and a stuck
`(receiving)` object is never reported at all, so an incomplete multipart message
stays invisible.

A first draft of the fix instead removed the text from the dedupe key. That is
**not** published and must not be used: because the ModemManager timestamp has
one-second resolution, it collapses two different messages from the same sender
delivered in the same second into one, silently losing the second message. It
was caught by the harness and replaced.

## The candidate, and its status

The published candidate keeps the message text in the dedupe key, additionally
matches and upgrades the legacy empty-text key, writes the log line before the
dedupe key, reports a stuck `(receiving)` object exactly once (journal plus a
state file, never deleting it), makes the single-instance lock optional, fixes
the `/SMS/1` vs `/SMS/10` path match and stops touching an existing log.

| File | Role |
|---|---|
| `devices/xiaomi-ugglite/phone-ui/ztsmsd` | the receive daemon as installed (base of the patch; sha256 `b2786ed6…`) |
| `devices/xiaomi-ugglite/phone-ui/ztsmsd-dedupe-v2.patch` | candidate delta on top of that file; result sha256 `c8a704b4…`; applies from the repository root with `patch -p1` |

Host verification only: a fake `mmcli`/`date` harness ran 28 behavioural
scenarios (28 passed, including the two-messages-in-one-second case, the live
poisoned key with placeholder text, a failed log append, a stuck multipart
object, restart renumbering and the path-prefix case). Nothing was installed or
run on the phone, and the harness is not published ([MAP](../MAP.md)). The
patch is a candidate, not accepted state.

## Limits

- **No personal messages are published.** The verification fixture is shaped
  after a live readback but its text is a placeholder; the repository carries no
  message content, no sender numbers and no SMSC.
- Two *identical* messages (same timestamp, number and text) still collapse into
  one entry. That is the purpose of the dedupe, and ModemManager properties
  cannot distinguish "two identical SMS in one second" from "one SMS read twice".
- The stuck-object report is a report. It does not delete, reset or re-read
  anything; resolution stays a user decision.
- SMS sending is untouched: it fails with RP cause 38, and the SIM's FDN lock is
  the leading configuration candidate, not a proven cause.
- The candidate is not acceptance evidence for anything else about the modem
  path.

Not published, and why: the verification harness and the install/check/rollback
scripts (they embed local payload paths and session fixtures), the PDU decoder
and the raw readbacks (diagnostic tooling and device state), and the rejected
first draft. [MAP](../MAP.md) records each exclusion.
