# Plano — Deploy Produção (todas as VMs) + Migração da IA/Captain para a Tozi

> Autor: Walisson (Simplex) · Assistido por Claude Code · Data: 2026-06-27
> Status: **PLANEJAMENTO** (execução end-to-end após aprovação — "só planejamento agora")
> Runbook base: `vault/04-Runbooks/RB - Deploy Chatwoot Producao.md`
> Lição obrigatória: `vault/01-Permanentes/Incidente - Pending Migration 24-abr-2026.md`

---

## 0. Estado atual (apurado em 27/jun, read-only)

### Código
- `origin/producao` está **5 commits atrás** de `origin/homologacao`. Os 5 são refinamento do captain:
  `46047d026` (buscar_imovel por código + buscar_lugar/Google Places), `b45f3f578` (credenciais Vista/Google por conta, multi-tenant), `ddd9450df` (regras de conduta no template), `80e2a9c9c` (replay-guard chunk-aware), `c29789ad8` (aviso fora-do-horário enxuto).
- Meu fix de UI **`3c7c3fbeb` (abas do chat-list) está só LOCAL — não pushado.** Precisa ir pra `homologacao` antes.
- **Nenhuma migration nova** entre `producao` e `homologacao` no git. As migrations estruturais da IA (`add_captain_assistant_to_agent_bots`, `add_agent_id_to_messages`, isolamento por agente) **já estão na branch `producao`** desde o deploy de 25/jun.

### ⚠️ Ressalva crítica (causa do incidente 24/abr)
Git ter a migration na branch **≠** ela estar **aplicada no banco** de cada VM. O `db:migrate:status` em CADA ambiente é **obrigatório** antes de qualquer restart. Risco específico: a FK órfã `20260330120000_add_foreign_key_constraints` — o `deploy.sh` roda `db:migrate` cego (aplica TODAS as pendentes); se essa FK ainda estiver `down` em alguma VM e tiver órfãos, o deploy trava no meio.

### Infra de deploy
- Orquestrador: **`deployment/deploy.sh`**, rodado **a partir da PRODUÇÃO (192.168.8.229)** — é lá que estão a `simplex.linux.pem` e o `sshpass`. **Daqui da homologação (232) não há acesso SSH às outras VMs.**
- VMs no `deploy.sh`: `PRODUCAO(local)`, `CATATAU(3.85.130.14)`, `SENTINELA(54.152.144.236)`, `ALTERNATIVO(192.168.8.169)`.
- **TOZI (`54.91.152.38`, AWS) está COMENTADA** — `# Descomentar quando instalar o ChatSPX`. Nunca recebeu deploy automatizado.

### Dados da IA (vivem na conta **3 = Simplex Tecnologia**, a sandbox de homologação)
| Assistant | Bot-espelho | Conteúdo |
|---|---|---|
| **Clara** (#3) | bot #3 | 1 doc · 19 chunks · 41 respostas · 6 cenários |
| **Júlia** (#10) | bot #10 | 1 doc · 19 chunks · 36 respostas · 1 cenário |
| Bruna (#11) | bot #11 | vazia (1 cenário) |
| Letícia (#12) | bot #12 | vazia |
| Marina (#13) | bot #13 | vazia |
| Rafa (#14) | bot #14 | vazia |
- `captain_custom_tools`: conta 3 tem 2 tools (buscar_imovel / buscar_lugar). Conta 1 tem 2.
- Credenciais Vista/Google: `account.custom_attributes['vista_api_key' | 'vista_base_url']` → fallback ENV `TOZI_VISTA_API_KEY` / `TOZI_VISTA_BASE_URL` (base legado `toz19328-rest.vistahost.com.br`).
- Mecanismo de espelho: **`rake captain:sync_mirrors`** (recria AgentBot-espelho de cada assistant).

---

## 1. Decisões — status
- ✅ **Modo da Tozi:** ESPELHO TOTAL (homologação manda em tudo; Tozi fica idêntica). [decidido]
- ✅ **Gate:** mostrar o diff e esperar OK antes de sobrescrever. [decidido]
- ✅ **Premissa:** a Tozi já roda a IA (versão antiga); homologação é a fonte. [confirmado pelo Walisson]
- ✅ **Embeddings:** regenerar no destino (re-treino dos docs). [decidido — recomendado]
- ⏳ **Quais assistants:** sai do diff na F1/F2 (Clara, Júlia + Bruna/Letícia/Marina/Rafa). Confirma no checkpoint se Marina/Rafa entram.
- ⏳ **Credenciais Vista/Google da Tozi:** preciso das chaves pra F6 (`custom_attributes`).
- ⏳ **Conta da Tozi (id) na VM dela:** sai do pré-flight F0.

---

## FASE A — Consolidar homologação (push do fix de UI)
> Autoridade: push é do @devops. Em execução end-to-end, faço com seu OK.
```bash
cd /home/chatwoot/chatwoot
git status                       # esperar: só version.json + .bak (limpo)
git push origin homologacao      # sobe 3c7c3fbeb (abas)
```
**Validação:** `git rev-list --count origin/homologacao..HEAD` → 0.

---

## FASE B — Pré-flight de PRODUÇÃO (read-only, RODAR DA 229)
```bash
ssh chatwoot@192.168.8.229
cd /home/chatwoot/chatwoot
source /usr/local/rvm/scripts/rvm && rvm use 3.4.4   # (ou rbenv, conforme a VM)
git fetch origin
git log -1 --format='codigo em disco: %h %ai %s'
git rev-parse --abbrev-ref HEAD
RAILS_ENV=production bundle exec rails db:migrate:status | grep '^\s*down'   # << TEM que vir vazio
systemctl show chatwoot-web.1 --property=ActiveEnterTimestamp
```
**Gate:** se aparecer alguma migration `down`, aplicar **uma a uma** com `db:migrate:up VERSION=…` (NUNCA `db:migrate VERSION=X` — aplica todas até X). Tratar a FK `20260330120000` à parte (limpar órfãos antes, ver incidente 24/abr).

---

## FASE C — Promover código homologacao → producao
```bash
git checkout producao
git pull origin producao
git merge homologacao            # fast-forward esperado (producao 0 atrás)
git push origin producao
git checkout homologacao
```
**Validação:** `git rev-list --count origin/producao..origin/homologacao` → 0.

---

## FASE D — Deploy em TODAS as VMs (a partir da 229)
```bash
cd /home/chatwoot/chatwoot
./deployment/deploy.sh producao
```
O script, por VM: `git pull producao` → `bundle install` → `pnpm install` → `assets:precompile` (NODE_OPTIONS 4096) → `db:migrate` → `restart chatwoot.target`. Pula VM já no último commit.
**Atenção:** o `db:migrate` do script é cego — por isso a Fase B (pré-flight de migrations) é pré-condição. Rodar fora de horário de pico.

---

## FASE E — Smoke test pós-restart (cada VM)
Os 3 endpoints do runbook NÃO podem dar 500:
- `GET /api/v1/accounts/{id}/inboxes`
- `GET /api/v1/accounts/{id}/portals`
- `GET /api/v1/accounts/{id}/scheduled_messages/inboxes`
+ validar UI: abas do chat-list quebrando certo (meu fix), IA respondendo só em conversa atribuída.
500 ⇒ migration pendente ⇒ `db:migrate:status` + `db:migrate:up`.

---

## FASE F — Espelhar a IA/Captain da homologação na VM da Tozi (54.91.152.38)

> **Modo: ESPELHO TOTAL** — homologação (conta 3) é a fonte da verdade; a IA da Tozi fica **idêntica**.
> Prompt/behavior, custom_tools, scenarios, responses E documents são sobrescritos.
> O que existir **só na Tozi** (e não na homologação) é **APAGADO**. Operação destrutiva.
> **Gate obrigatório:** gerar o diff → mostrar → esperar OK do Walisson antes de aplicar.
> Premissa confirmada: a Tozi **já roda** a IA (versão antiga). Matching de assistant por **nome**.

### F0 — Pré-flight Tozi (da 229, com a pem) — read-only
```bash
ssh -i simplex.linux.pem ubuntu@54.91.152.38 'hostname; test -d /home/chatwoot/chatwoot && echo TEM-CHATSPX || echo SEM-CHATSPX'
# na Tozi: identificar a conta da Tozi e listar a IA atual
RAILS_ENV=production bundle exec rails runner scan_all_ia.rb   # mesmo script usado na 232
```
Saída esperada: conta da Tozi (id), assistants por nome (Clara/Júlia/…), tools, responses, documents, scenarios.
Se vier SEM-CHATSPX, parar — a premissa ("está atrás") estaria errada e vira instalação (Ramo A), não espelho.

### F1 — Gerar o DIFF (homologação conta 3  ✕  Tozi) — espelho total
Comparar por **nome de assistant**. Para cada um, classificar:
- **CRIAR** (existe na homologação, não na Tozi)
- **ATUALIZAR** (existe nos dois — diff de prompt/behavior/tools/scenarios/responses/documents)
- **APAGAR** (existe só na Tozi — removido no espelho total)
Idem para custom_tools e qualquer config de conta.
(Rake a escrever: `captain:diff_mirror[<conta_tozi>]` lendo um JSON exportado da conta 3.)

### F2 — CHECKPOINT (esperar OK)  🚦
Mostrar o diff completo (especialmente os **APAGAR** e os **ATUALIZAR** de responses/documents). **Só prosseguir após OK explícito.**

### F3 — BACKUP da IA atual da Tozi (OBRIGATÓRIO — antes de qualquer escrita)
```bash
# dump seletivo das tabelas captain_* + agent_bots da conta da Tozi → arquivo datado
pg_dump ... -t captain_assistants -t captain_documents -t captain_document_chunks \
  -t captain_assistant_responses -t captain_scenarios -t captain_custom_tools \
  -t agent_bots -t agent_bot_inboxes --data-only > /home/chatwoot/backup_ia_tozi_<data>.sql
```
Guardar o backup fora da VM também. É o rollback da operação destrutiva.

### F4 — Aplicar o espelho total (transação)
Recria/atualiza a IA da Tozi idêntica à conta 3, dentro de uma transação:
- assistants (matching por nome): system prompt/behavior, config
- custom_tools (buscar_imovel/buscar_lugar)
- scenarios, responses, documents (texto-fonte)
- **apagar** assistants/responses/docs órfãos (só-Tozi)
(Rake a escrever: `captain:apply_mirror[<conta_tozi>, arquivo.json]` — idempotente, transacional, gera novos IDs no destino.)
**Chunks NÃO** são copiados — regenerados na F5.

### F5 — Regenerar embeddings + espelhos
```bash
RAILS_ENV=production bundle exec rails runner 'Captain::Document.where(account_id: <conta_tozi>).find_each(&:reprocess!)'  # método exato a confirmar
RAILS_ENV=production bundle exec rake captain:sync_mirrors   # recria os AgentBot-espelho
```

### F6 — Credenciais Vista/Google na conta da Tozi
```ruby
acc = Account.find(<conta_tozi>)
acc.custom_attributes['vista_api_key']  = '<chave Vista da Tozi>'
acc.custom_attributes['vista_base_url'] = 'https://toz19328-rest.vistahost.com.br'
acc.custom_attributes['google_places_api_key'] = '<chave Google>'
acc.save!
```
(custom_attributes é o caminho multi-tenant; ENV `TOZI_VISTA_*` é fallback legado.)

### F7 — Validação E2E da IA na Tozi
- Conversa de teste → IA responde só quando atribuída a ela/seu time (gate).
- Prompt novo refletido (mensagens batem com a versão da homologação).
- `buscar_imovel` retorna imóvel real do Vista da Tozi (valida F6).
- `buscar_lugar` (Google Places) desambigua bairro.
- Bots-espelho aparecem na lista de agentes com o nome da IA.

---

## ROLLBACK (por fase)
- **Código (C/D):** `git reset --hard <commit_anterior>` na branch producao da VM + `assets:precompile` + restart. **Cuidado:** se o bug estiver em commit ancestral, reset do HEAD não resolve (lição 24/abr) — checar com `git merge-base --is-ancestor`.
- **Migration:** a maioria das migrations da IA é aditiva (colunas/tabelas novas) — não quebram código antigo; rollback de schema raramente necessário. Para erro query-time (`PG::UndefinedColumn`), a fix é aplicar a migration (não restart).
- **Dados Tozi (F):** operação é **destrutiva** (espelho total apaga o que só existe na Tozi). Rollback = restaurar o **backup F3** (`backup_ia_tozi_<data>.sql`) na conta da Tozi. Por isso F3 é obrigatória ANTES de qualquer escrita. Origem (conta 3 da homologação) NUNCA é tocada (só leitura no export/diff).

---

## Riscos principais
1. **FK órfã `20260330120000`** travar o `db:migrate` cego do deploy.sh → mitigar na Fase B.
2. **Restart expõe migration latente** (incidente 24/abr) → Fase B obrigatória em cada VM.
3. **VM da Tozi sem ChatSPX** → Ramo A (instalação), mais demorado.
4. **Colisão de IDs** na migração de dados → mitigado por export→recriar (novos IDs).
5. **Credenciais Vista/Google** não migram com os dados → Fase F4 explícita.
6. **Push/merge concorrente do Paulo** (working tree compartilhado) → coordenar janela; `git fetch` + status antes de cada push.

## Ordem de execução
A → B → C → D → E (deploy de código, todas as VMs) → F0…F6 (IA da Tozi).
As rakes de export/import (F1/F3) e o método de reprocess (F5) precisam ser escritos/confirmados antes da execução.
