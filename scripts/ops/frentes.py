# -*- coding: utf-8 -*-
"""Painel das frentes paralelas do chatspx.

Junta, numa tela só, o que a sessão integradora precisa saber de cada frente:
o ÚLTIMO RESULTADO que ela reportou (lido direto da transcrição em disco, sem
depender de a sessão escrever handoff nem de alguém colar no chat) e o ESTADO
DO GIT dela (commits fora da homologação, se está pushada, se está deployada).

Descobre as sessões a partir de `git worktree list`, não de uma pasta fixa:
o Orca cria worktrees em `orca/workspaces/` com branch `PauloSeze/<slug>`, e
elas ficavam invisíveis quando o painel só olhava `chatspx-frentes/`.

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
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LIMITE = int(sys.argv[1]) if len(sys.argv) > 1 else 600
BASE = "origin/homologacao"


def git(*args):
    try:
        out = subprocess.run(["git", "-C", REPO] + list(args), capture_output=True,
                             text=True, encoding="utf-8", errors="replace", timeout=60)
        return out.stdout.strip() if out.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def worktrees():
    """[(caminho, branch)] de `git worktree list`, sem a integradora."""
    saida = []
    caminho = branch = None
    for linha in git("worktree", "list", "--porcelain").splitlines():
        if linha.startswith("worktree "):
            caminho = linha[9:].strip()
        elif linha.startswith("branch "):
            branch = linha[7:].strip().replace("refs/heads/", "")
        elif not linha.strip() and caminho:
            if os.path.normpath(caminho) != os.path.normpath(REPO):
                saida.append((caminho, branch))
            caminho = branch = None
    if caminho and os.path.normpath(caminho) != os.path.normpath(REPO):
        saida.append((caminho, branch))
    return saida


def pasta_transcricao(caminho_worktree):
    """O Claude Code codifica o cwd trocando ':' e barra por '-'."""
    p = caminho_worktree.replace("\\", "/")
    return os.path.join(PROJETOS, p.replace(":", "-").replace("/", "-"))


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


def estado_git(branch):
    """Onde a branch está: fora da homologação, pushada, e já na produção."""
    if not branch:
        return "detached"
    fora = git("rev-list", "--count", "%s..%s" % (BASE, branch)) or "?"
    partes = ["%s fora da hml" % fora]
    if git("rev-parse", "--verify", "--quiet", "origin/" + branch):
        nao = git("rev-list", "--count", "origin/%s..%s" % (branch, branch)) or "0"
        partes.append("pushada" if nao == "0" else "⚠ %s NÃO pushado" % nao)
    else:
        partes.append("⚠ SEM remoto")
    if fora not in ("0", "?"):
        anc = subprocess.run(["git", "-C", REPO, "merge-base", "--is-ancestor",
                              git("rev-parse", branch), "origin/producao"], capture_output=True)
        partes.append("na produção" if anc.returncode == 0 else "não deployado")
    return " · ".join(partes)


agora = datetime.datetime.now(datetime.timezone.utc)
git("fetch", "origin", "--quiet")

for caminho, branch in sorted(worktrees(), key=lambda x: x[0]):
    nome = os.path.basename(caminho.rstrip("/\\"))
    pasta = pasta_transcricao(caminho)
    arquivos = glob.glob(os.path.join(pasta, "*.jsonl"))
    onde = "orca" if "orca" in caminho.replace("\\", "/").lower() else "local"

    print("=" * 78)
    if not arquivos:
        print("%-13s %-9s %-30s (sem sessão)" % (nome.upper(), onde, branch or "-"))
        print()
        continue

    recente = max(arquivos, key=os.path.getmtime)
    res = ultimo_texto(recente)

    # Idade pela ÚLTIMA FALA, não pelo mtime: o arquivo é tocado por atividade que não
    # produz texto, e aí uma sessão morta há dias aparecia "ATIVA".
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
    marca = "🟢 ATIVA" if idade < 0.5 else ("🟡 %.0fh" % idade if idade < 24 else "⚪ %.0fd" % (idade / 24))

    print("%-13s %-9s %-30s %s" % (nome.upper(), onde, branch or "-", marca))
    print("   %s" % estado_git(branch))
    if not res:
        print("   (sem fala do assistente)")
        print()
        continue
    texto, ts = res
    tu = ultimo_user(recente)
    aviso = "   ⏳ pediram algo depois — trabalhando ou travada" if (tu and ts and tu > ts) else ""
    print("   você: %s   ·   ela: %s%s" % (humano(tu), humano(ts), aviso))
    if LIMITE > 0:
        print("-" * 78)
        print(texto if len(texto) <= LIMITE
              else texto[:LIMITE] + "\n[... +%d chars — rode com limite maior]" % (len(texto) - LIMITE))
    print()
