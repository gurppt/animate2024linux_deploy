# The 7 XWinTab patches (for Flash / Animate)
Upstream XWinTab (Graham--M) targets Rebelle. Flash CS6 exercises code paths that
Rebelle never uses, exposing 6 bugs + 1 missing feature. Fixed here:

1. **Wintab ordinals** — Flash resolves wintab functions *by ordinal*, not by
   name. Added a `src/wintab32.def` with the spec's canonical ordinals
   (WTInfoW@1020, WTOpenW@1021, WTGetW@1061, WTClose@22, WTPacketsGet@23,
   WTPacketsPeek@80, WTEnable@40, WTOverlap@41, WTQueueSizeGet@84, WTQueueSizeSet@85)
   and build against this `.def` (instead of `--kill-at`).

2. **Accept a button-less stylus** (`check_device`) — it required
   `num_buttons > 0`. The Huion pen reports 0 buttons under libinput (they live on
   the PAD). Relaxed: only require `valuator_info && axes >= 3`; `nButtons` kept.

3. **WTInfoW(0,0)** — Flash probes for tablet presence via `WTInfoW(0,0)`; it was
   unhandled -> 0 -> "no tablet". Added the handler (returns the size of the
   LOGCONTEXTW when a device is selected).

4. **WTI_DEVICES (capabilities)** — Flash queries `DVC_PKTDATA/CSRDATA/X/Y/NPRESSURE`
   to enable the pressure UI; these were unhandled. Added the `cat==WTI_DEVICES`
   block (WTPKT mask + AXIS structs X/Y/NPRESSURE, pressure max read from the device).

5. **`pkt_peek_itr` typo** (WTPacketsPeek) — `(PktPeekIterData *) data` (casting the
   wrong variable, pointing at itself -> uninitialised pointer). Crash: read at
   address 0x8 (the `dst` member, offset 8). Fixed to `(PktPeekIterData *) userData`.

6. **WTPacketsPeek NULL guard** — Flash calls WTPacketsPeek with a NULL buffer to
   *count* packets; `packet_copy` then wrote to 0x0. Crash: write at address 0x0.
   Guarded with `if (data->dst) ...` (same as WTPacketsGet).

7. **Context re-bind in WTOpen** — Flash re-opens a context for every new document
   without ever calling WTClose. The old guard `if (g_context.handle ...) return NULL`
   returned NULL -> new document with no pressure. Fixed: if a context already
   exists, re-bind it to the new window (under g_lock) and return the existing
   handle. (Original symptom: pressure disappeared as soon as Flash was left with
   no document open at all.)

8. **Late-device rescan and stable XCB connection** — tablet proximity and Xorg
   naming can change after Animate's first probe. `setup()` now reuses a healthy
   XCB connection, falls back from an exact `XWINTAB_DEVICE` match to the
   conservative `stylus`/`pen` token matcher, and `WTOpenW` requests a fresh
   scan when the initial probe found no device. This is the pressure fix
   validated with the Huion monitor pen in Animate 2024.
