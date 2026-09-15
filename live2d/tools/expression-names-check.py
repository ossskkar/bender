#!/usr/bin/env python3
"""Every expression name arisu-face.js asks for is registered in that rig.

    expression-names-check.py <lain>/arisu/live2d

No browser needed. setExpression() looks expressions up by Name in the
.model3.json, so a name the table uses and the rig lacks does nothing, silently.
Exits with the number of missing names.
"""
import json, pathlib, re, sys

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '.')
src = (root / 'arisu-face.js').read_text()
body = src[src.index('var TABLES'):src.index('var GESTURE_GROUP')]
missing = 0
# Each rig's block: `Name: { states: {...}, reactions: {...} }`.
for m in re.finditer(r"\n\s{4}(\w+): \{(.*?)\n\s{4}\}", body, re.S):
    model, block = m.group(1), m.group(2)
    manifest = root / 'Resources' / model / f'{model}.model3.json'
    if not manifest.exists():
        continue
    have = {e['Name'] for e in json.loads(manifest.read_text())
            .get('FileReferences', {}).get('Expressions', [])}
    for name in sorted(set(re.findall(r"'([^']+)'", block))):
        if name not in have:
            print(f'  {model}: table uses {name!r}, rig has no such expression')
            missing += 1
print('PASS' if not missing else f'FAIL: {missing} missing')
sys.exit(missing)
