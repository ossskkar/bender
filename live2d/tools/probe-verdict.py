#!/usr/bin/env python3
"""Score a Live2D probe run and say what each case actually saw.

    probe-verdict.py <cases-file> <results-file>

The cases file is `name<TAB>url<TAB>check`, one per line, in the same order as
the newline-delimited JSON in the results file. Prints one line per case:
`PASS <name> <json>` or `FAIL <name> <json>`, and exits with the number of
failures.

Its own file, and its own process, rather than an inline `python3 -c`: the check
expressions are full of quotes, and nesting them inside a shell single-quote
inside a Python double-quote is how a verification script ends up failing at a
line twenty lines from the actual mistake. It did exactly that twice.
"""

import json
import sys


def load_results(path):
    out = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if line:
                out.append(json.loads(line))
    return out


def load_cases(path):
    out = []
    with open(path) as fh:
        for line in fh:
            line = line.rstrip('\n')
            if not line.strip() or line.startswith('#'):
                continue
            parts = line.split('\t')
            while len(parts) < 3:
                parts.append('')
            out.append({'name': parts[0], 'url': parts[1], 'check': parts[2]})
    return out


def summarise(scene, model, frames, paint, d):
    """Just enough to see why a case went the way it did, without a wall of JSON."""
    return {
        'mode': scene.get('mode'),
        'room': scene.get('room'),
        'depth': scene.get('depth'),
        'spread': scene.get('spread'),
        'failed': scene.get('failed'),
        'display': scene.get('display'),
        'lit': model.get('lit'),
        'width': model.get('width'),
        'box': model.get('box'),
        'centre': model.get('centre'),
        'paint': paint or None,
        'ground': (d.get('ground') or {}).get('ground') and {
            'roomVar': (d.get('ground') or {}).get('roomVar'),
            'hasRoomClass': (d.get('ground') or {}).get('hasRoomClass'),
        } or None,
        'models': [(f.get('scene') or {}).get('model') for f in frames] or None,
        'error': d.get('error'),
        'why': model.get('why'),
    }


def main():
    if len(sys.argv) != 3:
        print('usage: probe-verdict.py <cases-file> <results-file>', file=sys.stderr)
        return 2

    cases = load_cases(sys.argv[1])
    results = load_results(sys.argv[2])

    failures = 0
    for i, case in enumerate(cases):
        d = results[i] if i < len(results) else {}
        scene = ((d.get('probe') or {}).get('scene')) or {}
        model = d.get('model') or {}
        frames = d.get('frames') or []
        paint = d.get('paint') or {}

        ns = {
            'scene': scene,
            'model': model,
            'probe': d.get('probe') or {},
            'dom': d.get('dom') or {},
            'frames': frames,
            'paint': paint,
            'ground': d.get('ground') or {},
            'readiness': d.get('readiness') or {},
            'ok': d.get('ok'),
        }
        try:
            # No builtins: the expressions are data and call nothing. eval over a
            # short local string from the cases file, not from user input.
            passed = bool(eval(case['check'], {'__builtins__': {}}, ns))  # noqa: S307
            note = ''
        except Exception as e:  # noqa: BLE001
            passed = False
            note = 'check threw: %s' % e

        detail = summarise(scene, model, frames, paint, d)
        if note:
            detail['error'] = note
        tag = 'PASS' if passed else 'FAIL'
        if not passed:
            failures += 1
        print('%s\t%s\t%s' % (tag, case['name'],
                              json.dumps(detail, separators=(',', ':'))))

    return failures


if __name__ == '__main__':
    sys.exit(main())
