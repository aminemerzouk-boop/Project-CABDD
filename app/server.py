#!/usr/bin/env python3
"""
CABDD — Tableau de bord web (Variante A)
Petit serveur stdlib qui sert l'interface statique et une API JSON
alimentée par PostgreSQL via le client `psql` (aucun driver requis).

Lancement :  python app/server.py            (port 8000)
Variables d'env : PORT, PGHOST, PGPORT, PGUSER, PGPASSWORD, PSQL
"""
import json
import os
import subprocess
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
STATIC = ROOT / "static"

PSQL = os.environ.get("PSQL", "psql")
PGHOST = os.environ.get("PGHOST", "127.0.0.1")
PGPORT = os.environ.get("PGPORT", "5432")
PGUSER = os.environ.get("PGUSER", "postgres")
PGPASSWORD = os.environ.get("PGPASSWORD", "postgres")
PORT = int(os.environ.get("PORT", "8000"))


def query(sql: str, db: str = "centre"):
    """Exécute une requête en TSV (un séparateur \x1f) et renvoie les lignes."""
    env = dict(os.environ, PGPASSWORD=PGPASSWORD, PGCLIENTENCODING="UTF8")
    proc = subprocess.run(
        [PSQL, "-h", PGHOST, "-p", PGPORT, "-U", PGUSER, "-d", db,
         "-t", "-A", "-F", "\x1f", "-v", "ON_ERROR_STOP=1", "-c", sql],
        capture_output=True, text=True, env=env, timeout=60)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or "erreur psql")
    rows = []
    for line in proc.stdout.splitlines():
        if line.strip():
            rows.append(line.split("\x1f"))
    return rows


def query_one(sql: str, db: str = "centre"):
    rows = query(sql, db)
    return rows[0][0] if rows and rows[0] else ""


def api_kpi():
    return {
        "valides": sum(int(query_one(t)) for t in (
            "SELECT count(*) FROM mesure_temperature",
            "SELECT count(*) FROM mesure_air",
            "SELECT count(*) FROM mesure_hydro")),
        "isolees": int(query_one("SELECT count(*) FROM mesure_isolee")),
        "stations": int(query_one("SELECT count(*) FROM station")),
        "capteurs": int(query_one("SELECT count(*) FROM capteur")),
        "lots": int(query_one("SELECT count(*) FROM lot_brut")),
    }


def api_zones():
    rows = query("""
        SELECT 'zone 1', count(*) FROM z1_mes.mesure_temperature
        UNION ALL SELECT 'zone 2', count(*) FROM z2_mes.mesure_temperature
        UNION ALL SELECT 'zone 1 air', count(*) FROM z1_mes.mesure_air
        UNION ALL SELECT 'zone 2 air', count(*) FROM z2_mes.mesure_air
        UNION ALL SELECT 'zone 1 hydro', count(*) FROM z1_mes.mesure_hydro
        UNION ALL SELECT 'zone 2 hydro', count(*) FROM z2_mes.mesure_hydro""")
    z = {"zone1": 0, "zone2": 0}
    for label, n in rows:
        key = "zone1" if "zone 1" in label else "zone2"
        z[key] += int(n)
    z["total"] = z["zone1"] + z["zone2"]
    return z


def api_stations():
    return [
        {"code": r[0], "nom": r[1], "wilaya": r[2], "zone": int(r[3])}
        for r in query("SELECT code_station, nom, wilaya, zone FROM station ORDER BY zone, code_station")
    ]


def api_bilan(debut, fin):
    xml = query_one(
        "SELECT generer_bilan_journalier_xml(DATE '%s', DATE '%s')::text" % (debut, fin))
    return {"debut": debut, "fin": fin, "xml": xml}


def api_explain():
    plan = query(
        "EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM mesure_hydro "
        "WHERE instant_mesure >= '2026-02-01' AND instant_mesure < '2026-03-01'")
    return {"plan": "\n".join(r[0] for r in plan)}


def api_explain_zone1():
    plan = query(
        "EXPLAIN (ANALYZE) SELECT count(*) FROM v_mesure_plat v JOIN station s USING (code_station) "
        "WHERE s.zone = 1 AND v.jour BETWEEN '2026-02-01' AND '2026-02-28'")
    return {"plan": "\n".join(r[0] for r in plan)}


CONTENT_TYPES = {".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8",
                 ".js": "text/javascript; charset=utf-8", ".svg": "image/svg+xml",
                 ".png": "image/png", ".ico": "image/x-icon"}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):  # silencieux
        pass

    def _json(self, obj, code=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _static(self, path):
        if path in ("/", ""):
            path = "/index.html"
        f = (STATIC / path.lstrip("/")).resolve()
        if not str(f).startswith(str(STATIC)) or not f.is_file():
            self.send_error(404)
            return
        body = f.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", CONTENT_TYPES.get(f.suffix, "application/octet-stream"))
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        try:
            if u.path == "/api/kpi":
                self._json(api_kpi())
            elif u.path == "/api/zones":
                self._json(api_zones())
            elif u.path == "/api/stations":
                self._json(api_stations())
            elif u.path == "/api/bilan":
                debut = q.get("debut", ["2026-02-01"])[0]
                fin = q.get("fin", ["2026-02-07"])[0]
                self._json(api_bilan(debut, fin))
            elif u.path == "/api/explain":
                self._json(api_explain())
            elif u.path == "/api/explain_zone1":
                self._json(api_explain_zone1())
            elif u.path.startswith("/api/"):
                self._json({"error": "endpoint inconnu"}, 404)
            else:
                self._static(u.path)
        except Exception as e:
            self._json({"error": str(e)}, 500)


if __name__ == "__main__":
    print(f"CABDD dashboard → http://0.0.0.0:{PORT}  (PG {PGHOST}:{PGPORT}/{PGUSER})")
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
