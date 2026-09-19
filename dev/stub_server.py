import http.server, socketserver, threading, time, sys, gzip, io

ROWS_OK = 500

def csv_body(n, cols=("id","name","date","value")):
    out = [",".join(cols)]
    for i in range(n):
        out.append(f"{i},row {i},2020-01-0{(i%9)+1},{i*1.5}")
    return ("\n".join(out) + "\n").encode()

class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass

    def _send(self, code, body, ctype="text/csv", extra=None, clen=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(clen if clen is not None else len(body)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        p = self.path.split("?")[0]
        try:
            if p.endswith("/ok.csv"):
                self._send(200, csv_body(ROWS_OK))
            elif p.endswith("/short.csv"):
                # a "complete" fetch that silently returns only 10 rows
                self._send(200, csv_body(10))
            elif p.endswith("/count.csv"):
                self._send(200, b"count\n1000000\n")
            elif p.endswith("/truncated.csv"):
                full = csv_body(ROWS_OK)
                cut = full[: len(full) // 2]
                # declare the full length, send half, then hang up
                self._send(200, cut, clen=len(full))
                self.close_connection = True
            elif p.endswith("/html200"):
                self._send(200, b"<html><body><h1>Service Unavailable</h1>"
                                b"<p>Try again later.</p></body></html>",
                           ctype="text/html")
            elif p.endswith("/html500"):
                self._send(500, b"<html><body>Internal Server Error</body></html>",
                           ctype="text/html")
            elif p.endswith("/empty"):
                self._send(200, b"")
            elif p.endswith("/headeronly.csv"):
                self._send(200, b"id,name,date,value\n")
            elif p.endswith("/redirect"):
                self.send_response(302)
                self.send_header("Location", "/ok.csv")
                self.send_header("Content-Length", "0")
                self.end_headers()
            elif p.endswith("/slow.csv"):
                body = csv_body(ROWS_OK)
                self.send_response(200)
                self.send_header("Content-Type", "text/csv")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                for i in range(0, len(body), 64):
                    self.wfile.write(body[i:i+64]); self.wfile.flush(); time.sleep(0.02)
            elif p.endswith("/wrongtype.csv"):
                self._send(200, csv_body(ROWS_OK), ctype="application/json")
            elif p.endswith("/gziplie.csv"):
                self._send(200, csv_body(ROWS_OK), extra={"Content-Encoding": "gzip"})
            elif p.endswith("/bom.csv"):
                self._send(200, b"\xef\xbb\xbf" + csv_body(ROWS_OK))
            elif p.endswith("/ragged.csv"):
                b = b"id,name,date,value\n1,a,2020-01-01,1\n2,b,2020-01-02\n3,c,2020-01-03,3,EXTRA\n"
                self._send(200, b)
            elif p.endswith("/nulbytes.csv"):
                self._send(200, b"id,name\n1,a\x00b\n2,c\n")
            else:
                self._send(404, b"not found", ctype="text/plain")
        except (BrokenPipeError, ConnectionResetError):
            pass

class S(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

port = int(sys.argv[1])
with S(("127.0.0.1", port), H) as httpd:
    httpd.serve_forever()

# Usage with rmoriedata:
#   python3 rmoriedata_stub_server.py 8731 &
#   R:  assignInNamespace(".rmd_endpoint",
#         function(type) "http://127.0.0.1:8731/html200", ns = "rmoriedata")
#       load_chicago_data("arrests", full = TRUE)
