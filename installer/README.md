# Guided installer

Run from the repository root:

```bash
./installer/install.sh --language en_US
```

The interactive installer uses a colour terminal interface, reports its
current stage and lets you choose the final installation directory. Downloads
use curl's progress bar with percentage, transfer rate and ETA. For scripted
use:

```bash
./installer/install.sh --install-dir /path/to/Animate2024 --language en_US --yes
```

After a successful deployment, a small installation record containing the
absolute path, UTC timestamp, unique installation ID and deploy commit is
written redundantly to:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/animate2024-linux/installation.conf
${XDG_CONFIG_HOME:-$HOME/.config}/animate2024-linux/installations.d/<ID>.conf
<INSTALLATION>/manifests/managed-install.conf
```

The installation root additionally contains:

```text
<INSTALLATION>/INSTALLATION-LOCATIONS.log
<INSTALLATION>/INSTALLATION.log
```

The first file is an English inventory of application, runtime, metadata and
log locations with supported and manual removal instructions. The second is a
copy of the successful installation transcript.

Every installer invocation also has a persistent console log:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/animate2024-linux/logs/
```

Running the installer again detects its records and offers safe uninstall.
If `.config` was removed, it searches managed manifests under
`~/.local/share` and `~/softs`. An explicit path is always available:

```bash
./installer/install.sh --install-dir /path/to/Animate2024 --uninstall
```

The non-interactive equivalent is:

```bash
./installer/install.sh --uninstall
```

Uninstall refuses to remove a directory unless both Animate and the generated
deployment manifests are present.

Downloads and prefix construction happen in the resumable work area; the
chosen final directory is populated only during stage 5. An existing empty
destination is accepted. A non-empty or already managed destination is
rejected during preflight, before any download. The interactive prompt accepts
only an absolute path or a path starting with `~/` and confirms it before
changing the system.

If installation fails, verified downloads and completed build state are kept
so the same command can resume. Once the prefix is validated, large decoded
payloads are removed before the final copy. After a successful installation,
the remaining workspace and download cache are removed automatically. Pass
`--keep-build-cache` to opt out for development or offline repetition.

The default path downloads the exact Creative Cloud shared components,
Animate 24.0.13.5 core and selected language package from Adobe's official
CDN. Every archive is accepted only after its pinned SHA-256 matches. It then
decodes Adobe's payload, constructs an identity-clean Proton prefix and
applies the P10/P11 Linux compatibility deploy.

It also downloads the exact GE-Proton 11-1, UMU Launcher 1.4.0 and SteamRT4
4.0.20260714.251823 releases. The final directory contains these runtimes, so
Steam and a system-wide Proton installation are not required. Missing host
packages are offered through the detected distribution's package manager.
On Debian, Ubuntu, Linux Mint and Pop!_OS, the installer enables the `i386` architecture
when necessary, refreshes APT indexes and installs the required 64/32-bit
graphics libraries. It deliberately does not run a full distribution upgrade.

Disk-space checks distinguish the final destination from the resumable work
area. When both are on the same filesystem, 20 GiB free is required. When they
are on separate filesystems, the destination requires 12 GiB and the work area
15 GiB. These conservative limits include interruption and filesystem
overhead; successful default installation removes its build cache.

For the owner's private bare-metal test, place the separately supplied
`Segoe-UI-Font-Family.zip` next to the cloned repository. The installer finds
that sibling file automatically, verifies the archive and all 12 selected
font faces, then installs them into the prefix. An explicit path also works:

```bash
ANIMATE_SEGOE_SOURCE=/path/to/Segoe-UI-Font-Family.zip \
  ./installer/install.sh
```

The font archive itself remains excluded from Git.

Useful commands:

```bash
./installer/install.sh --check
./installer/fetch-official-packages.sh --list-languages
./installer/install.sh --phase1 --language fr_FR
./installer/install.sh --phase2
```

An already installed legitimate prefix can be supplied without moving it:

```bash
ANIMATE_EXISTING_PREFIX=/path/to/prefix ./installer/install.sh
```

Do not commit anything placed in `installer/cache/`. Downloads, decoded
payloads and resumable state are intentionally ignored by Git.

The three-megabyte Adobe web stub is not required. Its WAM/WebView2 UI remains
unreliable under Wine; the direct official-CDN path obtains the same frozen
assets without copying account or activation state. Technical details and
patch reproduction details are tracked in `docs/PATCH_REPRODUCTION.md`.

Fresh-host status: clean Debian builds complete installation and reach Adobe's
official `susi_auth_workflow` without copied Adobe Credential Manager entries.
A separate virgin-machine launch nevertheless produced Adobe NGL error 10000
after the splash screen. Host and Wine WinHTTP endpoint checks succeed, so
account-clean interactive sign-in is still under investigation and is not yet
claimed as validated.
To force a genuinely account-clean build from the official Adobe packages,
even when a private local template is available:

```bash
ANIMATE_SOURCE_MODE=official ./installer/install.sh --all
```

The installer downloads Microsoft's pinned x64 WebView2 Fixed Version Runtime
directly from the official Microsoft CDN and obtains `WebView2Loader.dll` from
the official Microsoft NuGet package. Both downloads are SHA-256 verified
before extraction; no Windows WebView installer is executed. The version,
URLs, hashes and provenance are retained in the installed prefix.

Microsoft's pinned Visual C++ 2015–2022 x86 and x64 redistributables are also
downloaded directly from the official Visual Studio CDN and hash-verified.
Their signed CAB payloads are extracted deterministically into the clean
prefix; the Microsoft bootstrapper is not executed under Wine. This supplies
the native MFC runtime required by Animate's AIR extensions.

The MIT-licensed Flash/Animate XWinTab fork is vendored in
`vendor/xwintab`, including its source, eight documented compatibility fixes
and the validated x86-64 build. It is installed automatically so pressure
works when Animate is configured to use WinTab. No availability of the older
`flashcs6linux_deploy` repository is required.

The builder aborts if Wine Credential Manager entries for an Adobe account are
detected. Private templates may contain an already authenticated account and
must never be published or redistributed.
