# -*- coding: utf-8 -*-
"""Painel das frentes paralelas do chatspx.

Junta, numa tela só, o que a sessão integradora precisa saber de cada frente:
o ÚLTIMO RESULTADO que ela reportou (lido direto da transcrição em disco, sem
depender de a sessão escrever handoff nem de alguém colar no chat) e o ESTADO
DO GIT dela (commits fora da homologação, se está pushada, se está deployada).

Por que ler a transcrição: a convenção `docs/handoffs/spx-<frente>.md` existe
mas só metade das frentes adota, e handoff é escrito no fim — some quando a
sessão morre no meio. A transcrição está sempre lá.

Uso:
    python scripts/ops/frentes.py           # resumo (600 chars por frente)
    python scripts/ops/frentes.py 4000      # relato longo
    python scripts/ops/frentes.py 0         # só o cabeçalho git, sem texto
"""
import datetime
import glob
import json
import os
import subprocess
import sys

# Windows entrega stdout em cp1252 e engasga em "→", "·" e acento. Forçar UTF-8.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PROJETOS = os.path.join(os.path.expanduser("~"), ".claude", "projects")
PREFIXO = "C--Users-paulo-Workspaces-chatspx-frentes-"
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LIMITE = int(sys.argv[1]) if len(sys.argv) > 1 else 600


def git(*args):
    try:
        out = subprocess.run(["git", "-C", REPO] + list(args), capture_output=True,
                             text=True, encoding="utf-8", errors="replace", timeout=30)
        return out.stdout.strip() if out.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def ultimo_user(caminho):
    """Timestamp da última mensagem do PAULO. Distingue 'a sessão está pensando'
    de 'ninguém falou com ela' — sem isso o painel já me fez concluir errado."""
    ts = None
    with open(caminho, "r", encoding="utf-8", errors="replace") as fh:
        for linha in fh:
            if '"user"' not in linha:
                continue
            try:
                obj = json.loads(linha)
            except json.JSONDecodeError:
                continue
            if obj.get("type") == "user" and obj.get("timestamp"):
                ts = obj["timestamp"]
    return ts


def ultimo_texto(caminho):
    """(texto, timestamp) da última fala do assistente que tem texto de verdade."""
    ultimo = None
    with open(caminho, "r", encoding="utf-8", errors="replace") as fh:
        for linha in fh:
            if '"assistant"' not in linha:
                continue
            try:
                obj = json.loads(linha)
            except json.JSONDecodeError:
                continue
            if obj.get("type") != "assistant":
                continue
            conteudo = (obj.get("message") or {}).get("content")
            if isinstance(conteudo, str):
                partes = [conteudo]
            elif isinstance(conteudo, list):
                partes = [b.get("text", "") for b in conteudo
                          if isinstance(b, dict) and b.get("type") == "text"]
            else:
                partes = []
            texto = "\n".join(p for p in partes if p.strip()).strip()
            if texto:
                ultimo = (texto, obj.get("timestamp", ""))
    return ultimo


def humano(ts):
    if not ts:
        return "?"
    try:
        dt = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))
        return dt.astimezone(datetime.timezone(datetime.timedelta(hours=-4))).strftime("%d/%m %H:%M")
    except (ValueError, TypeError):
        return ts[:16]


def estado_git(frente):
    """Onde a frente está em relação à homologação, ao origin e ao que está no ar."""
    br = "spx/" + frente
    if not git("rev-parse", "--verify", "--quiet", br):
        return "branch não existe localmente"
    fora = git("rev-list", "--count", "origin/homologacao.." + br) or "?"
    naop = git("rev-list", "--count", "origin/" + br + ".." + br) or "0"
    partes = ["%s commits fora da homologação" % fora]
    if naop != "0":
        partes.append("⚠ %s NÃO pushado" % naop)
    else:
        partes.append("pushado")
    # deployado = ancestral do que a produção aponta
    if fora != "0" and fora != "?":
        head = git("rev-parse", br)
        anc = subprocess.run(["git", "-C", REPO, "merge-base", "--is-ancestor", head, "origin/producao"],
                             capture_output=True)
        partes.append("na produção" if anc.returncode == 0 else "não deployado")
    return " · ".join(partes)


agora = datetime.datetime.now(datetime.timezone.utc)
git("fetch", "origin", "--quiet")

for pasta in sorted(glob.glob(os.path.join(PROJETOS, PREFIXO + "*"))):
    frente = os.path.basename(pasta)[len(PREFIXO):]
    arquivos = glob.glob(os.path.join(pasta, "*.jsonl"))
    if not arquivos:
        continue
    recente = max(arquivos, key=os.path.getmtime)
    res = ultimo_texto(recente)

    # Idade pela ÚLTIMA FALA, não pelo mtime: o arquivo é tocado por atividade que não
    # produz texto (tool call, retomada), e aí uma sessão morta há dias aparecia "ATIVA".
    idade = None
    if res and res[1]:
        try:
            ult = datetime.datetime.fromisoformat(res[1].replace("Z", "+00:00"))
            idade = (agora - ult).total_seconds() / 3600.0
        except (ValueError, TypeError):
            idade = None
    if idade is None:
        idade = (agora - datetime.datetime.fromtimestamp(
            os.path.getmtime(recente), datetime.timezone.utc)).total_seconds() / 3600.0
    marca = "🟢 ATIVA" if idade < 0.5 else ("🟡 %.0fh parada" % idade if idade < 24
                                            else "⚪ %.0fd parada" % (idade / 24))

    print("=" * 78)
    print("%-11s %-14s %s" % (frente.upper(), marca, estado_git(frente)))
    if not res:
        print("  (sem fala do assistente nesta sessão)")
        print()
        continue
    texto, ts = res
    tu = ultimo_user(recente)
    aviso = ""
    if tu and ts and tu > ts:
        aviso = "   ⏳ pediram algo depois — sessão trabalhando ou travada"
    print("você falou: %s   ·   relato dela: %s%s" % (humano(tu), humano(ts), aviso))
    if LIMITE > 0:
        print("-" * 78)
        print(texto if len(texto) <= LIMITE
              else texto[:LIMITE] + "\n[... +%d chars — rode com limite maior]" % (len(texto) - LIMITE))
    print()
