---
description: Revisa um PR, e se nada quebrar, mergeia e leva para as VMs de produção
argument-hint: <numero do PR>
allowed-tools: Bash, Read, Grep, Glob, Edit, Write
---

Você vai conduzir a promoção do **PR #$1** do repositório `Dev-Simplex/chatspx`.

**Primeira vez nesta máquina?** Rode antes:
`bash scripts/ops/setup-promover-pr.sh` — ele confere os 4 requisitos (repo, `gh`
autenticado com permissão de merge, chave SSH das VMs, e as peças do comando) e
diz exatamente o que falta. Sem o SSH dá para revisar e mergear, mas não para
deployar.

Este comando existe porque o processo tem armadilhas que já derrubaram produção
nesta semana. Siga as fases na ordem. **Não pule a fase 1**, e não trate o
resultado do script como opinião: ele mede o que o GitHub esconde.

## Fase 1 — Raio-X (obrigatória, sempre primeiro)

```bash
python3 scripts/ops/pr-raiox.py $1 --frota
```

O script responde três coisas que você **não** deve tentar responder de cabeça:

- **O que o merge realmente traz.** A lista de arquivos do GitHub mede contra a
  merge-base e esconde carona. O PR #77 anunciava 2 arquivos e arrastou 95
  commits para 6 VMs.
- **O que o deploy vai exigir.** Frontend pede build de assets, migration pede
  `db:migrate`, `Gemfile.lock` vira release de plataforma com `bundle install`.
- **Onde a frota está.** Uma VM fora do commit da branch pode ter trabalho que
  só existe nela; um fast-forward ingênuo apagaria.

Se o veredito for **PARE E LEIA**, não siga sozinho: explique ao usuário o que
foi encontrado e pergunte como proceder.

## Fase 2 — Revisão de verdade

O script não lê código. Você lê:

1. `gh pr view $1 --json body --jq .body` e o diff (`git diff <base>..<head>`).
2. Procure o que costuma quebrar: chamada em laço que vira N requisições HTTP,
   limite de API (o Vista recusa paginação acima de 50 e devolve **vazio sem
   erro**), campo que sai do strong params, `update!` em jsonb que substitui em
   vez de mesclar, mudança de conduta que afeta outro fluxo.
3. **Rode os testes dos arquivos tocados** e compare com o baseline. O CI deste
   repositório é **vermelho por defeito**: falha de teste só conta se não falhar
   também na branch base. Nunca rode dois `rspec` ao mesmo tempo (mesmo banco).

## Fase 3 — Merge

```bash
sha=$(gh pr view $1 --json headRefOid --jq .headRefOid)
gh pr merge $1 --merge --match-head-commit "$sha"
```

O `--match-head-commit` existe porque o `gh` já pegou head velho por 30 segundos
e mergeou a versão errada. Se o PR precisa ir para produção sem levar o que já
está na homologação, use cherry-pick dos commits do autor em vez do merge direto.

## Fase 4 — Deploy (merge não muda nada no cliente)

Para cada VM, na ordem: **TOZI por último não** — TOZI é cliente real e vai
primeiro só quando o usuário pedir; caso contrário comece por CATATAU.

```bash
# 1. pacote (só o que entrou, conferido pelo tamanho: 2 arquivos ≈ poucos KB)
git bundle create /tmp/rel.bundle <branch> --not <commit_anterior>

# 2. em cada VM
git checkout -- public/version.json
git fetch /tmp/rel.bundle <branch> && git merge --ff-only FETCH_HEAD
# se tiver migration:
RAILS_ENV=production bundle exec rake db:migrate
# conferir SEMPRE antes do restart:
RAILS_ENV=production bundle exec rake db:migrate:status | grep -c '^   down'

# 3. só então
sudo systemctl restart chatwoot-web.1 chatwoot-worker.1
```

Com frontend, antes do passo 2: build **no checkout principal**
(`/home/chatwoot/chatwoot`), nunca dentro de worktree, onde o `pnpm exec vite
build` entra em loop infinito. Depois do build, gerar os `.gz` (o nginx usa
`gzip_static` e o vite não gera).

## Fase 5 — Provar que funcionou

Não diga "deployado". Mostre:

- o commit em cada VM (`git rev-parse --short=10 HEAD`)
- `systemctl is-active` e o healthcheck (`curl .../api`)
- **e o comportamento**: se o PR conserta a busca, faça uma busca; se muda a
  tela, baixe o entry pela URL pública e confira o 200.

Ao final, alinhe a `homologacao` com a `producao` se elas divergirem, e diga ao
usuário o que ficou pendente.

## Regras que não se negociam

- **Restart e reboot exigem OK explícito do usuário.**
- Antes de qualquer `merge --ff-only` numa VM, confira o HEAD **real** dela: a
  branch pode estar atrás do que roda no cliente.
- `git` rodado **dentro** da VM mente sobre divergência, porque o deploy por
  refspec não atualiza `refs/remotes/origin/*`. Compare sempre de uma cópia com
  fetch recente.
