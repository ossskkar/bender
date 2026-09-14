#!/usr/bin/env python3
"""Score the Glow-controls check: that the sliders actually move the light.

    glow-controls-verdict.py <probe-results.json>

The third result line, after the state-cue one. Exits with the number of
failures.

This is the check for "add controls to adjust it" specifically. The colours and
the halo are measured elsewhere; what is measured here is that a finger on a
slider reaches the CSS the halo is painted with, and that the panel's own reset
puts all four back.
"""

import json
import sys

# What the shipped defaults are. Repeated on purpose: a silent change should
# fail this rather than be blessed by it.
# The three controls whose values the reset must restore are compared against
# what the panel showed on opening, not against a literal: with no desk behind it
# the panel keeps its markup defaults, and a literal would be a claim about the
# desk rather than about the control.
RESTORED = ('size', 'x', 'y')


def main():
    if len(sys.argv) != 2:
        print('usage: glow-controls-verdict.py <results.json>', file=sys.stderr)
        return 2

    with open(sys.argv[1]) as fh:
        lines = [l for l in fh.read().splitlines() if l.strip()]
    if len(lines) < 2:
        print('  the probe printed no result for the glow controls')
        return 1

    d = json.loads(lines[1])

    # The harness's cue, not the probe's. Two cues arrive in one result: the
    # harness writes its snapshots into #arisu-probe (d.probe.cue), and the probe
    # separately reads the live computed styles (d.cue). The probe's has no
    # `snaps` key, and taking it first reported "the harness never reached the
    # controls" for a harness that had produced five snapshots and left them in
    # the file. The same precedence mistake had already been fixed in
    # cue-verdict.py and was left standing here.
    cue = (d.get('probe') or {}).get('cue') or d.get('cue') or {}
    snaps = {s.get('label'): s for s in (cue.get('snaps') or [])}
    fails = []

    print('glow controls:', cue.get('why') or '(no word from the harness)')
    if not snaps:
        print('  no snapshots -- the harness never reached the controls')
        return 1

    def want(label, field, expect, why):
        got = (snaps.get(label) or {}).get(field)
        ok = got == expect
        if not ok:
            fails.append('%s: %s is %r, expected %r' % (label, field, got, expect))
        print('  %s %-14s %-8s %-6s %s'
              % ('ok  ' if ok else 'FAIL', label, field, got,
                 '' if ok else 'want ' + str(expect)))
        return ok

    # The panel is reachable at all: a control nobody can open is not a control.
    if not snaps.get('panel open'):
        fails.append('the panel never opened, so the controls are unreachable')
        print('  FAIL the Glow section did not open')
        print()
        print('  %d failed:' % len(fails))
        for f in fails:
            print('    - ' + f)
        return len(fails)
    print('  ok   the Glow section opens')

    # A strength slider that changes nothing is the failure this catches.
    # Compared as numbers: the page writes "1" and an earlier version asked for
    # the string "1", failing a control that was working.
    def num(label, expect):
        got = (snaps.get(label) or {}).get('glow')
        try:
            ok = abs(float(got) - expect) < 0.005
        except (TypeError, ValueError):
            ok = False
        if not ok:
            fails.append('%s: --glow is %r, expected %s' % (label, got, expect))
        print('  %s %-16s %-8s %-6s %s'
              % ('ok  ' if ok else 'FAIL', label, 'glow', got,
                 '' if ok else 'want ' + str(expect)))
        return ok

    num('strength 3', 1)        # full strength is full white
    num('strength 0', 0)        # and 0 turns the light off
    num('after reset lit', 0.9)
    want('strength 0', 'strengthReadout', '0.00\u00d7', 'the readout follows')

    # Size and position reach the stylesheet.
    want('moved', 'size', '2.5', 'size reaches CSS')
    want('moved', 'x', '20%', 'x reaches CSS')
    want('moved', 'y', '80%', 'y reaches CSS')

    # And the reset puts everything back, compared against what the panel showed
    # on opening: that is what distinguishes a working control from values that
    # merely happened to be right.
    opening = snaps.get('panel open') or {}
    reset = snaps.get('after reset') or {}
    for field in RESTORED:
        got, expect = reset.get(field), opening.get(field)
        ok = got == expect
        if not ok:
            fails.append('after reset: %s is %r, expected %r'
                         % (field, got, expect))
        print('  %s %-16s %-8s %-6s %s'
              % ('ok  ' if ok else 'FAIL', 'after reset', field, got,
                 '' if ok else 'want ' + str(expect)))

    print()
    if fails:
        print('  %d failed:' % len(fails))
        for f in fails:
            print('    - ' + f)
    else:
        print('  the sliders move the light, and the reset puts it back')
    print('-' * 47)
    return len(fails)


if __name__ == '__main__':
    sys.exit(main())
