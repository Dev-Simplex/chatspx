#!/usr/bin/env python3
"""Raio-X de um Pull Request antes do merge.

    scripts/ops/pr-raiox.py 93
    scripts/ops/pr-raiox.py 93 --frota      # consulta tambem as VMs (mais lento)

Responde, em 10 segundos, as perguntas que decidem se um PR pode subir:
o que o merge REALMENTE traz, o que o deploy vai exigir e onde a frota esta.

POR QUE ESTE SCRIPT EXISTE
--------------------------
Cada verificacao aqui nasceu de um incidente real, nao de teoria:

* **A lista de arquivos do GitHub mente.** O `gh pr view --json files` e o
  `git diff base...head` (TRES pontos) medem contra a merge-base. Quando a
  branch do PR nasce de outra branch de trabalho, os dois mostram so o punhado
  de arquivos do autor e escondem tudo que vem junto. Em 02/09 o PR #77
  anunciava "2 arquivos, +47/-4" e o merge arrastou 95 commits e 293 arquivos
  para 6 VMs de producao. A conta certa e `git log base..head`, com DOIS pontos.

* **Nem toda mudanca sobe igual.** Frontend exige build de assets; migration
  exige `db:migrate`; `Gemfile.lock` exige `bundle install` e deixa de ser um
  PR de feature para virar release de plataforma. Em 03/09 um PR que parecia
  comum trazia 59 gems novas, incluindo uma troca de major do Puma.

* **Merge nao e deploy.** Enquanto o codigo nao esta no disco da VM, o cliente
  continua com o defeito. O #93 ficou mergeado com a busca da Tozi vazia.

O script NAO decide por voce e nao mergeia nada: ele so mede. A leitura do
codigo, os testes e a decisao continuam sendo trabalho de gente (ou do Claude).
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys

REPO = "Dev-Simplex/chatspx"

# VMs de producao. A Tozi entra sem IP fixo de proposito: o endereco dela ja
# mudou uma vez num stop/start da AWS (nao era Elastic IP), e um script que
# afirma um IP velho e pior do que um que admite nao saber.
FROTA = [
    ("PRODUCAO", "local"),
    ("CATATAU", "3.85.130.14"),
    ("SENTINELA", "54.166.220.138"),
    ("FABRICA", "3.87.182.184"),
    ("AGN", "13.221.167.143"),
]
PEM = "/home/chatwoot/chatwoot/simplex.linux.pem"

VERDE, AMARELO, VERMELHO, AZUL, RESET = "\033[32m", "\033[33m", "\033[31m", "\033[36m", "\033[0m"


def sh(cmd: list[str], timeout: int = 60) -> str:
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.stdout.strip()
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return ""


def titulo(txt: str) -> None:
    print(f"\n{AZUL}{'━' * 72}\n {txt}\n{'━' * 72}{RESET}")


def pr_info(numero: int) -> dict:
    saida = sh([
        "gh", "pr", "view", str(numero), "--repo", REPO, "--json",
        "number,title,state,baseRefName,headRefName,mergeable,mergeStateStatus,"
        "additions,deletions,changedFiles,commits,author,url",
    ])
    if not saida:
        sys.exit(f"{VERMELHO}Nao consegui ler o PR #{numero}. O `gh` esta autenticado?{RESET}")
    return json.loads(saida)


def analisa(numero: int, checar_frota: bool) -> int:
    sh(["git", "fetch", "origin", "--prune", "-q"], timeout=120)
    pr = pr_info(numero)
    base, head = f"origin/{pr['baseRefName']}", f"origin/{pr['headRefName']}"
    alertas: list[str] = []
    bloqueios: list[str] = []

    titulo(f"PR #{pr['number']} · {pr['title'][:60]}")
    print(f"  {pr['state']} · {pr['baseRefName']} ← {pr['headRefName']} · {pr['author']['login']}")
    print(f"  {pr['mergeable']}/{pr['mergeStateStatus']} · {pr['url']}")

    # ── 1. o tamanho REAL do merge ──────────────────────────────────────────
    # O numero que o GitHub mostra e three-dot (contra a merge-base). O que
    # importa e two-dot: o que entra na base se voce mergear agora.
    titulo("1. O que o merge REALMENTE traz")
    commits_reais = sh(["git", "rev-list", "--count", f"{base}..{head}"]) or "?"
    commits_pr = len(pr["commits"])
    # Arquivo tocado pelos COMMITS do PR, e nao `diff base..head`: o diff mostra
    # tambem o que a base ganhou depois e a branch nao tem, e isso aparece como
    # "removido", o que assusta sem motivo — o merge nao apaga esses arquivos.
    tocados = sh(["git", "diff", "--name-only", f"{base}...{head}"]).splitlines()
    arquivos_reais = len([l for l in tocados if l])
    diff_bruto = len([l for l in sh(["git", "diff", "--name-only", f"{base}..{head}"]).splitlines() if l])

    print(f"  o GitHub anuncia : {commits_pr} commits, {pr['changedFiles']} arquivos (+{pr['additions']}/-{pr['deletions']})")
    print(f"  o merge traz     : {commits_reais} commits, {arquivos_reais} arquivos alterados por ele")
    if diff_bruto > arquivos_reais:
        print(f"  {AZUL}▸ o `git diff {base}..{head}` mostraria {diff_bruto} arquivos, mas {diff_bruto - arquivos_reais} "
              f"deles\n    so existem na base e a branch nunca tocou. O merge NAO os apaga.{RESET}")

    # Carona = commit que entra no merge e NAO pertence ao PR. Comparo por SHA
    # (e nao pela contagem) porque o autor pode ter feito rebase, e ai os
    # numeros batem por acaso enquanto o conteudo e outro.
    do_pr = {c["oid"][:10] for c in pr["commits"]}
    no_merge = [l for l in sh(["git", "log", "--format=%h %s", f"{base}..{head}"]).splitlines() if l]
    carona = [l for l in no_merge if l.split()[0][:10] not in do_pr]

    if carona:
        bloqueios.append(
            f"O merge traz {len(carona)} commit(s) que NAO sao deste PR. A branch saiu de outra "
            "branch de trabalho e vai arrastar carona junto. Veja a lista abaixo e decida se "
            "quer tudo isso; para levar so o do autor, use cherry-pick."
        )
        print(f"\n  {VERMELHO}▸ commits de CARONA (nao sao deste PR):{RESET}")
        for linha in carona[:8]:
            print(f"      {linha[:70]}")
        if len(carona) > 8:
            print(f"      ... e mais {len(carona) - 8}")

    # ── 2. o que o deploy vai exigir ────────────────────────────────────────
    titulo("2. O que o deploy vai exigir")
    mudou = tocados  # o que o PR toca, nao o diff bruto (ver acima)
    migrations = [f for f in mudou if f.startswith("db/migrate/")]
    frontend = [f for f in mudou if f.startswith("app/javascript/")]
    deps_ruby = [f for f in mudou if f in ("Gemfile", "Gemfile.lock")]
    deps_js = [f for f in mudou if f in ("package.json", "pnpm-lock.yaml")]

    print(f"  migrations       : {len(migrations)}" + ("  → rake db:migrate em cada VM" if migrations else ""))
    print(f"  frontend         : {len(frontend)} arquivo(s)" + ("  → BUILD DE ASSETS (~4 min) + gzip" if frontend else ""))
    print(f"  dependencia ruby : {len(deps_ruby)}" + ("  → bundle install" if deps_ruby else ""))
    print(f"  dependencia js   : {len(deps_js)}" + ("  → pnpm install" if deps_js else ""))

    for f in migrations:
        print(f"      {f.split('/')[-1]}")

    if deps_ruby:
        gems = [l for l in sh(["git", "diff", f"{base}..{head}", "--", "Gemfile.lock"]).splitlines()
                if l.startswith("+    ") and "(" in l]
        bloqueios.append(
            f"Mexe em dependencia Ruby ({len(gems)} gem(s) mudam de versao). Isso NAO e um PR de "
            "feature, e um release de plataforma: exige bundle install em cada VM e uma janela "
            "combinada. Suba numa VM primeiro e observe antes de espalhar."
        )
        for g in gems[:6]:
            print(f"      {VERMELHO}{g.strip()[:60]}{RESET}")

    if frontend:
        alertas.append(
            "Tem frontend: o deploy precisa de build de assets no checkout PRINCIPAL "
            "(dentro de worktree o pnpm entra em loop infinito) e do gzip depois, "
            "senao o nginx serve o arquivo velho."
        )
    if migrations:
        alertas.append("Tem migration: rodar db:migrate em TODAS as VMs e conferir 0 pendentes antes do restart.")

    # ── 3. onde as branches estao ───────────────────────────────────────────
    titulo("3. Onde as branches estao")
    prod, hml = sh(["git", "rev-parse", "--short=10", "origin/producao"]), sh(["git", "rev-parse", "--short=10", "origin/homologacao"])
    print(f"  producao    : {prod}")
    print(f"  homologacao : {hml}")
    if prod == hml:
        print(f"  {VERDE}as duas no mesmo commit{RESET}")
    else:
        # git cherry compara por patch-id e enxerga atraves de cherry-pick;
        # comparar por SHA da falso-negativo neste repositorio.
        so_prod = len([l for l in sh(["git", "cherry", "origin/homologacao", "origin/producao"]).splitlines() if l.startswith("+")])
        so_hml = len([l for l in sh(["git", "cherry", "origin/producao", "origin/homologacao"]).splitlines() if l.startswith("+")])
        print(f"  divergem: {so_prod} commit(s) so em producao, {so_hml} so em homologacao")
        if so_prod:
            alertas.append(
                f"{so_prod} commit(s) existem em producao e NAO na homologacao. Promover a "
                "homologacao por cima desfaria esse trabalho. Leve-os para a hml antes."
            )

    # ── 4. a frota ──────────────────────────────────────────────────────────
    if checar_frota:
        titulo("4. Onde a frota esta (o que realmente roda no cliente)")
        for nome, ip in FROTA:
            if ip == "local":
                commit = sh(["git", "rev-parse", "--short=10", "HEAD"])
            else:
                commit = sh(["ssh", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=10",
                             "-i", PEM, f"ubuntu@{ip}",
                             "sudo -n -u chatwoot bash -lc 'cd /home/chatwoot/chatwoot; git rev-parse --short=10 HEAD'"],
                            timeout=45) or "sem resposta"
            marca = VERDE if commit == prod else AMARELO
            print(f"  {nome:<11} {marca}{commit}{RESET}")
            if commit not in (prod, "sem resposta"):
                alertas.append(f"{nome} esta em {commit}, diferente de origin/producao ({prod}). "
                               "Deployar por ff pode desfazer o que so existe la — conferir antes.")
        print(f"  {'TOZI':<11} (IP muda no stop/start da AWS — conferir pelo version.json da URL)")

    # ── veredito ────────────────────────────────────────────────────────────
    titulo("VEREDITO")
    if bloqueios:
        print(f"  {VERMELHO}PARE E LEIA{RESET}")
        for b in bloqueios:
            print(f"    ▸ {b}")
    if alertas:
        print(f"  {AMARELO}ATENCAO{RESET}")
        for a in alertas:
            print(f"    ▸ {a}")
    if not bloqueios and not alertas:
        print(f"  {VERDE}Nada mecanico impede o merge.{RESET}")

    print(f"""
  {AZUL}O que este script NAO faz, e continua sendo seu trabalho:{RESET}
    · ler o codigo e entender se a solucao esta certa
    · rodar os testes e comparar com o baseline
      (o CI deste repo e vermelho por defeito: medir local)
    · depois do merge, DEPLOYAR — merge nao muda nada no cliente
""")
    return 1 if bloqueios else 0


def main() -> int:
    p = argparse.ArgumentParser(description="Raio-X de um PR antes do merge.")
    p.add_argument("pr", type=int, help="numero do PR")
    p.add_argument("--frota", action="store_true", help="consultar tambem as VMs (mais lento)")
    args = p.parse_args()
    return analisa(args.pr, args.frota)


if __name__ == "__main__":
    sys.exit(main())
