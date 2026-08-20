# BRIEFING COMPARTILHADO — Auditoria Upstream Chatwoot → ChatSPX

> **LEIA ISTO ANTES DE COMEÇAR.** Todos os workers desta auditoria compartilham este contexto.

## Regra de ouro: AUDITORIA READ-ONLY

**NÃO altere nada do código.** Proibido: `git checkout`, `git merge`, `git cherry-pick`, `git rebase`,
`git stash`, `git reset`, `git clean`, `git switch`, editar/criar/apagar arquivos fora da sua pasta de
saída, `bundle install`, `yarn install`, `rails db:migrate`, restart de serviço, deploy.

Permitido: comandos git **de leitura** (`log`, `diff`, `show`, `rev-list`, `name-only`, `shortlog`,
`blame`, `grep`), leitura de arquivos, `gh api` / `gh release`, `rg`/`grep`, e **escrever apenas o seu
relatório** dentro de `plano/auditoria-upstream-4.12.1-4.16.2/`.

O working tree tem WIP não commitado de várias pessoas. Qualquer comando que mexa no working tree
destrói trabalho alheio. Não faça.

## Contexto do fork

- Repositório: `/home/chatwoot/chatwoot` — fork **ChatSPX** do Chatwoot.
- `origin` = `github.com/Dev-Simplex/chatspx` (nosso). `upstream` = `github.com/chatwoot/chatwoot`.
- Branch atual: `homologacao` (HEAD = `ee87f5e799`).
- Nós **paramos de puxar upstream na tag `v4.12.1`** (commit `899fce1c9286b793d165c8ad6c0200ab676f185b`,
  25/03/2026). Esse é o **merge-base exato** — confirmado.

### Números do delta (já apurados, não precisa recalcular)

| Lado | Commits | Arquivos tocados |
|---|---|---|
| **Nosso** (`v4.12.1..HEAD`) | 940 | 4.736 |
| **Upstream** (`v4.12.1..v4.16.2`) | 555 | 3.605 |
| **Colisão** (arquivos tocados pelos dois) | — | **558** |

- Migrations novas do upstream no período: **45**. Nossas: **105** (risco de colisão de timestamp).
- `upstream/develop` tem **+47 commits** além de `v4.16.2` (HEAD de 03/08/2026).

### Releases upstream no intervalo

`v4.13.0` (16/04) · `v4.14.0` (18/05) · `v4.14.1` (29/05) · `v4.14.2` (10/06) · `v4.15.0` (17/06) ·
`v4.15.1` (17/06) · `v4.16.0` (18/07) · `v4.16.1` (23/07) · `v4.16.2` (27/07) · `upstream/develop` (03/08)

### Refs úteis (já disponíveis localmente — não precisa fetch)

```bash
BASE=899fce1c9286b793d165c8ad6c0200ab676f185b   # v4.12.1
git log --oneline $BASE..v4.16.2                 # o que o upstream fez
git log --oneline $BASE..HEAD                    # o que nós fizemos
git diff --stat $BASE..v4.16.2 -- <path>
git show v4.16.2:<arquivo>                       # versão upstream de um arquivo
```

Listas prontas em `/tmp/claude-1001/-home-chatwoot-chatwoot/7e50d71a-ecc8-4f66-bc53-3d4b71535101/scratchpad/`:
`ours.txt`, `theirs.txt`, `overlap.txt` (os 558 arquivos em colisão).

`gh` CLI está autenticado — use `gh api repos/chatwoot/chatwoot/releases --paginate` para as release notes.

## O que a Simplex customizou pesado (áreas sensíveis a merge)

Contexto essencial para julgar risco de conflito. Nós construímos **em cima** do Chatwoot:

- **Automações / Flows** — motor próprio (`flow_runs`, `flow_step_logs`, canvas Vue Flow). Substitui/
  coexiste com `automation_rules` (mutuamente exclusivo por conta).
- **Captain / Agentes IA** — redesign completo de front (glass/aurora), copilot streaming, tools
  built-in + custom (`captain_custom_tools`), eval, auto-closure.
- **WhatsApp** — WAHA/Evolution além do canal oficial; grupos com autor por mensagem; health service.
- **Kanban** (v2), **chat interno**, **relatórios de atribuição** — features do Nicolas.
- **Central de Ajuda** embutida em iframe (portal `embed=true`).
- **i18n pt-BR** é prioridade (não só `en`).
- **Redesign de UI** WhatsApp-fiel: `_wa-skin.scss`, scrollbars por branding, CSS vars
  `rgb(var(--solid-2))`.
- `feature_flags` bitmask **está no limite (66 features)** — feature nova estoura o bigint;
  usamos `internal_attributes`.

## O que o relatório precisa entregar

Não queremos um changelog copiado. Queremos **decisão**. Para cada item relevante:

1. **O que é** (1-2 frases, em pt-BR).
2. **Versão/PR/commit** upstream de origem.
3. **Valor para o ChatSPX**: Alto / Médio / Baixo / Nenhum — e *por quê* (nosso negócio: WhatsApp,
   IA/Captain, automações, multi-cliente).
4. **Risco de merge**: Baixo / Médio / Alto — quantos dos nossos arquivos ele toca, se bate nas áreas
   sensíveis acima.
5. **Recomendação**: `TRAZER` / `TRAZER ADAPTADO` / `AVALIAR DEPOIS` / `DESCARTAR` / `JÁ TEMOS
   (equivalente próprio)`.
6. **Esforço estimado**: P (< 1 dia) / M (1-3 dias) / G (> 3 dias).

Seja honesto quando algo que o upstream fez **nós já resolvemos melhor** — marque `JÁ TEMOS`.
E seja explícito quando algo é **obrigatório** (segurança, CVE, correção de dado, breaking change de
dependência) mesmo que não traga valor de produto.

## Formato de saída

Escreva **um único arquivo markdown** em
`plano/auditoria-upstream-4.12.1-4.16.2/<SEU-ARQUIVO>.md` (o nome exato está na sua task).

Estrutura: sumário executivo (10 linhas no máximo) → tabela de itens → detalhamento dos itens de valor
Alto/Médio → riscos e pegadinhas → o que você NÃO conseguiu apurar.

Escreva em **pt-BR**. Termos técnicos e identificadores de código no original.
Cite sempre `arquivo:linha` ou hash de commit — o coordenador vai conferir.

## Ao terminar

Envie exatamente uma vez, do seu próprio terminal:

```bash
orca orchestration send --type worker_done \
  --subject "<status curto>" \
  --body "<3 frases: o que auditou, achados principais, o que ficou de fora>" \
  --task-id <TASK_ID> --dispatch-id <DISPATCH_ID> \
  --outcome succeeded \
  --report-path "plano/auditoria-upstream-4.12.1-4.16.2/<SEU-ARQUIVO>.md" --json
```

Se travar em algo que só o coordenador resolve, use `orca orchestration ask`.
