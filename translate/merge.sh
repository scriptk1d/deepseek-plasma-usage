#!/bin/sh
# SPDX-FileCopyrightText: 2026 cassidy
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Re-extracts the translatable strings from the widget into template.pot.
# Run this after adding, changing or removing an i18n() call, then update the
# tables in translate/messages/ and run translate/build.sh.
#
#   ./translate/merge.sh           rewrite template.pot from the sources
#   ./translate/merge.sh --check   fail if template.pot is out of date (CI use)
#
# `--check` exists because nothing else notices. build.sh --check proves the .po
# and .mo files match the tables in translate/messages/, but an i18n() call added
# to a source file without re-extracting leaves template.pot silently short of a
# string -- and every catalogue short of it too, since the tables are keyed by the
# pot. That is a missing translation in a shipped widget, found by a user.
#
# Extraction runs in two passes because gettext needs a different parser for
# each language: QML is parsed as C++-like, the js/ modules as JavaScript.
# (Parsing the js/ modules with the C++ parser produces a spurious
# "unterminated character constant" warning for wallet.js's shell quoting.)
#
# Keywords are the KDE set: i18n(msgid), i18nc(context, msgid),
# i18np(msgid, plural), i18ncp(context, msgid, plural).

set -eu

DIR=$(cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(cd -- "$DIR/.." && pwd)

KEYWORDS="-ci18n -ki18n:1 -ki18nc:1c,2 -ki18np:1,2 -ki18ncp:1c,2,3"
COMMON="--from-code=UTF-8 --width=200 --add-location=file --package-name=ai-usage -kde"

checkOnly=
if [ "${1:-}" = "--check" ]; then
    checkOnly=1
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# --- pass 1: QML ----------------------------------------------------------
# Relative paths so the "#:" references in the catalogues stay portable.
cd "$ROOT"
find contents -name '*.qml' | sort > "$DIR/infiles.list"
if [ -s "$DIR/infiles.list" ]; then
    xgettext $COMMON $KEYWORDS -C \
        --files-from="$DIR/infiles.list" \
        -o "$tmpdir/qml.pot"
fi

# --- pass 2: JavaScript ---------------------------------------------------
find contents -name '*.js' | sort > "$DIR/infiles.list"
if [ -s "$DIR/infiles.list" ]; then
    xgettext $COMMON $KEYWORDS --language=JavaScript \
        --files-from="$DIR/infiles.list" \
        -o "$tmpdir/js.pot"
fi

rm -f "$DIR/infiles.list"

# --- merge ----------------------------------------------------------------
set -- "$tmpdir"/*.pot
if [ "$#" -eq 1 ]; then
    cp "$1" "$tmpdir/merged.pot"
else
    msgcat --use-first -o "$tmpdir/merged.pot" "$@"
fi

# --- install, or prove it would be a no-op --------------------------------
# The creation date is stamped on every run, so it cannot take part in the
# comparison.
strip_dates() {
    grep -v '^"POT-Creation-Date:' "$1" > "$2" || true
}

if [ -z "$checkOnly" ]; then
    mv "$tmpdir/merged.pot" "$DIR/template.pot"
    printf 'Wrote %s (%s strings)\n' "$DIR/template.pot" "$(grep -c '^msgid ' "$DIR/template.pot")"
    exit 0
fi

if [ ! -f "$DIR/template.pot" ]; then
    echo "translate/merge.sh: template.pot is missing -- run without --check" >&2
    exit 1
fi

# The extraction is compared after canonicalisation, because two gettext
# versions are in circulation: a developer's (Fedora's 0.25) and the CI
# runner's (Ubuntu's 0.21). They disagree about the order xgettext emits
# entries in and about whether "% used" looks like a printf format (the
# older one adds `#, c-format` for the "% u"). Both are tooling noise, not
# catalogue changes, so blocks are sorted and c-format lines dropped for the
# comparison only; the committed file keeps its own layout.
canonical() {
    awk 'BEGIN { RS = ""; ORS = "\n\n" } { gsub(/#, c-format\n/, "") } 1' "$1" |
        LC_ALL=C sort
}

strip_dates "$DIR/template.pot" "$tmpdir/old.pot"
strip_dates "$tmpdir/merged.pot" "$tmpdir/new.pot"
canonical "$tmpdir/old.pot" > "$tmpdir/old.canon"
canonical "$tmpdir/new.pot" > "$tmpdir/new.canon"

if ! diff -u "$tmpdir/old.canon" "$tmpdir/new.canon" > "$tmpdir/pot.diff"; then
    echo "translate/merge.sh: template.pot is out of date -- run without --check" >&2
    echo "  (an i18n() call was added, changed or removed and not re-extracted)" >&2
    sed 's/^/  /' "$tmpdir/pot.diff" | head -40 >&2
    exit 1
fi

echo "translate/merge.sh: template.pot is up to date ($(grep -c '^msgid ' "$DIR/template.pot") strings)"
