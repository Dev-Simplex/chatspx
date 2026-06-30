# Runbook — Migração de servidor/sessão WAHA + aquecimento do mapping LID→PN

> Checklist OBRIGATÓRIO sempre que trocar o servidor WAHA (`WAHA_API_URL`), recriar
> uma sessão ou apontar um inbox para outro host WAHA. Pular estes passos reintroduz
> identificadores `@lid` na frota (contatos aparecem como `123456789@lid` em vez do
> nome/telefone real).

## Por que isto é necessário (causa-raiz)

O WhatsApp identifica alguns contatos por **LID** (`<números>@lid`), um identificador
opaco que NÃO é o telefone. O WAHA mantém um **cache LID→PN** (LID → phone number) que
ele aprende ao buscar grupos/contatos e ao processar tráfego. O Chatwoot resolve o LID
para o telefone real consultando esse cache (`Waha::ApiService#get_lid_phone_number` /
`get_lids_list`) dentro do `Contacts::ResolveLidJob`.

**Quando você troca de servidor WAHA (ou recria a sessão), esse cache nasce VAZIO.**
Todos os `get_lid_phone_number` retornam `pn: null` até o WAHA reaprender. Os
`Contacts::ResolveLidJob` que rodam nessa janela esgotam as 7 tentativas
(backoff ~18 min) e **morrem sem reagendamento**. Os contatos afetados ficam presos com
`@lid` indefinidamente.

> Incidente de referência: migração `api.chatspx.app` → `wapi.chatspx.app`
> (~2026-05-23). O novo host subiu com o cache LID→PN zerado e os `@lid` voltaram a
> aparecer na frota. Ver também `docs/.../project_waha_wapi_migration_2026_06_22`.

A partir do fix `fix/lid-resweep-p1` existe uma rede de segurança automática
(`Contacts::ResolveLidSweepJob`, cron horário) que recupera os presos sozinha assim que
o cache esquenta. Mesmo assim, **execute este runbook na migração** para acelerar a
recuperação e confirmar que ela aconteceu.

---

## Checklist de migração

### (a) Conferir a URL e que cada sessão existe no host novo

1. Confirme a variável de ambiente no host do Chatwoot:

   ```bash
   # deve apontar para o servidor WAHA NOVO
   grep -E '^WAHA_API_URL=' /home/chatwoot/chatwoot/.env
   grep -E '^WAHA_API_KEY=' /home/chatwoot/chatwoot/.env   # confirmar que a KEY confere
   ```

2. Liste as sessões que o Chatwoot espera (uma por inbox WAHA) e confronte com o que o
   servidor novo conhece:

   ```bash
   # nomes de sessão esperados pelo Chatwoot (rails runner / console)
   bundle exec rails runner 'puts Inbox.where.not(waha_session_name: [nil, ""]).distinct.pluck(:waha_session_name)'

   # sessões que o servidor WAHA NOVO realmente tem (all=true inclui as paradas)
   curl -s -H "X-Api-Key: $WAHA_API_KEY" "$WAHA_API_URL/api/sessions?all=true" | jq '.[].name'
   ```

   **Toda `waha_session_name` do Chatwoot precisa existir no host novo e estar
   `WORKING`.** Sessão ausente ou parada = inbound não chega e o LID nunca resolve.
   Crie/inicie a sessão no servidor novo antes de prosseguir.

### (b) Aquecer o mapping LID→PN (buscar grupos em todas as sessões)

O WAHA popula o cache LID→PN ao buscar grupos. Dispare o aquecimento em TODAS as sessões:

```bash
bundle exec rails runner 'Waha::RefreshGroupsJob.perform_now'
```

> O `Waha::RefreshGroupsJob` também roda no cron a cada 30 min (fila `:scheduled_jobs`,
> não mais `:low`). O `perform_now` acima força o aquecimento imediato na migração.
> Aguarde 1–2 min para o WAHA processar antes do passo (c).

### (c) Rodar o re-sweep (recuperar os @lid presos)

Opção 1 — re-sweep automático (preferido; usa o novo job, idempotente, capado e logado):

```bash
bundle exec rails runner 'Contacts::ResolveLidSweepJob.perform_now'
# Log esperado: [ResolveLidSweepJob] presos=N reenfileirados=N restantes=0 teto=1000
# Se "restantes>0": rode de novo após alguns minutos OU aumente o teto:
bundle exec rails runner 'Contacts::ResolveLidSweepJob.perform_now(5000)'
```

Opção 2 — backfill manual via rake (útil para um account específico e com `dry_run`):

```bash
# DRY-RUN primeiro (não grava): account_id, dry_run=true, batch, use_waha=true, session
bundle exec rake 'contacts:backfill_whatsapp_lid_phone[ACCOUNT_ID,true,200,true,SESSION_NAME]'
# Aplicar de fato (dry_run=false):
bundle exec rake 'contacts:backfill_whatsapp_lid_phone[ACCOUNT_ID,false,200,true,SESSION_NAME]'
```

> O re-sweep reenfileira a resolução na fila `:scheduled_jobs` (não `:high`), então não
> compete com a resolução em tempo real dos webhooks. Como é idempotente, pode rodar
> quantas vezes quiser.

### (d) Monitorar a contagem de @lid

Acompanhe a contagem caindo após (b)+(c). Repita em intervalos de alguns minutos:

```bash
bundle exec rails runner '
  ci  = ContactInbox.where("source_id LIKE ?", "%@lid").count
  cid = Contact.where("identifier LIKE ?", "%@lid").count
  cnm = Contact.where("name LIKE ?", "%@lid").count
  puts "contact_inbox.source_id @lid=#{ci}  contact.identifier @lid=#{cid}  contact.name @lid=#{cnm}"
'
```

Equivalente em SQL (psql):

```sql
SELECT
  (SELECT count(*) FROM contact_inboxes WHERE source_id LIKE '%@lid') AS ci_source_id,
  (SELECT count(*) FROM contacts        WHERE identifier LIKE '%@lid') AS contact_identifier,
  (SELECT count(*) FROM contacts        WHERE name LIKE '%@lid')       AS contact_name;
```

**Critério de sucesso:** as três contagens tendem a 0 conforme o cache do WAHA esquenta.
Sobras persistentes indicam LIDs que o WAHA ainda não reaprendeu (geram tráfego/entre em
um grupo com o contato) ou conflitos de telefone (ver abaixo).

---

## Notas operacionais

- **Filas (sidekiq.yml):** a ordem é estrita; `:low` é a 7ª e fica faminta sob carga.
  `Waha::RefreshGroupsJob` e `Contacts::ResolveLidSweepJob` rodam em `:scheduled_jobs`
  (fila dos crons, drena de forma confiável). Não volte o RefreshGroups para `:low`.
- **Conflito de telefone:** se o LID resolve para um telefone que já pertence a outro
  contato, o `Contacts::ResolveLidJob` agora MESCLA os contatos via `ContactMergeAction`
  (mantém o contato real, apaga o `@lid`) em vez de estourar
  `RecordInvalid: Phone number has already been taken`. O backfill rake apenas sinaliza
  o conflito em `custom_attributes` (`waha_phone_conflict_*`) — sem mesclar.
- **Não precisa restart** para rodar (b)/(c) via `rails runner`. Mudanças de fila/cron
  (este fix) só passam a valer após o deploy + restart dos workers Sidekiq — e restart
  é responsabilidade do usuário (frota AWS recebe código via git bundle).
- **Verifique também:** `bundle exec rails runner 'puts ENV["WAHA_API_URL"]'` dentro do
  processo do Chatwoot, para garantir que o app está lendo a URL nova (e não um valor
  antigo em cache de ambiente).
```
