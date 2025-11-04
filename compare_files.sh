#!/bin/bash
# Compare files between two directories
# Usage: ./compare_files.sh <dir1> <dir2>

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <directory1> <directory2>"
    exit 1
fi

diff -rq "$1" "$2" | grep -E "^Files|^Only" | head -20
