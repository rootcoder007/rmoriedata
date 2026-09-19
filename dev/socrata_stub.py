import http.server, socketserver, sys, time, urllib.parse

def csv_body(n, cols=("id","name","date","value")):
    out=[",".join(cols)]
    for i in range(n):
        out.append(f"{i},row {i},2020-01-0{(i%9)+1},{i*1.5}")
    return ("\n".join(out)+"\n").encode()

# route -> (rows served for a data request, count reported, kind)
MODES = {
    "healthy":      (500, 500,  "csv"),
    "short":        (10,  500,  "csv"),      # service says 500, returns 10
    "short_nocount":(10,  None, "csv"),      # short AND the count endpoint is down
    "headeronly":   (0,   500,  "csv"),
    "html200":      (None,500,  "html"),
    "html_nocount": (None,None, "html"),
    "ragged":       (None,500,  "ragged"),
    "ragged_nocount":(None,None,"ragged"),
    "empty":        (None,500,  "empty"),
    "nulbytes":     (None,500,  "nul"),
    "bom":          (500, 500,  "bom"),
    "slightly_short":(496,500,  "csv"),      # 0.8% short: inside the 1% tolerance
    "onepct_short": (490, 500,  "csv"),      # 2% short: outside it
    "huge":         (40,  8000000, "csv"),   # count exceeds the 5,000,000 floor
    "echo":         (500, 8000000, "csv"),
}

class H(http.server.BaseHTTPRequestHandler):
    protocol_version="HTTP/1.1"
    def log_message(self,*a): pass
    def _s(self, code, body, ct="text/csv"):
        self.send_response(code); self.send_header("Content-Type",ct)
        self.send_header("Content-Length",str(len(body))); self.end_headers()
        self.wfile.write(body)
    def do_GET(self):
        u=urllib.parse.urlparse(self.path)
        mode=u.path.strip("/").split("/")[-1].replace(".csv","")
        q=urllib.parse.unquote(u.query or "")
        if mode not in MODES: return self._s(404,b"no such mode",ct="text/plain")
        rows,count,kind=MODES[mode]
        is_count = "count(*)" in q or "select=count" in q
        try:
            if is_count:
                if count is None: return self._s(503,b"count unavailable",ct="text/plain")
                return self._s(200, f"count\n{count}\n".encode())
            if kind=="html":
                return self._s(200,b"<html><body><h1>Service Unavailable</h1>"
                                  b"<p>Try later.</p></body></html>",ct="text/html")
            if kind=="empty":  return self._s(200,b"")
            if kind=="ragged": return self._s(200,b"id,name,date,value\n1,a,2020-01-01,1\n"
                                                 b"2,b,2020-01-02\n3,c,2020-01-03,3,EXTRA\n")
            if kind=="nul":    return self._s(200,b"id,name\n1,a\x00b\n2,c\n")
            body=csv_body(rows if rows else 0)
            if kind=="bom": body=b"\xef\xbb\xbf"+body
            return self._s(200, body)
        except (BrokenPipeError,ConnectionResetError): pass

class S(socketserver.ThreadingTCPServer):
    allow_reuse_address=True; daemon_threads=True
with S(("127.0.0.1",int(sys.argv[1])),H) as d: d.serve_forever()

# Query-aware Socrata emulator: answers $select=count(*) and $limit= separately,
# so "the count endpoint is down while the data endpoint is degraded" is testable.
#   python3 rmoriedata_socrata_stub.py 8732 &
#   R: assignInNamespace(".rmd_endpoint",
#        function(type) "http://127.0.0.1:8732/short_nocount.csv", ns = "rmoriedata")
#      load_chicago_data("arrests", full = TRUE)
