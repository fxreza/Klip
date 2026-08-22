# Klip - working rules

## Build output directories end in `.noindex` - keep it that way

Two paths in this repo deliberately carry a `.noindex` suffix:

- `build.noindex/` - the local build output (`scripts/build_local.sh`,
  `scripts/run_app.sh`, `scripts/run_tests.sh`, `scripts/release.sh`)
- `dist/app.noindex/` - the unpacked live `Klip.app`
  (`scripts/release.sh`, `scripts/install_local.sh`)

Do not rename them back to `build/` and `dist/Klip.app`, and do not add a new
output directory without the suffix.

**Why.** macOS Spotlight never indexes a directory whose name ends in
`.noindex` (the same mechanism Xcode uses for DerivedData). Before this change
there were two `Klip.app` bundles in the Spotlight index - the real one in
`/Applications` and the build output here - so Spotlight and Raycast each showed
two identical results with no way to tell which one would launch. The suffix
hides the build output from the index, leaving `/Applications/Klip.app` as the
only hit. Source files are unaffected and stay searchable.

Note that `dist/` itself is **not** renamed: it is git-tracked (`.gitignore`
un-ignores `dist/*.dmg` and `dist/*.zip`) and referenced throughout `RELEASE.md`
and `docs/plan/`. Only the unpacked `.app` moved down into `dist/app.noindex/`.
A `.metadata_never_index` file does not work here - macOS honors that marker
only at a volume root, not in a subdirectory.

If you change an output path, keep the `.noindex` suffix and update the scripts
above, `.gitignore`, and `scripts/sync_xcodeproj.py`'s `EXCLUDED_DIR_NAMES`
together.
