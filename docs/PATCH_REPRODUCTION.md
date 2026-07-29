# Patch implementation and reproduction notes

This document describes the compatibility work applied to the original
Adobe Animate payload and the GE-Proton/Wine runtime. It is intended for
developers reviewing or reproducing the patches. It does not describe the
end-user installer.

The patch set is deliberately split into:

- source-level Wine changes;
- application-local API proxies;
- one byte-verified `dvaui.dll` transformation;
- a vendored WinTab implementation;
- runtime configuration and read-only overlays.

No authentication token, account state, hardware identity, or licence check is
modified by these patches.

## 1. Frozen inputs and integrity boundary

The compatibility work targets these exact inputs:

| Input | Identity |
|---|---|
| Animate executable | `Animate.exe` SHA-256 `2f883658cd4691a705af370206ddc7e8a7c12457c0db9102b53e5afde3afe777` |
| Original UI library | `dvaui.dll` SHA-256 `89654093e3fc0fd2031ab1542573adae1667e3433afd7b66b6447e6e4604b9b8` |
| Wine source baseline | commit `31af7f983b2e345d11340b120ae3a39d88c9338a` |
| Native GDI+ backend | SHA-256 `980ea189929d95eb36e35980fff0c81f7b78de9422771fde8f4ac7a779f5bd89` |

The expected output identities are recorded in
[`manifests/VERSIONS.txt`](../manifests/VERSIONS.txt) and
[`manifests/reference.sha256`](../manifests/reference.sha256).

Do not apply the binary transformation to a DLL with a different hash. Source
patches should also be reviewed when rebasing onto another Wine tree because
the affected state machines and internal structures are not stable APIs.

## 2. Preparing the Wine source tree

Check out the recorded Wine source baseline, then apply the X11 and input
patches from the repository root:

```bash
git checkout 31af7f983b2e345d11340b120ae3a39d88c9338a
patch -p1 < patches/winex11-animate-P1-P2-P6g-P10.patch
patch -p1 < patches/P11_INPUT_COALESCE_A1.patch
```

`P11_INPUT_X11_A2.patch` is retained as a diagnostic experiment. The final
launcher preserves Win32 `WM_MOUSEMOVE` messages in the server, but does not
enable the X11 event-preservation experiment.

Build the 64-bit Wine tree using the normal out-of-tree procedure for the
selected GE-Proton source:

```bash
mkdir build64
cd build64
../configure --enable-win64
make -j"$(nproc)"
```

The final package takes these build products:

```text
server/wineserver
dlls/winex11.drv/winex11.so
dlls/win32u/win32u.so
dlls/kernelbase/kernelbase.dll
```

The P11 `win32u` and `kernelbase` sources are preserved as complete reference
files under [`reference/p11-properties-a2/`](../reference/p11-properties-a2/).
They must be rebuilt against the same Wine tree and headers.

## 3. X11 floating-palette state machine

Source:

```text
dlls/winex11.drv/window.c
```

Complete patch:

```text
patches/winex11-animate-P1-P2-P6g-P10.patch
```

### 3.1 P1: preserve Win32 visibility intent

Wine tracks three asynchronous window-manager states:

```text
desired_state -> pending_state -> current_state
```

An out-of-order `WM_STATE` event could replace a requested
`WithdrawnState`. The later replay would then use the window manager's value
instead of the visibility requested by Win32, leaving an owned popup mapped as
a shadow or ghost.

The patch snapshots `desired_state.wm_state` before
`handle_state_change()` and restores `WithdrawnState` when the incoming event
tries to cancel a pending Win32 hide:

```c
UINT wanted = *desired;

if (!handle_state_change(...)) return;
if (wanted == WithdrawnState && *desired != WithdrawnState)
    *desired = WithdrawnState;
```

This changes only the replayed intent. It does not synthesize visibility or
alter application window styles.

### 3.2 P2: accept an old serial carrying the requested value

The generic state handler rejected every property event whose serial preceded
the expected request:

```c
if (serial < *expect_serial) reason = "old ";
```

That is incorrect when the older notification already contains the pending
value. In that case the later request can be a no-op and no second
`PropertyNotify` will arrive. The state machine remains blocked indefinitely.

The patched condition is:

```c
if (serial < *expect_serial && memcmp(pending, value, size))
    reason = "old ";
```

The event is accepted only when its payload is byte-equal to the pending state.

### 3.3 P6g: activation-scoped EWMH stacking

Animate palettes are owned popups. While Animate is active they must remain
above the main Animate window, but they must not remain globally above other
Linux applications.

The patch follows the root `_NET_ACTIVE_WINDOW` property rather than X input
focus. It resolves the active X window to a Wine `HWND`, obtains the owning
process ID and compares it with `GetCurrentProcessId()`.

For managed palettes, it sends explicit EWMH remove/add transactions:

```c
new_state = (old_state & ~(above | below)) |
            (active ? above : below);
```

The opposite state is removed before the requested state is added. Wine's
desired and pending masks are updated to match the transaction.

For override-redirect palettes, the patch uses `XRaiseWindow()` on activation
and `XLowerWindow()` after a real external activation. A temporary zero
`_NET_ACTIVE_WINDOW` produced during popup drag/reparent is ignored.

The compatibility path is gated by:

```c
process_name && !strcasecmp(process_name, "Animate.exe")
```

It additionally requires a visible, owned, non-tiny popup and excludes
fullscreen windows.

### 3.4 P10: keep panel-sized `NOACTIVATE` popups unmanaged

Animate implements a floating panel group as multiple owned popups. If the
window manager reparents and constrains only the outer popup, the DVA content
can lose its pointer-relative offset during a move.

`is_window_managed()` now returns false for the narrow panel signature:

```c
if (process_name && !strcasecmp(process_name, "Animate.exe") &&
    (style & WS_POPUP) && (ex_style & WS_EX_NOACTIVATE) &&
    NtUserGetWindowRelative(hwnd, GW_OWNER) &&
    NtUserGetWindowRect(hwnd, &rect, NtUserGetDpiForWindow(hwnd)) &&
    rect.right - rect.left > 32 && rect.bottom - rect.top > 32)
    return FALSE;
```

The main window, child controls, modal dialogs and tiny implementation popups
do not match this predicate.

### 3.5 Window-manager name normalization

Muffin reports itself as `Mutter (Muffin)`. The patch normalizes that string to
`Mutter`, allowing the existing Mutter compatibility path to be used:

```c
if (!strcmp(data->window_manager, "Mutter (Muffin)"))
    strcpy(data->window_manager, "Mutter");
```

## 4. Drag-motion preservation in wineserver

Source:

```text
server/queue.c
```

Patch:

```text
patches/P11_INPUT_COALESCE_A1.patch
```

Wine normally coalesces successive `WM_MOUSEMOVE` messages. When Animate's UI
thread is busy, a fast pen or mouse drag can therefore collapse into a small
number of long straight segments.

The patch prevents server-side coalescing only while the left button is held
and the compatibility switch is enabled:

```c
if ((msg->wparam & MK_LBUTTON) &&
    env_flag_enabled("ANIMATE_PRESERVE_DRAG_MOVES",
                     &animate_preserve_drag_moves))
    return 0;
```

Normal hover motion and all applications launched without the environment
switch retain Wine's original behavior. Optional counters record received,
merged and queued events when `ANIMATE_INPUT_TRACE=1`.

The final launcher sets:

```text
ANIMATE_PRESERVE_DRAG_MOVES=1
```

## 5. `SetWindowPos` feedback-loop suppression

Source reference:

```text
reference/p11-properties-a2/win32u-window.c.patched
```

Target:

```text
dlls/win32u/window.c
```

Properties-panel reconstruction repeatedly submits identical
`SetWindowPos` operations for tiny child controls. Passing each one through
the full user-driver path creates redundant dvaui/Wine layout feedback.

The patch uses a 64-entry thread-local cache and returns early only when every
argument is identical. Its scope is intentionally strict:

```c
flags == (SWP_NOZORDER | SWP_NOACTIVATE)
after == 0
0 <= cx && cx <= 32
0 <= cy && cy <= 32
window belongs to the current thread
window has WS_CHILD
```

The behavior is enabled only with:

```text
ANIMATE_SWP_DEDUP=1
```

Top-level windows, palettes, cross-thread windows, z-order changes, activation
changes and differently sized/repositioned controls continue through the
original implementation.

## 6. Immutable SVG attribute cache

Source references:

```text
reference/p11-properties-a2/kernelbase-file.c.ge-base
reference/p11-properties-a2/kernelbase-file.c.patched
```

Target:

```text
dlls/kernelbase/file.c
```

Animate queries attributes for the same UI SVG resources many times while
rebuilding Properties. Each normal `GetFileAttributesW` call reaches
`NtQueryAttributesFile`.

The patch adds a fixed 2048-entry, process-local, open-addressed table protected
by an `SRWLOCK`. It stores both successful attributes and the corresponding
Win32 error for failed lookups.

Caching is opt-in and restricted to paths satisfying all of:

```text
contains "Adobe Animate 2024"
contains "\svg\"
extension equals ".svg" case-insensitively
```

The relevant gate is:

```c
return extension && !wcsicmp(extension, L".svg");
```

Documents, preferences, temporary files and mutable project assets cannot
enter the cache. The final launcher sets:

```text
ANIMATE_FILE_ATTR_CACHE=1
```

When reproducing this DLL, apply only the Animate attribute-cache diff to the
same GE-Proton `kernelbase/file.c`; retain the other GE-specific changes
already present in that baseline.

## 7. Native GDI+ proxy

Sources:

```text
reference/p11-properties-a2/gdiplus_proxy.c
reference/p11-properties-a2/gdiplus_proxy.def
```

The original Microsoft DLL is stored as `gdiplus_real.dll`. The proxy is named
`gdiplus.dll`, exports the complete GDI+ surface through the `.def` file, and
forwards unmodified calls directly to `gdiplus_real`.

Only selected APIs are intercepted.

### 7.1 Invalid-float detection

The common predicate rejects NaN and implausibly large values without requiring
the C math runtime:

```c
static int badf(float v)
{
    return (v != v) || (v > 1e18f) || (v < -1e18f);
}
```

### 7.2 Font metric repair

Disassembly and runtime tracing identified a dvaui calculation at
`dvaui+0x27f198` equivalent to:

```text
dy = penY - (cellAscent * fontSize) / emHeight
```

For a rejected or incomplete font family, GDI+ could return a failing status
with a zero output value. A zero `emHeight`, especially combined with another
zero metric, propagates NaN into the world transform and text rectangle.

The proxy supplies conservative design-unit values and returns `Ok` only when
the real call failed or returned zero:

```c
EmHeight   -> 2048
CellAscent -> 1854
CellDescent-> 434
LineSpacing-> 2355
```

It also replaces invalid or non-positive font sizes with `11.0f`.

### 7.3 Transform and measurement repair

The proxy:

- converts invalid `GdipTranslateWorldTransform` components to zero;
- sanitizes invalid `GdipMeasureString` bounds;
- sanitizes per-glyph positions passed to `GdipDrawDriverString`;
- repairs invalid `GdipDrawString` rectangles;
- retries drawing through a finite transform when the original call cannot
  consume the invalid state.

The repair is performed at the API boundary so normal finite calls remain
unchanged.

### 7.4 Timeline numeric cleanup

The final proxy recognizes the narrow draw pattern used by Timeline numeric
fields. It saves/restores the graphics state, clears the stale numeric field
rectangle, and redraws the current value with finite placement. Label draws
and unrelated text are excluded by content, geometry and formatting checks.

Optional tracing can be enabled with:

```text
ANIMATE_GDIPLUS_NUMERIC_TRACE=1
```

Trace output records UTF-16 code units, font size, rectangle, world transform
and string-format alignment. This was used to distinguish the FPS label, frame
label, current-frame value and stale previous value.

### 7.5 Building the proxy

Use a 64-bit MinGW compiler and the provided definition file:

```bash
x86_64-w64-mingw32-gcc -shared -O2 -o gdiplus.dll reference/p11-properties-a2/gdiplus_proxy.c reference/p11-properties-a2/gdiplus_proxy.def
```

Verify that the resulting PE imports only expected Windows runtime DLLs and
that intercepted exports resolve locally while the remaining exports forward
to `gdiplus_real`:

```bash
objdump -p gdiplus.dll
```

## 8. COM MTA bootstrap through `version.dll`

Sources:

```text
reference/version_proxy.c
reference/version_proxy.def
```

Some Adobe worker threads use COM before the expected multithreaded apartment
exists. An application-local `version.dll` proxy is loaded early through the
normal Windows DLL search order.

Its one-time initialization performs:

```c
CoIncrementMTAUsage(&cookie);
real = LoadLibraryW(L"version_real.dll");
```

All Version API exports are then forwarded to the renamed real implementation.
Initialization uses `InterlockedCompareExchange` so concurrent first calls
cannot initialize twice.

Build it with:

```bash
x86_64-w64-mingw32-gcc -shared -O2 -lole32 -o version.dll reference/version_proxy.c reference/version_proxy.def
```

Place the files beside `Animate.exe`:

```text
version.dll
version_real.dll
```

The DLL override is `version=n,b`, which selects the application-local proxy
before the builtin implementation.

## 9. Byte-verified `dvaui.dll` transformation

Reproducer:

```text
installer/lib/patch-dvaui.sh
```

The script accepts only the original hash, the intermediate P10 hash, or the
final hash. At every patch site it compares the expected bytes before writing
and verifies the complete output hash afterward.

### 9.1 PE address mapping

For this DLL:

```text
ImageBase        0x180000000
.text RVA        0x1000
.text file offset 0x400
```

Therefore:

```text
RVA = file_offset - 0x400 + 0x1000
```

### 9.2 Legacy P10 control-flow sites

The three P10 sites replace the initial vtable-load instruction with a short
jump and one NOP:

| File offset | RVA | Expected | Replacement | Destination |
|---:|---:|---|---|---:|
| `0x0c0ad8` | `0x0c16d8` | `48 8b 01` | `eb 16 90` | `0x0c16f0` |
| `0x0c89f1` | `0x0c95f1` | `49 8b 07` | `eb 3c 90` | `0x0c962f` |
| `0x147b20` | `0x148720` | `49 8b 07` | `eb 70 90` | `0x148792` |

Representative original disassembly:

```asm
; RVA 0x0c16d8
mov  rax, [rcx]
call qword ptr [rax+0x10]
...
mov  rax, [rcx]
call qword ptr [rax+0x08]

; RVA 0x0c95f1
mov  rax, [r15]
mov  r8d, 0xffffffff
mov  rdx, r12
mov  rcx, r15
call qword ptr [rax+0x28]

; RVA 0x148720, start of a measurement loop
mov  rax, [r15]
mov  rdi, [rax+0x28]
...
call rdi
```

The short jumps bypass these three problematic layout/measurement paths while
leaving the surrounding functions and unwind data intact. The patcher records
them separately as `P10-G`, `P10-I` and `P10-J`.

### 9.3 P11 recursive `Show` notifications

Two UI functions complete their own visibility/invalidation work and then call
the same dispatcher with notification value `3`. Runtime call tracing and
disassembly identified value `3` as the recursive `Show` notification that
walks the freshly rebuilt Properties subtree.

Original sequences:

```asm
; RVA 0x482aff
mov  edx, 3
mov  rcx, rbx
call 0x1804345b0

; RVA 0x494f2c
mov  edx, 3
mov  rcx, rbx
call 0x1804345b0
```

Only the five-byte calls are replaced with NOPs:

| File offset | RVA | Expected call | Replacement |
|---:|---:|---|---|
| `0x481eff` | `0x482aff` | `e8 ac 1a fb ff` | `90 90 90 90 90` |
| `0x49432c` | `0x494f2c` | `e8 7f f6 f9 ff` | `90 90 90 90 90` |

SetParent, child-added/removed, rectangle, scale, invalidation and generic
dispatch paths remain byte-identical.

The transformation chain is:

```text
original SHA-256
89654093e3fc0fd2031ab1542573adae1667e3433afd7b66b6447e6e4604b9b8

P10 SHA-256
e8db1826f637fba862ab8e695fd02e8a6589691b6aa0a379199003e92de04b50

final SHA-256
a2ba92552431b9733363936cb4f6b0ac4e08a356f3acfaf184323a3985a9f871
```

Run the deterministic patcher as:

```bash
./installer/lib/patch-dvaui.sh /path/to/original/dvaui.dll ./dvaui.patched.dll
```

## 10. WinTab/XInput implementation

The vendored source and its licence are under:

```text
vendor/xwintab/
```

The relevant changes from upstream are:

1. export canonical WinTab ordinals through `wintab32.def`;
2. accept a stylus with valuators but no buttons;
3. implement the `WTInfoW(0,0)` presence probe;
4. implement `WTI_DEVICES` X/Y/normal-pressure capability queries;
5. correct the `WTPacketsPeek` iterator cast;
6. allow a null destination when the application is only counting packets;
7. rebind an existing context when a document opens another WinTab context;
8. reuse a healthy XCB connection and rescan when no pen was initially found;
9. prefer a configured device, then a conservative `stylus`/`pen` name match,
   while rejecting tablet-pad pseudo-pressure.

Build scripts:

```text
vendor/xwintab/build64-def.sh
vendor/xwintab/build32-def.sh
```

The 64-bit runtime files installed into `windows/system32` are:

```text
wintab32.dll
XWinTabHelper.dll.so
```

The selected XInput device can be forced with `XWINTAB_DEVICE`. The launcher
otherwise searches for a Huion pen subdevice first, then for a non-pad device
advertising `Abs Pressure`.

## 11. Runtime overlay and DLL selection

The compatibility binaries are mounted or selected at launch rather than
blindly overwriting every baseline file:

| Runtime component | Patched implementation |
|---|---|
| `winex11.so` | X11 palette visibility, activation and unmanaged-popup rules |
| `wineserver` | left-drag motion preservation |
| `win32u.so` | tiny child `SetWindowPos` deduplication |
| `kernelbase.dll` | immutable Animate SVG attribute cache |
| `gdiplus.dll` | native-backend proxy and numeric-field repair |
| `dvaui.dll` | byte-verified layout and recursive-show changes |
| `version.dll` | COM MTA bootstrap and Version API forwarding |
| `wintab32.dll` | WinTab API surface |
| `XWinTabHelper.dll.so` | XInput device and pressure bridge |

The corresponding launcher switches are:

```text
ANIMATE_PRESERVE_DRAG_MOVES=1
ANIMATE_SWP_DEDUP=1
ANIMATE_FILE_ATTR_CACHE=1
```

Required DLL overrides include:

```text
gdiplus=n
wintab32=n
version=n,b
Visual C++ runtime DLLs=n,b
```

`gdiplus_real.dll` remains the native backend behind the proxy. The stock
runtime modules and original `dvaui.dll` should always be retained separately
for hash comparison and A/B testing.

## 12. Verification procedure

Before accepting a reproduced patch set:

1. verify all frozen input hashes;
2. confirm that each source patch applies without fuzz;
3. rebuild from a clean source tree;
4. compare exports and imports with `objdump -p`;
5. run the `dvaui.dll` byte patcher and verify its final hash;
6. verify the packaged files with `verify.sh`;
7. confirm that the compatibility environment variables are present;
8. test main-window activation and external-application activation;
9. test grouped palette move, resize, detach and merge;
10. test Properties with every tool, especially Rectangle;
11. test Timeline FPS/current-frame updates and repeated `F5`;
12. test fast mouse drags and pen-pressure drawing;
13. retest with every optional patch disabled independently.

The most important review rule is scope: every workaround must remain limited
to Animate-specific paths, styles, process names, immutable resources or
explicit environment switches. A generic Wine behavior change requires
separate upstream-quality justification and tests.
