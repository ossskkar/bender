#!/usr/local/bin/python3.11
"""Arisu's deck -- the Mac half of the iPad's button grid.

The iPad shows the buttons and presses them; this executes them on the Mac.
It is the macropad's action executor, kept when the macropad itself was retired
(Oscar, 2026-09-26): the pad hardware and its LEDs, pads, knob and overlay are
gone, the part that actually does things is here, and the 36 buttons it starts
with are the pad's own bindings, flattened.

    deck.py serve                # run it (foreground; launchd calls this)
    deck.py press claude-code.k1 # execute one button by id, from the shell
    deck.py list                 # print the buttons

Endpoints, all JSON:

    GET  /deck        -> {"buttons": [...]}     what the iPad draws
    POST /deck/run    {"id": "mac.k1"}          execute that button
    POST /deck        {"buttons": [...]}        replace the whole set

**/run takes an id and never an action.** That is the one deliberate limit: the
iPad reaches this over the tailnet, and a run endpoint that accepted an action
body would be arbitrary shell execution on the Mac for anything that can reach
the port. Pressing a button he already wrote is a much smaller thing than
running whatever arrives. Editing the set is still arbitrary by nature -- that
is what a "shell" button is -- so the same tailnet trust applies to POST /deck
as to every other thing he runs on it, and this must never go on a funnel.

Why stdlib only, and the 3.11 shebang: launchd starts this with no virtualenv,
and `python3` on PATH here is an Xcode 3.7 from 2020. Inherited from the
macropad, where the same two facts held.
"""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.abspath(__file__))
# The store lives outside ~/Documents, and this is not a preference (2026-09-27).
# launchd is denied that directory by macOS TCC, and a denied open() here does
# not fail -- it *hangs*, forever, inside open(). The deck answered "/" in a
# millisecond and left every /deck request waiting until the client gave up,
# which on the iPad's rail looked like a spinner that never stopped.
#
# `buttons.json` beside this file is the seed and the readable copy of the 36
# bindings; nothing running under launchd may open it. Seed the store by hand:
#   cp buttons.json ~/.local/share/arisu-deck/buttons.json
# ARISU_DECK_BUTTONS overrides, and `serve --buttons` still wins over both.
SEED = os.path.join(ROOT, "buttons.json")
BUTTONS = os.environ.get("ARISU_DECK_BUTTONS") or os.path.expanduser(
    "~/.local/share/arisu-deck/buttons.json")
ACTION_TYPES = ("http", "shell", "applescript", "open", "notify", "text", "keys", "compound")
SYSTEM_CA = "/etc/ssl/cert.pem"
_ssl_context_cache = None


def load(path: str = BUTTONS) -> dict:
    with open(path) as handle:
        return json.load(handle)


def save(data: dict, path: str = BUTTONS) -> None:
    """Write the set atomically: a half-written buttons.json is a deck that does
    not come back, and this is edited from the iPad while the service is live."""
    tmp = path + ".tmp"
    with open(tmp, "w") as handle:
        json.dump(data, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    os.replace(tmp, path)


def clean(buttons) -> list:
    """Keep what a button is allowed to be. An unknown action type is refused
    here rather than at press time, so a bad edit fails while he is looking at
    it instead of the next time he reaches for the key."""
    if not isinstance(buttons, list):
        raise ValueError("buttons must be a list")
    out, seen = [], set()
    for raw in buttons:
        if not isinstance(raw, dict):
            raise ValueError("every button must be an object")
        bid = str(raw.get("id") or "").strip()
        action = raw.get("action")
        if not bid:
            raise ValueError("every button needs an id")
        if bid in seen:
            raise ValueError(f"two buttons share the id {bid!r}")
        if not isinstance(action, dict) or action.get("type") not in ACTION_TYPES:
            raise ValueError(f"{bid}: action must be one of {', '.join(ACTION_TYPES)}")
        seen.add(bid)
        out.append({
            "id": bid,
            "group": str(raw.get("group") or "").strip(),
            "label": str(raw.get("label") or bid).strip(),
            "icon": str(raw.get("icon") or "").strip(),
            # What a long press on the iPad says the button does.
            "about": str(raw.get("about") or "").strip(),
            "action": action,
        })
    return out


def ssl_context():
    """An SSL context that actually has certificates in it.

    The python.org 3.11 on this Mac was installed without ever running its
    "Install Certificates.command", so `ssl.create_default_context()` comes back
    with ZERO roots, and every HTTPS action then fails with
    CERTIFICATE_VERIFY_FAILED. The first action to try it was the Lain → Backlog
    key, which surfaced as red text in the panel — the only reason it was noticed
    at all.

    Loading the system roots is the fix rather than shelling out to curl: same
    trust store as every other program on the machine, nothing to install, and it
    holds however the daemon is launched.
    """
    global _ssl_context_cache
    if _ssl_context_cache is None:
        context = ssl.create_default_context()
        if context.cert_store_stats().get("x509_ca", 0) == 0 and os.path.exists(SYSTEM_CA):
            context.load_verify_locations(SYSTEM_CA)
        _ssl_context_cache = context
    return _ssl_context_cache


def press(combo: str = "cmd+v", timeout: int = 20):
    """Press a key combination in the front app via MacropadType.app, which alone
    holds Accessibility; `open` makes it its own process for TCC rather than a
    child of Python. Returns (ok, detail)."""
    result = os.path.join(os.path.expanduser("~/Library/Logs/macropad"), "type.out")
    try:
        os.remove(result)       # a stale "ok" must not pass for this run
    except OSError:
        pass
    _run(["/usr/bin/open", "-g", "-W", "--stdout", result,
          os.path.expanduser("~/Applications/MacropadType.app"), "--args", combo], timeout=timeout)
    try:
        with open(result) as handle:
            answer = handle.read().strip()
    except OSError:
        answer = "MacropadType did not run"
    return answer == "ok", answer


def _run(cmd, timeout: int = 20, shell: bool = False):
    """Run a command, return (ok, one-line detail). Never raises."""
    try:
        proc = subprocess.run(
            cmd,
            shell=shell,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return False, f"timed out after {timeout}s"
    except OSError as exc:
        return False, str(exc)
    out = (proc.stdout or "").strip() or (proc.stderr or "").strip()
    if proc.returncode != 0:
        return False, out[:300] or f"exit {proc.returncode}"
    return True, out[:300]


def execute(action: dict, dry_run: bool = False, timeout: int = 20):
    """Execute one action. Returns (ok, detail). Raises nothing.

    """
    kind = (action or {}).get("type")
    if not kind:
        return False, "binding has no action"
    # Type checking happens before the dry-run shortcut on purpose: catching a
    # typo'd action type is most of what a dry run is for, and a dry run that
    # waved through {"type": "htpp"} would be worse than none.
    if kind not in ACTION_TYPES:
        return False, f"unknown action type {kind!r}"

    # compound recurses before the dry-run shortcut so that a dry run checks
    # its steps as well; a compound that merely reported "dry-run: compound"
    # would hide exactly the wiring mistake a dry run exists to catch.
    if kind == "compound":
        steps = action.get("steps") or []
        if not steps:
            return False, "compound action has no steps"
        for index, step in enumerate(steps, 1):
            ok, detail = execute(step, dry_run=dry_run, timeout=timeout)
            if not ok:
                return False, f"step {index}/{len(steps)}: {detail}"
        return True, f"{len(steps)} steps ok"

    if dry_run:
        return True, f"dry-run: {kind}"

    if kind == "http":
        method = (action.get("method") or "GET").upper()
        url = action.get("url")
        if not url:
            return False, "http action has no url"
        body = action.get("body")
        data = json.dumps(body).encode("utf-8") if body is not None else None
        request = urllib.request.Request(url, data=data, method=method)
        if data is not None:
            request.add_header("Content-Type", "application/json")
        for name, value in (action.get("headers") or {}).items():
            request.add_header(name, str(value))
        try:
            with urllib.request.urlopen(request, timeout=timeout,
                                        context=ssl_context()) as response:
                text = response.read(400).decode("utf-8", "replace").replace("\n", " ")
                ok = 200 <= response.status < 300
                return ok, f"{response.status} {text[:200]}".strip()
        except urllib.error.HTTPError as exc:
            return False, f"HTTP {exc.code} {exc.reason}"
        except (urllib.error.URLError, OSError) as exc:
            return False, f"unreachable: {exc}"

    if kind == "shell":
        if not action.get("cmd"):
            return False, "shell action has no cmd"
        return _run(action["cmd"], timeout=timeout, shell=True)

    if kind == "applescript":
        if not action.get("script"):
            return False, "applescript action has no script"
        return _run(["/usr/bin/osascript", "-e", action["script"]], timeout=timeout)

    if kind == "open":
        if not action.get("url"):
            return False, "open action has no url"
        return _run(["/usr/bin/open", action["url"]], timeout=timeout)

    if kind == "text":
        # Canned text onto the clipboard, and optionally pasted into the front app.
        # Pasting is a Cmd-V keystroke, which needs Accessibility for python3.11.
        text = action.get("text")
        if not text:
            return False, "text action has no text"
        # When typing, whatever was on the clipboard is put back afterwards.
        previous = None
        if action.get("paste"):
            try:
                previous = subprocess.run(["/usr/bin/pbpaste"], capture_output=True,
                                          text=True, timeout=5).stdout
            except (OSError, subprocess.SubprocessError):
                pass
        try:
            subprocess.run(["/usr/bin/pbcopy"], input=text, text=True, timeout=5, check=True)
        except (OSError, subprocess.SubprocessError) as exc:
            return False, f"clipboard: {exc}"
        if not action.get("paste"):
            return True, "copied to the clipboard"
        typed, answer = press("cmd+v", timeout=timeout)
        if not typed:
            return False, f"copied, but typing failed: {answer}"
        if previous is not None:
            time.sleep(0.3)   # ponytail: fixed wait for the paste to land; raise it if slow apps get the old clipboard
            subprocess.run(["/usr/bin/pbcopy"], input=previous, text=True, timeout=5)
        return True, "typed"

    if kind == "keys":
        if not action.get("keys"):
            return False, "keys action has no keys"
        ok, answer = press(action["keys"], timeout=timeout)
        return ok, "pressed " + action["keys"] if ok else answer

    if kind == "notify":
        title = action.get("title") or "Arisu deck"
        text = action.get("text") or ""
        script = 'display notification {} with title {}'.format(
            json.dumps(text), json.dumps(title)
        )
        return _run(["/usr/bin/osascript", "-e", script], timeout=timeout)

    return False, f"unreachable: unhandled action type {kind!r}"


# --------------------------------------------------------------------------
# the service


# Which deck belongs to which Mac app. The iPad brings a group to the front
# when the Mac's frontmost app changes (Oscar, 2026-09-28), so the buttons he
# wants are already there when he looks down. Matched on the app's display
# name, lowercased; a group whose name is in the app's name needs no row here
# (Spotify -> spotify, Google Chrome -> chrome).
FRONT_GROUPS = {
    "claude": "claude-code",
    "terminal": "hermes",
    "iterm2": "hermes",
    "ghostty": "hermes",
    "safari": "chrome",
    "finder": "mac",
    "system settings": "mac",
}


_muted_by_us = False


def mute(on: bool) -> dict:
    """Mute the Mac's output, or undo our own mute. Unmute only when we were the
    ones who muted, so a Mac he had silenced himself stays silent."""
    global _muted_by_us
    osa = "/usr/bin/osascript"
    if on:
        ok, was = _run([osa, "-e", "output muted of (get volume settings)"], timeout=5)
        if ok and was.strip() == "true":
            return {"ok": True, "muted": True, "detail": "already muted"}
        ok, detail = _run([osa, "-e", "set volume output muted true"], timeout=5)
        _muted_by_us = ok
        return {"ok": ok, "muted": ok, "detail": detail}
    if not _muted_by_us:
        return {"ok": True, "muted": None, "detail": "not ours to unmute"}
    ok, detail = _run([osa, "-e", "set volume output muted false"], timeout=5)
    _muted_by_us = not ok
    return {"ok": ok, "muted": not ok, "detail": detail}


def front_app() -> str:
    """The Mac's frontmost application, by display name.

    `lsappinfo` and not AppleScript on purpose: asking System Events for it
    needs Automation consent, and a *pending* TCC decision is what left this
    server hanging inside a syscall for a day (2026-09-28). This reads
    CoreServices' own launch database and needs nothing.
    """
    try:
        asn = _run(["lsappinfo", "front"], timeout=3)[1].strip()
        if not asn:
            return ""
        name = _run(["lsappinfo", "info", "-only", "name", asn], timeout=3)[1]
    except Exception:
        return ""
    # '"LSDisplayName"="Claude"' -- the last quoted field is the name.
    parts = [p for p in name.strip().split('"') if p not in ("", "=")]
    return parts[-1] if parts else ""


def front_group(groups) -> str:
    """The deck for whatever is in front, or "" if none of them fits.

    Empty matters: it means *leave the rail where he put it*. Falling back to
    a default would drag him off his group every time he opened Mail.
    """
    app = front_app().lower()
    if not app:
        return ""
    for key, group in FRONT_GROUPS.items():
        if key in app and group in groups:
            return group
    return next((g for g in groups if g and g.lower() in app), "")


# Where the applications live, and where their icons are cached once they have
# been converted. The iPad draws the real icon on its button (Oscar,
# 2026-09-29); an SF Symbol of a window told him nothing about which app it was.
ICON_CACHE = os.path.expanduser("~/.cache/arisu-deck/icons")
APP_DIRS = ("/Applications", "/System/Applications",
            "/System/Applications/Utilities", "/Applications/Utilities",
            os.path.expanduser("~/Applications"))


def app_bundle(name: str):
    """The .app for a display name, or None. Plain directory lookups first --
    `mdfind` needs Spotlight to be up and is the slow path."""
    for base in APP_DIRS:
        path = os.path.join(base, name + ".app")
        if os.path.isdir(path):
            return path
    ok, out = _run(["mdfind", "-name", name + ".app", "-onlyin", "/Applications"],
                   timeout=5)
    for line in (out or "").splitlines():
        if line.endswith(name + ".app"):
            return line
    return None


def app_icon(name: str):
    """A PNG of the application's icon, cached. Returns bytes or None.

    `sips` does the conversion, which is in the OS and needs no consent; the
    alternative (AppKit through pyobjc) is a dependency and a GUI session.
    """
    png = os.path.join(ICON_CACHE, name.replace("/", "_") + ".png")
    try:
        if os.path.exists(png) and os.path.getsize(png) > 0:
            return open(png, "rb").read()
    except OSError:
        pass
    bundle = app_bundle(name)
    if not bundle:
        return None
    try:
        with open(os.path.join(bundle, "Contents", "Info.plist"), "rb") as f:
            info = plistlib.load(f)
    except (OSError, ValueError):
        return None
    icon = info.get("CFBundleIconFile") or info.get("CFBundleIconName") or ""
    if icon and not icon.endswith(".icns"):
        icon += ".icns"
    src = os.path.join(bundle, "Contents", "Resources", icon)
    if not icon or not os.path.exists(src):
        # Some bundles keep the icon in an asset catalog instead; the generic
        # application icon is a better answer than a broken image.
        src = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns"
        if not os.path.exists(src):
            return None
    try:
        os.makedirs(ICON_CACHE, exist_ok=True)
    except OSError:
        return None
    ok, _ = _run(["sips", "-s", "format", "png", "-Z", "180", src, "--out", png],
                 timeout=20)
    if not ok:
        return None
    try:
        return open(png, "rb").read()
    except OSError:
        return None


class Handler(BaseHTTPRequestHandler):
    path_to_buttons = BUTTONS
    quiet = False

    def log_message(self, fmt, *args):
        if not self.quiet:
            sys.stderr.write("deck  %s\n" % (fmt % args))

    def reply(self, status: int, payload: dict):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            # The iPad went to sleep mid-answer. Not an error worth a traceback.
            pass

    def read_json(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return {}
        return json.loads(self.rfile.read(length).decode("utf-8"))

    def do_GET(self):
        # The query is not part of the path: /deck/icon?name=… matched nothing
        # until this split existed (2026-09-29).
        path = urllib.parse.urlparse(self.path).path.rstrip("/") or "/"
        try:
            data = load(self.path_to_buttons)
        except (OSError, ValueError) as exc:
            return self.reply(500, {"error": f"buttons.json: {exc}"})
        buttons = data.get("buttons") or []
        groups = list(dict.fromkeys(b.get("group", "") for b in buttons))
        # Polled every couple of seconds by the rail, so it answers with the
        # app and nothing else -- the buttons have not changed.
        if path == "/deck/front":
            return self.reply(200, {"app": front_app(), "group": front_group(groups)})
        # The application's own icon, for its button on the iPad. Only for the
        # names buttons.json lists: this is a socket on the tailnet, and a name
        # off the wire must not reach the filesystem.
        if path == "/deck/icon":
            want = urllib.parse.parse_qs(
                urllib.parse.urlparse(self.path).query).get("name", [""])[0]
            if want not in (data.get("apps") or []):
                return self.reply(404, {"error": "not one of his apps"})
            png = app_icon(want)
            if not png:
                return self.reply(404, {"error": "no icon"})
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(png)))
            self.send_header("Cache-Control", "max-age=86400")
            self.end_headers()
            try:
                self.wfile.write(png)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        if path != "/deck":
            return self.reply(404, {"error": "no such path"})
        self.reply(200, {"buttons": buttons, "front": front_group(groups),
                         "apps": data.get("apps") or []})

    def do_POST(self):
        path = self.path.rstrip("/") or "/"
        try:
            payload = self.read_json()
        except ValueError as exc:
            return self.reply(400, {"error": f"bad json: {exc}"})

        if path == "/deck/run":
            bid = str(payload.get("id") or "")
            try:
                buttons = load(self.path_to_buttons).get("buttons") or []
            except (OSError, ValueError) as exc:
                return self.reply(500, {"error": f"buttons.json: {exc}"})
            found = next((b for b in buttons if b.get("id") == bid), None)
            if found is None:
                return self.reply(404, {"error": f"no button {bid!r}"})
            ok, detail = execute(found.get("action") or {})
            return self.reply(200 if ok else 500,
                              {"ok": ok, "id": bid, "detail": detail})

        # Bring one of his applications to the front. The name must be one of
        # the ones `buttons.json` lists -- this is a socket on the tailnet, and
        # `open -a` with a name off the wire is a way to start anything on the
        # Mac. Argv, never a shell string, for the same reason.
        if path == "/deck/app":
            name = str(payload.get("name") or "")
            try:
                known = load(self.path_to_buttons).get("apps") or []
            except (OSError, ValueError) as exc:
                return self.reply(500, {"error": f"buttons.json: {exc}"})
            if name not in known:
                return self.reply(404, {"error": f"not one of his apps: {name!r}"})
            ok, detail = _run(["open", "-a", name], timeout=10)
            return self.reply(200 if ok else 500,
                              {"ok": ok, "app": name, "detail": detail or name})

        # The iPad's REC button: the Mac goes quiet while he dumps, then back
        # to how it was (Oscar, 2026-10-01). Fixed scripts, nothing off the wire.
        if path == "/deck/mute":
            return self.reply(200, mute(bool(payload.get("on"))))

        if path == "/deck":
            try:
                buttons = clean(payload.get("buttons"))
            except ValueError as exc:
                return self.reply(400, {"error": str(exc)})
            try:
                data = load(self.path_to_buttons)
            except (OSError, ValueError):
                data = {}
            data["buttons"] = buttons
            # The apps may be reordered from the iPad, never added to: the
            # list is what gates `open -a` in /deck/app.
            apps = payload.get("apps")
            if isinstance(apps, list) and sorted(apps) == sorted(data.get("apps") or []):
                data["apps"] = apps
            try:
                save(data, self.path_to_buttons)
            except OSError as exc:
                return self.reply(500, {"error": f"could not save: {exc}"})
            return self.reply(200, {"ok": True, "buttons": len(buttons)})

        self.reply(404, {"error": "no such path"})


def serve(port: int, path: str, quiet: bool) -> int:
    Handler.path_to_buttons = path
    Handler.quiet = quiet
    # Localhost only. The iPad arrives through `tailscale serve`, which
    # terminates TLS and proxies in -- so the tailnet is the boundary and this
    # socket is never on a LAN. See the module docstring.
    httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    httpd.daemon_threads = True
    print(f"arisu deck  http://127.0.0.1:{port}/deck   buttons={path}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
    return 0


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Arisu's deck: the Mac half.")
    parser.add_argument("command", choices=("serve", "press", "list", "selftest"))
    parser.add_argument("id", nargs="?", help="button id, for press")
    parser.add_argument("--buttons", default=BUTTONS)
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(argv)

    if args.command == "selftest":
        return selftest()

    try:
        data = load(args.buttons)
    except (OSError, ValueError) as exc:
        print(f"buttons.json: {exc}", file=sys.stderr)
        return 1
    buttons = data.get("buttons") or []

    if args.command == "list":
        for b in buttons:
            print(f"{b['id']:<18} {b.get('label',''):<16} {b['action'].get('type')}")
        return 0

    if args.command == "press":
        found = next((b for b in buttons if b.get("id") == args.id), None)
        if found is None:
            print(f"no button {args.id!r}", file=sys.stderr)
            return 1
        ok, detail = execute(found["action"])
        print(detail)
        return 0 if ok else 1

    return serve(args.port or int(data.get("port") or 8887), args.buttons, args.quiet)


def selftest() -> int:
    """The smallest thing that fails if the deck breaks: the shipped buttons
    load and validate, every action type round-trips through `execute` as a dry
    run, and a bad edit is refused."""
    import tempfile

    data = load()
    buttons = clean(data["buttons"])
    assert len(buttons) >= 36, f"expected at least the pad's 36 buttons, got {len(buttons)}"
    assert len({b["id"] for b in buttons}) == len(buttons), "button ids are not unique"

    for kind in ACTION_TYPES:
        if kind == "compound":
            continue
        ok, detail = execute({"type": kind, "cmd": "true", "url": "x", "script": "x",
                              "text": "x", "keys": "escape", "title": "x"}, dry_run=True)
        assert ok, f"{kind}: {detail}"
    ok, detail = execute({"type": "compound", "steps": [{"type": "shell", "cmd": "true"}]},
                         dry_run=True)
    assert ok, detail
    assert execute({"type": "nope"}, dry_run=True)[0] is False, "unknown type slipped through"

    # Which deck the Mac's frontmost app asks for. The empty answer is the one
    # that matters: it means leave the rail where he put it, and an app he has
    # never mapped must never drag him back to a default.
    groups = ["claude-code", "mac", "lain", "hermes", "spotify", "chrome"]
    seen = {}
    try:
        real = front_app
        for app, want in (("Claude", "claude-code"), ("Terminal", "hermes"),
                          ("Google Chrome", "chrome"), ("Spotify", "spotify"),
                          ("Mail", ""), ("", "")):
            globals()["front_app"] = lambda a=app: a
            got = front_group(groups)
            seen[app] = got
            assert got == want, f"{app!r} -> {got!r}, wanted {want!r}"
    finally:
        globals()["front_app"] = real
    assert execute({"type": "compound", "steps": []}, dry_run=True)[0] is False, "empty compound"

    for bad, why in [([{"id": "a"}], "no action"),
                     ([{"id": "a", "action": {"type": "htpp"}}], "typo'd type"),
                     ([{"id": "a", "action": {"type": "shell"}},
                       {"id": "a", "action": {"type": "shell"}}], "duplicate id")]:
        try:
            clean(bad)
        except ValueError:
            pass
        else:
            raise AssertionError(f"{why} was accepted")

    with tempfile.TemporaryDirectory() as box:
        path = os.path.join(box, "buttons.json")
        save({"buttons": buttons}, path)
        assert len(load(path)["buttons"]) == len(buttons), "did not survive a save and load"

    print("deck selftest ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
