#!/usr/bin/env python3
"""Add new keys from a fresh game.toml template into a player's existing one.

The installer must never overwrite a config someone has tuned. But leaving the
fresh copy beside it as game.toml.new means a player who updates keeps running
the old file and never learns that the release added anything - the frame-rate
row and the one-click presets both live in game.toml, so to them the update
simply did nothing.

So: keep every value the player has, and append only the keys the template has
and their file does not, with the template's own comments attached. Nothing is
edited or removed, so a tuned value is safe by construction; the worst case is
that a key the player deliberately deleted comes back.

Some groups are ours, not the player's: the launcher presets and promoted
rows are product definitions rather than preferences, so those are replaced
wholesale from the template (--replace) instead of only added when absent -
otherwise a release that improves a preset would never reach anyone who
already has a config.

Usage:  merge_runtime_config.py [--replace SECTION]... <template> <existing>
Prints one line per addition. Exit 0 whether or not anything was added; exit 2
if either file cannot be parsed (the caller then leaves the .new file alone).
"""
import sys
import tomllib


def parse(path):
    with open(path, "rb") as fh:
        return tomllib.load(fh)


def parse_lines(lines):
    return tomllib.loads("\n".join(lines))


def blocks(lines):
    """Split a TOML file into (section, key, text) blocks.

    A block is one top-level key or one array-of-tables entry, together with
    the comment lines immediately above it - those comments are the reason a
    player can read our config at all, so they travel with the key.
    """
    out = []
    section = ""          # current [table] / [[array]] header, "" = document root
    pending = []          # comment/blank lines not yet attached to a key
    i = 0
    while i < len(lines):
        raw = lines[i]
        s = raw.strip()
        if not s or s.startswith("#"):
            pending.append(raw)
            i += 1
            continue
        if s.startswith("["):
            header = s.strip("[]")
            is_array = s.startswith("[[")
            if is_array:
                # Array-of-tables entry: the header plus every line until the
                # next header is one indivisible block.
                body = [*pending, raw]
                i += 1
                while i < len(lines) and not lines[i].strip().startswith("["):
                    body.append(lines[i])
                    i += 1
                while body and not body[-1].strip():
                    body.pop()
                out.append((header, None, body))
            else:
                section = header
                out.append((section, "__section__", [*pending, raw]))
                i += 1
            pending = []
            continue
        key = s.split("=", 1)[0].strip()
        body = [*pending, raw]
        i += 1
        # Continuation lines of a multi-line value (arrays spanning lines).
        depth = raw.count("[") - raw.count("]")
        while depth > 0 and i < len(lines):
            body.append(lines[i])
            depth += lines[i].count("[") - lines[i].count("]")
            i += 1
        out.append((section, key, body))
        pending = []
    return out


def has_path(doc, section, key):
    node = doc
    if section:
        for part in section.split("."):
            if not isinstance(node, dict) or part not in node:
                return False
            node = node[part]
    if key is None:                      # array-of-tables: section itself
        return True
    return isinstance(node, dict) and key in node


def main(argv):
    replace = []
    force = []
    args = []
    i = 1
    while i < len(argv):
        if argv[i] == "--replace" and i + 1 < len(argv):
            replace.append(argv[i + 1])
            i += 2
            continue
        if argv[i] == "--force-key" and i + 1 < len(argv):
            force.append(argv[i + 1])
            i += 2
            continue
        args.append(argv[i])
        i += 1
    if len(args) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    template_path, existing_path = args[0], args[1]
    try:
        template = parse(template_path)
        existing = parse(existing_path)
    except Exception as exc:                       # noqa: BLE001
        print(f"  config merge skipped ({exc})", file=sys.stderr)
        return 2

    with open(template_path, encoding="utf-8") as fh:
        template_lines = fh.read().splitlines()
    with open(existing_path, encoding="utf-8") as fh:
        existing_text = fh.read()

    existing_lines = existing_text.splitlines()
    # Drop keys whose VALUE the product owns and has changed - a layout move,
    # not a preference. Deleting the player's line makes it "missing", so the
    # normal add-what-is-absent pass below reinstates it from the template with
    # the template's value and comments. Used sparingly: mods_dir moved from
    # "patches" to "mods" when the enhancement tree took upstream's name, and
    # leaving a player's old value in place would have stranded them on a
    # per-disc tree no release writes to any more.
    if force:
        want = set(force)
        kept = []
        for section, key, body in blocks(existing_lines):
            if key is not None and key != "__section__" and \
                    (f"{section}.{key}" if section else key) in want:
                continue
            kept.extend(body)
        existing_lines = kept
        existing = parse_lines(existing_lines)
    # Drop the groups we own outright; the template's versions are appended
    # below like any other missing group.
    if replace:
        kept, dropped = [], 0
        for section, key, body in blocks(existing_lines):
            if key is None and section in replace:
                dropped += len(body)
                continue
            kept.extend(body)
        if dropped:
            existing_lines = kept
    existing_blocks = blocks(existing_lines)
    have_sections = {sec for sec, _key, _b in existing_blocks if sec}
    # array-of-tables headers the player's file already carries
    have_arrays = {sec for sec, key, _b in existing_blocks if key is None}

    additions = []       # (section, key, text-lines)
    for section, key, body in blocks(template_lines):
        if key == "__section__":
            continue
        if key is None:
            # Only add a whole array-of-tables group when the player has none
            # of that group at all - never duplicate entries they may have
            # edited or pruned.
            if section not in have_arrays:
                additions.append((section, None, body))
            continue
        if not has_path(existing, section, key):
            additions.append((section, key, body))

    if not additions:
        return 0

    # Insert each addition at the END of its section, so a key never lands
    # under a later table header and silently changes meaning.
    out = list(existing_lines)

    def section_end(name):
        """Index just past the last line belonging to section `name`."""
        if not name:
            # document root ends at the first table header
            for idx, line in enumerate(out):
                if line.strip().startswith("["):
                    return idx
            return len(out)
        start = None
        for idx, line in enumerate(out):
            if line.strip() in (f"[{name}]", f"[[{name}]]"):
                start = idx
                break
        if start is None:
            return None
        idx = start + 1
        last = idx
        while idx < len(out):
            if out[idx].strip().startswith("["):
                break
            if out[idx].strip():
                last = idx + 1
            idx += 1
        return last

    for section, key, body in additions:
        if key is None:
            out.extend(["", *body])                # arrays go at end of file
            continue
        at = section_end(section)
        if at is None:                             # section missing entirely
            out.extend(["", f"[{section}]", *body])
            continue
        out[at:at] = ["", *body]

    with open(existing_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out).rstrip("\n") + "\n")

    named = [f"[{s}] {k}" if s else k for s, k, _ in additions if k]
    groups = sorted({s for s, k, _ in additions if k is None})
    for item in named:
        print(f"  added {item}")
    for group in groups:
        n = sum(1 for s, k, _ in additions if k is None and s == group)
        print(f"  added [[{group}]] x{n}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
