#!/bin/bash

set -u
set -e

# Arguments:
# $1: the images directory
IMAGES_DIR="$1"

echo "ARM64 build completed - use direct kernel boot (Option 1) for easiest startup"