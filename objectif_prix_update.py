#!/usr/bin/env python3
"""Objectif Prix 2 : suis ton épargne vers les articles que tu veux, prix idealo relevés chaque jour.

Options en ligne de commande :
  --minimized   démarre la fenêtre réduite (utilisé par le lancement automatique)
  --install     ajoute l'appli au menu de Linux Mint (ajouter --autostart pour le démarrage auto)
"""

import html as htmllib
import json
import math
import queue
import random
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import os
import uuid
import webbrowser
import tkinter as tk
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from tkinter import font as tkfont
from tkinter import messagebox

# ----------------------------------------------------------------------------
# Réglages
# ----------------------------------------------------------------------------

DATA_DIR = Path.home() / ".config" / "objectif-prix"
DATA_FILE = DATA_DIR / "data.json"
ACCOUNT_FILE = DATA_DIR / "account.json"

# Synchronisation iPhone <-> PC : un « gist » secret dans ton compte GitHub
GITHUB_API = "https://api.github.com"
GIST_FILE = "objectif-prix.json"
GIST_DESC = "Objectif Prix (données synchronisées)"
TOKEN_URL = "https://github.com/settings/tokens/new?scopes=gist&description=Objectif%20Prix"
SYNC_DELAY_MS = 4000                 # attente après une modification avant d'envoyer
SYNC_EVERY_MS = 10 * 60 * 1000       # synchro automatique toutes les 10 min

APP_DIR = Path.home() / ".local" / "share" / "objectif-prix"
DESKTOP_FILE = Path.home() / ".local" / "share" / "applications" / "objectif-prix.desktop"
AUTOSTART_FILE = Path.home() / ".config" / "autostart" / "objectif-prix.desktop"
ICON_FILE = Path.home() / ".local" / "share" / "icons" / "hicolor" / "scalable" / "apps" / "objectif-prix.svg"

REFRESH_EVERY = timedelta(days=1)         # un relevé de prix par jour
RETRY_AFTER_FAILURE = timedelta(hours=3)  # en cas d'échec, on réessaie plus tard
CHECK_INTERVAL_MS = 30 * 60 * 1000        # l'appli regarde toutes les 30 min si un relevé est dû
SPACING_BETWEEN_FETCHES = 3               # secondes entre deux pages idealo

HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "fr-FR,fr;q=0.9,en;q=0.5",
}

# Palette
BG = "#0A0E1A"
PANEL = "#121829"
PANEL2 = "#1A2340"
INPUT = "#0D1322"
BORDER = "#26304F"
TEXT = "#EAF0FF"
MUTED = "#8390B0"
ACCENT = "#2DE2B1"
ACCENT2 = "#7C5CFF"
GOOD = "#2DE2B1"
BAD = "#FF5C7A"
GOLD = "#FFC857"
ON_ACCENT = "#04281F"

MONTHS = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet",
          "août", "septembre", "octobre", "novembre", "décembre"]

ICON_SVG = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">
<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
<stop offset="0" stop-color="#7C5CFF"/><stop offset="1" stop-color="#2DE2B1"/></linearGradient></defs>
<rect width="128" height="128" rx="28" fill="#0A0E1A"/>
<circle cx="64" cy="64" r="36" fill="none" stroke="#26304F" stroke-width="12"/>
<circle cx="64" cy="64" r="36" fill="none" stroke="url(#g)" stroke-width="12" stroke-linecap="round"
 stroke-dasharray="150 226" transform="rotate(-90 64 64)"/>
<circle cx="64" cy="64" r="8" fill="#2DE2B1"/>
</svg>
"""


# ----------------------------------------------------------------------------
# Lecture du prix sur une page web
# ----------------------------------------------------------------------------

def to_float(txt):
    """Convertit '1 299,99', '1299.99' ou '1.299,99' en float."""
    txt = str(txt).strip()
    for ch in (" ", "\xa0", " ", "€", "EUR"):
        txt = txt.replace(ch, "")
    if "," in txt and "." in txt:
        if txt.rfind(",") > txt.rfind("."):
            txt = txt.replace(".", "").replace(",", ".")
        else:
            txt = txt.replace(",", "")
    elif "," in txt:
        txt = txt.replace(",", ".")
    return float(txt)


def _walk_prices(node):
    if isinstance(node, dict):
        for key in ("lowPrice", "price"):
            if key in node:
                try:
                    yield to_float(node[key])
                except (ValueError, TypeError):
                    pass
        for value in node.values():
            yield from _walk_prices(value)
    elif isinstance(node, list):
        for value in node:
            yield from _walk_prices(value)


def extract_price(page):
    """Retourne (prix, titre) trouvés dans le HTML, ou (None, titre)."""
    title = None
    m = re.search(r'<meta[^>]+property="og:title"[^>]+content="([^"]+)"', page, re.I)
    if not m:
        m = re.search(r"<title[^>]*>(.*?)</title>", page, re.I | re.S)
    if m:
        title = htmllib.unescape(m.group(1)).strip()

    # 1) Données structurées JSON-LD (le plus fiable)
    for block in re.findall(
        r'<script[^>]+type="application/ld\+json"[^>]*>(.*?)</script>', page, re.I | re.S
    ):
        try:
            data = json.loads(block)
        except ValueError:
            continue
        for price in _walk_prices(data):
            if price > 0:
                return price, title

    # 2) Balises meta
    m = re.search(
        r'<meta[^>]+(?:property|itemprop|name)="(?:product:price:amount|price|lowPrice)"'
        r'[^>]+content="([^"]+)"',
        page,
        re.I,
    )
    if m:
        try:
            price = to_float(m.group(1))
            if price > 0:
                return price, title
        except ValueError:
            pass

    # 3) Texte "à partir de 299,00 €"
    m = re.search(r"à partir de\s*(?:<[^>]+>\s*)*([\d\s \xa0.,]+?)\s*(?:<[^>]+>\s*)*€", page, re.I)
    if m:
        try:
            price = to_float(m.group(1))
            if price > 0:
                return price, title
        except ValueError:
            pass

    return None, title


def fetch_price(url):
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            raw = resp.read()
            charset = resp.headers.get_content_charset() or "utf-8"
    except urllib.error.HTTPError as e:
        if e.code in (403, 429):
            raise RuntimeError(
                f"idealo a refusé la lecture automatique (erreur {e.code}). "
                "Utilise « Prix manuel »."
            )
        raise RuntimeError(f"Erreur HTTP {e.code} en ouvrant la page.")
    except urllib.error.URLError as e:
        raise RuntimeError(f"Connexion impossible : {e.reason}")
    except TimeoutError:
        raise RuntimeError("La page met trop de temps à répondre.")

    page = raw.decode(charset, errors="replace")
    price, title = extract_price(page)
    if price is None:
        raise RuntimeError("Prix introuvable sur cette page. Vérifie le lien ou utilise « Prix manuel ».")
    return price, title


# ----------------------------------------------------------------------------
# Données
# ----------------------------------------------------------------------------

def now_iso():
    return datetime.now().isoformat(timespec="seconds")


def new_goal(name="", url="", monthly=0.0, alert_below=0.0):
    return {
        "id": str(uuid.uuid4()),
        "name": name,
        "url": url,
        "price": None,
        "saved": 0.0,
        "monthly": monthly,
        "alert_below": alert_below,
        "last_check": None,
        "last_attempt": None,
        "last_error": None,
        "alerted_price": None,
        "history": [],   # [{"date": "2026-11-08", "price": 279.0}]
        "log": [],       # [{"ts": iso, "amount": 25.0, "note": ""}]
        "updated_at": utc_now(),   # dernière modification (UTC), sert à la synchro
        "deleted": False,          # objectif supprimé (conservé un temps pour la synchro)
    }


def _read_data():
    data = {"version": 2, "selected": None, "goals": []}
    try:
        raw = json.loads(DATA_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return data

    if raw.get("version") == 2:
        data["selected"] = raw.get("selected")
        for g in raw.get("goals", []):
            base = new_goal()
            base.update(g)
            data["goals"].append(base)
        return data

    # Migration depuis la version 1 (un seul objectif)
    if raw.get("name") or raw.get("url") or raw.get("saved"):
        g = new_goal(raw.get("name", ""), raw.get("url", ""))
        g["price"] = raw.get("price")
        g["saved"] = float(raw.get("saved") or 0)
        g["last_check"] = raw.get("last_check")
        g["last_attempt"] = raw.get("last_attempt")
        for h in raw.get("history", []):
            try:
                d = datetime.strptime(h["date"], "%d/%m/%Y").date().isoformat()
                g["history"].append({"date": d, "price": float(h["price"])})
            except (KeyError, ValueError, TypeError):
                continue
        if g["saved"] > 0:
            g["log"].append({"ts": now_iso(), "amount": round(g["saved"], 2), "note": "Repris de la version 1"})
        data["goals"].append(g)
        data["selected"] = g["id"]
    try:
        shutil.copy2(DATA_FILE, DATA_DIR / "data.v1.json")
    except OSError:
        pass
    return data


def load_data():
    """Charge les données et met les identifiants au format commun (UUID) pour la synchro."""
    data = _read_data()
    remap = {}
    for g in data["goals"]:
        old = g["id"]
        try:
            g["id"] = str(uuid.UUID(str(old)))
        except ValueError:
            g["id"] = str(uuid.uuid4())
        remap[old] = g["id"]
        if not g.get("updated_at"):
            g["updated_at"] = utc_now()
        g["deleted"] = bool(g.get("deleted"))
    if data.get("selected") in remap:
        data["selected"] = remap[data["selected"]]
    return data


def save_data(data):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    tmp = DATA_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(DATA_FILE)


def parse_dt(value):
    try:
        return datetime.fromisoformat(value) if value else None
    except ValueError:
        return None


# ----------------------------------------------------------------------------
# Synchronisation : un gist secret de ton compte GitHub contient tes objectifs
# ----------------------------------------------------------------------------

EPOCH = "1970-01-01T00:00:00Z"


def utc_now():
    return datetime.now(timezone.utc).replace(microsecond=0).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_utc(value):
    """'2026-11-08T13:00:00Z' (ou ISO local sans fuseau) -> datetime UTC, None si invalide."""
    if not value:
        return None
    try:
        d = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None
    if d.tzinfo is None:
        d = d.astimezone()  # sans fuseau = heure locale
    return d.astimezone(timezone.utc)


def local_to_utc(value):
    d = parse_utc(value)
    return d.strftime("%Y-%m-%dT%H:%M:%SZ") if d else None


def utc_to_local(value):
    d = parse_utc(value)
    return d.astimezone().replace(tzinfo=None).isoformat(timespec="seconds") if d else None


def day_to_utc(day):
    return f"{day}T12:00:00Z"


def utc_to_day(value):
    d = parse_utc(value)
    return d.astimezone().date().isoformat() if d else None


def stamp(g):
    return parse_utc(g.get("updated_at")) or parse_utc(EPOCH)


def touch(g):
    """Marque l'objectif comme modifié maintenant (toujours strictement plus récent que sa version précédente)."""
    now, prev = parse_utc(utc_now()), stamp(g)
    if now <= prev:
        now = prev + timedelta(seconds=1)
    g["updated_at"] = now.strftime("%Y-%m-%dT%H:%M:%SZ")


def goal_to_wire(g):
    """Objectif local -> format commun iPhone / PC."""
    return {
        "id": g["id"].lower(),
        "name": g["name"],
        "url": g["url"],
        "price": g["price"],
        "saved": g["saved"],
        "monthly": g["monthly"],
        "alertBelow": g["alert_below"],
        "lastCheck": local_to_utc(g.get("last_check")),
        "history": [{"t": day_to_utc(h["date"]), "price": h["price"]} for h in g["history"]],
        "log": [{"t": local_to_utc(e["ts"]) or utc_now(), "amount": e["amount"], "note": e.get("note") or ""}
                for e in g["log"]],
        "updatedAt": g.get("updated_at") or EPOCH,
        "deleted": bool(g.get("deleted")),
    }


def goal_from_wire(w):
    """Format commun -> objectif local. Lève KeyError/ValueError/TypeError si le document est invalide."""
    g = new_goal(w.get("name") or "", w.get("url") or "",
                 float(w.get("monthly") or 0), float(w.get("alertBelow") or 0))
    g["id"] = str(uuid.UUID(str(w["id"])))
    g["price"] = None if w.get("price") is None else float(w["price"])
    g["saved"] = float(w.get("saved") or 0)
    g["last_check"] = utc_to_local(w.get("lastCheck"))
    hist = []
    for h in w.get("history") or []:
        day = utc_to_day(h.get("t"))
        if day:
            hist.append({"date": day, "price": float(h["price"])})
    g["history"] = sorted(hist, key=lambda h: h["date"])
    g["log"] = [{"ts": utc_to_local(e.get("t")) or now_iso(), "amount": float(e["amount"]),
                 "note": e.get("note") or ""} for e in (w.get("log") or [])]
    g["updated_at"] = w.get("updatedAt") or EPOCH
    g["deleted"] = bool(w.get("deleted"))
    return g


def merge_goals(local, remote):
    """Fusionne deux listes d'objectifs : pour chacun, la version modifiée en dernier gagne."""
    by_id = {g["id"]: g for g in local}
    order = [g["id"] for g in local]
    for r in remote:
        l = by_id.get(r["id"])
        if l is None:
            by_id[r["id"]] = r
            order.append(r["id"])
        elif stamp(r) > stamp(l):
            r = dict(r)
            for key in ("last_attempt", "last_error", "alerted_price"):  # propres à cet appareil
                r[key] = l.get(key)
            by_id[r["id"]] = r
    cutoff = datetime.now(timezone.utc) - timedelta(days=60)
    return [by_id[i] for i in order if not (by_id[i].get("deleted") and stamp(by_id[i]) < cutoff)]


def differs(a, b):
    return {g["id"]: stamp(g) for g in a} != {g["id"]: stamp(g) for g in b}


def needs_push(merged, remote):
    known = {g["id"]: stamp(g) for g in remote}
    return any(known.get(g["id"]) != stamp(g) for g in merged)


def make_doc(goals):
    return {"app": "objectif-prix", "version": 1, "goals": [goal_to_wire(g) for g in goals]}


def load_account():
    try:
        return json.loads(ACCOUNT_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def save_account(acc):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    fd = os.open(ACCOUNT_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)  # lisible par toi seul
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(acc, f)


class GistClient:
    def __init__(self, token, base=None):
        self.token = token.strip()
        self.base = base or GITHUB_API

    def _call(self, method, path, body=None, absolute=False):
        url = path if absolute else self.base + path
        data = json.dumps(body).encode("utf-8") if body is not None else None
        req = urllib.request.Request(url, data=data, method=method, headers={
            "Authorization": "Bearer " + self.token,
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "objectif-prix",
            "Content-Type": "application/json",
        })
        try:
            with urllib.request.urlopen(req, timeout=25) as resp:
                raw = resp.read().decode("utf-8")
        except urllib.error.HTTPError as e:
            if e.code == 401:
                raise RuntimeError("Jeton refusé : il est invalide ou a expiré.")
            if e.code == 403:
                raise RuntimeError("GitHub refuse l'accès (jeton sans la permission « gist », ou limite atteinte).")
            if e.code == 404:
                raise RuntimeError("Données en ligne introuvables (gist supprimé ?). Déconnecte-toi puis reconnecte-toi.")
            raise RuntimeError(f"Erreur GitHub {e.code}.")
        except urllib.error.URLError as e:
            raise RuntimeError(f"Connexion impossible : {e.reason}")
        except TimeoutError:
            raise RuntimeError("GitHub met trop de temps à répondre.")
        return json.loads(raw) if raw else {}

    def whoami(self):
        return self._call("GET", "/user")["login"]

    def find_gist(self):
        """Retourne l'id du plus ancien gist « Objectif Prix » du compte, ou None."""
        best = None
        for page in range(1, 6):
            items = self._call("GET", f"/gists?per_page=100&page={page}")
            for it in items:
                if GIST_FILE in (it.get("files") or {}) and (it.get("description") or "").startswith("Objectif Prix"):
                    if best is None or (it.get("created_at") or "") < (best.get("created_at") or ""):
                        best = it
            if len(items) < 100:
                break
        return best["id"] if best else None

    def create(self, doc):
        body = {"description": GIST_DESC, "public": False,
                "files": {GIST_FILE: {"content": json.dumps(doc, ensure_ascii=False)}}}
        return self._call("POST", "/gists", body)["id"]

    def read(self, gist_id):
        data = self._call("GET", f"/gists/{gist_id}")
        f = (data.get("files") or {}).get(GIST_FILE)
        if not f:
            raise RuntimeError("Fichier de données absent du gist.")
        content = f.get("content") or ""
        raw_url = f.get("raw_url") or ""
        if f.get("truncated") and raw_url.startswith("https://gist.githubusercontent.com/"):
            req = urllib.request.Request(raw_url, headers={"User-Agent": "objectif-prix"})
            with urllib.request.urlopen(req, timeout=25) as resp:
                content = resp.read().decode("utf-8")
        try:
            doc = json.loads(content) if content.strip() else {}
        except ValueError:
            raise RuntimeError("Le fichier de données en ligne est illisible.")
        return doc if isinstance(doc, dict) else {}

    def write(self, gist_id, doc):
        body = {"files": {GIST_FILE: {"content": json.dumps(doc, ensure_ascii=False)}}}
        self._call("PATCH", f"/gists/{gist_id}", body)


# ----------------------------------------------------------------------------
# Calculs et mise en forme
# ----------------------------------------------------------------------------

def fmt_eur(x):
    s = f"{x:,.2f}".replace(",", " ").replace(".", ",")
    return f"{s} €"


def fmt_axis(v, spread):
    s = f"{v:.0f}" if spread > 8 else f"{v:.2f}".replace(".", ",")
    return f"{s} €"


def fmt_num(x):
    return ("%g" % x).replace(".", ",")


def parse_optional(txt):
    txt = txt.strip()
    if not txt:
        return 0.0
    value = to_float(txt)
    if value < 0:
        raise ValueError("négatif")
    return value


def metrics(g):
    price, saved = g["price"], g["saved"]
    pct = min(saved / price * 100, 100) if price else 0.0
    remaining = max(price - saved, 0.0) if price else None
    return price, saved, pct, remaining


def estimate(g, remaining):
    if remaining is None:
        return "—", "Prix inconnu pour l'instant"
    if remaining <= 0:
        return "Atteint !", "Tu peux l'acheter"
    monthly = g.get("monthly") or 0
    if monthly <= 0:
        return "—", "Fixe une épargne mensuelle"
    months = remaining / monthly
    d = date.today() + timedelta(days=round(months * 30.44))
    return f"{MONTHS[d.month - 1]} {d.year}", f"{math.ceil(months)} mois à {fmt_eur(monthly)}/mois"


def variation(g):
    h = g["history"]
    if g["price"] is None:
        return "Aucun prix relevé", MUTED
    if len(h) >= 2:
        diff = h[-1]["price"] - h[-2]["price"]
        try:
            d = date.fromisoformat(h[-2]["date"]).strftime("%d/%m")
        except ValueError:
            d = "?"
        if abs(diff) < 0.005:
            return "Stable", MUTED
        arrow = "▼" if diff < 0 else "▲"
        return f"{arrow} {fmt_eur(abs(diff))} depuis le {d}", (GOOD if diff < 0 else BAD)
    return "Premier relevé", MUTED


def blend(c1, c2, t):
    t = max(0.0, min(1.0, t))
    a = [int(c1[i:i + 2], 16) for i in (1, 3, 5)]
    b = [int(c2[i:i + 2], 16) for i in (1, 3, 5)]
    return "#%02x%02x%02x" % tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def notify(title, body):
    exe = shutil.which("notify-send")
    if not exe:
        return
    try:
        subprocess.Popen([exe, "-a", "Objectif Prix", title, body],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass


# ----------------------------------------------------------------------------
# Installation dans le menu / démarrage automatique
# ----------------------------------------------------------------------------

def desktop_entry(target, minimized):
    cmd = f'python3 "{target}"' + (" --minimized" if minimized else "")
    return (
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Name=Objectif Prix\n"
        "Comment=Suis ton épargne vers l'article que tu veux\n"
        f"Exec={cmd}\n"
        f"Icon={ICON_FILE}\n"
        "Terminal=false\n"
        "Categories=Utility;Office;Finance;\n"
        "StartupWMClass=Objectifprix\n"
    )


def install_launcher(autostart=False):
    APP_DIR.mkdir(parents=True, exist_ok=True)
    src = Path(__file__).resolve()
    target = APP_DIR / "objectif_prix.py"
    if not target.exists() or src != target.resolve():
        shutil.copy2(src, target)

    ICON_FILE.parent.mkdir(parents=True, exist_ok=True)
    ICON_FILE.write_text(ICON_SVG, encoding="utf-8")

    DESKTOP_FILE.parent.mkdir(parents=True, exist_ok=True)
    DESKTOP_FILE.write_text(desktop_entry(target, False), encoding="utf-8")

    if autostart:
        AUTOSTART_FILE.parent.mkdir(parents=True, exist_ok=True)
        AUTOSTART_FILE.write_text(desktop_entry(target, True), encoding="utf-8")
    elif AUTOSTART_FILE.exists():
        AUTOSTART_FILE.unlink()

    exe = shutil.which("update-desktop-database")
    if exe:
        try:
            subprocess.run([exe, str(DESKTOP_FILE.parent)], timeout=10,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (OSError, subprocess.SubprocessError):
            pass
    return "Ajouté au menu : cherche « Objectif Prix » dans tes applications."


def remove_autostart():
    if AUTOSTART_FILE.exists():
        AUTOSTART_FILE.unlink()


# ----------------------------------------------------------------------------
# Widgets maison
# ----------------------------------------------------------------------------

def rrect(c, x1, y1, x2, y2, r, **kw):
    r = max(0, min(r, (x2 - x1) / 2, (y2 - y1) / 2))
    pts = [x1 + r, y1, x1 + r, y1, x2 - r, y1, x2 - r, y1, x2, y1, x2, y1 + r, x2, y1 + r,
           x2, y2 - r, x2, y2 - r, x2, y2, x2 - r, y2, x2 - r, y2, x1 + r, y2, x1 + r, y2,
           x1, y2, x1, y2 - r, x1, y2 - r, x1, y1 + r, x1, y1 + r, x1, y1]
    return c.create_polygon(pts, smooth=True, **kw)


class RoundButton(tk.Canvas):
    def __init__(self, parent, text, command, bg, fg, hover, w=120, h=38, r=12,
                 font=None, parent_bg=PANEL):
        super().__init__(parent, width=w, height=h, bg=parent_bg, highlightthickness=0, cursor="hand2")
        self.w, self.h, self.r = w, h, r
        self.text, self.command, self.fg = text, command, fg
        self.base, self.hover, self.font = bg, hover, font
        self._render(self.base)
        self.bind("<Enter>", lambda e: self._render(self.hover))
        self.bind("<Leave>", lambda e: self._render(self.base))
        self.bind("<ButtonRelease-1>", self._click)

    def _render(self, color):
        self.delete("all")
        rrect(self, 1, 1, self.w - 1, self.h - 1, self.r, fill=color, outline=color)
        self.create_text(self.w / 2, self.h / 2, text=self.text, fill=self.fg, font=self.font)

    def set_text(self, text):
        self.text = text
        self._render(self.base)

    def _click(self, e):
        if 0 <= e.x <= self.w and 0 <= e.y <= self.h and self.command:
            self.command()


class RoundPanel(tk.Canvas):
    """Panneau aux coins arrondis qui contient un Frame (self.inner)."""

    def __init__(self, parent, outer, fill, border, width, pad=22):
        super().__init__(parent, width=width, bg=outer, highlightthickness=0)
        self.fill, self.border, self.pad = fill, border, pad
        self.inner = tk.Frame(self, bg=fill)
        self.create_window(pad, pad, window=self.inner, anchor="nw", width=width - 2 * pad)
        self.bind("<Configure>", self._redraw)

    def _redraw(self, e):
        self.delete("bg")
        rrect(self, 1, 1, e.width - 1, e.height - 1, 22, fill=self.fill, outline=self.border, tags="bg")
        self.tag_lower("bg")


class FormDialog(tk.Toplevel):
    def __init__(self, app, title, fields, submit_text, on_submit, danger=None, intro=None):
        super().__init__(app.root)
        self.app, self.on_submit, self.danger = app, on_submit, danger
        self.configure(bg=PANEL)
        self.title(title)
        self.transient(app.root)
        self.resizable(False, False)

        body = tk.Frame(self, bg=PANEL, padx=28, pady=24)
        body.pack(fill="both")
        tk.Label(body, text=title, bg=PANEL, fg=TEXT, font=app.f(16, True)).pack(anchor="w")
        if intro:
            tk.Label(body, text=intro, bg=PANEL, fg=MUTED, font=app.f(10), wraplength=440,
                     justify="left").pack(anchor="w", pady=(6, 0))

        self.vars = {}
        first = None
        for key, label, value, hint in fields:
            tk.Label(body, text=label.upper(), bg=PANEL, fg=MUTED, font=app.f(8, True)).pack(anchor="w", pady=(14, 4))
            var = tk.StringVar(value=value)
            self.vars[key] = var
            wrap, entry = app.make_entry(body, var, 11, 46)
            wrap.pack(fill="x")
            if first is None:
                first = entry
            if hint:
                tk.Label(body, text=hint, bg=PANEL, fg=MUTED, font=app.f(9)).pack(anchor="w", pady=(3, 0))

        self.err = tk.Label(body, text="", bg=PANEL, fg=BAD, font=app.f(10), wraplength=440, justify="left")
        self.err.pack(anchor="w", pady=(12, 0))

        row = tk.Frame(body, bg=PANEL)
        row.pack(fill="x", pady=(14, 0))
        RoundButton(row, submit_text, self.submit, bg=ACCENT, fg=ON_ACCENT, hover=blend(ACCENT, "#FFFFFF", 0.2),
                    w=150, h=40, font=app.f(10, True), parent_bg=PANEL).pack(side="right")
        RoundButton(row, "Annuler", self.destroy, bg=PANEL2, fg=TEXT, hover=BORDER,
                    w=100, h=40, font=app.f(10, True), parent_bg=PANEL).pack(side="right", padx=8)
        if danger:
            RoundButton(row, danger[0], self._danger, bg=blend(BAD, PANEL, 0.75), fg=BAD,
                        hover=blend(BAD, PANEL, 0.6), w=110, h=40, font=app.f(10, True),
                        parent_bg=PANEL).pack(side="left")

        self.bind("<Return>", lambda e: self.submit())
        self.bind("<Escape>", lambda e: self.destroy())
        self.update_idletasks()
        x = app.root.winfo_rootx() + (app.root.winfo_width() - self.winfo_reqwidth()) // 2
        y = app.root.winfo_rooty() + max((app.root.winfo_height() - self.winfo_reqheight()) // 3, 20)
        self.geometry(f"+{max(x, 0)}+{max(y, 0)}")
        if first is not None:
            first.focus_set()
        self.after(80, self._grab)

    def _grab(self):
        try:
            self.grab_set()
        except tk.TclError:
            pass

    def submit(self):
        values = {k: v.get().strip() for k, v in self.vars.items()}
        error = self.on_submit(values)
        if error:
            self.err.config(text=error)
        else:
            self.destroy()

    def _danger(self):
        if self.danger[1]():
            self.destroy()


# ----------------------------------------------------------------------------
# Application
# ----------------------------------------------------------------------------

class App:
    def __init__(self, root, minimized=False):
        self.root = root
        root.title("Objectif Prix")
        root.configure(bg=BG)
        root.geometry("1180x760")
        root.minsize(1060, 680)

        self.fam = self.pick_font()
        self.tip_font = tkfont.Font(family=self.fam, size=10, weight="bold")
        self.data = load_data()
        alive = self.alive()
        if alive and not self.goal:
            self.data["selected"] = alive[0]["id"]

        # synchronisation
        self.account = load_account()
        self.sync_results = queue.Queue()
        self.sync_busy = False
        self.sync_again = False
        self.sync_manual = False
        self.sync_text = ""
        self.sync_error = False
        self._sync_job = None
        self.account_win = None
        self.account_body = None
        self.account_status = None

        self.results = queue.Queue()
        self.fetching = False
        self.fetch_manual = False
        self.ring_val = 0.0
        self._ring_job = None
        self._toast_job = None
        self._pct_seen = {}
        self.chart_pts = []
        self.chart_bounds = (0, 0)

        self.build_ui()
        self.refresh_all(reanimate=True)
        self.root.after(300, self.poll_results)
        self.root.after(300, self.poll_sync)
        self.root.after(800, self.start_sync)          # d'abord récupérer les changements de l'autre appareil
        self.root.after(SYNC_EVERY_MS, self.periodic_sync)
        self.root.after(6000, self.auto_check)         # puis relever les prix
        if minimized:
            self.root.iconify()

    # ---- utilitaires -------------------------------------------------------
    def pick_font(self):
        fams = set(tkfont.families(self.root))
        for name in ("Ubuntu", "Inter", "Noto Sans", "DejaVu Sans", "Liberation Sans"):
            if name in fams:
                return name
        return "Helvetica"

    def f(self, size, bold=False):
        return (self.fam, size, "bold") if bold else (self.fam, size)

    def alive(self):
        return [g for g in self.data["goals"] if not g.get("deleted")]

    @property
    def goal(self):
        sel = self.data.get("selected")
        for g in self.data["goals"]:
            if g["id"] == sel and not g.get("deleted"):
                return g
        return None

    def make_entry(self, parent, var, size=12, width=10, justify="left"):
        wrap = tk.Frame(parent, bg=BORDER, padx=1, pady=1)
        entry = tk.Entry(wrap, textvariable=var, bg=INPUT, fg=TEXT, insertbackground=ACCENT,
                         relief="flat", bd=0, highlightthickness=0, font=self.f(size),
                         justify=justify, width=width)
        entry.pack(fill="x", ipady=8, padx=2)
        entry.bind("<FocusIn>", lambda e: wrap.config(bg=ACCENT))
        entry.bind("<FocusOut>", lambda e: wrap.config(bg=BORDER))
        return wrap, entry

    def btn(self, parent, text, command, kind="ghost", w=110, h=36, parent_bg=BG):
        if kind == "primary":
            bg, fg, hov = ACCENT, ON_ACCENT, blend(ACCENT, "#FFFFFF", 0.2)
        else:
            bg, fg, hov = PANEL2, TEXT, BORDER
        return RoundButton(parent, text, command, bg=bg, fg=fg, hover=hov, w=w, h=h,
                           font=self.f(10, True), parent_bg=parent_bg)

    def toast(self, text, kind="info"):
        bg, fg = {"info": (PANEL2, TEXT), "good": (ACCENT, ON_ACCENT), "bad": (BAD, "#2B0510")}[kind]
        if self._toast_job:
            self.root.after_cancel(self._toast_job)
        self.toast_lbl.config(text=text, bg=bg, fg=fg)
        self.toast_lbl.place(relx=1.0, rely=1.0, x=-26, y=-24, anchor="se")
        self.toast_lbl.lift()
        self._toast_job = self.root.after(5500, self.toast_lbl.place_forget)

    # ---- construction de l'interface --------------------------------------
    def build_ui(self):
        root = self.root
        root.columnconfigure(1, weight=1)
        root.rowconfigure(0, weight=1)

        # Barre latérale
        self.side = tk.Frame(root, bg=PANEL, width=280)
        self.side.grid(row=0, column=0, sticky="ns")
        self.side.pack_propagate(False)

        head = tk.Frame(self.side, bg=PANEL)
        head.pack(fill="x", padx=20, pady=(24, 18))
        logo = tk.Canvas(head, width=38, height=38, bg=PANEL, highlightthickness=0)
        logo.pack(side="left")
        logo.create_oval(5, 5, 33, 33, outline=BORDER, width=6)
        logo.create_arc(5, 5, 33, 33, start=90, extent=-240, style=tk.ARC, outline=ACCENT, width=6)
        tk.Label(head, text="Objectif Prix", bg=PANEL, fg=TEXT, font=self.f(16, True)).pack(side="left", padx=12)

        tk.Label(self.side, text="MES OBJECTIFS", bg=PANEL, fg=MUTED, font=self.f(8, True)).pack(anchor="w", padx=22)

        self.list_canvas = tk.Canvas(self.side, bg=PANEL, highlightthickness=0)
        self.list_canvas.pack(fill="both", expand=True, padx=(12, 8), pady=(8, 8))
        self.list_inner = tk.Frame(self.list_canvas, bg=PANEL)
        self.list_win = self.list_canvas.create_window((0, 0), window=self.list_inner, anchor="nw")
        self.list_inner.bind("<Configure>", lambda e: self.list_canvas.configure(
            scrollregion=self.list_canvas.bbox("all")))
        self.list_canvas.bind("<Configure>", lambda e: self.list_canvas.itemconfigure(self.list_win, width=e.width))
        self.list_canvas.bind("<Enter>", self._bind_wheel)
        self.list_canvas.bind("<Leave>", self._unbind_wheel)

        bottom = tk.Frame(self.side, bg=PANEL)
        bottom.pack(fill="x", padx=20, pady=(0, 20))
        RoundButton(bottom, "+  Nouvel objectif", lambda: self.goal_dialog(None), bg=ACCENT, fg=ON_ACCENT,
                    hover=blend(ACCENT, "#FFFFFF", 0.2), w=238, h=44, r=14, font=self.f(11, True),
                    parent_bg=PANEL).pack()
        self.sync_lbl = tk.Label(bottom, text=self.sidebar_sync_text(), bg=PANEL, fg=MUTED, font=self.f(10),
                                 cursor="hand2", wraplength=238, justify="center")
        self.sync_lbl.pack(pady=(14, 0))
        self.sync_lbl.bind("<Button-1>", lambda e: self.open_account())
        self.sync_lbl.bind("<Enter>", lambda e: self.sync_lbl.config(fg=TEXT))
        self.sync_lbl.bind("<Leave>", lambda e: self.sync_lbl.config(fg=BAD if self.sync_error else MUTED))
        settings = tk.Label(bottom, text="Réglages", bg=PANEL, fg=MUTED, font=self.f(10), cursor="hand2")
        settings.pack(pady=(8, 0))
        settings.bind("<Button-1>", lambda e: self.open_settings())
        settings.bind("<Enter>", lambda e: settings.config(fg=TEXT))
        settings.bind("<Leave>", lambda e: settings.config(fg=MUTED))

        # Zone principale
        self.main = tk.Frame(root, bg=BG)
        self.main.grid(row=0, column=1, sticky="nsew", padx=22, pady=18)
        self.main.columnconfigure(0, weight=1)
        self.main.rowconfigure(2, weight=1)

        hdr = tk.Frame(self.main, bg=BG)
        hdr.grid(row=0, column=0, sticky="ew")
        hdr.columnconfigure(0, weight=1)
        left = tk.Frame(hdr, bg=BG)
        left.grid(row=0, column=0, sticky="w")
        self.title_lbl = tk.Label(left, text="", bg=BG, fg=TEXT, font=self.f(24, True), anchor="w")
        self.title_lbl.pack(anchor="w")
        self.sub_lbl = tk.Label(left, text="", bg=BG, fg=MUTED, font=self.f(10), anchor="w")
        self.sub_lbl.pack(anchor="w", pady=(2, 0))
        right = tk.Frame(hdr, bg=BG)
        right.grid(row=0, column=1, sticky="e")
        self.btn_refresh = self.btn(right, "Actualiser", self.refresh_selected, w=104)
        self.btn_refresh.pack(side="left", padx=4)
        self.btn(right, "Prix manuel", self.manual_price_dialog, w=116).pack(side="left", padx=4)
        self.btn(right, "Modifier", lambda: self.goal_dialog(self.goal), w=96).pack(side="left", padx=4)

        self.hero = tk.Canvas(self.main, height=250, bg=BG, highlightthickness=0)
        self.hero.grid(row=1, column=0, sticky="ew", pady=(16, 16))
        self.hero.bind("<Configure>", lambda e: self.draw_hero())

        low = tk.Frame(self.main, bg=BG)
        low.grid(row=2, column=0, sticky="nsew")
        low.columnconfigure(0, weight=1)
        low.rowconfigure(0, weight=1)

        self.chart = tk.Canvas(low, bg=BG, highlightthickness=0)
        self.chart.grid(row=0, column=0, sticky="nsew", padx=(0, 16))
        self.chart.bind("<Configure>", lambda e: self.draw_chart())
        self.chart.bind("<Motion>", self.on_chart_motion)
        self.chart.bind("<Leave>", lambda e: self.chart.delete("hover"))

        self.money_panel = RoundPanel(low, outer=BG, fill=PANEL, border=BORDER, width=360)
        self.money_panel.grid(row=0, column=1, sticky="ns")
        self.build_money(self.money_panel.inner)

        # Écran vide (aucun objectif)
        self.empty = tk.Frame(self.main, bg=BG)
        box = tk.Frame(self.empty, bg=BG)
        box.place(relx=0.5, rely=0.45, anchor="center")
        tk.Label(box, text="Aucun objectif pour l'instant", bg=BG, fg=TEXT, font=self.f(26, True)).pack()
        tk.Label(box, text="Colle le lien d'un produit idealo et commence à épargner pour l'avoir.",
                 bg=BG, fg=MUTED, font=self.f(12)).pack(pady=(8, 22))
        RoundButton(box, "Créer mon premier objectif", lambda: self.goal_dialog(None), bg=ACCENT, fg=ON_ACCENT,
                    hover=blend(ACCENT, "#FFFFFF", 0.2), w=280, h=50, r=16, font=self.f(12, True),
                    parent_bg=BG).pack()

        self.toast_lbl = tk.Label(root, text="", font=self.f(11, True), padx=16, pady=10)

    def build_money(self, inner):
        tk.Label(inner, text="MON ARGENT", bg=PANEL, fg=MUTED, font=self.f(8, True)).pack(anchor="w")
        row = tk.Frame(inner, bg=PANEL)
        row.pack(fill="x", pady=(10, 0))
        self.amount_var = tk.StringVar()
        wrap, self.amount_entry = self.make_entry(row, self.amount_var, 20, 8, justify="right")
        wrap.pack(side="left", fill="x", expand=True)
        tk.Label(row, text="€", bg=PANEL, fg=MUTED, font=self.f(20, True)).pack(side="left", padx=(10, 0))
        self.amount_entry.bind("<Return>", lambda e: self.change_saved(+1))

        self.note_var = tk.StringVar()
        wrap2, note_entry = self.make_entry(inner, self.note_var, 10, 20)
        wrap2.pack(fill="x", pady=(10, 0))
        tk.Label(inner, text="Note facultative (ex : prime, cadeau…)", bg=PANEL, fg=MUTED,
                 font=self.f(9)).pack(anchor="w", pady=(3, 0))

        btns = tk.Frame(inner, bg=PANEL)
        btns.pack(fill="x", pady=(14, 0))
        RoundButton(btns, "+  Ajouter", lambda: self.change_saved(+1), bg=ACCENT, fg=ON_ACCENT,
                    hover=blend(ACCENT, "#FFFFFF", 0.2), w=150, h=44, r=14, font=self.f(11, True),
                    parent_bg=PANEL).pack(side="left")
        RoundButton(btns, "−  Retirer", lambda: self.change_saved(-1), bg=blend(BAD, PANEL, 0.75), fg=BAD,
                    hover=blend(BAD, PANEL, 0.6), w=150, h=44, r=14, font=self.f(11, True),
                    parent_bg=PANEL).pack(side="right")

        tk.Frame(inner, bg=BORDER, height=1).pack(fill="x", pady=(20, 14))
        tk.Label(inner, text="ACTIVITÉ", bg=PANEL, fg=MUTED, font=self.f(8, True)).pack(anchor="w")
        self.log_frame = tk.Frame(inner, bg=PANEL)
        self.log_frame.pack(fill="x", pady=(6, 0))

    def _bind_wheel(self, e):
        self.root.bind_all("<Button-4>", lambda ev: self.list_canvas.yview_scroll(-1, "units"))
        self.root.bind_all("<Button-5>", lambda ev: self.list_canvas.yview_scroll(1, "units"))

    def _unbind_wheel(self, e):
        self.root.unbind_all("<Button-4>")
        self.root.unbind_all("<Button-5>")

    # ---- rafraîchissement global ------------------------------------------
    def refresh_all(self, reanimate=False):
        self.rebuild_list()
        g = self.goal
        if not g:
            self.empty.place(relx=0, rely=0, relwidth=1, relheight=1)
            self.empty.lift()
            self.title_lbl.config(text="")
            self.sub_lbl.config(text="")
            return
        self.empty.place_forget()

        self.title_lbl.config(text=g["name"] or "Sans nom")
        if g.get("last_error"):
            self.sub_lbl.config(text="Dernier relevé échoué : " + g["last_error"][:110], fg=BAD)
        else:
            parts = [urllib.parse.urlparse(g["url"]).netloc.replace("www.", "") if g["url"] else "Prix saisi à la main"]
            lc = parse_dt(g["last_check"])
            if lc:
                parts.append("mis à jour le " + lc.strftime("%d/%m à %H:%M"))
            self.sub_lbl.config(text="  ·  ".join(parts), fg=MUTED)

        self.draw_hero()
        self.draw_chart()
        self.rebuild_log()

        pct = metrics(g)[2]
        if reanimate:
            self.ring_val = 0.0
        self.animate_ring(pct)

        prev = self._pct_seen.get(g["id"])
        if prev is not None and prev < 100 <= pct:
            self.start_confetti()
            notify("Objectif atteint !", f"Tu as de quoi acheter : {g['name'] or 'ton article'}")
        self._pct_seen[g["id"]] = pct

    def rebuild_list(self):
        for w in self.list_inner.winfo_children():
            w.destroy()
        for g in self.alive():
            self.make_goal_card(g)

    def make_goal_card(self, g):
        sel = g["id"] == self.data["selected"]
        bg = PANEL2 if sel else PANEL
        card = tk.Frame(self.list_inner, bg=bg, cursor="hand2")
        card.pack(fill="x", pady=4, padx=4)
        strip = tk.Frame(card, bg=ACCENT if sel else bg, width=3)
        strip.pack(side="left", fill="y")
        body = tk.Frame(card, bg=bg)
        body.pack(side="left", fill="both", expand=True, padx=12, pady=11)
        name = tk.Label(body, text=g["name"] or "Sans nom", bg=bg, fg=TEXT, font=self.f(11, True),
                        anchor="w", justify="left", wraplength=190)
        name.pack(fill="x")
        price, saved, pct, _ = metrics(g)
        sub_txt = f"{fmt_eur(saved)} sur {fmt_eur(price)}" if price else f"{fmt_eur(saved)} · prix inconnu"
        sub = tk.Label(body, text=sub_txt, bg=bg, fg=MUTED, font=self.f(9), anchor="w")
        sub.pack(fill="x", pady=(2, 7))
        bar = tk.Canvas(body, height=6, width=190, bg=bg, highlightthickness=0)
        bar.pack(anchor="w")
        bar.create_rectangle(0, 0, 190, 6, fill=BORDER, outline=BORDER)
        if pct > 0:
            bar.create_rectangle(0, 0, 190 * pct / 100, 6, fill=GOLD if pct >= 100 else ACCENT, outline="")
        gid = g["id"]
        for w in (card, strip, body, name, sub, bar):
            w.bind("<Button-1>", lambda e, i=gid: self.select_goal(i))

    def rebuild_log(self):
        for w in self.log_frame.winfo_children():
            w.destroy()
        g = self.goal
        entries = list(reversed(g["log"][-6:])) if g else []
        if not entries:
            tk.Label(self.log_frame, text="Aucun mouvement pour l'instant.", bg=PANEL, fg=MUTED,
                     font=self.f(10)).pack(anchor="w", pady=4)
            return
        for e in entries:
            row = tk.Frame(self.log_frame, bg=PANEL)
            row.pack(fill="x", pady=3)
            amt = e["amount"]
            tk.Label(row, text=("+ " if amt > 0 else "− ") + fmt_eur(abs(amt)), bg=PANEL,
                     fg=GOOD if amt > 0 else BAD, font=self.f(11, True)).pack(side="left")
            ts = parse_dt(e.get("ts"))
            extra = ts.strftime("%d/%m") if ts else ""
            if e.get("note"):
                extra += "  ·  " + e["note"][:22]
            tk.Label(row, text="   " + extra, bg=PANEL, fg=MUTED, font=self.f(10)).pack(side="left")

    # ---- dessin : bandeau principal ---------------------------------------
    def draw_hero(self):
        c = self.hero
        c.delete("all")
        w = max(c.winfo_width(), 700)
        h = 250
        rrect(c, 1, 1, w - 1, h - 1, 24, fill=PANEL, outline=BORDER)
        g = self.goal
        if not g:
            return
        cx, cy, R = 135, 125, 88
        c.create_oval(cx - R, cy - R, cx + R, cy + R, outline=PANEL2, width=18)

        price, saved, pct, rem = metrics(g)
        var_txt, var_col = variation(g)
        est_val, est_sub = estimate(g, rem)
        lows = [p["price"] for p in g["history"]]
        low_txt = f"Plus bas relevé : {fmt_eur(min(lows))}" if lows else "En attente d'un relevé"
        if rem is None:
            rem_txt = "—"
        elif rem <= 0:
            rem_txt = "Atteint !"
        else:
            rem_txt = fmt_eur(rem)

        tiles = [
            ("PRIX ACTUEL", fmt_eur(price) if price else "—", var_txt, var_col),
            ("ÉPARGNÉ", fmt_eur(saved), f"{pct:.0f} % de l'objectif", MUTED),
            ("IL MANQUE", rem_txt, low_txt, MUTED),
            ("DATE ESTIMÉE", est_val, est_sub, MUTED),
        ]
        x0, x1 = 290, w - 26
        tw = (x1 - x0 - 14) / 2
        for i, (label, value, sub, col) in enumerate(tiles):
            tx = x0 + (i % 2) * (tw + 14)
            ty = 22 + (i // 2) * 112
            rrect(c, tx, ty, tx + tw, ty + 104, 18, fill=PANEL2, outline=PANEL2)
            c.create_text(tx + 20, ty + 24, text=label, anchor="w", fill=MUTED, font=self.f(8, True))
            c.create_text(tx + 20, ty + 54, text=value, anchor="w", fill=TEXT, font=self.f(18, True))
            c.create_text(tx + 20, ty + 84, text=sub, anchor="w", fill=col, font=self.f(9))
        self.draw_ring(self.ring_val)

    def draw_ring(self, val):
        c = self.hero
        c.delete("ring")
        cx, cy, R = 135, 125, 88
        total = val * 3.6
        reached = val >= 99.95
        c1, c2 = (GOLD, ACCENT) if reached else (ACCENT2, ACCENT)
        step = 3
        for k in range(int(math.ceil(total / step))):
            a0 = k * step
            ext = min(step, total - a0)
            if ext <= 0:
                break
            col = blend(c1, c2, (a0 + ext / 2) / 360)
            c.create_arc(cx - R, cy - R, cx + R, cy + R, start=90 - a0 - ext,
                         extent=min(ext + 0.8, 359.9), style=tk.ARC, outline=col, width=18, tags="ring")
        if val > 0.3:
            for ang, col in ((0, c1), (total, blend(c1, c2, total / 360))):
                th = math.radians(90 - ang)
                px, py = cx + R * math.cos(th), cy - R * math.sin(th)
                c.create_oval(px - 9, py - 9, px + 9, py + 9, fill=col, outline=col, tags="ring")
        c.create_text(cx, cy - 10, text=f"{val:.0f} %", fill=GOLD if reached else TEXT,
                      font=self.f(32, True), tags="ring")
        c.create_text(cx, cy + 28, text="de l'objectif", fill=MUTED, font=self.f(10), tags="ring")

    def animate_ring(self, target):
        target = max(0.0, min(100.0, target))
        if self._ring_job:
            self.root.after_cancel(self._ring_job)
            self._ring_job = None
        start, t0, dur = self.ring_val, time.time(), 0.8

        def step():
            k = min((time.time() - t0) / dur, 1.0)
            self.ring_val = start + (target - start) * (1 - (1 - k) ** 3)
            self.draw_ring(self.ring_val)
            if k < 1:
                self._ring_job = self.root.after(16, step)
            else:
                self._ring_job = None

        step()

    def start_confetti(self):
        c = self.hero
        cx, cy = 135, 125
        colors = [ACCENT, ACCENT2, GOLD, BAD, TEXT]
        parts = []
        for _ in range(90):
            pw, ph = random.randint(4, 8), random.randint(3, 6)
            item = c.create_rectangle(cx, cy, cx + pw, cy + ph, fill=random.choice(colors),
                                      outline="", tags="confetti")
            parts.append([item, random.uniform(-7, 7), random.uniform(-11, -3)])
        frames = [0]

        def tick():
            frames[0] += 1
            for p in parts:
                p[2] += 0.4
                c.move(p[0], p[1], p[2])
            if frames[0] < 80:
                self.root.after(28, tick)
            else:
                c.delete("confetti")

        tick()

    # ---- dessin : graphique du prix ---------------------------------------
    def draw_chart(self):
        c = self.chart
        c.delete("all")
        w, h = c.winfo_width(), c.winfo_height()
        self.chart_pts = []
        if w < 80 or h < 80:
            return
        rrect(c, 1, 1, w - 1, h - 1, 24, fill=PANEL, outline=BORDER)
        c.create_text(26, 30, text="ÉVOLUTION DU PRIX", anchor="w", fill=MUTED, font=self.f(8, True))
        g = self.goal
        if not g:
            return

        pts = []
        for p in g["history"]:
            try:
                pts.append((date.fromisoformat(p["date"]), float(p["price"])))
            except (ValueError, KeyError):
                continue
        pts.sort(key=lambda t: t[0])
        if not pts:
            c.create_text(w / 2, h / 2 - 8, text="Pas encore de relevé de prix", fill=TEXT, font=self.f(13, True))
            c.create_text(w / 2, h / 2 + 16, text="Le graphique se construit au fil des jours.",
                          fill=MUTED, font=self.f(10))
            return

        prices = [p[1] for p in pts]
        ymin, ymax = min(prices), max(prices)
        c.create_text(w - 26, 30, anchor="e", fill=MUTED, font=self.f(9),
                      text=f"plus bas {fmt_eur(ymin)}   ·   plus haut {fmt_eur(ymax)}")

        left, right, top, bottom = 70, w - 34, 60, h - 42
        self.chart_bounds = (top, bottom)
        spread = ymax - ymin
        pad = spread * 0.25 if spread > 0 else max(ymax * 0.05, 1.0)
        lo, hi = ymin - pad, ymax + pad

        def ypos(v):
            return bottom - (v - lo) / (hi - lo) * (bottom - top)

        d0, d1 = pts[0][0].toordinal(), pts[-1][0].toordinal()

        def xpos(d):
            if d1 == d0:
                return (left + right) / 2
            return left + (d.toordinal() - d0) / (d1 - d0) * (right - left)

        for i in range(4):
            v = lo + (hi - lo) * i / 3
            y = ypos(v)
            c.create_line(left, y, right, y, fill=PANEL2)
            c.create_text(left - 12, y, text=fmt_axis(v, hi - lo), anchor="e", fill=MUTED, font=self.f(9))

        if lo <= g["saved"] <= hi and g["saved"] > 0:
            ys = ypos(g["saved"])
            c.create_line(left, ys, right, ys, fill=GOLD, dash=(6, 5))
            c.create_text(right, ys - 10, text="mon épargne", anchor="e", fill=GOLD, font=self.f(9))

        coords = [(xpos(d), ypos(v), d, v) for d, v in pts]
        self.chart_pts = coords
        if len(coords) >= 2:
            flat = [k for p in coords for k in (p[0], p[1])]
            c.create_polygon(flat + [coords[-1][0], bottom, coords[0][0], bottom],
                             fill=blend(ACCENT, PANEL, 0.88), outline="")
            c.create_line(flat, fill=ACCENT, width=3, capstyle=tk.ROUND, joinstyle=tk.ROUND)
        if len(coords) <= 40:
            for x, y, _, _ in coords[:-1]:
                c.create_oval(x - 3.5, y - 3.5, x + 3.5, y + 3.5, fill=ACCENT, outline=PANEL, width=1)
        lx, ly, _, lv = coords[-1]
        c.create_oval(lx - 11, ly - 11, lx + 11, ly + 11, fill=blend(ACCENT, PANEL, 0.8), outline="")
        c.create_oval(lx - 6, ly - 6, lx + 6, ly + 6, fill=ACCENT, outline=PANEL, width=2)

        c.create_text(left, bottom + 22, text=pts[0][0].strftime("%d/%m/%Y"), anchor="w", fill=MUTED, font=self.f(9))
        if len(pts) > 1:
            c.create_text(right, bottom + 22, text=pts[-1][0].strftime("%d/%m/%Y"), anchor="e",
                          fill=MUTED, font=self.f(9))

    def on_chart_motion(self, e):
        c = self.chart
        c.delete("hover")
        if not self.chart_pts:
            return
        x, y, d, price = min(self.chart_pts, key=lambda p: abs(p[0] - e.x))
        if abs(x - e.x) > 40:
            return
        top, bottom = self.chart_bounds
        c.create_line(x, top, x, bottom, fill=BORDER, dash=(3, 3), tags="hover")
        c.create_oval(x - 7, y - 7, x + 7, y + 7, fill=TEXT, outline=ACCENT, width=3, tags="hover")
        label = f"{d.strftime('%d/%m/%Y')}    {fmt_eur(price)}"
        tw = self.tip_font.measure(label) + 28
        bx = min(max(x - tw / 2, 8), c.winfo_width() - tw - 8)
        by = y - 52 if y - 52 > 40 else y + 18
        rrect(c, bx, by, bx + tw, by + 32, 10, fill=PANEL2, outline=ACCENT, tags="hover")
        c.create_text(bx + tw / 2, by + 16, text=label, fill=TEXT, font=self.f(10, True), tags="hover")

    # ---- objectifs ----------------------------------------------------------
    def select_goal(self, gid):
        if gid == self.data["selected"]:
            return
        self.data["selected"] = gid
        save_data(self.data)
        self.refresh_all(reanimate=True)

    def goal_dialog(self, goal):
        editing = goal is not None
        fields = [
            ("name", "Produit", goal["name"] if editing else "", "Ex : Apple Watch SE 3"),
            ("url", "Lien idealo", goal["url"] if editing else "",
             "Adresse de la page produit sur idealo.fr. Vide = prix saisi à la main."),
            ("monthly", "Épargne par mois (€)", fmt_num(goal["monthly"]) if editing and goal["monthly"] else "",
             "Sert à estimer la date à laquelle tu pourras l'acheter."),
            ("alert", "Alerte si le prix passe sous (€)",
             fmt_num(goal["alert_below"]) if editing and goal["alert_below"] else "",
             "Tu reçois une notification quand le prix descend sous ce seuil."),
        ]

        def on_submit(v):
            try:
                monthly, alert = parse_optional(v["monthly"]), parse_optional(v["alert"])
            except ValueError:
                return "Les montants doivent être des nombres positifs (ex : 50 ou 12,5)."
            url = v["url"]
            if url and not re.match(r"https?://", url):
                return "Le lien doit commencer par http:// ou https://"
            if not v["name"] and not url:
                return "Donne au moins un nom ou un lien."

            if editing:
                changed = url != goal["url"]
                goal.update(name=v["name"], url=url, monthly=monthly, alert_below=alert)
                if changed:
                    goal.update(last_check=None, last_attempt=None, last_error=None, alerted_price=None)
                    if url:
                        goal.update(price=None, history=[])
                target = goal
            else:
                target = new_goal(v["name"], url, monthly, alert)
                self.data["goals"].append(target)
                self.data["selected"] = target["id"]
                changed = bool(url)
            touch(target)
            save_data(self.data)
            self.mark_dirty()
            self.refresh_all(reanimate=not editing)
            if url and changed:
                self.start_fetch([target], manual=True)
            return None

        danger = ("Supprimer", lambda: self.delete_goal(goal)) if editing else None
        FormDialog(self, "Modifier l'objectif" if editing else "Nouvel objectif", fields,
                   "Enregistrer", on_submit, danger=danger)

    def delete_goal(self, goal):
        if not messagebox.askyesno("Supprimer l'objectif",
                                   f"Supprimer « {goal['name'] or 'cet objectif'} » et son historique ?",
                                   parent=self.root):
            return False
        goal["deleted"] = True              # on garde une trace pour que l'autre appareil le supprime aussi
        touch(goal)
        alive = self.alive()
        self.data["selected"] = alive[0]["id"] if alive else None
        save_data(self.data)
        self.mark_dirty()
        self.refresh_all(reanimate=True)
        return True

    def manual_price_dialog(self):
        g = self.goal
        if not g:
            return
        hint = f"Prix actuel enregistré : {fmt_eur(g['price'])}" if g["price"] else "Aucun prix enregistré."

        def on_submit(v):
            try:
                price = to_float(v["price"])
                if price <= 0:
                    raise ValueError
            except ValueError:
                return "Entre un prix valide (ex : 279 ou 279,99)."
            self.record_price(g, price, notify_user=False)
            self.toast("Prix enregistré", "good")
            return None

        FormDialog(self, "Prix manuel", [("price", "Prix (€)", "", hint)], "Enregistrer", on_submit,
                   intro="Pratique si idealo bloque la lecture automatique. "
                         "Le prochain relevé automatique pourra le remplacer.")

    # ---- argent -------------------------------------------------------------
    def change_saved(self, sign):
        g = self.goal
        if not g:
            return
        try:
            amount = to_float(self.amount_var.get())
        except ValueError:
            self.toast("Montant invalide (ex : 25 ou 12,50)", "bad")
            return
        if amount <= 0:
            self.toast("Le montant doit être supérieur à 0", "bad")
            return
        if sign < 0:
            amount = min(amount, g["saved"])
            if amount <= 0:
                self.toast("Il n'y a rien à retirer", "bad")
                return
        g["saved"] = round(max(g["saved"] + sign * amount, 0), 2)
        g["log"].append({"ts": now_iso(), "amount": round(sign * amount, 2), "note": self.note_var.get().strip()})
        g["log"] = g["log"][-200:]
        touch(g)
        save_data(self.data)
        self.mark_dirty()
        self.amount_var.set("")
        self.note_var.set("")
        self.refresh_all()

    # ---- prix ---------------------------------------------------------------
    def record_price(self, g, price, notify_user=True):
        old = g["price"]
        today = date.today().isoformat()
        g["price"] = round(price, 2)
        g["last_check"] = now_iso()
        g["last_error"] = None
        hist = g["history"]
        if hist and hist[-1]["date"] == today:
            hist[-1]["price"] = g["price"]
        else:
            hist.append({"date": today, "price": g["price"]})
        g["history"] = hist[-365:]

        msgs = []
        if old is not None and g["price"] < old - 0.004:
            msgs.append(f"Baisse de prix : {fmt_eur(old)} → {fmt_eur(g['price'])}")
        thr = g.get("alert_below") or 0
        if thr > 0 and g["price"] <= thr and g.get("alerted_price") != g["price"]:
            msgs.append(f"Sous ton seuil de {fmt_eur(thr)}")
            g["alerted_price"] = g["price"]
        elif thr > 0 and g["price"] > thr:
            g["alerted_price"] = None
        touch(g)
        save_data(self.data)
        self.mark_dirty()

        if msgs and notify_user:
            notify(g["name"] or "Objectif Prix", "  ·  ".join(msgs))
            self.toast(f"{g['name'] or 'Objectif'} : {msgs[0]}", "good")
        if g["id"] == self.data["selected"]:
            self.refresh_all()
        else:
            self.rebuild_list()

    def is_due(self, g):
        now = datetime.now()
        last_ok, last_try = parse_dt(g["last_check"]), parse_dt(g["last_attempt"])
        if last_try and (last_ok is None or last_try > last_ok) and now - last_try < RETRY_AFTER_FAILURE:
            return False
        return last_ok is None or now - last_ok >= REFRESH_EVERY

    def auto_check(self):
        due = [g for g in self.alive() if g["url"] and self.is_due(g)]
        if due and not self.fetching:
            self.start_fetch(due, manual=False)
        self.root.after(CHECK_INTERVAL_MS, self.auto_check)

    def refresh_selected(self):
        g = self.goal
        if not g:
            return
        if not g["url"]:
            self.toast("Pas de lien pour cet objectif : utilise « Prix manuel »", "info")
            return
        self.start_fetch([g], manual=True)

    def start_fetch(self, goals, manual):
        if self.fetching:
            if manual:
                self.toast("Une mise à jour est déjà en cours…", "info")
            return
        self.fetching = True
        self.fetch_manual = manual
        self.btn_refresh.set_text("En cours…")
        jobs = [(g["id"], g["url"]) for g in goals]
        for g in goals:
            g["last_attempt"] = now_iso()
        save_data(self.data)

        def worker():
            for i, (gid, url) in enumerate(jobs):
                if i:
                    time.sleep(SPACING_BETWEEN_FETCHES)
                try:
                    price, title = fetch_price(url)
                    self.results.put(("ok", gid, price, title))
                except Exception as e:  # noqa: BLE001
                    self.results.put(("err", gid, str(e), None))
            self.results.put(("done", None, None, None))

        threading.Thread(target=worker, daemon=True).start()

    def poll_results(self):
        try:
            while True:
                kind, gid, a, b = self.results.get_nowait()
                g = next((x for x in self.data["goals"] if x["id"] == gid), None)
                if kind == "done":
                    self.fetching = False
                    self.btn_refresh.set_text("Actualiser")
                elif g is None or g.get("deleted"):
                    continue
                elif kind == "ok":
                    if not g["name"] and b:
                        g["name"] = b[:60]
                    self.record_price(g, a)
                    if self.fetch_manual and g["id"] == self.data["selected"]:
                        self.toast("Prix mis à jour", "good")
                else:
                    g["last_error"] = a
                    save_data(self.data)
                    if self.fetch_manual:
                        self.toast(a, "bad")
                    if g["id"] == self.data["selected"]:
                        self.refresh_all()
        except queue.Empty:
            pass
        self.root.after(300, self.poll_results)

    # ---- synchronisation ----------------------------------------------------
    def sync_connected(self):
        return bool(self.account.get("token") and self.account.get("gist_id"))

    def sidebar_sync_text(self):
        if not self.sync_connected():
            return "Compte  ·  non connecté"
        return "Compte  ·  " + (self.sync_text or "connecté")

    def set_sync_status(self, text, error=False):
        self.sync_text, self.sync_error = text, error
        try:
            self.sync_lbl.config(text=self.sidebar_sync_text(), fg=BAD if error else MUTED)
        except (AttributeError, tk.TclError):
            pass
        try:
            if self.account_status is not None:
                ok = (not error) and text.startswith("Synchronisé")
                self.account_status.config(text=text, fg=BAD if error else (GOOD if ok else MUTED))
        except tk.TclError:
            self.account_status = None

    def mark_dirty(self):
        """À appeler après chaque modification : envoie les changements quelques secondes plus tard."""
        if not self.sync_connected():
            return
        if self._sync_job:
            self.root.after_cancel(self._sync_job)
        self._sync_job = self.root.after(SYNC_DELAY_MS, self.start_sync)

    def periodic_sync(self):
        self.start_sync()
        self.root.after(SYNC_EVERY_MS, self.periodic_sync)

    def start_sync(self, manual=False):
        self._sync_job = None
        if not self.sync_connected():
            return
        if self.sync_busy:
            self.sync_again = True
            return
        self.sync_busy = True
        self.sync_manual = manual
        self.set_sync_status("Synchronisation…")
        token, gist_id = self.account["token"], self.account["gist_id"]

        def worker():
            try:
                self.sync_results.put(("pulled", GistClient(token).read(gist_id)))
            except Exception as e:  # noqa: BLE001
                self.sync_results.put(("error", str(e)))

        threading.Thread(target=worker, daemon=True).start()

    def poll_sync(self):
        try:
            while True:
                kind, payload = self.sync_results.get_nowait()
                try:
                    if kind == "pulled":
                        self.on_pulled(payload)
                    elif kind == "pushed":
                        self.finish_sync()
                    elif kind == "connected":
                        self.on_connected(payload)
                    elif kind == "connect_error":
                        self.set_sync_status(payload, True)
                    else:
                        self.finish_sync(payload)
                except Exception as e:  # noqa: BLE001
                    self.finish_sync(f"Erreur de synchronisation : {e}")
        except queue.Empty:
            pass
        self.root.after(300, self.poll_sync)

    def on_pulled(self, doc):
        remote = []
        for w in doc.get("goals") or []:
            try:
                remote.append(goal_from_wire(w))
            except (KeyError, TypeError, ValueError, AttributeError):
                continue
        merged = merge_goals(self.data["goals"], remote)
        if differs(merged, self.data["goals"]):
            self.data["goals"] = merged
            alive = self.alive()
            if not alive:
                self.data["selected"] = None
            elif not self.goal:
                self.data["selected"] = alive[0]["id"]
            save_data(self.data)
            self.refresh_all()

        if needs_push(merged, remote):
            payload = make_doc(merged)
            token, gist_id = self.account["token"], self.account["gist_id"]

            def worker():
                try:
                    GistClient(token).write(gist_id, payload)
                    self.sync_results.put(("pushed", None))
                except Exception as e:  # noqa: BLE001
                    self.sync_results.put(("error", str(e)))

            threading.Thread(target=worker, daemon=True).start()
        else:
            self.finish_sync()

    def finish_sync(self, error=None):
        self.sync_busy = False
        if error:
            self.set_sync_status(error, True)
            if self.sync_manual:
                self.toast(error, "bad")
        else:
            self.set_sync_status("Synchronisé à " + datetime.now().strftime("%H:%M"))
            if self.sync_manual:
                self.toast("Synchronisation terminée", "good")
        self.sync_manual = False
        if self.sync_again:
            self.sync_again = False
            self.start_sync()

    def connect_account(self, token):
        token = token.strip()
        if not token:
            self.set_sync_status("Colle d'abord ton jeton GitHub.", True)
            return
        self.set_sync_status("Connexion…")
        payload = make_doc(self.data["goals"])

        def worker():
            try:
                client = GistClient(token)
                login = client.whoami()
                gist_id = client.find_gist() or client.create(payload)
                self.sync_results.put(("connected", {"token": token, "gist_id": gist_id, "login": login}))
            except Exception as e:  # noqa: BLE001
                self.sync_results.put(("connect_error", str(e)))

        threading.Thread(target=worker, daemon=True).start()

    def on_connected(self, info):
        self.account = dict(info)
        save_account(self.account)
        self.sync_text = ""
        self.sync_error = False
        self.render_account()
        self.set_sync_status("Connecté")
        self.start_sync(manual=True)

    def disconnect_account(self):
        if not messagebox.askyesno("Se déconnecter",
                                   "Se déconnecter du compte ? Tes objectifs restent sur cet ordinateur, "
                                   "mais ne seront plus synchronisés.", parent=self.account_win or self.root):
            return
        self.account = {}
        save_account({})
        self.sync_text = ""
        self.sync_error = False
        self.sync_again = False
        self.render_account()
        self.set_sync_status("")

    def open_account(self):
        try:
            if self.account_win is not None and self.account_win.winfo_exists():
                self.account_win.lift()
                return
        except tk.TclError:
            pass
        win = tk.Toplevel(self.root)
        win.configure(bg=PANEL)
        win.title("Compte")
        win.transient(self.root)
        win.resizable(False, False)
        self.account_win = win
        self.account_body = tk.Frame(win, bg=PANEL, padx=28, pady=24)
        self.account_body.pack()
        win.bind("<Escape>", lambda e: win.destroy())
        self.render_account()

    def render_account(self):
        body = self.account_body
        try:
            if body is None or not body.winfo_exists():
                return
        except tk.TclError:
            return
        for w in body.winfo_children():
            w.destroy()

        tk.Label(body, text="Compte", bg=PANEL, fg=TEXT, font=self.f(16, True)).pack(anchor="w")
        self.account_status = tk.Label(body, text=self.sync_text, bg=PANEL, fg=BAD if self.sync_error else MUTED,
                                       font=self.f(10), wraplength=440, justify="left")

        if self.sync_connected():
            tk.Label(body, text=f"Connecté en tant que {self.account.get('login', '?')}", bg=PANEL, fg=GOOD,
                     font=self.f(12, True)).pack(anchor="w", pady=(10, 0))
            tk.Label(body, text="Tes objectifs, ton épargne et ton historique sont les mêmes sur ton ordinateur et "
                                "sur ton iPhone. Connecte l'autre appareil avec le même compte GitHub.",
                     bg=PANEL, fg=MUTED, font=self.f(10), wraplength=440, justify="left").pack(anchor="w", pady=(8, 0))
            self.account_status.pack(anchor="w", pady=(14, 0))
            row = tk.Frame(body, bg=PANEL)
            row.pack(fill="x", pady=(18, 0))
            RoundButton(row, "Synchroniser maintenant", lambda: self.start_sync(manual=True), bg=ACCENT,
                        fg=ON_ACCENT, hover=blend(ACCENT, "#FFFFFF", 0.2), w=210, h=42,
                        font=self.f(10, True), parent_bg=PANEL).pack(side="left")
            RoundButton(row, "Se déconnecter", self.disconnect_account, bg=PANEL2, fg=TEXT, hover=BORDER,
                        w=140, h=42, font=self.f(10, True), parent_bg=PANEL).pack(side="left", padx=10)
        else:
            tk.Label(body, text="Synchronise tes objectifs entre ton ordinateur et ton iPhone, avec ton compte "
                                "GitHub. Rien d'autre à créer.", bg=PANEL, fg=MUTED, font=self.f(10),
                     wraplength=440, justify="left").pack(anchor="w", pady=(8, 0))
            tk.Label(body, text="1.  Clique sur le lien : GitHub ouvre la création d'un jeton déjà réglé sur « gist ».\n"
                                "2.  Mets « No expiration » dans Expiration, puis « Generate token » en bas.\n"
                                "3.  Copie le jeton (il commence par ghp_) et colle-le ci-dessous.",
                     bg=PANEL, fg=TEXT, font=self.f(10), wraplength=440, justify="left").pack(anchor="w", pady=(14, 0))
            link = tk.Label(body, text="Créer mon jeton GitHub  ↗", bg=PANEL, fg=ACCENT, cursor="hand2",
                            font=self.f(11, True))
            link.pack(anchor="w", pady=(10, 0))
            link.bind("<Button-1>", lambda e: webbrowser.open(TOKEN_URL))

            tk.Label(body, text="JETON GITHUB", bg=PANEL, fg=MUTED, font=self.f(8, True)).pack(anchor="w", pady=(16, 4))
            token_var = tk.StringVar()
            wrap, entry = self.make_entry(body, token_var, 11, 46)
            entry.config(show="•")
            wrap.pack(fill="x")
            entry.bind("<Return>", lambda e: self.connect_account(token_var.get()))
            self.account_status.pack(anchor="w", pady=(10, 0))
            RoundButton(body, "Se connecter", lambda: self.connect_account(token_var.get()), bg=ACCENT,
                        fg=ON_ACCENT, hover=blend(ACCENT, "#FFFFFF", 0.2), w=150, h=42,
                        font=self.f(10, True), parent_bg=PANEL).pack(anchor="w", pady=(14, 0))

        tk.Label(body, text="Tes données sont stockées dans un « gist secret » de ton compte GitHub : il n'est pas "
                            "listé publiquement, mais toute personne qui aurait son lien pourrait le lire. "
                            "Il ne contient que les noms, prix et montants de tes objectifs.",
                 bg=PANEL, fg=MUTED, font=self.f(9), wraplength=440, justify="left").pack(anchor="w", pady=(18, 0))

    # ---- réglages -----------------------------------------------------------
    def open_settings(self):
        win = tk.Toplevel(self.root)
        win.configure(bg=PANEL)
        win.title("Réglages")
        win.transient(self.root)
        win.resizable(False, False)
        body = tk.Frame(win, bg=PANEL, padx=28, pady=24)
        body.pack()
        tk.Label(body, text="Réglages", bg=PANEL, fg=TEXT, font=self.f(16, True)).pack(anchor="w")
        tk.Label(body, text="Ajoute l'appli au menu de Linux Mint pour la lancer comme n'importe quel "
                            "programme, sans terminal.", bg=PANEL, fg=MUTED, font=self.f(10),
                 wraplength=420, justify="left").pack(anchor="w", pady=(8, 14))
        status = tk.Label(body, text="", bg=PANEL, fg=GOOD, font=self.f(10), wraplength=420, justify="left")
        auto_var = tk.BooleanVar(value=AUTOSTART_FILE.exists())

        def do_install():
            try:
                status.config(text=install_launcher(auto_var.get()), fg=GOOD)
            except OSError as e:
                status.config(text=f"Échec : {e}", fg=BAD)

        def toggle():
            try:
                if auto_var.get():
                    install_launcher(True)
                    status.config(text="L'appli se lancera à l'ouverture de session.", fg=GOOD)
                else:
                    remove_autostart()
                    status.config(text="Lancement automatique désactivé.", fg=GOOD)
            except OSError as e:
                status.config(text=f"Échec : {e}", fg=BAD)

        RoundButton(body, "Ajouter au menu des applications", do_install, bg=ACCENT, fg=ON_ACCENT,
                    hover=blend(ACCENT, "#FFFFFF", 0.2), w=320, h=42, font=self.f(10, True),
                    parent_bg=PANEL).pack(anchor="w")
        tk.Checkbutton(body, text="Lancer automatiquement à l'ouverture de session", variable=auto_var,
                       command=toggle, bg=PANEL, fg=TEXT, selectcolor=INPUT, activebackground=PANEL,
                       activeforeground=TEXT, font=self.f(10), highlightthickness=0, bd=0).pack(anchor="w", pady=(16, 0))
        status.pack(anchor="w", pady=(12, 0))
        tk.Label(body, text=f"Tes données : {DATA_FILE}", bg=PANEL, fg=MUTED, font=self.f(9),
                 wraplength=420, justify="left").pack(anchor="w", pady=(16, 0))
        win.bind("<Escape>", lambda e: win.destroy())


def main():
    if "--install" in sys.argv:
        print(install_launcher("--autostart" in sys.argv))
        return
    root = tk.Tk(className="Objectifprix")
    App(root, minimized="--minimized" in sys.argv)
    root.mainloop()


if __name__ == "__main__":
    main()
