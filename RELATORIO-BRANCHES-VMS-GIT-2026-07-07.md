# Relatório de estado — branches × VMs × git

> **Data:** 2026-07-07 · **Gerado para:** análise do dev · **Repo:** `Dev-Simplex/chatspx`
> Snapshot do que está **no GitHub** vs. o que está **rodando em cada VM** (HEADs verificados ao vivo por SSH). Fotografia de um momento — reconfirme os HEADs antes de agir.
>
> ⚠️ Não confundir com `docs/clientes/tozi/RELATORIO-ESTADO-DEPLOY-2026-07-07.md`, que trata dos **3 fixes de código da Clara** (conv 18876). Este aqui é o **panorama de branches/VMs/git**.

---

## 0. Contexto de topologia (ler primeiro)

O `chatspx` é **um fork único do Chatwoot** que serve vários clientes como **contas (tenants)** na mesma base de código.

- Só o **CÓDIGO** (branch `producao`) replica pras VMs.
- O **COMPORTAMENTO de cada IA** (prompt, persona, tom, modelo LLM) vive no **BANCO de cada conta** — **não** está no git e **não** replica.
- "Homologação"/"produção" são **por cliente** — cada um tem sua VM.

| Cliente | Ambiente | Host / VM | Conta(s) | Branch que serve |
|---|---|---|---|---|
| Tozi | 🔴 Produção (cliente real) | `3.82.215.109` (AWS) | **6** | `producao` |
| Tozi | Homologação (sandbox) | `192.168.8.232` (LAN) | **3** | `homologacao` (auto-pull) |
| Fábrica / Atacadão | Box único (greenfield) | `3.87.182.184` (AWS) | **1**·**2** | `producao` |

---

## 1. O que cada VM realmente roda (git HEAD ao vivo)

| VM / Cliente | Conta | Branch | HEAD rodando | Situação |
|---|---|---|---|---|
| **Tozi PROD** `3.82.215.109` | 6 | `producao` | `2fa8d9eb6` | ✅ No tip de `origin/producao` · sem migration pendente |
| **Tozi HML** `192.168.8.232` | 3 | `homologacao` | `af53584c2` | ✅ Contém os 8 commits de comportamento · reiniciada (código ativo) · sem migration pendente · ⚠️ **5 commits off-git** (ver §4) |
| **Fábrica/Atacadão** `3.87.182.184` | 1·2 | `producao` | `c8f3dc803` | ⚠️ **Off-git** — 176 commits locais nunca empurrados; **não contém** o tip atual de `producao` |

**Como foi verificado:** SSH via helpers em `scripts/ops/` (`tozi-prod.sh`, `tozi-hml.sh`, `fabrica.sh`) rodando `git rev-parse` / `git log` / `git merge-base` / `db:migrate:status` / `systemctl show`. Comandos exatos no Anexo A.

---

## 2. Estado do git na nuvem (GitHub `origin`)

```
origin/producao    @ 2fa8d9eb6   ← Tozi PROD está exatamente aqui ✅
origin/homologacao @ 1f59794f7   ← 8 commits À FRENTE de producao (só comportamento IA da Tozi)
```

### 2.1. `origin/homologacao` tem 8 commits que `producao` NÃO tem

Todos são melhorias de comportamento da IA (Clara/Tozi). Já estão rodando na **HML** (§4), mas **ainda não subiram pra produção da Tozi (conta 6)**:

| Hash | Descrição |
|---|---|
| `1f59794f7` | injeta o horário de funcionamento do config no prompt |
| `6c4e0da01` | trava link de imóvel — só URL que a busca retornou |
| `475457363` | busca amplia o tipo dentro do bairro pedido em vez de cair no fallback |
| `18b1b0a45` | pausa do almoço não é "fechado" — injeta quando o atendimento reabre |
| `3dfe14927` | nunca envia o literal `[IGNORAR]` ao cliente |
| `872441878` | follow-up cala quando cliente deferiu e nunca repete a cutucada |
| `b6fd1e87a` | trava foto ao código buscado (impede envio de imóvel errado) |
| `3f95174a3` | buscar_imovel mostra características e filtra por piscina |

> ⚠️ `1f59794f7` mexe no **molde compartilhado** (`assistant.liquid` / `runtime_context.liquid`) + `agentable` → exige **restart do worker** pra carregar. Na `.232` já foi reiniciado (§4); numa eventual subida pra `producao` isso vale pra `.109`.

### 2.2. `origin/producao` tem 14 commits que `homologacao` não tem

Contexto (não é regressão): merges `homologacao→producao` já feitos + hotfixes/reverts aplicados direto em `producao`. Destaques:

```
2fa8d9eb6 revert(nps): cooldown volta a contar so NPS respondido (revert de c4abdcd54e)
68a234cfb fix(setup): set_env nao corrompe mais valores com @
1d3607f2e fix(ui): timestamp compacto no card de conversa
d3509f0e8 fix(i18n): resolve colisao da chave ONBOARDING
390403c50..917c5cff1  (7x) merge: homologacao -> producao
667dbeebb merge: reconcilia linha 9c9a (endpoint ai_config #assistants + fix forward-dup)
```

---

## 3. Branch de feature atual + trabalho não-commitado (máquina do Paulo)

**`feat/ai-config-receptor`** (`dbd74af90`) — branch parqueada, **131 commits atrás** de `homologacao`. Tem 6 commits fora de `producao`:

```
dbd74af90 feat(tozi): gazetteer de Sinop pra IA conhecer a cidade
4f1fccae2 chore(estrutura): separa docs, scripts e deploy por cliente
e68a5c715 feat(ai-config): receptor de change-sets de comportamento das IAs (v1)
21929abe9 feat(campanhas): API do ciclo de disparo + guarda de atendimento ativo (Fase 2a)
0967e95c3 feat(campanhas): engine de disparo WhatsApp replicável (Fase 0 — backend)
e9cf79754 feat(campanhas): botao 'Criar campanha' WhatsApp de volta
```

⚠️ **Trabalho recente que existe SÓ no disco local (não commitado, não pushado, não em VM):**

- **Eval nativo completo:** `enterprise/app/models/captain/conversation_eval.rb`, `.../jobs/captain/conversation_eval_job.rb` + `..._scheduler_job.rb`, `enterprise/lib/captain/conversation_eval_service.rb` + `conversation_eval_schema.rb` + `prompts/conversation_eval.liquid`, migration `db/migrate/20260702180000_create_captain_conversation_evals.rb`, `lib/tasks/spx_eval.rake`
- **Tools de localização:** `enterprise/lib/captain/tools/enviar_localizacao_tool.rb` + `enviar_localizacao_imovel_tool.rb`
- **Modificados não-commitados:** `.../copilot/get_conversation_analysis_service.rb`, `config/schedule.yml`, `docs/clientes/tozi/gazetteer-sinop.json`, `mapa-mental-sinop.md`, `scripts/spx/tozi/build_gazetteer_config.rb`, `AGENTS.md`, `.claude/STATE.md`

---

## 4. 🔴 Código off-git nas VMs (risco de perda) — 2 pontos

**Padrão preocupante:** há código commitado **direto nas VMs** que nunca foi empurrado pro GitHub. Se o box cair, esse código se perde.

### 4.1. Tozi HML `.232` (conta 3) — 5 commits off-git

A HML está no HEAD `af53584c2`, que **não existe no GitHub** (nem em `origin/homologacao`, nem em `origin/nicolas`). São 5 commits locais do box:

```
af53584c2 merge(nicolas): traz chat-interno, relatórios de atribuição e WAHA interativo
215faa8c9 Merge remote-tracking branch 'origin/homologacao' into sync/nicolas-vinda
2887a96f2 fix(automacoes): nó de espera na paleta + rótulo de nós sem action_name
99d21d7ab feat(automacoes): gatilho por palavra-chave (keyword trigger)
116c86778 feat(automacoes): estado + esperas — flow_runs, wait, ResumeJob (base F2)
```

- ✅ **Bom:** essa linha **contém** o tip `1f59794f7` → os 8 commits de comportamento (§2.1) estão rodando na HML.
- ✅ **Reiniciada e ativa:** worker/web reiniciados em **14:56 UTC** (07/07), depois do último commit (**14:36 UTC**) → o código atual, incluindo o molde compartilhado `1f59794f7`, está carregado.
- ✅ **Sem migration pendente.**
- ⚠️ **Débito:** o merge do Nicolas + a base de automações (keyword trigger, flow_runs/wait/ResumeJob) **precisam ser reconciliados pro GitHub**.

### 4.2. Fábrica/Atacadão `3.87.182.184` (contas 1/2) — 176 commits off-git

Box em branch `producao` no HEAD `c8f3dc803`, **176 commits à frente** do `origin/producao` que o box conhece, e que **não contém** o tip atual (`2fa8d9eb6`). É uma **linha paralela** (redesign Agentes IA no kit Ai*, tools/integrações multi-tenant, geocoding built-in, fixes WAHA/LID, aba "Aguardando atendimento") **nunca reconciliada** pro repo. Maior massa de código off-git do parque.

---

## 5. Resumo executivo

- **Tozi PRODUÇÃO (conta 6):** saudável, no tip de `producao`, sem migration pendente — **porém sem as 8 melhorias de comportamento da §2.1**. Pra Clara "menos perdida" em produção, esses 8 precisam ir `homologacao → producao` + deploy na `.109`.
- **Tozi HOMOLOGAÇÃO (.232, conta 3):** ✅ os 8 commits estão rodando e a VM foi reiniciada (código ativo). ⚠️ Mas roda 5 commits **off-git** (Nicolas/automações).
- **Fábrica:** linha **off-git divergida** (176 commits fora do GitHub). Risco de perda de código.

---

## 6. Ações recomendadas / pontos pro dev decidir

1. **Deploy Tozi PROD (conta 6):** avaliar merge dos 8 commits (§2.1) em `producao`, push, pull na `.109`, `db:migrate:status` **antes** de qualquer restart, e restart do worker (`1f59794f7` exige). ⚠️ Só com OK explícito do Paulo — cliente real.
2. **Reconciliar off-git da HML (§4.1):** trazer o merge do Nicolas + base de automações pro GitHub (branch dedicada + PR) antes que a `.232` seja recriada/atualizada por cima.
3. **Reconciliar Fábrica off-git (§4.2, 176 commits):** trazer pro repo ou ao menos backup do box `3.87.182.184`.
4. **Trabalho local não-commitado (§3):** evals + tools deveriam entrar numa branch e ser pushados; hoje só existem na máquina do Paulo.

### Perguntas abertas pro dev
- Os 8 commits de comportamento vão pra produção **em bloco** ou selecionados? (`1f59794f7` toca molde compartilhado — atenção multi-tenant.)
- Estratégia de reconciliação das duas linhas off-git (HML Nicolas × Fábrica): PR incremental ou snapshot congelado?
- O eval nativo (§3) entra em qual branch/onda de deploy?

---

## Anexo A — comandos de reprodução

```bash
# Refs remotos atualizados
git fetch origin --prune

# Relações entre branches
git log --oneline origin/producao..origin/homologacao   # o que HML tem e PROD não (8)
git log --oneline origin/homologacao..origin/producao   # o que PROD tem e HML não (14)

# HEAD ao vivo — Tozi PROD (conta 6)
scripts/ops/tozi-prod.sh run "git rev-parse --abbrev-ref HEAD; git log -1 --oneline"
scripts/ops/tozi-prod.sh run 'eval "$(rbenv init -)"; bundle exec rails db:migrate:status | grep -i down'

# HEAD ao vivo — Tozi HML (conta 3) — SÓ funciona da LAN
scripts/ops/tozi-hml.sh chatwoot "cd /home/chatwoot/chatwoot && git log -1 --oneline; git merge-base --is-ancestor 1f59794f7 HEAD && echo CONTEM || echo NAO"
scripts/ops/tozi-hml.sh ssh 'systemctl show chatwoot-worker.1 chatwoot-web.1 --property=ActiveEnterTimestamp'

# HEAD ao vivo — Fábrica (contas 1/2)
scripts/ops/fabrica.sh run 'git log --oneline -8; git branch -vv | grep "^\*"'
```

> Mapa canônico de ambientes/deploy por cliente: `scripts/ops/AMBIENTES.md`.
