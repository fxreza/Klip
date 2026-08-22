#!/usr/bin/env python3
"""Sync Klip.xcodeproj/project.pbxproj with the on-disk source tree.

The canonical build (scripts/build_local.sh / build_dmg.sh) globs
`*.swift Models/*.swift Services/*.swift Views/**/*.swift`, so it never goes
stale. Klip.xcodeproj is a convenience for people who *do* have Xcode, and
without this script it silently drifts: file references pile up for files
that were deleted, and new files never get added.

This script parses project.pbxproj *textually* (it is an old-style ASCII
plist; NSPropertyListSerialization round-trips it but reformats everything,
which would make every future diff enormous). Instead we do targeted
line-level edits so re-running the script after new files are added produces
a small, readable diff.

For the app target (product type application) it:
  - drops PBXBuildFile / PBXFileReference / PBXGroup-child / Sources-phase
    entries for .swift files that no longer exist on disk;
  - adds those entries for every .swift file under Models/, Services/,
    Views/ (recursively) plus root-level *.swift files, skipping Tests/,
    BufferTests/, reference/, build/, scripts/; nested groups (e.g.
    "Views/History") are created on demand to mirror the folder layout;
  - adds PBXFileReference/PBXBuildFile entries (in the same group as the
    existing Cocoa.framework) plus a Frameworks-phase entry for each
    framework in NEW_FRAMEWORKS that isn't linked yet;
  - adds SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor; to the app target's and
    the test target's build configurations (the project-file equivalent of
    the build scripts' `-default-isolation MainActor`).

Object ids for anything the script adds are derived deterministically (a
truncated uppercase md5 of a stable key), so re-running with no source
changes produces byte-identical output. Anchors that already exist in the
file (native targets, build phases, groups, configurations) are *discovered*
by walking the project's own object graph rather than hardcoded, so the
script keeps working if ids are ever regenerated.

Usage:
    python3 scripts/sync_xcodeproj.py            # apply and rewrite the file
    python3 scripts/sync_xcodeproj.py --check    # report only; exit 1 if not in sync
"""
from __future__ import annotations

import re as _re
def _q(v):
    """Quote a pbxproj scalar when it contains characters outside the bare-word set."""
    return v if _re.fullmatch(r"[A-Za-z0-9_./]+", v) else '"' + v.replace('"', '\\"') + '"'


import argparse
import hashlib
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PBXPROJ_PATH = REPO_ROOT / "Klip.xcodeproj" / "project.pbxproj"

EXCLUDED_DIR_NAMES = {"Tests", "BufferTests", "reference", "build", "scripts"}
SOURCE_DIRS = ("Models", "Services", "Views")

# Frameworks the build scripts link beyond Cocoa (Cocoa is already wired up
# in the project file).
NEW_FRAMEWORKS = ["SwiftUI", "Carbon", "Vision", "Quartz", "QuickLookThumbnailing"]

OBJ_HEAD_RE = re.compile(r"^\t\t([0-9A-Za-z]+)(?: /\* (.*?) \*/)? = \{")
ISA_RE = re.compile(r"isa = (\w+);")


def gen_id(*parts: str) -> str:
    """Stable 24-hex-char id derived from a namespaced key, e.g. gen_id('fileref', path)."""
    digest = hashlib.md5("|".join(parts).encode("utf-8")).hexdigest().upper()
    return digest[:24]


def discover_swift_files() -> list[str]:
    """Every .swift file the app target should contain, as repo-relative POSIX paths."""
    found: set[str] = set()
    for top in SOURCE_DIRS:
        d = REPO_ROOT / top
        if not d.is_dir():
            continue
        for p in d.rglob("*.swift"):
            rel = p.relative_to(REPO_ROOT)
            if any(part in EXCLUDED_DIR_NAMES for part in rel.parts):
                continue
            found.add(rel.as_posix())
    for p in REPO_ROOT.glob("*.swift"):
        found.add(p.name)
    return sorted(found)


# --------------------------------------------------------------------------
# Low-level line-based helpers over the pbxproj's `objects = { ... }` body.
# Every object in this file (PBXBuildFile, PBXFileReference, PBXGroup,
# PBXNativeTarget, XCBuildConfiguration, ...) starts at exactly two tabs of
# indentation; nested dict/array bodies are indented one tab deeper, so
# scanning for the next line that is *exactly* "\t\t};" reliably finds the
# matching close even when the object contains its own nested { } (e.g.
# XCBuildConfiguration.buildSettings).
# --------------------------------------------------------------------------


def parse_objects(lines: list[str]):
    """Return {id: (comment, start, end, isa)} for every top-level object."""
    objects: dict[str, tuple[str | None, int, int, str | None]] = {}
    i = 0
    n = len(lines)
    while i < n:
        m = OBJ_HEAD_RE.match(lines[i])
        if not m:
            i += 1
            continue
        oid, comment = m.group(1), m.group(2)
        if lines[i].rstrip("\n").endswith("};"):
            start = end = i
            i += 1
        else:
            start = i
            j = i + 1
            while j < n and lines[j].rstrip("\n") != "\t\t};":
                j += 1
            end = j
            i = j + 1
        block_text = "".join(lines[start : end + 1])
        isa_m = ISA_RE.search(block_text)
        objects[oid] = (comment, start, end, isa_m.group(1) if isa_m else None)
    return objects


def block_text(lines: list[str], start: int, end: int) -> str:
    return "".join(lines[start : end + 1])


def find_array_insert_line(lines: list[str], start: int, end: int, array_name: str) -> int:
    """Index (within `lines`) of the "\t\t\t);" that closes `array_name = ( ... )`
    inside block [start, end]. Insert new entries just before this index."""
    open_re = re.compile(r"^\t\t\t" + re.escape(array_name) + r" = \($")
    for i in range(start, end + 1):
        if open_re.match(lines[i].rstrip("\n")):
            j = i + 1
            while lines[j].rstrip("\n") != "\t\t\t);":
                j += 1
            return j
    raise KeyError(f"array {array_name!r} not found in block {start}-{end}")


def find_dict_insert_line(lines: list[str], start: int, end: int, dict_name: str) -> int:
    open_re = re.compile(r"^\t\t\t" + re.escape(dict_name) + r" = \{$")
    for i in range(start, end + 1):
        if open_re.match(lines[i].rstrip("\n")):
            j = i + 1
            while lines[j].rstrip("\n") != "\t\t\t};":
                j += 1
            return j
    raise KeyError(f"dict {dict_name!r} not found in block {start}-{end}")


def get_attr(text: str, name: str) -> str | None:
    """Look up `name = value;` whether it's on its own indented line (a
    multi-line block, e.g. PBXGroup) or packed into a single-line entry
    (e.g. a PBXFileReference like `ID /* c */ = {isa = ...; path = X; };`)."""
    m = re.search(r"\b" + re.escape(name) + r" = (.*?);", text)
    if not m:
        return None
    value = m.group(1)
    if " /* " in value:  # e.g. "FFF00003 /* Build configuration list ... */"
        value = value.split(" /* ", 1)[0]
    return value.strip().strip('"')


def get_id_list(text: str, array_name: str) -> list[str]:
    m = re.search(
        r"^\t\t\t" + re.escape(array_name) + r" = \(\n(.*?)\n\t\t\t\);",
        text,
        re.M | re.S,
    )
    if not m:
        return []
    return re.findall(r"^\t\t\t\t([0-9A-Za-z]+) /\* .*? \*/,?$", m.group(1), re.M)


# --------------------------------------------------------------------------
# Project graph discovery (anchors are found, never hardcoded).
# --------------------------------------------------------------------------


class Project:
    def __init__(self, lines: list[str]):
        self.lines = lines
        self.objects = parse_objects(lines)

        project_id = next(oid for oid, (_, _, _, isa) in self.objects.items() if isa == "PBXProject")
        _, ps, pe, _ = self.objects[project_id]
        ptext = block_text(lines, ps, pe)
        self.main_group = get_attr(ptext, "mainGroup")

        app_target = None
        test_target = None
        for oid, (_, s, e, isa) in self.objects.items():
            if isa != "PBXNativeTarget":
                continue
            text = block_text(lines, s, e)
            ptype = get_attr(text, "productType")
            if ptype == "com.apple.product-type.application":
                app_target = (oid, text)
            elif ptype and "unit-test" in ptype:
                test_target = (oid, text)
        if app_target is None:
            raise RuntimeError("no application PBXNativeTarget found")
        self.app_target_id = app_target[0]
        self.test_target_id = test_target[0] if test_target else None

        self.app_sources_id, self.app_frameworks_id = self._phase_ids(app_target[1])
        self.app_config_ids = self._config_ids(app_target[1])
        self.test_config_ids = self._config_ids(test_target[1]) if test_target else []

        # Build the group tree: parent pointers + each group's own path segment.
        self.parent_of: dict[str, str] = {}
        self.path_segment: dict[str, str | None] = {}
        self._walk_group(self.main_group)

        # The child of mainGroup with path "." is the app's source root.
        self.app_root_group = None
        for cid in get_id_list(block_text(self.lines, *self.objects[self.main_group][1:3]), "children"):
            if self.objects.get(cid, (None,))[3] == "PBXGroup" and self.path_segment.get(cid) == ".":
                self.app_root_group = cid
                break
        if self.app_root_group is None:
            raise RuntimeError("could not find the app's root group (path '.') under mainGroup")

        # Locate the group that already holds framework references (the
        # parent of the existing Cocoa.framework file reference), so new
        # framework refs land in the same place without hardcoding an id.
        cocoa_id = None
        for oid, (comment, s, e, isa) in self.objects.items():
            if isa == "PBXFileReference" and comment == "Cocoa.framework":
                cocoa_id = oid
                break
        self.frameworks_group = self.parent_of.get(cocoa_id) if cocoa_id else None

    def _phase_ids(self, target_text: str) -> tuple[str, str]:
        phase_ids = get_id_list(target_text, "buildPhases")
        sources_id = frameworks_id = None
        for pid in phase_ids:
            isa = self.objects.get(pid, (None, None, None, None))[3]
            if isa == "PBXSourcesBuildPhase":
                sources_id = pid
            elif isa == "PBXFrameworksBuildPhase":
                frameworks_id = pid
        if not sources_id or not frameworks_id:
            raise RuntimeError("could not find Sources/Frameworks build phases for target")
        return sources_id, frameworks_id

    def _config_ids(self, target_text: str) -> list[str]:
        config_list_id = get_attr(target_text, "buildConfigurationList")
        _, s, e, _ = self.objects[config_list_id]
        return get_id_list(block_text(self.lines, s, e), "buildConfigurations")

    def _walk_group(self, gid: str):
        _, s, e, isa = self.objects[gid]
        if isa != "PBXGroup":
            return
        text = block_text(self.lines, s, e)
        self.path_segment[gid] = get_attr(text, "path")
        for cid in get_id_list(text, "children"):
            self.parent_of[cid] = gid
            if self.objects.get(cid, (None,))[3] == "PBXGroup":
                self._walk_group(cid)

    def full_path(self, fileref_id: str) -> str | None:
        """Repo-relative path for a file reference, or None if unreachable from mainGroup."""
        _, s, e, isa = self.objects.get(fileref_id, (None, None, None, None))
        if isa != "PBXFileReference":
            return None
        own_path = get_attr(block_text(self.lines, s, e), "path")
        if own_path is None:
            return None
        segments = []
        gid = self.parent_of.get(fileref_id)
        seen = set()
        while gid is not None and gid not in seen:
            seen.add(gid)
            seg = self.path_segment.get(gid)
            if seg and seg != ".":
                segments.append(seg)
            gid = self.parent_of.get(gid)
        segments.reverse()
        segments.append(own_path)
        return "/".join(segments)

    def is_under_app_root(self, oid: str) -> bool:
        gid = self.parent_of.get(oid)
        seen = set()
        while gid is not None and gid not in seen:
            if gid == self.app_root_group:
                return True
            seen.add(gid)
            gid = self.parent_of.get(gid)
        return False


# --------------------------------------------------------------------------
# Removal pass: drop every line whose leading token is an id slated for
# deletion. This single rule covers a fileRef's own definition, its
# PBXBuildFile's own definition, its appearance as a bare group-child entry,
# and its buildFile's appearance in a Sources/Frameworks phase list, because
# in all of those forms the id is the first token on the line.
# --------------------------------------------------------------------------


def strip_lines_with_leading_ids(lines: list[str], ids: set[str]) -> list[str]:
    out = []
    for line in lines:
        token = line.lstrip("\t").split(" ", 1)[0].rstrip(",")
        if token in ids:
            continue
        out.append(line)
    return out


def insert_lines(lines: list[str], index: int, new_lines: list[str]) -> list[str]:
    return lines[:index] + new_lines + lines[index:]


def sync(check_only: bool) -> int:
    original_text = PBXPROJ_PATH.read_text()
    lines = original_text.splitlines(keepends=True)

    proj = Project(lines)

    # ---- Step 1: find swift files to remove ----
    existing_swift: dict[str, str] = {}  # path -> fileref id
    for oid, (comment, s, e, isa) in proj.objects.items():
        if isa != "PBXFileReference":
            continue
        text = block_text(lines, s, e)
        if get_attr(text, "lastKnownFileType") != "sourcecode.swift":
            continue
        if not proj.is_under_app_root(oid):
            continue  # e.g. BufferTests/ClipboardItemTests.swift - never touched
        path = proj.full_path(oid)
        if path:
            existing_swift[path] = oid

    desired = set(discover_swift_files())
    to_remove_paths = sorted(p for p in existing_swift if p not in desired)

    # Map fileref id -> its PBXBuildFile id (via "fileRef = X" on one line).
    buildfile_of: dict[str, str] = {}
    for oid, (comment, s, e, isa) in proj.objects.items():
        if isa != "PBXBuildFile":
            continue
        text = block_text(lines, s, e)
        m = re.search(r"fileRef = ([0-9A-Za-z]+)", text)
        if m:
            buildfile_of[m.group(1)] = oid

    remove_ids: set[str] = set()
    for path in to_remove_paths:
        fref = existing_swift[path]
        remove_ids.add(fref)
        bf = buildfile_of.get(fref)
        if bf:
            remove_ids.add(bf)

    if remove_ids:
        lines = strip_lines_with_leading_ids(lines, remove_ids)
        # Re-parse: subsequent steps need fresh, correct block boundaries.
        proj = Project(lines)

    # ---- Step 2: framework additions ----
    existing_framework_names = set()
    for oid, (comment, s, e, isa) in proj.objects.items():
        if isa != "PBXFileReference":
            continue
        text = block_text(lines, s, e)
        if get_attr(text, "lastKnownFileType") == "wrapper.framework":
            name = comment or get_attr(text, "name") or get_attr(text, "path")
            if name:
                existing_framework_names.add(name.replace(".framework", ""))

    frameworks_added = []
    for fw in NEW_FRAMEWORKS:
        if fw in existing_framework_names:
            continue
        fref_id = gen_id("fileref", f"{fw}.framework")
        bf_id = gen_id("buildfile", f"{fw}.framework", "Frameworks")
        fref_line = (
            f'\t\t{fref_id} /* {fw}.framework */ = {{isa = PBXFileReference; '
            f'lastKnownFileType = wrapper.framework; name = {fw}.framework; '
            f'path = System/Library/Frameworks/{fw}.framework; sourceTree = SDKROOT; }};\n'
        )
        bf_line = (
            f"\t\t{bf_id} /* {fw}.framework in Frameworks */ = "
            f"{{isa = PBXBuildFile; fileRef = {fref_id} /* {fw}.framework */; }};\n"
        )

        # Insert file reference before "/* End PBXFileReference section */".
        fref_end = next(
            i for i, l in enumerate(lines) if l.strip() == "/* End PBXFileReference section */"
        )
        lines = insert_lines(lines, fref_end, [fref_line])
        # Insert build file before "/* End PBXBuildFile section */".
        bf_end = next(
            i for i, l in enumerate(lines) if l.strip() == "/* End PBXBuildFile section */"
        )
        lines = insert_lines(lines, bf_end, [bf_line])

        proj = Project(lines)
        # Add to the frameworks group's children.
        _, gs, ge, _ = proj.objects[proj.frameworks_group]
        idx = find_array_insert_line(lines, gs, ge, "children")
        lines = insert_lines(lines, idx, [f"\t\t\t\t{fref_id} /* {fw}.framework */,\n"])
        proj = Project(lines)
        # Add to the app's Frameworks build phase.
        _, fs, fe, _ = proj.objects[proj.app_frameworks_id]
        idx = find_array_insert_line(lines, fs, fe, "files")
        lines = insert_lines(lines, idx, [f"\t\t\t\t{bf_id} /* {fw}.framework in Frameworks */,\n"])
        proj = Project(lines)

        frameworks_added.append(fw)

    # ---- Step 3: swift file additions (create nested groups as needed) ----
    to_add_paths = sorted(p for p in desired if p not in existing_swift)

    def ensure_group_for_dir(dirpath: str) -> str:
        """Return the group id for `dirpath` (relative to the app root),
        creating any missing nested groups (named/pathed after each folder)."""
        nonlocal lines
        proj_local = Project(lines)
        current = proj_local.app_root_group
        if dirpath == "":
            return current
        prefix_parts: list[str] = []
        for segment in dirpath.split("/"):
            prefix_parts.append(segment)
            proj_local = Project(lines)
            _, cs, ce, _ = proj_local.objects[current]
            children = get_id_list(block_text(lines, cs, ce), "children")
            match = None
            for cid in children:
                if proj_local.objects.get(cid, (None,))[3] != "PBXGroup":
                    continue
                _, gs2, ge2, _ = proj_local.objects[cid]
                if get_attr(block_text(lines, gs2, ge2), "path") == segment:
                    match = cid
                    break
            if match is None:
                new_gid = gen_id("group", "/".join(prefix_parts))
                new_block = (
                    f"\t\t{new_gid} /* {segment} */ = {{\n"
                    f"\t\t\tisa = PBXGroup;\n"
                    f"\t\t\tchildren = (\n"
                    f"\t\t\t);\n"
                    f"\t\t\tpath = {_q(segment)};\n"
                    f'\t\t\tsourceTree = "<group>";\n'
                    f"\t\t}};\n"
                )
                group_end = next(
                    i for i, l in enumerate(lines) if l.strip() == "/* End PBXGroup section */"
                )
                lines = insert_lines(lines, group_end, new_block.splitlines(keepends=True))
                proj_local = Project(lines)
                _, cs, ce, _ = proj_local.objects[current]
                idx = find_array_insert_line(lines, cs, ce, "children")
                lines = insert_lines(lines, idx, [f"\t\t\t\t{new_gid} /* {segment} */,\n"])
                match = new_gid
            current = match
        return current

    files_added = []
    for path in to_add_paths:
        dirpath, _, basename = path.rpartition("/")
        group_id = ensure_group_for_dir(dirpath)

        fref_id = gen_id("fileref", path)
        bf_id = gen_id("buildfile", path, "Sources")
        fref_line = (
            f"\t\t{fref_id} /* {basename} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = sourcecode.swift; path = {_q(basename)}; "
            f'sourceTree = "<group>"; }};\n'
        )
        bf_line = (
            f"\t\t{bf_id} /* {basename} in Sources */ = "
            f"{{isa = PBXBuildFile; fileRef = {fref_id} /* {basename} */; }};\n"
        )

        fref_end = next(
            i for i, l in enumerate(lines) if l.strip() == "/* End PBXFileReference section */"
        )
        lines = insert_lines(lines, fref_end, [fref_line])
        bf_end = next(
            i for i, l in enumerate(lines) if l.strip() == "/* End PBXBuildFile section */"
        )
        lines = insert_lines(lines, bf_end, [bf_line])

        proj = Project(lines)
        _, gs, ge, _ = proj.objects[group_id]
        idx = find_array_insert_line(lines, gs, ge, "children")
        lines = insert_lines(lines, idx, [f"\t\t\t\t{fref_id} /* {basename} */,\n"])

        proj = Project(lines)
        _, ss, se, _ = proj.objects[proj.app_sources_id]
        idx = find_array_insert_line(lines, ss, se, "files")
        lines = insert_lines(lines, idx, [f"\t\t\t\t{bf_id} /* {basename} in Sources */,\n"])

        files_added.append(path)

    # ---- Step 4: SWIFT_DEFAULT_ACTOR_ISOLATION on app + test configurations ----
    proj = Project(lines)
    configs_updated = []
    for cid in proj.app_config_ids + proj.test_config_ids:
        _, cs, ce, _ = proj.objects[cid]
        text = block_text(lines, cs, ce)
        if "SWIFT_DEFAULT_ACTOR_ISOLATION" in text:
            continue
        idx = find_dict_insert_line(lines, cs, ce, "buildSettings")
        lines = insert_lines(lines, idx, ["\t\t\t\tSWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;\n"])
        configs_updated.append(cid)
        proj = Project(lines)

    new_text = "".join(lines)

    # ---- Step 5: sanity check - every swift PBXFileReference path must exist ----
    final_proj = Project(lines)
    missing = []
    for oid, (comment, s, e, isa) in final_proj.objects.items():
        if isa != "PBXFileReference":
            continue
        text = block_text(lines, s, e)
        if get_attr(text, "lastKnownFileType") != "sourcecode.swift":
            continue
        if not final_proj.is_under_app_root(oid):
            continue
        path = final_proj.full_path(oid)
        if path and not (REPO_ROOT / path).exists():
            missing.append(path)

    changed = new_text != original_text

    print("== sync_xcodeproj summary ==")
    print(f"swift files removed: {len(to_remove_paths)}")
    for p in to_remove_paths:
        print(f"  - {p}")
    print(f"swift files added: {len(files_added)}")
    for p in files_added:
        print(f"  + {p}")
    print(f"frameworks added: {frameworks_added or 'none'}")
    print(f"configurations updated with SWIFT_DEFAULT_ACTOR_ISOLATION: {len(configs_updated)}")
    if missing:
        print(f"WARNING: {len(missing)} referenced path(s) do not exist on disk:")
        for p in missing:
            print(f"  ! {p}")
    else:
        print("all referenced swift paths verified to exist on disk")

    if check_only:
        if changed:
            print("project.pbxproj is OUT OF SYNC (run without --check to fix)")
            return 1
        print("project.pbxproj is up to date")
        return 0

    if changed:
        PBXPROJ_PATH.write_text(new_text)
        print(f"wrote {PBXPROJ_PATH}")
    else:
        print("project.pbxproj already up to date; nothing written")
    return 1 if missing else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check", action="store_true", help="report differences without writing; exit 1 if out of sync"
    )
    args = parser.parse_args()
    sys.exit(sync(check_only=args.check))


if __name__ == "__main__":
    main()
