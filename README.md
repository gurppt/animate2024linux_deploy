# Adobe Animate 2024 on Linux

<img width="1917" height="1076" alt="Adobe Animate 2024 running on Linux" src="https://github.com/user-attachments/assets/7a31b020-c207-4db6-9d28-82d841ce5759" />

This project installs and runs **Adobe Animate 2024 24.0.13.5** on Linux using
a pinned GE-Proton/UMU environment and a set of focused compatibility patches.
The result is self-contained and relocatable: it does not require Steam,
system-wide Wine, or a system-wide Proton installation.

The clean installer has been tested successfully on Linux Mint. Debian,
Ubuntu, Linux Mint and Pop!_OS are the currently supported Debian-family
targets. An **X11 session** is strongly recommended.

This repository does not contain Adobe application files, account data,
activation state, or licence bypasses. The installer downloads the frozen
application packages from Adobe's official CDN and verifies their hashes. A
legitimate Adobe licence/sign-in is still required where Adobe requests it.

## What works

- clean installation from a Git clone;
- document creation, editing, saving and reopening;
- canvas, Timeline, Properties, tools and floating palettes;
- pressure-sensitive drawing through WinTab/XInput;
- WebView2 and Adobe embedded components;
- hardware-accelerated or software-rendered launch;
- installation in a user-selected directory;
- managed uninstall and manual-removal documentation.

## Install from zero

### 1. Install Git

Debian, Ubuntu, Linux Mint or Pop!_OS:

```bash
sudo apt update
sudo apt install -y git
```

### 2. Clone the repository

```bash
git clone https://github.com/gurppt/animate2024linux_deploy.git
cd animate2024linux_deploy
```

### 3. Run the installer

```bash
./installer/install.sh
```

The guided installer:

1. asks where Animate should be installed;
2. checks the distribution, architecture and available disk space;
3. offers to install missing host packages with `sudo`;
4. enables Debian i386 multiarch when required by Proton;
5. downloads pinned Adobe, Microsoft, GE-Proton, UMU and SteamRT4 components;
6. verifies every downloaded archive;
7. builds an account-clean Windows prefix;
8. applies the Linux compatibility layers;
9. verifies the final installation;
10. removes temporary build data after success.

Use an absolute path when choosing the installation directory. For example:

```text
/home/gurp/softs/animate2024
```

For a non-interactive English installation:

```bash
./installer/install.sh --install-dir /home/gurp/softs/animate2024 --language en_US --yes
```

List the available language packages with:

```bash
./installer/fetch-official-packages.sh --list-languages
```

An interrupted installation can normally be resumed by running the same
command again. Verified downloads and completed build state are kept after a
failure. They are removed only after a successful installation unless
`--keep-build-cache` is used.

### 4. Launch Animate

Use the path selected during installation:

```bash
cd /home/gurp/softs/animate2024
./launch-animate2024.sh
```

Hardware acceleration is the default. If the New Document interface is black,
or the native graphics mode is unstable, use:

```bash
ANIMATE_GPU_MODE=safe ./launch-animate2024.sh
```

Safe mode uses software rendering and is slower. To explicitly request the
desktop GPU:

```bash
ANIMATE_GPU_MODE=native ./launch-animate2024.sh
```

Replace the example path in these commands if you selected another directory.

### 5. Optional application-menu shortcut

Set `INSTALL_DIR` to the directory selected during installation, then create a
desktop entry:

```bash
INSTALL_DIR="/home/gurp/softs/animate2024"
mkdir -p "$HOME/.local/share/applications"
printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Name=Adobe Animate 2024' 'Comment=Run Adobe Animate 2024 through GE-Proton' "Exec=env ANIMATE_GPU_MODE=native $INSTALL_DIR/launch-animate2024.sh" 'Terminal=false' 'Categories=Graphics;Development;' 'StartupNotify=true' >"$HOME/.local/share/applications/adobe-animate-2024.desktop"
chmod +x "$HOME/.local/share/applications/adobe-animate-2024.desktop"
```

If native graphics mode is not usable, change `ANIMATE_GPU_MODE=native` to
`ANIMATE_GPU_MODE=safe` in the desktop entry.

Some desktops update the application menu immediately. Otherwise, log out and
back in, or run this if available:

```bash
update-desktop-database "$HOME/.local/share/applications"
```

## Optional Segoe UI fonts

Segoe UI improves the metrics and appearance of some tabs, numeric fields and
Adobe panels. Fonts are not included in this repository. You must provide a
copy that you are legally allowed to use.

The currently supported archive is named:

```text
Segoe-UI-Font-Family.zip
```

Its expected SHA-256 is:

```text
c648c3ab81881ea55f725164e0164fc835e20972a0df87d40bb1898540514aed
```

The simplest method is to add the archive **before installation**.

### Method A: place it next to the clone

Example layout:

```text
~/Downloads/
├── animate2024linux_deploy/
└── Segoe-UI-Font-Family.zip
```

Then run:

```bash
cd ~/Downloads/animate2024linux_deploy
./installer/install.sh
```

### Method B: provide its exact path

```bash
ANIMATE_SEGOE_SOURCE="$HOME/Downloads/Segoe-UI-Font-Family.zip" ./installer/install.sh
```

The installer verifies the archive and all 12 selected font faces before
modifying the prefix. A different archive is rejected rather than installed
silently.

## Verify, diagnose or uninstall

Verify the installed files:

```bash
cd /home/gurp/softs/animate2024
./verify.sh
```

Collect host, GPU, runtime, WebView2 and Adobe NGL diagnostics:

```bash
./diagnose.sh
```

Uninstall using the Git clone:

```bash
cd animate2024linux_deploy
./installer/install.sh --uninstall
```

If the user configuration record was deleted, give the exact installation
path:

```bash
./installer/install.sh --install-dir /home/gurp/softs/animate2024 --uninstall
```

Every completed installation contains:

- `INSTALLATION-LOCATIONS.log`: English inventory of installed and external
  paths, plus manual-removal instructions;
- `INSTALLATION.log`: installer transcript;
- `logs/`: launch and recovery-watcher logs;
- `manifests/`: integrity hashes and managed-install metadata.

The uninstaller removes the self-contained Animate installation and its
matching user records. It intentionally leaves shared system packages in
place.

## Technical implementation

### Native MSXML3 cursor-property parser

The installer vendors a pinned 32-bit and 64-bit MSXML3 pair and launches
Animate with `msxml3=n`. This is required for DVA cursor metadata: Wine's
builtin MSXML3 rejects the otherwise valid property-list embedded in
`CursorDataID-17`, causing an `Error parsing properties list from memory`
dialog when the pointer crosses New Document presets. The launcher verifies
all four DLL hashes before starting Animate so the result does not depend on
the distribution's Wine or winetricks package version.

### Reproducible installation

The installer performs the following deterministic operations:

1. downloads the pinned Creative Cloud shared package, Animate 24.0.13.5 core
   and requested language package from Adobe's CDN;
2. verifies their SHA-256 values;
3. normalises Windows paths and decodes Adobe's raw-LZMA2 payloads;
4. creates a fresh Proton prefix without copied Adobe credentials;
5. installs the required Adobe Common Files, NGL and CEF components;
6. installs verified Microsoft GDI+, Visual C++ 2015–2022 and a fixed WebView2
   runtime;
7. applies the compatibility modules described below;
8. bundles GE-Proton 11-1, UMU Launcher 1.4.0 and the pinned SteamRT4 runtime;
9. writes integrity manifests and verifies the relocatable result.

Runtime auto-updates are disabled so the tested Wine/Proton behaviour cannot
change silently.

### COM/MTA startup

An application-local `version.dll` proxy initializes a process-wide
multithreaded COM apartment with `CoIncrementMTAUsage`, then forwards the
normal Version API calls to `version_real.dll`. This allows Adobe workers and
embedded web components to start with the COM model they expect.

### WebView2 and Microsoft runtimes

- A pinned x64 WebView2 Fixed Version Runtime is stored inside the prefix.
- Its versioned application path and EdgeUpdate registry entries are created.
- `WEBVIEW2_BROWSER_EXECUTABLE_FOLDER` selects that bundled runtime.
- Verified Visual C++ x86/x64 runtime DLLs are installed into the prefix.
- Native Microsoft GDI+ is used behind a compatibility proxy.

### GDI+, fonts and dynamic fields

The GDI+ proxy sanitizes invalid numeric data produced by Animate/dvaui:

- `NaN` translations and text coordinates;
- invalid font sizes and family metrics;
- zero-height or invalid text rectangles;
- failed string measurement/drawing fallbacks;
- Timeline FPS/frame-counter placement and stale-value cleanup.

The prefix includes Adobe Clean, removes problematic Wine bitmap-font
interference, records Windows font substitutions, and can optionally include
the verified Segoe UI family. A bubblewrap wrapper masks host font directories
to keep Adobe's font enumeration deterministic.

### Floating palettes and X11

The P10 `winex11.so` layer contains four scoped changes:

- **P1:** preserves popup visibility when the window manager temporarily
  reports a contradictory state;
- **P2:** accepts an older X11 property notification when it already contains
  the requested state;
- **P6g:** keeps Animate palettes above their owner only while Animate is the
  active host application;
- **P10:** leaves panel-sized owned `WS_EX_NOACTIVATE` popups unmanaged,
  preventing grouped palettes such as Color/Swatches from jumping away from
  the pointer.

Main windows, modal dialogs, tiny implementation windows and unrelated Wine
applications are excluded from these rules.

### Properties panel and tool latency

The P11 Properties layer combines five modules:

- `wineserver`: preserves intermediate `WM_MOUSEMOVE` events during
  left-button drawing drags;
- `win32u.so`: ignores strictly identical `SetWindowPos` requests for tiny
  same-thread child controls;
- `kernelbase.dll`: caches file attributes only for immutable
  `Adobe Animate 2024\svg\*.svg` resources;
- `gdiplus.dll`: supplies numeric-field and Timeline rendering fixes;
- `dvaui.dll`: removes two recursive Properties `Show` notifications after
  verifying the exact original bytes.

These changes reduce redundant Properties-panel reconstruction, especially
when selecting Rectangle, without caching documents or changing top-level
window behaviour.

### Tablet pressure

The vendored MIT XWinTab layer and its XInput helper:

- select the pen device exposing a real `Abs Pressure` axis;
- avoid selecting a tablet Pad pseudo-axis;
- support device-name fallback and rescanning;
- provide WinTab pressure to Animate.

Tablet pressure has currently been tested only with a Huion device, using a
0–2047 pressure range. Wacom tablets and other brands are untested at this
time.

### Recovery and relocation

A watcher detects Animate's recovery dialog when the splash screen hides it,
removes the covering splash and raises the dialog. At every launch, absolute
Proton symlinks inside the prefix are repaired and the installation directory
is exposed to pressure-vessel, allowing the complete directory to be moved or
renamed.

## Pinned versions

| Component | Version |
|---|---|
| Adobe Animate | 24.0.13.5 |
| GE-Proton | GE-Proton11-1 |
| UMU Launcher | 1.4.0 |
| SteamRT4 | 4.0.20260714.251823 |
| Wine source baseline | `31af7f983b2e345d11340b120ae3a39d88c9338a` |

The patches are tied to these versions and verified binary hashes. Do not
apply them to another Animate or Proton build without checking the expected
bytes and hashes.

## Known limitations

- X11 is the reference session; native Wayland is not yet the primary target.
- Safe GPU mode is slower because it uses software rendering.
- Adobe/CEF shutdown can take time, and Proton may report that some threads
  could not be suspended before its timeout.
- After `F5`, the Timeline frame value can briefly move during a dvaui relayout.
- Adobe authentication still depends on Adobe services and a legitimate
  account. If sign-in fails, preserve `INSTALLATION.log`, the installation
  `logs/` directory and the output of `diagnose.sh`.

## Project documentation

Developer-level source changes, disassembly sites and patch reproduction steps
are documented in
[`docs/PATCH_REPRODUCTION.md`](docs/PATCH_REPRODUCTION.md). The public
installer guide is available at [`installer/README.md`](installer/README.md).
