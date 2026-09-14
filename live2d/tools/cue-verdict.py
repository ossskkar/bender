#!/usr/bin/env python3
"""Score the state-cue DOM check and say what reached the screen.

    cue-verdict.py <probe-results.json>

Exits with the number of failures.

Its own file rather than a heredoc inside cue-verify.sh: that script already
carries a JavaScript harness, and nesting a third language inside the second is
how a check ends up failing for reasons unrelated to what it checks.

Every comparison here normalises first, and each normalisation is a bug that was
found by it failing:

  * the module pads its colour triples so the table stays scannable --
    "255, 176,  59" -- and the browser hands the same colour back with single
    spaces. Comparing the strings compared the padding.
  * the browser writes "0.1" where the module says 0.10.
  * CSS reports animationName "none", where Python has None, for the same fact.
"""

import json
import sys

# The module owns these. Repeated here on purpose: a silent change to a colour
# should fail this check rather than be blessed by it.
#
#   label: (colour, glow, animation)
EXPECTED = {
    'asleep':    ('104, 118, 150', 0.36, None),
    'idle':      ('69, 230, 247',  0.50, None),
    'listening': ('74, 222, 128',  0.63, None),
    'thinking':  ('255, 176, 59',  0.90, 'arisu-think'),
    'speaking':  ('255, 99, 132',  0.86, 'arisu-speak'),
    'you':       ('178, 132, 255', 0.70, None),
}


def norm_colour(v):
    """A colour, comparable, with the padding removed."""
    return ', '.join(p.strip() for p in str(v or '').split(','))


def norm_num(v, places=2):
    """A glow, as a number, rounded.

    The page multiplies a state's glow by the strength slider, so the CSS carries
    binary noise: 0.4 * 0.9 arrives as 0.36000000000000004. Comparing floats
    exactly failed five working states at once."""
    try:
        return round(float(v), places)
    except (TypeError, ValueError):
        return None


def norm_anim(v):
    """CSS "none" and Python None are the same fact."""
    return None if v in (None, '', 'none') else v


def main():
    if len(sys.argv) != 2:
        print('usage: cue-verdict.py <results.json>', file=sys.stderr)
        return 2

    with open(sys.argv[1]) as fh:
        lines = [l for l in fh.read().splitlines() if l.strip()]
    if not lines:
        print('  the probe printed nothing')
        return 1

    d = json.loads(lines[0])

    # Two cues arrive in one result and they are not interchangeable:
    #
    #   d.probe.cue   what THE HARNESS wrote into #arisu-probe -- the snapshots
    #   d.cue         what the probe itself read off the live computed styles
    #
    # The harness's is the one with the snapshots. Reading d.cue first found a
    # real object with no `snaps` key and reported "no snapshots at all" for a
    # harness that had produced eight of them and left them in the file -- the
    # most misleading thing this script could say.
    cue = (d.get('probe') or {}).get('cue') or d.get('cue') or {}

    print('probe ok:', d.get('ok'), '| note:', d.get('error') or 'none')
    if cue.get('why') and cue['why'] != 'ok':
        print('harness said:', cue['why'])
    print()

    snaps = cue.get('snaps') or []
    if not snaps:
        print('  no snapshots at all -- the page never reached the harness')
        return 1

    fails = []
    layer = snaps[0].get('layer') or {}
    loud = None

    for s in snaps:
        label = s.get('label')
        want = EXPECTED.get(label)

        if not want:
            # The two extra snapshots are about the assertions below.
            if label == 'speaking-loud':
                loud = (s.get('layer') or {}).get('loud')
                print('  %-14s state %s  voice alpha %s'
                      % (label, s.get('state'), loud))
                # Deliberately NOT asserted: which state the light is in when
                # the voice snapshot is taken. The page polls /arisu/state, and
                # with no desk behind it that poll fails and the page paints
                # `asleep` -- so this snapshot races the page's own state
                # machine. That the state is red while she speaks is asserted on
                # the `speaking` snapshot above, where nothing is racing it.
                # Her voice should lift the light, so anything at or below the
                # resting value means the amplitude is not reaching it. The
                # page maps amplitude 0..1 to 0..0.85, so 0.9 becomes 0.765.
                if loud is None or loud <= 0.5:
                    fails.append('her voice did not lift the light (--loud %s)' % loud)
            elif label == 'after-idle':
                print('  %-14s animated=%s' % (label, s.get('animated')))
                if norm_anim(s.get('animated')) is not None:
                    fails.append('the light is still breathing after speaking')
            continue

        before = len(fails)
        if norm_colour(s.get('state')) != norm_colour(want[0]):
            fails.append('%s colour is %s, expected %s'
                         % (label, s.get('state'), want[0]))
        # The page rounds what it writes to two places (cues.js, twoDp), so this
        # compares exact values rather than compensating for float noise here.
        # Compensating here is what failed: rounding 0.855 in the reader gives
        # 0.85 and the expected 0.86 is 0.010000000000000009 away, so a working
        # state failed on the last binary digit.
        got_glow = norm_num(s.get('glow'))
        if got_glow is None or abs(got_glow - want[1]) > 0.005:
            fails.append('%s glow is %s, expected %s'
                         % (label, s.get('glow'), want[1]))
        if norm_anim(s.get('animated')) != want[2]:
            fails.append('%s pulse is %s, expected %s'
                         % (label, s.get('animated'), want[2]))
        # The cue is the glow, not a word. Checked on every snapshot rather
        # than once, because the element reappearing would mean the text cue had
        # been reintroduced rather than never removed.
        if s.get('hasTextElement'):
            fails.append('%s: a text readout is on the page; the cue is the glow'
                         % label)
        expect_cls = label if want[2] else ''
        if (s.get('glowClass') or '') != expect_cls:
            fails.append('%s glow class is %r, expected %r'
                         % (label, s.get('glowClass'), expect_cls))

        print('  %s %-13s %-16s glow %-5s %s'
              % ('ok  ' if len(fails) == before else 'FAIL', label,
                 s.get('state'), s.get('glow'),
                 'pulse ' + str(s.get('animated'))
                 if norm_anim(s.get('animated')) else 'still'))

    print()
    print('  halo: %sx%s %s, blend %s, %s gradient(s)'
          % (layer.get('w'), layer.get('h'), layer.get('position'),
             layer.get('blend'), layer.get('gradients')))
    print('  voice: --loud %s' % loud)
    if not layer.get('w') or not layer.get('h'):
        fails.append('the halo has no size, so nothing is painted')
    # A halo behind her needs the bright core as well as the broad wash. One
    # gradient is a whole-screen wash, which is what Oscar corrected.
    if (layer.get('gradients') or 0) < 3:
        fails.append('the light is %s gradient(s); a halo needs the wash, the '
                     'core and the floor' % layer.get('gradients'))
    if layer.get('blend') not in ('screen', 'lighten', 'plus-lighter'):
        fails.append('the gradients do not add (blend %s), so the core replaces '
                     'the wash instead of brightening it' % layer.get('blend'))

    print()
    if fails:
        print('  %d failed:' % len(fails))
        for f in fails:
            print('    - ' + f)
    else:
        print('  every cue reached the screen')
    print('-' * 47)
    return len(fails)


if __name__ == '__main__':
    sys.exit(main())
