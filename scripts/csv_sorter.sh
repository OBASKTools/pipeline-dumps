#!/usr/bin/env bash
#
# csv_sorter_by_length.sh
#
# This script reorders all files matching relationship_*.csv in the current directory
# so that the header stays first, and all other rows are sorted by line length
# This helps preserve order-sensitive processing, while keeping structural consistency.

for f in relationship_*.csv; do
  {
    head -n1 "$f"                                                            # Header
    tail -n +2 "$f" | awk '{ print length, $0 }' | sort -n | cut -d' ' -f2-  # Sort by line length
  } > "$f.tmp"

  mv "$f.tmp" "$f"
done
