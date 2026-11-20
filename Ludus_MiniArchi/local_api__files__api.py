from http.server import BaseHTTPRequestHandler, HTTPServer
import psycopg2

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            c = psycopg2.connect(host="10.1.30.10", dbname="mobilite",
                                 user="api", password="Demo-Api-2026!",
                                 connect_timeout=3)
            cur = c.cursor()
            cur.execute("SELECT count(*) FROM clients")
            n = cur.fetchone()[0]
            c.close()
            body, code = "API01 OK - %d clients lus depuis DB01\n" % n, 200
        except Exception as e:
            body, code = "Erreur base de donnees : %s\n" % e, 500
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(body.encode())

HTTPServer(("127.0.0.1", 5000), H).serve_forever()
