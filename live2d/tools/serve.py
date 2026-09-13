#!/usr/bin/env python3
"""A threaded static server for the verification rig.

    serve.py [port] [root]

Why not `python3 -m http.server`: it is single-threaded. That is fine for one
page, and it quietly ruins a batch run -- a browser opens several connections per
origin, the server serves them one at a time, and a page's own model textures
queue behind the previous page's still-open keep-alive connections. The probe
then reports "no model canvas" for cases that are perfectly fine, which is a lie
about the code and cost two rounds of hunting a bug that was not there.

The desk serves threaded. So does this.
"""

import functools
import http.server
import socketserver
import sys


class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        """Silent. A batch run makes hundreds of requests and the noise buries
        the probe output, which is the only thing anyone is reading here."""
        pass

    def end_headers(self):
        # Nothing here is worth caching between cases, and a cached bundle would
        # mean verifying the previous build.
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8899
    root = sys.argv[2] if len(sys.argv) > 2 else '.'
    handler = functools.partial(Handler, directory=root)
    with Server(('127.0.0.1', port), handler) as httpd:
        print('serving %s on http://127.0.0.1:%d (threaded)' % (root, port),
              flush=True)
        httpd.serve_forever()


if __name__ == '__main__':
    main()
