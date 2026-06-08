# Runbook — Validação do `Waha::InboundReconcilerJob` (homologação → produção)

Rede de segurança server-side para o freeze do GOWS (#1482): reinjeta inbound do WhatsApp
que a WAHA deixou de empurrar durante o congelamento. **Por padrão é no-op** (gated por
`WAHA_RECONCILER_ENABLED`). Este runbook valida que ligá-lo **não gera duplicatas** antes de
habilitar em produção.

> ⚠️ Pré-requisito ainda PENDENTE: índice unique parcial em `messages(inbox_id, source_id)
> WHERE source_id IS NOT NULL`. Sem ele, a dedup depende de (a) match por `source_id` e
> (b) heurística content+timestamp (janela ±900s). Daí a necessidade desta validação.

## Limitação conhecida
- **TEXT-ONLY**: `reinject_message` faz `return if content.blank?`. Áudio/imagem/vídeo/doc
  perdidos no freeze **não** são reinjetados — só o restart de sessão (watchdog) recupera mídia.

## Risco que estamos validando
`extract_message_id` (REST `/messages`) usa `key.id || id`; o caminho live grava
`source_id = message[:id].to_s`. Se os formatos divergirem (key.id curto vs WAMID serializado),
o match por `source_id` falha e sobra só a heurística content+timestamp — que **pode duplicar**
mensagens de texto curto/repetido dentro da janela de 15min.

## Passo a passo (HOMOLOGAÇÃO)

1. **Ligar** em homologação:
   ```bash
   # .env de homologação
   WAHA_RECONCILER_ENABLED=true
   # reiniciar scheduler + worker que consome a fila 'low'
   sudo systemctl restart chatwoot-worker.1 chatwoot-worker.bulk
   ```
   Confirmar que o job saiu do no-op:
   ```bash
   journalctl -u chatwoot-worker.1 -f | grep -i InboundReconciler   # deve logar execução a cada 5min
   ```

2. **Baseline** — antes de simular freeze, snapshot por inbox WAHA:
   ```sql
   SELECT inbox_id, count(*) FROM messages
   WHERE message_type = 0 AND created_at > now() - interval '1 day'
   GROUP BY inbox_id;
   ```

3. **Simular o freeze** (ou usar uma janela real): pausar o push da WAHA por ~10min
   (ex.: parar o "chatwoot app" da WAHA, ou usar uma sessão que congelou) e mandar algumas
   mensagens de teste de texto (incluindo repetidas/curtas para estressar a heurística).

4. **Deixar o reconciler rodar** 2–3 ciclos (10–15min) e religar o push.

5. **Detectar duplicatas** (o critério de aceite é ZERO):
   ```sql
   -- duplicata por source_id no mesmo inbox
   SELECT inbox_id, source_id, count(*)
   FROM messages
   WHERE message_type = 0 AND source_id IS NOT NULL
     AND created_at > now() - interval '1 hour'
   GROUP BY inbox_id, source_id HAVING count(*) > 1;

   -- duplicata por conteúdo+conversa em janela curta (texto repetido)
   SELECT conversation_id, content, count(*)
   FROM messages
   WHERE message_type = 0 AND content <> ''
     AND created_at > now() - interval '1 hour'
   GROUP BY conversation_id, content, date_trunc('minute', created_at)
   HAVING count(*) > 1;
   ```

6. **Aceite**: zero duplicatas em ambas as queries, em pelo menos 3 ciclos do job e com mensagens
   de texto repetido. Conferir nos logs quantas mensagens foram reinjetadas (sanidade: bate com o
   que ficou preso no freeze).

## Promoção para PRODUÇÃO
Só após o aceite em homologação:
```bash
# .env de produção
WAHA_RECONCILER_ENABLED=true
sudo systemctl restart chatwoot-worker.1 chatwoot-worker.bulk
```
Monitorar as mesmas queries de duplicata nas primeiras 24h.

## Rollback (imediato)
```bash
# remover/!=true em WAHA_RECONCILER_ENABLED no .env
sudo systemctl restart chatwoot-worker.1 chatwoot-worker.bulk
```
O job volta a ser no-op no próximo ciclo. Nenhuma mensagem já reinjetada é removida
(rollback só impede novas reinjeções).
