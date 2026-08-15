# BRIEFING — Pesquisa: Grupos de WhatsApp (WAHA) no ChatSPX

> Documento de contexto compartilhado. **Todo worker deve ler este arquivo antes de começar.**
> Data: 2026-07-27 · Coordenador: Claude (terminal principal) · Solicitante: Walisson

---

## 1. O problema relatado pelo usuário

O ChatSPX (fork do Chatwoot) usa a **WAHA** (https://waha.devlike.pro/) como API não-oficial de
WhatsApp. Em **conversas de grupo**, a experiência está ruim:

### Sintoma A — LID cru vazando na interface

As mensagens de grupo aparecem com o identificador técnico do participante colado no nome:

```
👥 ‎Rogerio José Da Silva (229480102662169@lid)
Qual Wi-Fi está?
✏️ Editado no WhatsApp
Jul 27, 7:49 AM

TI TOZI - Inovação (GROUP)
👥 Angela Tozi (260330953380002@lid)
TOZIADM
Jul 27, 7:51 AM

TI TOZI - Inovação (GROUP)
👥 *Angela Tozi (260330953380002@lid)* Resolvido ✅
👥 ‎Rogerio José Da Silva (229480102662169@lid)
Reagiu com 👍
Jul 27, 9:03 AM
```

Observações do coordenador sobre esse dump:
- O nome do participante **já vem resolvido** (“Rogerio José Da Silva”, “Angela Tozi”) — o problema
  não é falta de nome, é o **`(<lid>@lid)` sendo concatenado** no texto visível.
- O prefixo `👥 ` e o sufixo `(GROUP)` **não existem em lugar nenhum do repositório**
  (`grep -rn "(GROUP)"` e busca pelo emoji U+1F465 em `app/ lib/ enterprise/` = zero resultados
  fora de emoji picker/help center). **Descobrir quem monta essas strings é uma das perguntas
  centrais da pesquisa.**
- Há um caractere invisível `U+200E` (LEFT-TO-RIGHT MARK) antes de “Rogerio” — pista de que a
  string vem de um payload cru do WhatsApp, não de código nosso.
- A citação/reply (`👥 *Angela Tozi (...)* Resolvido ✅`) e a reação (“Reagiu com 👍”) também
  carregam o LID — ou seja, o vazamento acontece em vários caminhos de renderização.

### Sintoma B — Grupo não mostra os integrantes

A conversa aparece só como `TI TOZI - Inovação (GROUP)`. Não há em lugar nenhum da UI a **lista de
participantes do grupo** (quem está no grupo, telefone, admin/não-admin, avatar).

---

## 2. Escopo desta rodada

**SOMENTE PESQUISA.** O usuário foi explícito: *"só pesquisa nesse momento, não economize."*

- ❌ **NÃO alterar código de aplicação.** Nenhum arquivo em `app/`, `lib/`, `enterprise/`,
  `config/`, `db/` pode ser editado.
- ❌ **NÃO rodar migration, NÃO commitar, NÃO push, NÃO deploy, NÃO restart de serviço.**
- ✅ **PODE e DEVE** escrever o relatório final em `plano/pesquisa-grupos-waha/`.
- ✅ Leitura de código, git log, docs, banco (SELECT), APIs externas (GET), web research.

### Blindagem de produção (regra dura, incidente prévio)

- Trabalhe **apenas** nesta VM: `192.168.8.232` (homologação). Diretório `/home/chatwoot/chatwoot`.
- **NUNCA** faça SSH para outra VM da frota, **nunca** toque em `.109` (Tozi PROD), `.229`,
  fábrica, ou qualquer host de cliente.
- Contra a API WAHA: **somente verbos de leitura (GET)**. Nenhum POST/PUT/DELETE, nada de
  `send`, `restart`, `logout`, `start`, `stop`, criar/editar grupo, sair de grupo.
- Contra o banco: **somente SELECT**. Nenhum UPDATE/INSERT/DELETE, nenhum `rails runner` que
  escreva. Se usar `rails runner`/`rails c`, prefixe mentalmente cada linha com "isso é leitura?".
- Nenhuma mensagem real pode ser enviada a nenhum número ou grupo, em nenhuma hipótese.

---

## 3. O que o coordenador já levantou (ponto de partida, não conclusão)

### Arquivos WAHA no repo

```
app/services/waha/api_service.rb                      (11.7 KB — cliente HTTP da WAHA)
app/services/waha/message_status_sync_service.rb
app/services/waha/outbound_special_message_service.rb
app/services/waha/poll_vote_service.rb
app/jobs/waha/refresh_groups_job.rb                   (aquece cache LID→PN via GET /groups)
app/jobs/waha/inbound_reconciler_job.rb
app/jobs/waha/message_status_sync_job.rb
app/jobs/webhooks/waha_events_job.rb                  (17 linhas)
app/controllers/webhooks/waha_controller.rb           (47 linhas)
app/controllers/public/api/v1/inboxes_controller.rb   (197 linhas — normalização LID→PN)
app/controllers/api/v1/accounts/waha_connections_controller.rb
app/services/messages/waha_message_resolvable.rb
app/builders/contact_inbox_with_contact_builder.rb    (migração @lid → @c.us)
app/policies/waha_connection_policy.rb
app/javascript/dashboard/api/wahaConnections.js
app/javascript/dashboard/routes/dashboard/settings/wahaConnections/
app/javascript/dashboard/components/app/WahaConnectionsBanner.vue
spec/services/waha/
deployment/waha-watchdog/
db/migrate/20251202210211_add_waha_session_name_to_inboxes.rb
```

### Documentação interna existente

```
docs/waha-lid-normalizacao.md              (47 linhas — LEIA)
docs/runbook-waha-migration-lid-warmup.md  (140 linhas — LEIA)
docs/waha-failure-reporting.md
docs/runbooks/waha-anti-oom-plan.md
deployment/runbook-waha-inbound-reconciler.md
```

### Métodos relevantes já identificados em `Waha::ApiService`

```ruby
get_lid_phone_number(session_name, lid)   # GET /api/{session}/lids/{lid}
get_lids_list(session_name, limit:, offset:)  # GET /api/{session}/lids  (fallback)
get_groups(session_name)                  # GET /api/{session}/groups
check_contact_exists(session_name:, phone:)
get_session_me(name)
get_messages(session_name, chat_id, ...)
```

Note: **não existe** hoje nenhum método para `GET /api/{session}/groups/{id}/participants`
nem nada que persista participantes de grupo. `get_groups` só é chamado como **efeito colateral**
para aquecer o mapa LID→PN dentro da WAHA (ver `RefreshGroupsJob`).

### Detecção de grupo hoje

Único lugar que reconhece grupo é o roteador do Captain (IA):

```ruby
# enterprise/app/services/captain/behavior/router_service.rb:33-46
# "o JID/chat_id do contato termina com `@g.us`"
return true if contact.identifier.to_s.end_with?('@g.us')
return true if custom['waha_whatsapp_chat_id'].to_s.end_with?('@g.us')
return true if custom['waha_whatsapp_jid'].to_s.end_with?('@g.us')
```

Ou seja: o sistema sabe **desviar a IA** de grupos, mas não modela grupo como entidade.

### Histórico de commits WAHA (git log resumido)

```
42e356b8eb fix(observabilidade): silencia ruído de LID vazio + guard blocked? nil (GlitchTip)
af53584c25 merge(nicolas): chat-interno, relatórios de atribuição e WAHA interativo
4a337015c6 feat(whatsapp): ingestão de votos de enquete via webhook WAHA inbound
8644a144bd feat(whatsapp): mensagens interativas (botões/lista) via WAHA REST
ddab9d387a fix(waha): mescla LID em conflito de telefone + re-sweep agendado dos @lid presos
6a905e0680 fix(waha): cap status-sync reads per session + circuit breaker + payload menor
2f01903b2b feat(waha): apagar mensagem estilo "Editada" + delete-for-everyone
c052f226a3 feat(waha): fallback de tempo real para freeze/crash do GOWS
2548a34903 fix(waha): resolver LID definitivamente com retry agressivo e refresh de grupos
06ede7dd32 fix: melhorar dedup de conversas e adicionar retry de LID
01c8ecfa88 fix: contact phone/email not showing + remove @c.us from names
b86bc3a4ab verificação de lid
```

Leitura do coordenador: **já houve várias tentativas de domar o LID**, todas focadas em
*conversas 1:1* (deduplicação de contato/conversa). O caso **grupo** parece nunca ter sido tratado.

### Fatos de ambiente

- Esta VM (`192.168.8.232`) é **inteira de homologação** — rodar `RAILS_ENV=production` aqui é seguro.
- Domínios `chatspx.app` e `hmlchat.simplexsolucoes.com.br` = este mesmo ambiente.
- Cliente do dump: **Tozi** (grupo "TI TOZI - Inovação").
- Motor de automações: existe plataforma nativa "Flow"; havia n8n legado. **Se a string
  `👥 ... (GROUP)` for montada fora do Rails, o n8n/receptor externo é o principal suspeito.**
- Observabilidade: GlitchTip em `glitchtip.chatspx.app` (1 projeto por cliente).

---

## 4. Perguntas que a pesquisa precisa responder

Divididas entre os workers, mas todo mundo deve ter o mapa completo em mente:

1. **Quem monta** `👥 Nome (lid@lid)` e `Nome (GROUP)`? Rails, n8n, receptor externo, ou a própria WAHA?
2. **O que a WAHA entrega** hoje sobre grupos e participantes que nós não estamos usando?
3. **Por que o LID não é resolvido** no caminho de grupo (se em 1:1 há normalização)?
4. **Como o Chatwoot deveria modelar** um grupo: contato = grupo, participante = quê?
5. **Como exibir** participante por mensagem e a lista de integrantes, sem brigar com o core?
6. **Qual o menor caminho** para um ganho visível (tirar o LID do texto) e qual o caminho completo?

---

## 5. Formato de entrega (obrigatório)

Cada worker escreve **um único arquivo markdown** em:

```
/home/chatwoot/chatwoot/plano/pesquisa-grupos-waha/<SEU-NUMERO>-<slug>.md
```

Estrutura mínima:

```markdown
# W<N> — <Título>

## Resumo executivo
(5-10 linhas. O que você descobriu que muda a decisão.)

## Achados
(numerados, cada um com EVIDÊNCIA: caminho:linha, trecho de payload, URL da doc, saída de query.
 Distinga claramente FATO VERIFICADO de HIPÓTESE NÃO CONFIRMADA.)

## Lacunas / o que não consegui verificar
(honestidade > completude aparente)

## Implicações para a solução
(o que isso habilita ou impede)

## Referências
```

**Regras de qualidade:**
- Toda afirmação sobre o código precisa de `caminho/arquivo.rb:linha`.
- Toda afirmação sobre a WAHA precisa de URL da doc **ou** saída real de request.
- Se você não conseguiu confirmar algo, escreva "NÃO CONFIRMADO" — não invente.
- Se descobrir algo que contradiz este briefing, **diga isso em destaque**. O briefing é um
  ponto de partida do coordenador, não verdade revelada.

Ao terminar, envie `worker_done` conforme o preâmbulo do seu dispatch, com `reportPath` apontando
para o arquivo que você escreveu.
