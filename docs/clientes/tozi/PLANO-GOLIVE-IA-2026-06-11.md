# Plano de go-live da IA — 11/06/2026 (Paulo + Dev Sênior + Ederson)

> **Meta:** ao fim de 11/06, Clara rodando em piloto limpo na inbox 91. Em 12/06, aberta para leads reais — "IA convincente" atendendo, qualificando, buscando imóvel, mandando foto, entendendo áudio, fazendo follow-up e entregando pro corretor com notificação.
> **Estado verificado em prod (10/06, read-only):** cérebro pronto (knowledge hybrid, 3 cenários, tools presentes, chaves OK, cota 99,8k). Pending limbo NÃO recorre (prod tem guarda dupla no reopen + `pending_status_enabled=false`). Fallback do handoff e typing indicator presentes. **Gaps reais: transcrição de áudio bloqueada (2 gates), fix do disparo fora de prod, 403 dos corretores, notificações default OFF, feature_memory/faq ligados.**
> **Regra de ouro:** antes de QUALQUER restart → `rails db:migrate:status` e confirmar **0 down**. Nunca `db:migrate` puro na AWS (landmine).

---

## Critério de sucesso (o que é "IA convincente" em 12/06)

1. Lead manda **texto, áudio ou foto** → Clara responde em tom natural (humanizer + typing), no contexto certo (cenário Vendas/Locação/Suporte).
2. Lead pede imóvel → Clara busca no **Vista** e manda opções reais (+ fotos sob pedido).
3. Lead some → Clara **cutuca sozinha** (máx 4, horário civilizado); esfriou → cadência HSM assume.
4. Lead quente → **handoff** com dossiê em nota privada + corretor **recebe push/e-mail**.
5. Humano responde → Clara **cala** na hora; label `atendimento` ou checkbox trava quando quiserem.
6. Corretor **consegue abrir** toda conversa atribuída a ele (403 morto).
7. Rollback em 10 segundos se algo der errado (desconectar a CaptainInbox).

---

## Divisão de papéis

| Quem | Foco do dia |
|---|---|
| **Dev Sênior** | Patches cirúrgicos em prod (T1–T4), scripts de dados (T5–T6), suporte ao teste |
| **Paulo** | Decisões de produto (D1–D3), config da Clara (T7), switch do go-live (T9), teste E2E (T10) |
| **Ederson** | Mutirão das 432 sem resposta (T8), comunicação/treinamento do time Tozi, validação de negócio no teste |

---

## Decisões a bater no início do dia (15 min, os três)

- **D1 — Replies de disparo:** quando a whitelist abrir (12/06), a Clara passa a responder TAMBÉM os ~6.100 leads de disparo que responderem (HSM não conta como "humano respondeu"; se o corretor já falou, ela cala sozinha). **Recomendação: deixar a Clara atender** (é qualificação 24/7 — o objetivo do projeto), avisando os corretores. Alternativa pronta: script bulk de label `atendimento` nas conversas de disparo abertas → Clara as ignora (T11, fica preparado).
- **D2 — Fora do horário comercial:** hoje a Clara RESPONDE fora do horário (behavior sem `outside_hours_action`), e o prompt manda qualificar fundo + prometer retorno. **Recomendação: manter** (atendimento 24/7 é vantagem).
- **D3 — feature_memory/feature_faq:** hoje TRUE → religar a Clara faz cada resolve da inbox 91 gerar 1–2 chamadas LLM (notas com PII + FAQs automáticas). **Recomendação: desligar ambos no go-live** (T7); revisitar depois com calma. (As notas geradas nem voltam ao prompt do agente — memória write-only.)
- **D4 — DEFINIDO (Paulo, 10/06): a IA determina o TIME pela INTENÇÃO.** Implementação sem código, logo após o go-live (D+1/D+2): (1) criar labels `intencao:locacao|venda|financeiro|manutencao|desocupacao|juridico` no catálogo; (2) instruir os cenários da Clara a etiquetar via tool `add_label_to_conversation`; (3) uma automation rule por intenção: condição label = `intencao:X` **e team vazio** → ação `assign_team` (os 13 times funcionais já existem e o card move pro funil do time sozinho). A #53 não interfere (só roda na reabertura; a classificação vem depois). Evolução Fase 1: tool nativa `atribuir(team)` + HandoffTool com team_id, e a #53 é aposentada.

---

## MANHÃ — Bloco 1 · Patches de código em prod (Dev Sênior, ~2h)

> Acesso: `ssh -i Downloads/handoff-tozi/simplex.linux.pem ubuntu@3.82.215.109` · app em `/home/chatwoot/chatwoot` · rodar como `sudo -u chatwoot`.
> Antes de mexer: backup dos 3 arquivos (`cp arquivo arquivo.bak.20260611`).

### T1 — Transcrição de áudio (bloqueador de "IA convincente")
Prod barra áudio em DOIS gates:
1. **Código** — `enterprise/app/services/messages/audio_transcription_service.rb`, método `can_transcribe?`: prod só aceita a flag legada `captain_integration` (que está FALSE na conta). Trocar a linha do gate pela versão do commit `1671b9017` (repo local já tem):
   ```ruby
   return false unless account.feature_enabled?('captain_integration') || account.feature_enabled?('captain_integration_v2')
   ```
   Como o resto do arquivo não divergiu, pode transportar o arquivo inteiro do repo local (diff antes para confirmar: `diff <(ssh ... cat .../audio_transcription_service.rb) enterprise/app/services/messages/audio_transcription_service.rb`).
2. **Setting da conta** (console, junto com T5/T6):
   ```ruby
   a = Account.find(6); a.audio_transcriptions = true; a.save!
   ```

### T2 — Fix do 403 dos corretores (1 linha)
`app/controllers/api/v1/accounts/conversations_controller.rb`, método `authorize_team_access` (linha ~231) — adicionar logo após os returns existentes:
```ruby
return if @conversation.assignee_id == Current.user&.id  # dono da conversa sempre abre
```
Princípio: atribuição implica acesso. Commitar o mesmo fix na `paulao`.
*(Causa medida: ~700 conversas abertas com assignee de um corretor e team de outro — resíduo das reatribuições via `update_columns`. O fix de código mata a classe inteira; higiene de dados é o T6.)*

### T3 — Fix anti-duplicata do disparo (commit `11b913531`)
**Patch cirúrgico em 3 pontos** no `app/jobs/spx/tozi/disparo_lead_job.rb` de prod (que está SEM a lógica de inquilinos — **não transportar o arquivo inteiro**, clobberaria diferente do local):
1. Trocar `source_id: phone.delete('+')` por `source_id: resolved_source_id(inbox, phone)`.
2. Trocar o `Conversation.create!` incondicional por `conversation = find_or_create_conversation(inbox, contact_inbox, assignee_id, campaign_id, template)`.
3. Colar os 2 helpers privados `resolved_source_id` e `find_or_create_conversation` (copiar de `git show 11b913531` no repo local).
Sem isso, o próximo disparo volta a fabricar fichas/conversas duplicadas.

### T4 — Restart (uma vez só, depois dos 3 patches)
```bash
cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails db:migrate:status | grep -c down   # tem que dar 0
sudo systemctl restart chatwoot-web.1 chatwoot-worker.1
curl -sf -o /dev/null -w "%{http_code}" https://tozi.chatspx.app && echo " OK"
```

---

## MANHÃ — Bloco 2 · Dados e config (Dev Sênior + Paulo, ~1h30)

> Tudo via `rails runner` em prod. Scripts curtos — colar um por um.

### T5 — Notificações dos corretores (o elo quebrado do incidente)
```ruby
# push/e-mail de "lead respondeu na SUA conversa" e "menção" vêm DESLIGADOS de fábrica
[126, 127, 128, 131].each do |uid|
  ns = NotificationSetting.find_by(account_id: 6, user_id: uid)
  next unless ns
  ns.selected_email_flags = (ns.selected_email_flags + %i[email_conversation_assignment email_assigned_conversation_new_message email_conversation_mention]).uniq
  ns.selected_push_flags  = (ns.selected_push_flags  + %i[push_conversation_assignment push_assigned_conversation_new_message push_conversation_mention]).uniq
  ns.save!
  puts "ok #{uid}"
end
```
**Ederson:** orientar cada corretor a abrir o SPX no navegador e ACEITAR a permissão de notificação (sem isso o push não tem pra onde ir). iPhone: instalar como PWA.

### T6 — Times: membership + higiene (complementa o T2)
```ruby
# Marcus e Bruno não são membros de NENHUM time (nem dos próprios "X - disparo")
TeamMember.find_or_create_by!(team_id: 64, user_id: 128)  # marcus - disparo
TeamMember.find_or_create_by!(team_id: 65, user_id: 131)  # bruno - disparo

# Higiene: conversas abertas de disparo com team de OUTRO corretor → team do dono atual
MAP = { 126 => 62, 127 => 63, 128 => 64, 131 => 65 }
MAP.each do |uid, tid|
  n = Conversation.where(inbox_id: 91, status: :open, assignee_id: uid, team_id: [61, 62, 63, 64, 65]).where.not(team_id: tid)
                  .update_all(team_id: tid)
  puts "assignee #{uid}: #{n} conversas → team #{tid}"
end
# (conversas com team FUNCIONAL trocado ficam como estão — o fix T2 já permite o dono abrir)
```

### T7 — Config da Clara (Paulo, decisão D3 aplicada)
```ruby
a = Captain::Assistant.find(7)
a.config = a.config.merge('feature_memory' => false, 'feature_faq' => false)   # D3
b = a.behavior
b['router']['only_contact_phones'] = ['+5566996350491', '<numero_dev>', '<numero_ederson>']  # piloto interno
a.behavior = b
a.save!
```
Depois do smoke test com FAQ ("aceitam pet?"), confirmar que a consulta à knowledge continua OK (se quebrar, religar só `feature_faq`).

### T8 — Mutirão das 432 (Ederson, paralelo o dia todo)
Gerar a lista por corretor (dev roda e exporta):
```ruby
rows = ActiveRecord::Base.connection.select_all(<<~SQL)
  SELECT c.display_id, u.name AS corretor, ct.name AS contato, ct.phone_number,
         to_char(m.created_at, 'DD/MM HH24:MI') AS esperando_desde
  FROM conversations c
  JOIN users u ON u.id = c.assignee_id
  JOIN contacts ct ON ct.id = c.contact_id
  JOIN LATERAL (SELECT created_at, message_type FROM messages
                WHERE conversation_id = c.id AND message_type IN (0,1)
                ORDER BY created_at DESC LIMIT 1) m ON true
  WHERE c.inbox_id = 91 AND c.status = 0 AND m.message_type = 0
    AND m.created_at < now() - interval '12 hours'
  ORDER BY u.name, m.created_at
SQL
```
Ederson distribui pro time responder HOJE (são leads esperando há dias). ⚠ Janela 24h fechada na maioria → responder via template aprovado (o composer já oferece quando a janela expira).
**Ederson também:** comunicar o time Tozi — amanhã a IA entra em piloto; pra silenciar a Clara numa conversa: label `atendimento` OU checkbox "atendimento humano"; resolver/abrir continua sendo do time.

---

## TARDE — Bloco 3 · Go-live piloto + teste E2E

### T9 — O switch (Paulo, 1 comando)
```ruby
CaptainInbox.create!(inbox_id: 91, captain_assistant_id: 7)
```
Rollback instantâneo a qualquer momento: `CaptainInbox.find_by(inbox_id: 91).destroy`.

### T10 — Roteiro de teste E2E (números do piloto; ~1h, os três juntos)

| # | Teste | Esperado |
|---|---|---|
| 1 | "oi, tô procurando casa pra alugar" | Júlia responde natural, 1 pergunta por vez, qualifica |
| 2 | "3 quartos, até R$ 2.500, perto da UNEMAT" | `buscar_imovel` → opções REAIS do Vista com link |
| 3 | "manda fotos da segunda opção" | 3 fotos reais chegam |
| 4 | **Áudio**: "me liga depois das 14h" | Clara entende e responde (valida T1) |
| 5 | **Foto** de fachada/planta | Clara comenta o conteúdo da imagem |
| 6 | "vocês aceitam pet?" / "como funciona o caução?" | resposta da knowledge (valida D3/T7) |
| 7 | Parar de responder 2–3 min após pergunta dela | cutucada contextual chega (follow-up in-window) |
| 8 | "quero falar com um corretor" | nota privada com dossiê + conversa atribuída + **push chega no corretor** (valida T5) |
| 9 | Corretor responde em público | Clara cala (skip pós-humano) |
| 10 | Marcar label `atendimento` em outra conversa de teste | Clara ignora a conversa |
| 11 | Resolver a conversa e mandar nova mensagem | reabre OPEN (sem pending) e a Clara atende |
| 12 | Mandar só "blz" | silêncio ([IGNORAR]) |
| 13 | **Corretor Lucas** abre conversa que dava 403 | abre normal (valida T2) |

### Monitoramento durante o teste (dev deixa rodando)
```ruby
# decisões da Clara em tempo real
Captain::AssistantLog.where(assistant_id: 7).where('created_at > ?', 1.hour.ago)
                     .group(:event_type).count
# e: .where(event_type: 'error').last(5) para qualquer erro
```

### T11 — Preparar (não executar) o controle de escopo dos disparos
Se D1 = "Clara NÃO atende replies de disparo" → deixar pronto:
```ruby
# bulk label 'atendimento' nas conversas de disparo abertas (Clara passa a ignorá-las)
Conversation.where(inbox_id: 91, status: :open).where.not(campaign_id: nil)
            .find_each { |c| c.add_labels(['atendimento']) }
```

### T12 — Fim do dia: piloto com leads reais
Adicionar 5–10 números de leads REAIS novos na whitelist (`only_contact_phones`) e observar até a noite (AssistantLog + transcrições).

---

## 12/06 — Abertura (se GO)

**Critérios de GO:** 13/13 do roteiro OK · zero `error` no AssistantLog · respostas dentro da persona nos leads reais do T12 · push chegando nos corretores.

1. Manhã: revisar as conversas do piloto noturno com Ederson (tom, alucinação, handoff).
2. `b['router']['only_contact_phones'] = []` → **geral** (com D1 aplicada — script T11 se for o caso).
3. Os três monitoram o dia inteiro (AssistantLog por hora + aba da inbox 91). Trava por conversa: label `atendimento`.
4. Rollback geral em 10s se precisar: destruir a CaptainInbox (a config toda fica intacta pra religar).

---

## Fora do escopo de amanhã (não dispersar)
Reconciliação completa rollout↔paulao (P0, mas é projeto próprio — agendar); Meta Lead Ads → prod (exige HSM de abertura + fix do source_id antes do switch do callback); módulo de campanhas; Evals (worker 8910); follow-up 2ª leva inquilinos. Tudo mapeado em `docs/MAPEAMENTO-SPX-ORQUESTRACAO-IA-2026-06-10.md` §10.

## Notas de bolso
- A guarda do reopen em prod (rollout) NÃO existe na `paulao` local — na reconciliação, levar **a guarda da rollout + o `ensure_conversation_open` da paulao** (são complementares).
- ⚠ Nunca ligar "status pendente" da inbox 91 na UI — reabre o limbo.
- A regra #53 segue ativa: reabertura zera dono (a Clara atende mesmo sem dono; o handoff dela re-atribui). Conviver por enquanto; substituir pela triagem orquestrada na Fase 1 do plano-mestre.
- Cada redeploy da `rollout` re-dropa os patches T1/T3 (off-git) — anotar no runbook de deploy até a reconciliação.
