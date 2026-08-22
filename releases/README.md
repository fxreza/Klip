# releases/

Versioned builds, one folder per tag. Never overwrite a folder once published.

```
releases/
  v2.5.0-upstream/   <- baseline = upstream samirpatil2000/buffer tag buffer-v2.5.0 (unmodified)
  v3.0.0/            <- first release of this fork (folders, lock, clipfield UI, ...)
  v3.1.0/
```

Each folder holds: `Buffer_Silicon.dmg`, `Buffer_Silicon.zip`, `Buffer_Intel.dmg`, `Buffer_Intel.zip`, `release_notes.md`, and `checksums.txt`.

Build with `sh build_dmg.sh` (see RELEASE.md), then copy the artifacts here and into `dist/`.
Git tag format stays `buffer-vX.Y.Z` (matches upstream + UpdateService expectations).
