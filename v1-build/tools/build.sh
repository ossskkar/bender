#!/bin/sh
# The whole chain from Codex's V11: paint -> proportions -> hair -> parts.
#   sh build.sh <out.vrm>
set -e
cd "$(dirname "$0")/.."
python3 tools/make_white_suit.py arisu_v11_material_refine.vrm /tmp/arisu_build_1.vrm
python3 tools/reshape.py /tmp/arisu_build_1.vrm /tmp/arisu_build_2.vrm
python3 tools/long_hair.py /tmp/arisu_build_2.vrm /tmp/arisu_build_3.vrm
python3 tools/add_parts.py /tmp/arisu_build_3.vrm "$1"
rm -f /tmp/arisu_build_1.vrm /tmp/arisu_build_2.vrm /tmp/arisu_build_3.vrm
