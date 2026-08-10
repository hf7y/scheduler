#!/usr/bin/env python3
"""WIP / exploratory, committed as-is 2026-08-10 -- not polished or finished,
pending a higher-level design pass (see the tracking issue linked from the PR
that added this file).

Detect near-identical text blocks duplicated across schedule/*.conf prompt
fields (BATCH_PROMPT, SWEEP_PROMPT). See
tests/conf-prompt-duplication-witness.sh for the rationale and the 8-line
threshold's reasoning. Prints one "DUP ..." line per finding and exits 1 if
any are found, 0 otherwise. Exits 2 on a usage/parse error.
"""
import difflib
import re
import sys

FIELDS = ("BATCH_PROMPT", "SWEEP_PROMPT")


def extract_prompts(path):
    with open(path, "r") as f:
        text = f.read()
    out = {}
    for field in FIELDS:
        m = re.search(r'^%s="' % field, text, re.MULTILINE)
        if not m:
            continue
        start = m.end()
        i = start
        n = len(text)
        while i < n:
            c = text[i]
            if c == "\\":
                i += 2
                continue
            if c == '"':
                break
            i += 1
        value = text[start:i]
        start_line = text[:start].count("\n") + 1
        lines = value.split("\n")
        out[field] = (start_line, lines)
    return out


def entries_for(paths):
    entries = []
    for p in paths:
        for field, (start_line, lines) in extract_prompts(p).items():
            nb = [(start_line + idx, l.rstrip()) for idx, l in enumerate(lines) if l.strip() != ""]
            if nb:
                entries.append((p, field, nb))
    return entries


def find_duplicates(paths, threshold):
    entries = entries_for(paths)
    findings = []
    for i in range(len(entries)):
        for j in range(i + 1, len(entries)):
            conf_a, field_a, lines_a = entries[i]
            conf_b, field_b, lines_b = entries[j]
            if conf_a == conf_b:
                continue
            a_texts = [t for _, t in lines_a]
            b_texts = [t for _, t in lines_b]
            sm = difflib.SequenceMatcher(a=a_texts, b=b_texts, autojunk=False)
            for block in sm.get_matching_blocks():
                if block.size >= threshold:
                    a_start = lines_a[block.a][0]
                    a_end = lines_a[block.a + block.size - 1][0]
                    b_start = lines_b[block.b][0]
                    b_end = lines_b[block.b + block.size - 1][0]
                    findings.append(
                        (conf_a, field_a, a_start, a_end, conf_b, field_b, b_start, b_end, a_texts[block.a])
                    )
    return findings


def main(argv):
    if len(argv) < 3:
        print("usage: conf-prompt-dup-detect.py THRESHOLD conf1 [conf2 ...]", file=sys.stderr)
        return 2
    threshold = int(argv[1])
    paths = argv[2:]
    findings = find_duplicates(paths, threshold)
    for (ca, fa, sa, ea, cb, fb, sb, eb, first) in findings:
        print(
            "DUP %s(%s):%d-%d == %s(%s):%d-%d first-line=%r"
            % (ca, fa, sa, ea, cb, fb, sb, eb, first)
        )
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
