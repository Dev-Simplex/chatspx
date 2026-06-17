# WAHA — Reporte de falha de envio (Opção A)

> Como o app externo `chatwoot-waha-app` deve reportar de volta ao Chatwoot quando
> um envio para o WAHA **falha de fato**, para que o agente veja "Falha ao enviar"
> em vez da mensagem ficar presa em `sent` para sempre.

## Contexto

No canal WAHA (`Channel::Api`) o Chatwoot **não** envia a mídia diretamente: o
`chatwoot-waha-app` consome o `webhook_url` da inbox e posta no WAHA
(`/api/sendFile|sendImage|...`). O status de entrega volta só por polling
(`Waha::MessageStatusSyncService`), que **nunca marca `failed`** — de propósito,
porque ausência de ACK ≠ falha (mídia sem legenda, sessão fora do ar etc.
legitimamente ficam sem ACK por minutos). Resultado: uma falha real de envio era
silenciosa.

A correção (Opção A, sem heurística de timeout) é: **o app externo reporta o
erro explicitamente**. Esse caminho é seguro — zero falso-positivo — porque só
marca falha quando o WAHA de fato recusou.

## Contrato

Quando o envio ao WAHA falhar, o `chatwoot-waha-app` deve chamar:

```
PUT /api/v1/accounts/{account_id}/conversations/{conversation_id}/messages/{message_id}
Content-Type: application/json
api_access_token: <token do agente/bot da inbox>

{
  "status": "failed",
  "external_error": "<motivo legível, ex.: 'WAHA: file too large' ou erro da engine>"
}
```

- `message_id` é o id da mensagem Chatwoot (vem no payload do webhook que o app já consome).
- `external_error` é exibido ao agente no balão (tooltip do ícone de erro) e dispara
  o shake + botão "Reenviar" (ver F2).

### Resposta
- `200` com o JSON da mensagem atualizada (status `failed`).
- O endpoint e o `Messages::StatusUpdateService` **já existiam**; nada novo no
  Chatwoot além das salvaguardas abaixo.

## Salvaguardas no lado Chatwoot (já implementadas)

`Messages::StatusUpdateService#valid_status_transition?`:
- **Bloqueia `delivered`/`read` → `failed`.** Se o WAHA já confirmou entrega/leitura,
  um reporte de falha tardio/concorrente é ignorado (não "desfaz" uma entrega real).
- Transições válidas para falha: apenas a partir de `sent` (ou já `failed`).
- `external_error` só é persistido quando `status == 'failed'`; é limpo em qualquer
  outra transição (ex.: se depois chegar `delivered`).

### Idempotência / re-ACK
O `Waha::MessageStatusSyncService` consulta apenas mensagens `sent`/`delivered`,
então uma mensagem marcada `failed` **não** é reexaminada pelo polling — o estado
de falha reportado pelo app é autoritativo e não "flapa".

## O que NÃO foi feito (decisão consciente)
- **Opção B (marcar `failed` por timeout sem ACK)** não foi implementada: risco de
  falso-positivo em mídia sem legenda / sessão fora do ar. Caso um dia se queira,
  deve vir atrás de feature-flag (default OFF), excluir mídia-sem-legenda e permitir
  re-ACK voltar para entregue.

## Teste manual
1. Forçar o WAHA a recusar um envio (ex.: arquivo que a engine rejeita).
2. App externo chama o `PUT` acima com `status=failed`.
3. Agente vê "Falha ao enviar" + motivo no balão; "Reenviar" funciona (sem duplicar).
4. Conferir que uma mensagem já `delivered` que receba um `failed` tardio **permanece** `delivered`.
