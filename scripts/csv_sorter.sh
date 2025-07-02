#!/usr/bin/env bash
#
# csv_sorter.sh
#
# This script reorders all files matching relationship_*.csv in the current directory
# so that any “empty” rows (lines starting with a comma) appear immediately after
# the header. This ensures that later, “proper” rows won’t overwrite valid annotation
# data when imported (e.g. into Neo4j). Each file is processed in-place.
for f in relationship_*.csv; do
  {
    head -n1 "$f"                     # only once: the header
    tail -n +2 "$f" | grep '^,'       # empty rows from line 2 onward
    tail -n +2 "$f" | grep -v '^,'    # good rows from line 2 onward
  } > "$f.tmp"

  mv "$f.tmp" "$f"
done
