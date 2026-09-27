# Contrato: Captador ↔ ChatSPX (nível 2, parte 1)

App "Captador" em Configurações → Integrações. Especificação completa: `comercial-captador/pesquisa/22-spec-chatspx-nivel2.md` (§1, §2, §5).

## Ligar numa conta

1. Super Admin → conta → **Captador integration enabled**. Chave `accounts.settings.captador_integration`; desligada, o app some da lista, `/spx/captador/*` responde 401 e nenhum evento sai.
2. Integrações → Captador, com os campos:
   - `captador_url`: endereço base, por exemplo `https://captador.spx.ia.br`;
   - `instance_key`: chave dada pela tela Conexões do Captador;
   - `shared_secret`: no mínimo 32 caracteres, gerado no Captador;
   - `allowed_inbox_ids`: CSV das caixas liberadas; vazio libera nenhuma;
   - `allow_login`: marcar só na conta de login.
3. Ao criar o hook, o `Crm::SetupJob` cria a label `captador` e os atributos `cnpj` e `captador_lead_id` (contato) e `captador_lead_id` (conversa).

Sem migração: tudo vive em `accounts.settings`, `integrations_hooks.settings` e no Redis.

## Assinatura (Captador → ChatSPX)

| Header | Valor |
|---|---|
| `X-Captador-Account` | `account_id` da conta no ChatSPX |
| `X-Captador-Timestamp` | epoch em segundos; fora de ±300 s → 401 |
| `X-Captador-Signature` | `sha256=` + hex de `HMAC_SHA256(shared_secret, "<ts>.<MÉTODO>.<path?query>.<corpo bruto>")` |
| `Idempotency-Key` | obrigatório em `leads`; 8 a 128 caracteres `[A-Za-z0-9_-]` (UUID serve) |

Qualquer falha de assinatura, conta sem a chave ou hook desligado: `401` sem corpo. Os erros de negócio vêm como `{ "error_code": "...", "meta": {...} }`.

## `POST /spx/captador/v1/sessoes` (login)

Só no hook com `allow_login`. Não cria token nem sessão no ChatSPX e não devolve `access_token`.

```json
{ "email": "maria@simplex…", "password": "…" }
200 { "user": { "id": 42, "name": "Maria", "available_name": "Maria", "email": "…", "avatar_url": "" },
      "account": { "id": 1, "name": "Simplex", "role": "administrator", "permissions": ["administrator"] },
      "teams": [ { "id": 7, "name": "comercial" } ] }
206 { "mfa_required": true, "mfa_token": "…" }   → repetir com { "mfa_token": "…", "otp_code": "123456" } (ou "backup_code")
```

| HTTP | `error_code` | Quando |
|---|---|---|
| 401 | `invalid_credentials` | senha errada, e-mail inexistente, usuário inativo ou código 2FA errado (genérico) |
| 401 | `mfa_token_invalid` | `mfa_token` inválido ou vencido (5 min): recomeçar pelo e-mail e senha |
| 403 | `saml_required` | usuário SAML |
| 403 | `not_account_member` | não é membro da conta do hook |
| 403 | `login_not_allowed` | hook sem `allow_login` |
| 429 | — | Rack::Attack: 10 tentativas por e-mail a cada 15 min; 10 códigos por `mfa_token` por minuto |

## `POST /spx/captador/v1/leads` (abrir conversa)

```json
{ "lead": { "id": "b3f1…", "cnpj": "12345678000199", "nome": "Padaria X Ltda", "telefone": "+5565999998888", "email": "…" },
  "acting_user_id": 42, "inbox_id": 91, "team_id": 7, "assignee_id": 42,
  "template": { "name": "prospeccao_b2b_v1", "language": "pt_BR", "processed_params": { "body": { "1": "Padaria X" } } },
  "preview": "Olá! Vi que a Padaria X…" }
201 (conversa nova) | 200 (reutilizada)
{ "contact_id": 5012, "conversation_id": 1234, "message_id": 99881, "reused": false,
  "conversation_url": "https://chat…/app/accounts/1/conversations/1234" }
```

- O remetente é `acting_user_id`. Sem `assignee_id`, o dono é ele.
- **Caixa oficial** (`Channel::Whatsapp`): `template` obrigatório, conferido antes de gravar. `preview` vira o texto da bolha; sem ele, o corpo do modelo renderizado.
- **Caixa não oficial** (`Channel::Api`, WAHA): `preview` é enviado como texto livre e `template` é ignorado. O risco ao número é do operador.
- `conversation_id` é o `display_id`. `201` quer dizer "mensagem criada", não "entregue": a falha chega por evento.
- Contato casado só por telefone (nunca por e-mail); o e-mail só é gravado se o contato não tiver um. A conversa ganha `custom_attributes.captador_lead_id` e `captador_url` (por merge) e a label `captador`; o contato ganha `cnpj` e `captador_lead_id`.
- Mesma `Idempotency-Key` com o mesmo corpo em 24 h: a mesma resposta, sem 2ª mensagem. Erro não fica guardado.

| HTTP | `error_code` | Quando |
|---|---|---|
| 400 | `idempotency_key_required` | sem `Idempotency-Key` válida |
| 404 | `not_found` | usuário, caixa, time ou dono fora da conta |
| 403 | `inbox_access_denied` | `acting_user_id` não é admin nem membro da caixa |
| 403 | `conversation_access_blocked` (+ `meta.current_assignee`, `team`, `existing_request`) | conversa aberta do contato é de outro time ou isolada para outro agente |
| 422 | `assignment_required` | conta com "assumir para responder" e a conversa tem outro dono |
| 409 | `contact_inbox_conflict` (+ `meta` da ficha) | número ligado a outra ficha na caixa Cloud |
| 409 | `idempotency_conflict` | mesma chave com outro corpo, ou o 1º pedido ainda em curso |
| 422 | `invalid_payload` | sem `lead.id` |
| 422 | `channel_not_allowed` | caixa fora de `allowed_inbox_ids` ou que não é WhatsApp/WAHA |
| 422 | `inbox_read_only` | caixa somente leitura |
| 422 | `template_not_approved` | modelo inexistente, não aprovado ou em outro idioma |
| 422 | `template_params_mismatch` | as chaves de `processed_params.body` diferem das variáveis do corpo |
| 422 | `content_required` | caixa não oficial sem `preview` |
| 422 | `phone_invalid` | telefone não vira `+55` + DDD + 8 ou 9 dígitos |
| 422 | `contact_opted_out` | contato suprimido para marketing |
| 422 | `whatsapp_number_invalid` | `whatsapp_number_exists == false` ou contato bloqueado |

## Eventos (ChatSPX → Captador)

`Spx::CaptadorListener` → `WebhookJob` → `POST <captador_url>/webhooks/chatspx/<instance_key>`, com `X-Chatwoot-Delivery`, `X-Chatwoot-Timestamp` e `X-Chatwoot-Signature` (`sha256=` + HMAC de `"<ts>.<corpo>"` com o `shared_secret`). São 5 tentativas quando o destino não recebeu. Só conversas com `custom_attributes.captador_lead_id`.

| `event` | Quando | Payload |
|---|---|---|
| `message_created` | lead escreveu (`incoming`) ou alguém respondeu (`outgoing`, não privada) | `message.webhook_data`; recusa do lead vem com `captador: { "opt_out": true }` |
| `message_updated` | mudou `status` (`delivered`, `read`, `failed`) | `message.webhook_data` + `changed_attributes`; motivo da falha em `content_attributes.external_error` |
| `conversation_status_changed` | resolvida, reaberta, adiada | `conversation.webhook_data` + `changed_attributes` |
| `conversation_updated` | mudou `assignee_id` ou `team_id` | `conversation.webhook_data` + `changed_attributes` |

A 1ª mensagem aberta pelo próprio Captador também gera `message_created` (`outgoing`): ela traz `additional_attributes.echo_id = "captador:<Idempotency-Key>"`.

Fica para a parte 2: catálogo, reconciliação (`conversas`) e o painel na lateral da conversa.
