# Workflow de branches e worktrees — Chat SPX

> **Fonte da verdade** de como o trabalho flui no `chatspx`. Se uma sessão Claude (ou um dev)
> está em dúvida sobre "em que branch eu commito isto?", a resposta está aqui.
> Complementa: `AGENTS.md` (§Isolamento multi-cliente), `.claude/STATE.md` (in-flight),
> `scripts/ops/AMBIENTES.md` (mapa de deploy por cliente).

---

## TL;DR — a regra de uma linha

**A branch certa é escolhida pela PASTA que você abre, não por `git checkout` manual.**

- **Código compartilhado / plataforma** (vale pra todos os clientes) → repo principal `chatspx/`, numa **feature branch** (`feat/*`, `spx/*`). Nunca commite direto em `homologacao`/`producao`.
- **Operação de UM cliente** (conduta de IA, deploy, análise) → abra o Claude **na pasta-worktree do cliente** em `chatspx-clientes/<cliente>/` (cada uma tem `CLAUDE.local.md` fixando CLIENTE·CONTA·VM).

Abriu a pasta certa → está no lugar certo. Errar = abrir a pasta errada, não "estar na branch errada".

---

## Conceito rápido: worktree ≠ clone

Todas as worktrees do `chatspx` **compartilham o mesmo `.git`** (mesmo histórico, mesmos commits, mesmos remotes). O que muda entre pastas é só **qual branch está aberta em cada uma**. Por isso dá pra ter Tozi-produção e Tozi-homologação abertos ao mesmo tempo, em pastas separadas, sem ficar trocando de branch. Um `git fetch` numa pasta vale pra todas.

---

## Topologia de branches

| Branch | Papel | Quem commita | Onde roda |
|---|---|---|---|
| `feat/*`, `spx/*` | **Unidade de trabalho** — 1 branch por task/feature | qualquer dev | VM de teste do dev |
| `paulao` | **Branch de dev do Paulo** (VM pessoal de teste) | Paulo | VM Dev `paulao` (na frota Almirante) |
| `nicolas` | **Branch de dev do Nicolas** | Nicolas | VM Dev `nicolas` (na frota Almirante) |
| `homologacao` | **Staging** — integração antes de prod | via merge (não direto) | 1 VM `homologacao` (Proxmox) — contas 3/4/5 |
| `producao` | **Produção** — o único que **replica** pras VMs de cliente | via merge (não direto) | **5 VMs CRÍTICAS**: `producao` · `catatau` · `sentinela` · `tozi` (c6) · `fabrica` (c1/2) |
| `master` | Chatwoot upstream (open-source). **NÃO é o produto** — só a base do fork. Não tocar. | ninguém (só sync upstream) | — |

> ⚠️ **`paulao` precisa de reconciliação antes de reviver:** a branch `origin/paulao` está ancestral de `producao` (nada único), MAS a **VM `paulao` roda um commit à frente do `origin/paulao`** (trabalho off-git no box). Antes de resetar a branch, **fazer backup/push do que está na VM** — senão estranda. Ver "Reviver a branch de dev".

---

## O fluxo (dev VM → homologação → produção)

```
  feature branch (feat/*, spx/*)      ← onde o CÓDIGO é escrito, 1 por task
          │
          │  dev testa na SUA VM (branch de dev: paulao=Paulo, nicolas=Nicolas)
          ▼
     homologacao         staging (contas 3/4/5 — clientes reais leves)
          │
          │  valida em homologação
          ▼
     producao            → REPLICA pras 5 VMs de produção (catatau/sentinela/tozi/fabrica/producao)
```

**Promoção é sempre por merge + deploy gated** — nunca commit direto em `homologacao`/`producao`.

---

## Deploy: NÃO há auto-pull — é propose→approve pelo Almirante

Confirmado (08/07) via Almirante `drift_check`/`version_matrix`: **nenhuma VM faz auto-pull.** Mergear em `homologacao` **não desce nada ao vivo** — o código só entra numa VM quando um deploy é **proposto** (por você/Claude via `propose_deploy_vm`) e **aprovado por um humano** no painel (anti-self-review; a tool de `approve` nem existe pro LLM). Isso corrige a nota antiga do `AGENTS.md` que falava em "auto-pull da .232".

- **Merge** de PR = **gate humano** (irreversível; só no painel/GitHub por um humano admin). O Claude propõe e revisa, não faz self-merge.
- **Deploy/restart** = Claude `propose_deploy_vm(<vm>)` → humano aprova. Antes de restart: `migration_status` (migration pendente + restart = 500 em cadeia).

---

## Onde cada tipo de sessão trabalha

**A) Código compartilhado / plataforma** → pasta `chatspx/` (repo principal)
- Feature branch por task → merge em `homologacao` → merge em `producao`.
- Ex.: motor de rodízio, receptor de config IA, mudança em `enterprise/`, UI.

**B) Operação de um cliente** → pasta-worktree em `chatspx-clientes/`:

| Pasta | Cliente | Conta | Branch (detached) | VM |
|---|---|---|---|---|
| `chatspx-clientes/tozi-prod/` | Tozi 🔴 PROD | 6 | `producao` | `tozi` (`3.82.215.109`) |
| `chatspx-clientes/tozi-hml/` | Tozi HML | 3 | `homologacao` | `homologacao` |
| `chatspx-clientes/fabrica/` | Fábrica/Atacadão | 1/2 | base prod | `fabrica` (`3.87.182.184`) |

> **Comportamento de IA (prompt/persona/tom/conduta) NÃO é código.** Vive no **banco de cada conta**, não replica entre VMs, e se mexe via helper (`scripts/ops/<cliente>.sh`) ou Almirante (`ai_*`). Só `producao` (código) replica. Ver `AGENTS.md` §Isolamento.

> **Ler conversas / diagnosticar comportamento** = SSH no banco da VM (o Almirante **não lê conversas**). Independente da branch do worktree local — dá pra analisar a conta 6 por SSH mesmo com o worktree local desatualizado.

### Worktrees de task (efêmeras) — não confundir
`.claude/worktrees/*` (ex.: `tozi-eval`, `tozi-handoff`, `tozi-rodizio`) são worktrees **por task**, estilo Codex, isoladas pra uma feature. Descartáveis. Diferente das `chatspx-clientes/*`, que são **fixas por cliente**.

---

## Frentes de trabalho em paralelo — `chatspx-frentes/*` (criadas 29/07)

**Por que existem:** o git não permite duas worktrees na mesma branch. Enquanto todas as sessões
compartilhavam a pasta `chatspx/` (única com a `homologacao` aberta), trabalho paralelo virava
colisão — em 29/07 duas sessões commitaram na mesma worktree em 9 segundos e uma quase regrediu
o fix da outra. Uma frente = uma pasta = uma branch resolve isso na raiz.

| Pasta | Branch | Frente |
|---|---|---|
| `chatspx-frentes/rodizio/` | `spx/rodizio` | rodízio, handoff reservado, SLA, espelho do card no Vista |
| `chatspx-frentes/followup/` | `spx/followup` | follow-up, encerramento, agendamento, notificações |
| `chatspx-frentes/eval/` | `spx/eval` | Eval 2.0 (F3 outcomes, F5 golden set), sentimento, abordagem |
| `chatspx-frentes/campanhas/` | `spx/campanhas` | Meta Leads, analítico de campanha, módulo de disparo |
| `chatspx-frentes/fricoes/` | `spx/fricoes` | fricções de uso (erro de envio, lida/não-lida, chaves, link do site) |

Cada pasta tem um `CLAUDE.local.md` com o escopo da frente, as peças que já existem (pra não
reinventar) e os guard-rails. Nova frente: `git worktree add ../chatspx-frentes/<nome> -b spx/<nome> origin/homologacao`.

### Contrato das frentes
1. **Executora commita só na própria `spx/<frente>`.** Nunca em `homologacao`/`producao`.
2. **Só a sessão da pasta `chatspx/` integra** — ela é a única que mergeia, propõe deploy e fala
   com o Almirante. As frentes não pusham `homologacao`/`producao`.
3. **Fim de sessão: `git push -u origin spx/<frente>`.** Branch local-only = trabalho que vive só
   no notebook.
4. **Fecha na sessão: merge ou delete.** Branch órfã é lixo — em 29/07 havia 6 delas
   (`spx/fix-fotos-handoff*`, `tmp/f*-eval`, `worktree-tozi-eval`) cujo conteúdo já estava em
   `producao` por cherry-pick, só confundindo quem auditava.
5. **Bug de outra frente: anote e avise, não corrija.** Duas frentes no mesmo arquivo é como
   nasce o conflito de linhagem tripla.

### Se uma sessão de CLIENTE precisar mexer em código compartilhado
Não vá pra pasta `chatspx/` commitar. Use (ou crie) a worktree da frente correspondente — foi
por essa lacuna que a sessão da Fábrica commitou na worktree primária em 29/07.

---

## Regras não-negociáveis

1. **Nunca commitar direto em `producao` nem `homologacao`.** Sempre via feature branch → merge.
2. **Merge de PR e deploy são gates humanos.** O Claude propõe/revisa; humano aprova (anti-self-review).
3. **`master` não se toca** — é o upstream do Chatwoot, não o produto.
4. **Toda branch de trabalho deve estar no `origin` no fim do dia.** Branch local-only = trabalho que vive só no notebook (risco de perda total). Idem: commit no box de dev que nunca sobe pro GitHub.
5. **Antes de `restart` em prod:** `rails db:migrate:status` / Almirante `migration_status` (migration pendente + restart = 500 em cadeia).

---

## Higiene de branches

- **Fim do dia:** `git push` de toda feature branch com trabalho novo (mesmo WIP). O `origin` é o backup.
- **Feature branch mergeada:** pode deletar local + remota depois de confirmar que entrou em `homologacao`.
- **Detectar o que ficou de fora** (commits fora de prod/homolog):
  ```bash
  git rev-list --count <branch> ^origin/producao ^origin/homologacao   # >0 = tem trabalho não promovido
  git branch -r --contains <sha>                                       # vazio = commit só local
  ```

---

## Reviver a branch de dev (`paulao`) no modelo "cada dev sua VM"

A VM `paulao` existe e está viva, mas roda commit à frente do `origin/paulao` (off-git). Sequência **segura**:

1. **Backup do box primeiro:** SSH na VM `paulao`, `git push origin paulao` (ou salvar o patch de `a1ca9dd81`). Só depois de garantir que nada da VM vive só lá.
2. Resetar `paulao` sobre a base atual: `git checkout paulao && git reset --hard origin/homologacao` **(destrutivo — só com OK explícito e após o passo 1)**.
3. VM do Paulo trackeia `paulao`; dev testa lá; promove pra `homologacao` por merge/PR.
4. Espelhar o mesmo pra `nicolas`.

---

## Pendências de reconciliação (auditoria 2026-07-08)

- 🟢 **`feat/aguardando-atendimento`** — 3 commits de handoff (Paulo, 24/jun) — **pushados pro origin em 08/07** (não vive mais só no notebook).
- 🟡 **VM `paulao` à frente do `origin/paulao`** (`a1ca9dd81`) — reconciliar/pushar antes de reviver a branch.
- 🟡 **VM `homologacao` à frente do `origin/homologacao`** (commits do Nicolas no box) — reconciliar com o GitHub.
- 🟢 `origin/paulao`, `origin/nicolas`, hotfix FK CASCADE, migration do eval: já reconciliados/salvos.
