#!/usr/bin/env python3
"""Prune an extracted OpenCCU-Base source to the paths openccu-base-paths.txt lists.

Usage: prune_source.py PATHS_FILE SOURCE_DIR          delete everything in SOURCE_DIR the list
                                                       does not name, and the directories left empty
       prune_source.py --match PATHS_FILE PATH...     print, per PATH, the entry that matches it
                                                       or "-" (tab-separated)
       prune_source.py --list PATHS_FILE               print the entries (a syntax check)

package/openccu-base runs the first form as a post-extract hook (package/eq3_char_loop too), so the
build sees only what the list names. The list is git filter-repo's --paths-from-file format: a
plain line matches the path itself and everything below it (a trailing slash is allowed), a line
"regex:<re>" is a Python regular expression matched at the start of the path, blank lines and
"#" comments are ignored. The prune fails, and deletes nothing, when an entry matches no path:
upstream moved or dropped something the list names.
"""
import os
import re
import sys


class Entry:
    def __init__(self, lineno, text):
        self.lineno = lineno
        self.text = text
        if text.startswith("regex:"):
            self.pattern = re.compile(text[len("regex:"):])
            self.prefix = None
        elif text.startswith("glob:"):
            raise SystemExit("%d: glob: entries are not supported, use a path or regex: (%s)" % (lineno, text))
        else:
            self.pattern = None
            self.prefix = text.rstrip("/")
            if not self.prefix or self.prefix.startswith("/") or "/../" in "/%s/" % self.prefix:
                raise SystemExit("%d: not a relative path: %s" % (lineno, text))

    def matches(self, path):
        if self.pattern is not None:
            return self.pattern.match(path) is not None
        return path == self.prefix or path.startswith(self.prefix + "/")


def read_entries(paths_file):
    entries = []
    with open(paths_file, encoding="utf-8") as f:
        for lineno, line in enumerate(f, 1):
            text = line.strip()
            if not text or text.startswith("#"):
                continue
            entries.append(Entry(lineno, text))
    if not entries:
        raise SystemExit("%s names no path" % paths_file)
    return entries


def first_match(entries, path):
    for entry in entries:
        if entry.matches(path):
            return entry
    return None


def walk(root):
    """Yield every file and symlink below root as a relative POSIX path (symlinks are not followed)."""
    for dirpath, dirnames, filenames in os.walk(root):
        rel = os.path.relpath(dirpath, root)
        prefix = "" if rel == "." else rel.replace(os.sep, "/") + "/"
        for name in list(dirnames):
            if os.path.islink(os.path.join(dirpath, name)):
                dirnames.remove(name)
                yield prefix + name
        for name in filenames:
            yield prefix + name


def prune(paths_file, source_dir):
    entries = read_entries(paths_file)
    if not os.path.isdir(source_dir):
        raise SystemExit("not a directory: %s" % source_dir)
    keep, remove, used = [], [], set()
    for path in walk(source_dir):
        entry = first_match(entries, path)
        if entry is None:
            remove.append(path)
        else:
            keep.append(path)
            used.add(entry.lineno)
    unused = [e for e in entries if e.lineno not in used]
    if unused:
        for e in unused:
            print("prune_source: ERROR: %s:%d names nothing in %s: %s"
                  % (paths_file, e.lineno, source_dir, e.text), file=sys.stderr)
        raise SystemExit(1)
    if not keep:
        raise SystemExit("prune_source: nothing to keep in %s" % source_dir)
    for path in remove:
        os.unlink(os.path.join(source_dir, path))
    for dirpath, _dirnames, _filenames in os.walk(source_dir, topdown=False):
        if dirpath != source_dir and not os.listdir(dirpath):
            os.rmdir(dirpath)
    print("prune_source: %s: kept %d of %d files, %d entries of %s"
          % (source_dir, len(keep), len(keep) + len(remove), len(entries), paths_file))


def main(argv):
    if len(argv) >= 3 and argv[0] == "--match":
        entries = read_entries(argv[1])
        for path in argv[2:]:
            entry = first_match(entries, path.rstrip("/"))
            print("%s\t%s" % (path, entry.text if entry else "-"))
    elif len(argv) == 2 and argv[0] == "--list":
        for entry in read_entries(argv[1]):
            print(entry.text)
    elif len(argv) == 2 and not argv[0].startswith("-"):
        prune(argv[0], argv[1])
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
