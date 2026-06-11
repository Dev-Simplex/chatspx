"""Audit ALL Vue files using useMapGetter for missing template references.

Usage:
  python3 bin/check_vue_template_refs.py            # working tree (default, dev/CI)
  python3 bin/check_vue_template_refs.py --staged   # staged content (pre-commit hook)
"""
import re, subprocess, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
USE_STAGED = '--staged' in sys.argv

# Get all vue files that use useMapGetter
result = subprocess.run(['grep','-rl','useMapGetter', str(ROOT/'app/javascript/dashboard'), '--include=*.vue'], capture_output=True, text=True)
files = [Path(p).relative_to(ROOT) for p in result.stdout.strip().splitlines()]

VUE_BUILTINS = {"$t","$tc","$te","$d","$n","$emit","$slots","$attrs","$refs","$el","$nextTick","true","false","null","undefined","this","Math","Object","Array","String","Number","Boolean","JSON","Date","Promise","window","document","console","parseInt","parseFloat","encodeURIComponent","decodeURIComponent","decodeURI","encodeURI","setTimeout","clearTimeout","setInterval","clearInterval","isNaN","isFinite"}
CSS_FN = {"clamp","var","calc","rgb","rgba","hsl","hsla","translateX","translateY","translateZ","translate","rotate","scale","skew","bezier","cubic-bezier","not","is","where","has","min","max","minmax","repeat","fit-content","attr","url"}

def get_committed(p):
    """Read file content. Default: working tree. With --staged: git index."""
    if USE_STAGED:
        r = subprocess.run(['git','-C',str(ROOT),'show', f':{p}'], capture_output=True, text=True)
        if r.returncode == 0 and r.stdout:
            return r.stdout
    full = ROOT / p
    try:
        return full.read_text(encoding='utf-8')
    except Exception:
        return None

def declared_names(s):
    names = set()
    for m in re.finditer(r"\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\b", s): names.add(m.group(1))
    for m in re.finditer(r"\b(?:const|let|var)\s*\{([^}]*)\}\s*=", s):
        for piece in m.group(1).split(','):
            piece = piece.strip()
            if not piece: continue
            if ':' in piece: piece = piece.split(':',1)[1].strip()
            piece = piece.split('=')[0].strip()
            piece = re.sub(r'[^\w$]', '', piece)
            if piece: names.add(piece)
    for m in re.finditer(r"\bfunction\s+([A-Za-z_$][\w$]*)\s*\(", s): names.add(m.group(1))
    for m in re.finditer(r"\bimport\s+([A-Za-z_$][\w$]*)\s+from", s): names.add(m.group(1))
    for m in re.finditer(r"\bimport\s+\{([^}]*)\}\s+from", s):
        for piece in m.group(1).split(','):
            piece = piece.strip()
            if ' as ' in piece: piece = piece.split(' as ')[1].strip()
            piece = re.sub(r'[^\w$]', '', piece)
            if piece: names.add(piece)
    return names

problems = []
for f in sorted(files, key=str):
    f = str(f)
    content = get_committed(f)
    if not content: continue
    scripts = re.findall(r"<script\b[^>]*>([\s\S]*?)</script>", content, re.IGNORECASE)
    templates = re.findall(r"<template\b[^>]*>([\s\S]*?)</template>", content, re.IGNORECASE)
    if not templates: continue
    script = "\n".join(scripts)
    t = re.sub(r"<!--[\s\S]*?-->", "", "\n".join(templates))
    dec = declared_names(script)
    aliases = set()
    for m in re.finditer(r'v-for\s*=\s*"\s*\(?\s*([A-Za-z_$][\w$]*)(?:\s*,\s*([A-Za-z_$][\w$]*))?(?:\s*,\s*([A-Za-z_$][\w$]*))?\s*\)?\s+(?:in|of)\b', t):
        for g in m.groups():
            if g: aliases.add(g)
    for m in re.finditer(r'(?:v-slot(?::[a-zA-Z-]+)?|#[a-zA-Z-]+)\s*=\s*"\s*\{?([^}"]+)\}?"', t):
        for piece in m.group(1).split(','):
            piece = piece.strip()
            if ':' in piece: piece = piece.split(':',1)[1].strip()
            piece = re.sub(r'[^\w$]', '', piece)
            if piece: aliases.add(piece)
    exprs = []
    for m in re.finditer(r"\{\{([\s\S]*?)\}\}", t): exprs.append(m.group(1))
    for m in re.finditer(r'(?:[:@]|v-[a-zA-Z-]+(?::[a-zA-Z-]+)?)[\w.\-:]*\s*=\s*"([^"]*)"', t):
        exprs.append(m.group(1))
    for m in re.finditer(r"(?:[:@]|v-[a-zA-Z-]+(?::[a-zA-Z-]+)?)[\w.\-:]*\s*=\s*'([^']*)'", t):
        exprs.append(m.group(1))
    suspicious = []
    for e in exprs:
        if re.search(r'\[(?:\w+:)?[^\]]*\b(clamp|calc|var|rgba?|hsla?|translate[XYZ]?|rotate|scale|skew|bezier|cubic-bezier|not|is|where|has|min|max|minmax|repeat|fit-content|attr|url)\s*\(', e):
            continue
        e_stripped = re.sub(r"'[^']*'", "''", e)
        e_stripped = re.sub(r'"[^"]*"', '""', e_stripped)
        for m in re.finditer(r"(?<![\w.$])([A-Za-z_$][\w$]*)\s*\(", e_stripped):
            cid = m.group(1)
            if cid in dec or cid in aliases or cid in VUE_BUILTINS or cid in CSS_FN: continue
            if re.search(r"\b" + re.escape(cid) + r"\b", script): continue
            if cid == 'in': continue
            suspicious.append((cid, e.strip()[:140]))
    if suspicious:
        problems.append((f, suspicious))

mode = 'staged' if USE_STAGED else 'working tree'
print(f"[check_vue_template_refs] mode={mode} checked={len(files)} files problems={len(problems)}\n")
for f, sus in problems:
    print(f"=== {f}")
    seen = set()
    for cid, expr in sus:
        if (cid, expr) in seen: continue
        seen.add((cid, expr))
        print(f"  call: {cid}(...)    in: {expr}")
    print()
sys.exit(1 if problems else 0)
