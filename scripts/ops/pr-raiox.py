#!/usr/bin/env python3
"""Raio-X de um Pull Request antes do merge.

    scripts/ops/pr-raiox.py 93
    scripts/ops/pr-raiox.py 93 --frota      # consulta tambem as VMs (mais lento)
    scripts/ops/pr-raiox.py 93 hotfix       # algo quebrou em producao (ou --hotfix)

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
import os
import re
import shlex
import subprocess
import sys

REPO = "Dev-Simplex/chatspx"

# VMs de producao. O IP da TOZI ja mudou uma vez num stop/start da AWS (a
# instancia nao tem Elastic IP): se um dia der "sem resposta" aqui, o endereco
# provavelmente trocou de novo — confira no console EC2 antes de concluir que a
# maquina caiu, e atualize esta linha.
# PRODUCAO tem endereco proprio de proposito. Antes ela era "local", o que
# equivalia a dizer "a maquina onde este script esta rodando" — verdade na .229,
# que E a producao, e mentira em qualquer outra. Rodado da VM do dev, o raio-X
# mostrava o checkout DELE na linha PRODUCAO, ou seja, respondia sobre a maquina
# errada com toda a confianca do mundo. Medido em 08/09/2026.
FROTA = [
    ("PRODUCAO", "192.168.8.229"),
    ("TOZI", "3.94.9.51"),
    ("CATATAU", "3.85.130.14"),
    ("SENTINELA", "54.166.220.138"),
    ("FABRICA", "3.87.182.184"),
    ("AGN", "13.221.167.143"),
    # Cliente novo desde 10/09/2026. Ficou fora desta tabela no primeiro dia e, por isso, fora de
    # quatro deploys seguidos: quem conferia a frota por aqui nem sabia que ela existia.
    ("CDSOLAR", "13.218.193.75"),
    # Mesma historia da CDSOLAR, e pior: ficou fora de SEIS lotes (de 29 a 30/09/2026) porque nao
    # estava nem aqui, nem no deployment/deploy.sh, nem no panel. Foi descoberta em 30/09 porque o
    # dono perguntou por ela pelo dominio (rocketstudio.chatspx.app).
    ("ROCKET", "2.25.195.47"),
]
# A ROCKET e a unica fora da AWS: roda na Hostinger e o login dela e `root`, nao `ubuntu`. A chave
# e a MESMA da frota. Quem nao esta aqui entra como ubuntu.
USUARIO_SSH = {"ROCKET": "root"}
# Homologacao e VMs dos devs (fase 6 do /promover-pr). Aqui a branch de cada VM
# NAO e a `producao`, e nada chega nelas sozinho: nao existe auto-pull. Em
# 18/09/2026 os 6 PRs do dia entraram pela `homologacao` e a .232 ficou 52
# commits atras. Nas VMs dos devs o criterio e "contem o commit", nao "mesmo
# commit": elas tem trabalho do dev por cima. A VM do Walisson (.46) fica fora a
# pedido dele. Desde 13/10/2026 os devs dividem uma VM so, a .98, na branch
# `desenvolvimento`.
VMS_FASE6 = [
    ("HOMOLOGACAO", "192.168.8.232", "homologacao"),
    ("DEV", "192.168.8.98", "desenvolvimento"),
]
# A chave e procurada em tres lugares, nesta ordem. O motivo esta na regra do
# OpenSSH: ele recusa chave privada com bit de grupo ou de outros QUANDO o dono do
# arquivo e o usuario que roda ("bad permissions / This private key will be
# ignored"), e nao aplica a checagem quando o arquivo e de outro dono.
#
# Na VM do Nicolas o arquivo do repo e 640 do usuario `chatwoot`, com o grupo
# `chatwoot` (do qual `nicolas` participa). Isso funciona para o `nicolas`, que nao
# e o dono, e FALHA para o `chatwoot`, que e. Em 04/09/2026 esse detalhe fez este
# script reportar as 5 VMs remotas como "sem resposta" durante uma promocao — a
# frota estava inteira no ar, quem nao conectava era a chave.
#
# Apertar o arquivo compartilhado para 600 conserta um usuario e quebra o outro.
# Por isso: cada um tem a SUA copia privada em ~/.ssh/simplex.linux.pem (600), e o
# arquivo compartilhado continua valendo para quem nao e dono dele.
def _enderecos_desta_maquina() -> set:
    """Os IPs desta maquina, para saber qual linha da FROTA e o proprio checkout.

    Existe porque a alternativa (marcar uma linha como "local") transforma o
    relatorio em algo que depende de onde ele foi rodado, e a linha PRODUCAO
    passa a apontar para quem perguntou.
    """
    saida = sh(["hostname", "-I"], timeout=10)
    return {ip for ip in saida.split() if ip}


def _pem() -> str:
    do_ambiente = os.environ.get("TOZI_PEM")
    if do_ambiente:
        return do_ambiente

    privada = os.path.expanduser("~/.ssh/simplex.linux.pem")
    if os.path.exists(privada):
        return privada

    return "/home/chatwoot/chatwoot/simplex.linux.pem"


PEM = _pem()

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


def analisa(numero: int, checar_frota: bool, hotfix: bool = False) -> int:
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
        aqui = _enderecos_desta_maquina()
        # Desde 18/09/2026 o restart e do timer das 20:00 de Cuiaba
        # (deployment/chatwoot-restart-noturno.*): o commit no disco ja nao diz o
        # que o cliente ve. Por isso o mesmo SSH traz tambem se os servicos servem o
        # disco, o estado do timer e a ultima linha do log dele. "Serve o disco" e a
        # regua do chatwoot-restart-noturno.sh: todo chatwoot-web* e chatwoot-worker*
        # ativo subiu depois da ultima vez que a branch andou. Vale o mais antigo,
        # porque o web pode ter caido e subido sozinho de dia com os workers ainda no
        # codigo velho. Com varios units o `systemctl show --value` separa os valores
        # por linha em branco, dai o `awk NF`. O local tambem le o
        # /home/chatwoot/chatwoot: rodado de um worktree, o HEAD do diretorio atual e
        # o do worktree, nao o que o web serve.
        cmd = ("cd /home/chatwoot/chatwoot || exit 1; b=$(git rev-parse --abbrev-ref HEAD); "
               "printf '%s|%s|%s|%s|%s|%s\\n' \"$(git rev-parse --short=10 HEAD)\" "
               "\"$(git reflog -1 --date=unix --format=%gd \"$b\")\" "
               "\"$(systemctl list-units --type=service --state=active --no-legend --plain 'chatwoot-web*' "
               "'chatwoot-worker*' | awk '{print $1}' | xargs -r systemctl show -p ActiveEnterTimestamp --value "
               "--timestamp=unix | tr -d @ | awk NF | sort -n | head -n1)\" "
               "\"$(systemctl show chatwoot-restart-noturno.timer -p LoadState --value)\" "
               "\"$(systemctl is-active chatwoot-restart-noturno.timer)\" "
               "\"$(tail -n1 log/restart-noturno.log 2>/dev/null)\"")
        for nome, ip in FROTA:
            if ip in aqui:
                saida, falha = sh(["bash", "-c", cmd]), "sem resposta"
            elif nome == "PRODUCAO":
                # A .229 nao usa a chave da AWS (o acesso dela e por senha), entao de
                # fora ela so responde se a maquina de onde voce roda ja tiver chave
                # publica autorizada la. Quando nao tem, dizer "nao medida" e melhor
                # do que herdar o HEAD local e chamar isso de producao.
                saida = sh(["ssh", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=8",
                            "-o", "BatchMode=yes", f"chatwoot@{ip}", cmd], timeout=30)
                falha = "nao medida daqui"
            else:
                saida = sh(["ssh", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=10",
                            "-i", PEM, f"{USUARIO_SSH.get(nome, 'ubuntu')}@{ip}",
                            f"sudo -n -u chatwoot bash -lc {shlex.quote(cmd)}"],
                           timeout=45)
                falha = "sem resposta"
            partes = saida.splitlines()[-1].split("|") if saida else []
            if len(partes) != 6 or not partes[0]:
                commit, extra = falha, ""
            else:
                commit, branch_andou, mais_antigo, timer_load, timer_ativo, ultima = partes
                andou, subiu = re.search(r"@\{(\d+)\}", branch_andou), re.search(r"(\d+)", mais_antigo)
                timer = "ativo" if timer_ativo == "active" else "ausente" if timer_load == "not-found" else "inativo"
                if not (andou and subiu):
                    serve = "?"
                elif int(subiu.group(1)) >= int(andou.group(1)):
                    serve = "sim"
                else:
                    serve = "nao (carrega as 20:00)" if timer == "ativo" else "nao (so com restart)"
                extra = f"  serve o disco: {serve} · timer: {timer}"
                noite = ultima.split()
                if len(noite) >= 2:
                    extra += f" · ultima noite: {noite[1]} em {noite[0][:10]}"
            marca = VERDE if commit == prod else AMARELO
            print(f"  {nome:<11} {marca}{commit}{RESET}{extra}")
            if commit == "nao medida daqui":
                alertas.append(f"{nome} ({ip}) nao respondeu desta maquina: o numero dela NAO esta "
                               "nesta tabela. Meca de la antes de concluir que a frota esta alinhada.")
            elif commit not in (prod, "sem resposta"):
                alertas.append(f"{nome} esta em {commit}, diferente de origin/producao ({prod}). "
                               "Deployar por ff pode desfazer o que so existe la — conferir antes.")

        # ── 5. homologacao e VMs dos devs ───────────────────────────────────
        # So leitura: nada de fetch, e --no-optional-locks no status para nao
        # disputar o index.lock com o dev que esta trabalhando ali. Se o objeto
        # do commit nem existe na VM, o HEAD dela nao pode conte-lo: da NAO sem
        # precisar de fetch. O public/version.json e reescrito a cada deploy e
        # nao e trabalho de ninguem, por isso nao conta como arquivo em edicao.
        titulo("5. Homologacao e VMs dos devs")
        sha = sh(["git", "rev-parse", "origin/producao"])
        cmd = ("cd /home/chatwoot/chatwoot || exit 1; "
               f"if git cat-file -e '{sha}^{{commit}}' 2>/dev/null && git merge-base --is-ancestor {sha} HEAD; "
               "then c=sim; else c=nao; fi; "
               "e=$(git --no-optional-locks status --porcelain --untracked-files=no | grep -cv ' public/version.json$'); "
               "echo $(git rev-parse --abbrev-ref HEAD) $(git rev-parse --short=10 HEAD) $c $e "
               "$(git rev-list --count HEAD --not --remotes)")
        atrasadas = []
        for nome, ip, branch in VMS_FASE6:
            if ip in aqui:
                saida = sh(["bash", "-c", cmd], timeout=30)
            else:
                saida = sh(["ssh", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=8",
                            "-o", "BatchMode=yes", f"chatwoot@{ip}", cmd], timeout=30)
            campos = saida.split()
            if len(campos) != 5:
                print(f"  {nome:<11} {AMARELO}nao medida daqui{RESET}")
                continue
            atual, head_vm, contem, editados, so_disco = campos
            if contem == "sim":
                marca, falta = VERDE, "em dia"
            else:
                atrasadas.append(nome)
                marca = AMARELO
                if editados != "0":
                    falta = f"BLOQUEADA: {editados} arquivo(s) em edicao"
                elif nome == "HOMOLOGACAO":
                    falta = "atras: ff para o mesmo commit"
                else:
                    falta = "atras: merge da producao"
            onde = atual if atual == branch else f"{atual} (esperada: {branch})"
            print(f"  {nome:<11} {marca}{head_vm}{RESET}  {onde} · {falta}")
            if so_disco != "0":
                alertas.append(f"{nome} tem {so_disco} commit(s) que so existem no disco dela, nenhum remote "
                               "tem. Backup antes de mexer (fase 6).")
        if atrasadas:
            alertas.append(f"Homologacao/devs atras: {', '.join(atrasadas)}. "
                           "A fase 6 do /promover-pr oferece alinhar.")

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
    if hotfix:
        print(f"  {AMARELO}HOTFIX{RESET}: restart na hora so nas VMs quebradas; o resto carrega as 20:00.")

    print(f"""
  {AZUL}O que este script NAO faz, e continua sendo seu trabalho:{RESET}
    · ler o codigo e entender se a solucao esta certa
    · rodar os testes e comparar com o baseline
      (o CI deste repo e vermelho por defeito: medir local)
    · depois do merge, DEPLOYAR — merge nao muda nada no cliente
""")
    return 1 if bloqueios else 0


def main() -> int:
    p = argparse.ArgumentParser(description="Raio-X de um ou mais PRs antes do merge.")
    p.add_argument("prs", nargs="+", help="numero(s) do(s) PR(s); a palavra hotfix pode vir junto")
    p.add_argument("--frota", action="store_true", help="consultar tambem as VMs (mais lento)")
    p.add_argument("--hotfix", action="store_true", help="algo quebrou em producao: restart na hora nas VMs quebradas")
    # O /promover-pr repassa o $ARGUMENTS inteiro (ex.: "190 hotfix --frota"), entao a palavra
    # hotfix chega misturada aos numeros; parse_intermixed_args aceita as opcoes em qualquer ordem.
    args = p.parse_intermixed_args()
    hotfix = args.hotfix or any(a.lower() == "hotfix" for a in args.prs)
    prs = [a for a in args.prs if a.lower() != "hotfix"]
    invalidos = [a for a in prs if not a.isdigit()]
    if invalidos:
        p.error(f"{', '.join(invalidos)}: nao e numero de PR nem 'hotfix'")
    if not prs:
        p.error("informe ao menos um numero de PR")
    args.prs = [int(a) for a in prs]

    # Com varios PRs, a frota e as branches sao as MESMAS para todos: consultar
    # uma vez por PR seria N vezes o mesmo SSH. Entao so o ultimo consulta.
    problemas = 0
    for i, numero in enumerate(args.prs):
        ultimo = i == len(args.prs) - 1
        problemas += analisa(numero, args.frota and ultimo, hotfix and ultimo)

    if len(args.prs) > 1:
        titulo(f"LOTE DE {len(args.prs)} PRs")
        print(f"  {len(args.prs) - problemas} sem bloqueio · {problemas} com bloqueio\n")
        print(f"  {AZUL}Subindo em lote, faca UM deploy so no fim, nao um por PR:{RESET}")
        print("    · mergeie todos, na ordem em que forem aprovados")
        print("    · promova a branch UMA vez")
        print("    · um unico bundle, um unico restart por VM")
        print("  Menos janela de instabilidade e menos chance de deixar VM para tras.\n")
    return 1 if problemas else 0


if __name__ == "__main__":
    sys.exit(main())
