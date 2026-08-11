#!/usr/bin/env python3
"""Detect prose duplicated across schedule/ prompt sources.

See tests/conf-prompt-duplication-witness.sh for why this exists, what the
threshold means, and how the ratchet works. This file is only the detector.

INPUTS are paths. A `*.conf` contributes its BATCH_PROMPT and SWEEP_PROMPT
values; any other file (in practice schedule/_standing-rules.md) contributes
its whole text as one entry. Including the shared fragment is the point of
the second form: after the extraction in #71 the interesting duplication is
no longer conf-vs-conf but a copy of the shared block re-inlined BACK into a
conf, and only comparing against the fragment catches that.

OUTPUT is one TSV line per finding, key fields first so a caller can project
a stable ratchet key with `cut -f1-3`:

    <fileA>:<fieldA> <TAB> <fileB>:<fieldB> <TAB> <sha12> <TAB> <n> <TAB> <a-range> <TAB> <b-range> <TAB> <first line>

sha12 is the first 12 hex of the sha256 of the matched block itself. It is
the key rather than the line numbers deliberately -- line numbers move when
unrelated prose above them is edited, which would make the ratchet need
re-accepting for changes that changed nothing, and re-accepting on autopilot
is how a baseline stops being read. Hashing the text also means an edit to
ONE of two copies changes the key and the finding goes red. That is not
brittleness, that is the alarm: divergence between copies is the failure the
whole check exists to name.

Exit 0 clean, 1 findings printed, 2 usage error. Paths are reported by
basename so a ratchet accepted on a laptop still matches in CI, where the
checkout lives somewhere else entirely.
"""
import difflib
import hashlib
import os
import re
import sys

FIELDS = ("BATCH_PROMPT", "SWEEP_PROMPT")

# Conf prompts are shell double-quoted strings, so a literal quote or dollar
# inside them is backslash-escaped; the same words in a .md are not. Without
# this the copy-back check above would miss any block containing a quote --
# a false negative in exactly the case the check was added for.
UNESCAPE = ((r"\"", '"'), (r"\$", "$"), (r"\`", "`"), (r"\\", "\\"))


def _unescape(s):
    for a, b in UNESCAPE:
        s = s.replace(a, b)
    return s


def extract_conf_prompts(text):
    """{field: (first_line_no, [lines])} for each prompt assignment present."""
    out = {}
    for field in FIELDS:
        m = re.search(r'^%s="' % field, text, re.MULTILINE)
        if not m:
            continue
        start = m.end()
        i, n = start, len(text)
        while i < n:
            if text[i] == "\\":
                i += 2
                continue
            if text[i] == '"':
                break
            i += 1
        out[field] = (text[:start].count("\n") + 1,
                      _unescape(text[start:i]).split("\n"))
    return out


def entries_for(paths):
    """[(label, field, [(line_no, text)])] -- blank lines dropped."""
    entries = []
    for p in paths:
        label = os.path.basename(p)
        with open(p) as f:
            text = f.read()
        if p.endswith(".conf"):
            found = extract_conf_prompts(text)
        else:
            found = {"FILE": (1, text.split("\n"))}
        for field, (start, lines) in found.items():
            nb = [(start + i, l.rstrip()) for i, l in enumerate(lines) if l.strip()]
            if nb:
                entries.append((label, field, nb))
    return entries


def find_duplicates(paths, threshold):
    entries = entries_for(paths)
    findings = []
    for i in range(len(entries)):
        for j in range(i + 1, len(entries)):
            la, fa, lines_a = entries[i]
            lb, fb, lines_b = entries[j]
            if la == lb:
                continue
            ta = [t for _, t in lines_a]
            tb = [t for _, t in lines_b]
            sm = difflib.SequenceMatcher(a=ta, b=tb, autojunk=False)
            for blk in sm.get_matching_blocks():
                if blk.size < threshold:
                    continue
                body = "\n".join(ta[blk.a:blk.a + blk.size])
                findings.append((
                    "%s:%s" % (la, fa),
                    "%s:%s" % (lb, fb),
                    hashlib.sha256(body.encode()).hexdigest()[:12],
                    blk.size,
                    "%d-%d" % (lines_a[blk.a][0], lines_a[blk.a + blk.size - 1][0]),
                    "%d-%d" % (lines_b[blk.b][0], lines_b[blk.b + blk.size - 1][0]),
                    ta[blk.a],
                ))
    # Sort by the ratchet key so output is stable across filesystem order.
    findings.sort(key=lambda f: (f[0], f[1], f[2]))
    return findings


def main(argv):
    if len(argv) < 3:
        print("usage: conf-prompt-dup-detect.py THRESHOLD path [path ...]",
              file=sys.stderr)
        return 2
    try:
        threshold = int(argv[1])
    except ValueError:
        print("conf-prompt-dup-detect.py: THRESHOLD must be an integer",
              file=sys.stderr)
        return 2
    findings = find_duplicates(argv[2:], threshold)
    for f in findings:
        print("\t".join(str(x) for x in f))
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
