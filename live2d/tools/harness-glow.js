// The Glow controls, checked on the page that owns them.
//
// cues.js is tested in Node; the halo's gradients are measured by harness.js.
// This is the third piece: that the sliders in the settings sheet actually move
// the light, which is a claim about the page's own wiring and cannot be checked
// from either of the others.
//
// It runs on the client page (which has the sheet), drives the real input
// elements, and reads the CSS variables back.
(function () {
  var out = { snaps: [] };

  var realFetch = window.fetch;
  window.fetch = function (u) {
    var url = String(u);
    if (url.indexOf('/arisu/state') === 0 || url.indexOf('/arisu/commands') === 0) {
      return Promise.reject(new Error('harness: no desk'));
    }
    return realFetch.apply(this, arguments);
  };

  // Set a state and read --glow in ONE expression. Two calls are two round trips,
  // and the page polls /arisu/state every 4s: it repaints `asleep` between them,
  // so a strength of 0.9 came back as asleep's 0.36.
  function cueAt(state) {
    return String(window.eval(
      "window.__setState('" + state + "');"
      + "getComputedStyle(document.documentElement)"
      + ".getPropertyValue('--glow').trim()"));
  }

  function read(label) {
    var root = getComputedStyle(document.documentElement);
    out.snaps.push({
      label: label,
      glow: root.getPropertyValue('--glow').trim(),
      size: root.getPropertyValue('--glow-size').trim(),
      x: root.getPropertyValue('--glow-x').trim(),
      y: root.getPropertyValue('--glow-y').trim(),
      strengthReadout: (document.getElementById('glowstrength-n') || {}).textContent
    });
  }

  // A slider, moved the way a finger moves it.
  function move(id, value) {
    var el = document.getElementById(id);
    if (!el) return false;
    el.value = String(value);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    return true;
  }

  var reported = false;
  function report(why) {
    if (reported) return;
    reported = true;
    var pre = document.getElementById('arisu-probe');
    if (!pre) {
      pre = document.createElement('pre');
      pre.id = 'arisu-probe';
      pre.style.display = 'none';
      document.body.appendChild(pre);
    }
    pre.textContent = JSON.stringify({ cue: { snaps: out.snaps, why: why } });
  }

  // A reporter that fires whatever happens. Without it, a harness that never
  // reaches its controls writes nothing, and the verdict reports "no snapshots"
  // -- which says nothing about why.
  setTimeout(function () {
    report('timed out after 13s: glowstrength='
           + !!document.getElementById('glowstrength')
           + ' section=' + !!document.getElementById('glow-section')
           + ' setState=' + (typeof window.__setState)
           + ' snaps=' + out.snaps.length);
  }, 13000);

  var tries = 0;
  (function wait() {
    if (!document.getElementById('glowstrength')
        || typeof window.__setState !== 'function') {
      if (++tries < 400) return setTimeout(wait, 30);
      return report('the glow controls never appeared: glowstrength='
                    + !!document.getElementById('glowstrength')
                    + ' setState=' + (typeof window.__setState));
    }

    window.__setState('thinking');

    // The section has to be reachable: a control nobody can open is not a
    // control. The gear is what opens it, and openSettings() fetches
    // /arisu/characters first -- so the read that says "on the saved values" has
    // to happen after that answer, not before it. Taken earlier it reported the
    // module's defaults and called them the character's settings, which is a
    // green tick over a wrong claim.
    document.getElementById('gear').click();

    // A short settle, not a wait for the panel to populate.
    //
    // openSettings() awaits /arisu/characters, and on this rig there is no desk,
    // so it never finishes: the controls keep the markup's placeholder and a
    // harness that waited for a real value waited forever. The controls are wired
    // at parse time, so what is being checked -- that a slider reaches the CSS --
    // does not need the saved settings at all. That they come from the desk is
    // the panel's own test.
    setTimeout(function () {
      var section = document.getElementById('glow-section');
      if (!section || section.classList.contains('hide')) {
        return report('the Glow section is hidden');
      }
      // Recorded so the reset can be checked against it. Comparing against a
      // literal assumed the saved settings, which on a desk without its data is
      // a claim about something other than the control.
      read('panel open');

      if (!move('glowstrength', 3)) return report('no strength slider');
      out.snaps.push({ label: 'strength 3', glow: cueAt('thinking') });
      if (!move('glowstrength', 0)) return report('no strength slider');
      out.snaps.push({ label: 'strength 0', glow: cueAt('thinking') });
      read('strength 0');
      if (!move('glowstrength', 0.9)) return report('no strength slider');
      if (!move('glowsize', 2.5)) return report('no size slider');
      if (!move('glowx', 20)) return report('no x slider');
      if (!move('glowy', 80)) return report('no y slider');
      read('moved');

      // And back to where it started through the panel's own reset, which is
      // also what tells apart "the slider works" from "the values happen to be
      // right": the reset has to put all four back.
      document.getElementById('glowreset').click();
      read('after reset');
      out.snaps.push({ label: 'after reset lit', glow: cueAt('thinking') });
      report('ok');
    }, 600);
  })();
})();
