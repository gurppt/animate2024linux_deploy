# Pinned MSXML3 runtime

These files are the known-good native MSXML3 pair used by the canonical
Animate 2024 prefix. Both architectures are required because the prefix
contains 64-bit Animate components and 32-bit Adobe support processes.

| File | SHA-256 |
| --- | --- |
| `system32/msxml3.dll` | `dbebbda0c3f26ef348d239c5180d2559129944092095cd1764db0f197b1fbc9d` |
| `system32/msxml3r.dll` | `dcbf9db53a272510255a7500614933cee21165e1960ee149de2267152034b093` |
| `syswow64/msxml3.dll` | `a98ce3223f50eeb3fe9f1a28a81393bce13ab3d837dab8f5e66d260a669ce00d` |
| `syswow64/msxml3r.dll` | `b604ab2b27598de28a5ed89626c41e6ea551eae362e83ec421a52f426b31f551` |

The deployment copies these files into the Wine prefix and forces
`msxml3=n`. See `docs/PATCH_REPRODUCTION.md` for the native trace and failure
mechanism.
