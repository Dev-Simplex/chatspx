# Contrato: Captador ↔ ChatSPX (nível 2)

App "Captador" em Configurações → Integrações. Especificação completa: `comercial-captador/pesquisa/22-spec-chatspx-nivel2.md` (§1, §2, §5). Parte 1: login, leads e eventos. Parte 2: catálogo, reconciliação e painel da conversa.

## Ligar numa conta

1. Super Admin → conta → **Captador integration enabled**. Chave `accounts.settings.captador_integration`; desligada, o app some da lista, `/spx/captador/*` responde 401 e nenhum evento sai.
2. Integrações → Captador, com os campos:
   - `captador_url`: endereço base, por exemplo `https://captador.spx.ia.br`. O hook só aceita `https://`. O fork só chama (painel e eventos) hosts da variável `CAPTADOR_HOSTS_PERMITIDOS` (lista separada por vírgula; padrão `captador.spx.ia.br`), na porta 443, sem seguir redirecionamento e nunca para IP interno. Fora disso, o painel mostra "O Captador não respondeu" e os eventos não saem;
   - `instance_key`: chave dada pela tela Conexões do Captador (`[A-Za-z0-9_-]`);
   - `shared_secret`: no mínimo 32 caracteres, gerado no Captador. Fica cifrado no JSONB e é somente escrita: a API devolve apenas `shared_secret_configured`; na edição, vazio mantém o atual;
   - `allowed_inbox_ids`: CSV das caixas liberadas; vazio libera nenhuma. Vale para abrir conversa e para os eventos das conversas sem carimbo (ver Eventos);
   - `allow_login`: marcar só na conta de login.
3. Ao criar o hook, o `Crm::SetupJob` cria a label `captador` e os atributos `cnpj` e `captador_lead_id` (contato) e `captador_lead_id` (conversa).

Os passos 1 e 2 também podem ser feitos pelo próprio Captador, de uma vez, pela rota de ativação da Frota (ver Frota).

Sem migração: tudo vive em `accounts.settings`, `integrations_hooks.settings` e no Redis.

## Assinatura (Captador → ChatSPX)

| Header | Valor |
|---|---|
| `X-Captador-Account` | `account_id` da conta no ChatSPX |
| `X-Captador-Timestamp` | epoch em segundos; fora de ±300 s → 401 |
| `X-Captador-Signature` | v1: `sha256=<hex>`; v2: `v2=<hex>` |
| `Idempotency-Key` | obrigatório em `leads`; 8 a 128 caracteres `[A-Za-z0-9_-]` (UUID serve) |

O receptor aceita os dois formatos. A v1 permanece `HMAC_SHA256(shared_secret, "<ts>.<MÉTODO>.<path?query>.<corpo bruto>")`. A v2 é o HMAC-SHA256 destas linhas UTF-8, unidas por LF e sem LF final:

```text
v2
<timestamp>
<MÉTODO em maiúsculas>
<path?query exatamente recebido>
<X-Captador-Account>
idempotency-key:<Idempotency-Key ou vazio>
<SHA-256 hex minúsculo do corpo bruto>
```

O Captador só envia v2 com `ASSINATURA_V2=true`. Qualquer falha de assinatura, conta sem a chave ou hook desligado: `401` sem corpo. Uma assinatura de mutação aceita só pode ser usada uma vez em 10 minutos; os erros de negócio vêm como `{ "error_code": "...", "meta": {...} }`.

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
| 401 | `invalid_credentials` | senha errada, e-mail inexistente, usuário inativo, fora da conta ou código 2FA errado (genérico) |
| 401 | `mfa_token_invalid` | `mfa_token` inválido ou vencido (5 min): recomeçar pelo e-mail e senha |
| 403 | `saml_required` | usuário SAML |
| 403 | `login_not_allowed` | hook sem `allow_login` |
| 429 | — | 10 senhas por e-mail/15 min; 10 códigos por `mfa_token`/min e por usuário/15 min |

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

`Spx::CaptadorListener` → `WebhookJob` → `POST <captador_url>/webhooks/chatspx/<instance_key>`, com `X-Chatwoot-Delivery`, `X-Chatwoot-Timestamp` e `X-Chatwoot-Signature` (`sha256=` + HMAC de `"<ts>.<corpo>"` com o `shared_secret`). Eventos continuam em v1 nesta fase; o Captador deduplica também assinatura + timestamp. São 5 tentativas quando o destino não recebeu. Antes da fila, o fork resolve o host e recusa qualquer IP interno.

Quais conversas geram evento (sempre com a chave da conta ligada e o hook ativo):
- **com o carimbo** `custom_attributes.captador_lead_id`: todas, de qualquer caixa;
- **sem o carimbo** (aberta direto no ChatSPX, ou nova depois de resolvida): só as de caixa listada em `allowed_inbox_ids`. Lista vazia libera nenhuma, a mesma regra do `POST leads` e do catálogo. O Captador liga a conversa ao lead pelo telefone do contato, que vem em `conversation.meta.sender.phone_number` (E.164 ou `null`), com a caixa em `conversation.inbox_id` (nos eventos de conversa, `meta.sender` e `inbox_id` ficam na raiz).

Os filtros por evento da tabela abaixo valem para os dois casos. Nota privada nunca sai, e o payload da conversa só traz mensagens públicas. `conversation_created` não é enviado: o Captador liga pela primeira `message_created`.

| `event` | Quando | Payload |
|---|---|---|
| `message_created` | lead escreveu (`incoming`) ou alguém respondeu (`outgoing`, não privada) | `message.webhook_data`; recusa do lead vem com `captador: { "opt_out": true }` |
| `message_updated` | mudou `status` (`delivered`, `read`, `failed`) | `message.webhook_data` + `changed_attributes` (`[{ "status": { "previous_value": "sent", "current_value": "failed" } }]`); motivo da falha em `content_attributes.external_error` |
| `conversation_status_changed` | resolvida, reaberta, adiada | `conversation.webhook_data` + `changed_attributes` |
| `conversation_updated` | mudou `assignee_id` ou `team_id`, inclusive no mesmo save que muda o status (aí chega junto com um `conversation_status_changed`) | `conversation.webhook_data` + `changed_attributes` |

A 1ª mensagem aberta pelo próprio Captador também gera `message_created` (`outgoing`): ela traz `additional_attributes.echo_id = "captador:<Idempotency-Key>"`.

## `GET /spx/captador/v1/catalogo`

Assinado como os outros (corpo vazio na assinatura). Lista as caixas de WhatsApp da conta, liberadas ou não, sem nenhuma credencial (`provider_config`, `hmac_token`, `namespace` do modelo e `webhook_url` não saem).

```json
200 { "account": { "id": 1, "name": "Simplex" },
      "inboxes": [
        { "id": 91, "name": "Comercial", "channel_type": "Channel::Whatsapp", "official": true, "provider": "whatsapp_cloud",
          "phone_number": "+5565…", "read_only": false, "allowed": true,
          "templates": [ { "name": "prospeccao_b2b_v1", "language": "pt_BR", "category": "MARKETING", "components": […] } ] },
        { "id": 92, "name": "WAHA Vendas", "channel_type": "Channel::Api", "official": false, "provider": "waha",
          "phone_number": null, "read_only": false, "allowed": false, "templates": [] } ],
      "teams": [ { "id": 7, "name": "comercial" } ],
      "agents": [ { "id": 42, "name": "Maria", "available_name": "Maria", "email": "…", "role": "agent", "inbox_ids": [92] } ] }
```

- `official: true` → só modelo aprovado (`templates` traz só os `APPROVED`); `official: false` → texto livre (WAHA quando `provider = "waha"`; `"api"` é caixa API sem sessão WAHA).
- `allowed` reflete `allowed_inbox_ids` do hook: o `POST leads` recusa as outras com 422 `channel_not_allowed`.
- `inbox_ids` do agente: caixas por onde ele pode enviar (administrador: todas as listadas; agente: as de que é membro). As outras dão 403 `inbox_access_denied` no `POST leads`.
- A lista de agentes também serve para desativar no Captador quem saiu da conta.

## `GET /spx/captador/v1/conversas` (reconciliação)

`?lead_ids=a,b&contact_ids=5012,5013&since=2026-09-27T10:00:00Z`. Assinado com o `path?query` exatamente como enviado.

- `lead_ids`: casa `custom_attributes.captador_lead_id` da conversa. `contact_ids`: todas as conversas do contato, porque a resposta de um lead depois de a conversa ser resolvida abre conversa nova sem o carimbo. No máximo 100 ids somando os dois.
- `since` (opcional, ISO 8601 ou epoch em segundos): só as conversas que mudaram depois do instante, seja a conversa, o `last_activity_at` ou qualquer mensagem dela (status de entrega). Use o `server_time` da resposta anterior como o próximo `since`.
- No máximo 500 conversas por chamada, em ordem de id.

```json
200 { "server_time": "2026-09-27T11:00:00.123Z",
      "conversations": [
        { "conversation_id": 1234, "contact_id": 5012, "inbox_id": 91, "lead_id": "b3f1…", "status": "open",
          "assignee": { "id": 42, "name": "Maria" }, "team": { "id": 7, "name": "comercial" },
          "last_activity_at": "…", "last_incoming_at": "…",
          "captador_message": { "id": 99881, "status": "failed", "created_at": "…", "external_error": "131026: …" },
          "opt_out": false } ] }
```

- `lead_id` vem da conversa ou, sem o carimbo, do contato. `captador_message` é a última mensagem aberta pelo Captador na conversa (`echo_id` `captador:…`), ou `null`. `opt_out` é a supressão de marketing do contato.
- Erros 422: `ids_required`, `too_many_ids`, `invalid_since`.

## Painel da conversa (ChatSPX → Captador)

O painel "Lead no Captador" fica na lateral da conversa, nas contas com o app ligado. O navegador só fala com o ChatSPX (`GET`/`POST /api/v1/accounts/:account_id/integrations/captador/{lead,mover}`, com a sessão normal): sem iframe, sem CORS e sem cookie de terceiro, o que funciona no Safari do iPhone.

O proxy do fork:
- aplica a policy da conversa, a guarda de time e o isolamento por agente;
- tira o `lead_id` da conversa (ou do contato), nunca do navegador;
- sem `captador_lead_id`, não chama o Captador.

**O Captador precisa atender duas rotas:**
- `GET <captador_url>/integracao/chatspx/v1/leads?contact_id=<id>&conversation_id=<display_id>`, com as chaves da query em ordem alfabética, como o fork envia;
- `POST <captador_url>/integracao/chatspx/v1/leads/<lead_id>/mover`, com corpo `{"etapa_id": 3}`.

| Header | Valor |
|---|---|
| `X-Captador-Instancia` | `instance_key` do hook |
| `X-Chatspx-Usuario` | id do usuário do ChatSPX que está no painel (o mesmo `user.id` do login) |
| `X-Captador-Timestamp` | epoch em segundos (janela de ±300 s) |
| `X-Captador-Assinatura` | v1: `sha256=<hex>`; v2: `v2=<hex>` |

- A v1 usa `"<ts>.<MÉTODO>.<path?query>.<corpo>"`. A v2 usa as mesmas sete linhas descritas acima, trocando o identificador por `X-Captador-Instancia` e a linha de cabeçalho por `x-chatspx-usuario:<X-Chatspx-Usuario>`.
- O fork continua enviando v1; `CAPTADOR_ASSINATURA_V2=true` vira painel GET/POST para v2. No GET, o corpo é vazio (hash SHA-256 da string vazia).
- Resposta 200 (nos dois): `Nivel2Lead` = `{ lead: Lead | null, empresa: EmpresaResumo | null, etapas: [Etapa], url: string | null, pode_mover: boolean }`.
  - `empresa` e `pode_mover` são **acréscimos ao rascunho**, opcionais. `empresa` é o resumo da Receita que o painel mostra; `pode_mover: false` esconde "Mover para…" (sem o campo, o botão aparece).
  - O `mover` devolve o lead já na etapa nova.
- Campos que o painel usa:
  - `lead`: `nome`, `cnpj`, `etapa_id`, `parado`, `perdido.motivo` (`pediu_nao_contatar` vira "Não contatar"), `dono.nome`, `origem`, `ultima_atividade_em` e `municipio`;
  - `empresa`: `situacao.descricao`, `cnae_principal.descricao`, `porte.descricao`, `municipio.{nome,uf}`, `data_abertura` e `nao_contatar`;
  - `etapas[]`: `id`, `nome` e `ativa` (o menu lista as ativas, menos a atual);
  - `url`, que é o link do "Abrir no Captador", aberto em nova aba.
- Erros:
  - 403 `application/problem+json` com `codigo: "acesso_pendente"`: o painel mostra "Peça acesso ao Captador para ver este lead";
  - 404 ou `lead: null`: "Esse contato não veio do Captador";
  - outro 4xx no mover: o painel mostra o `detail` no aviso, e o proxy repassa o status e o corpo como vieram;
  - 401, 5xx, queda ou mais de 3 s: o proxy responde 502 `captador_unavailable` e o painel mostra "O Captador não respondeu agora", com "Tentar de novo".

## Frota (Captador → ChatSPX, por instalação)

Serve para o Captador listar as contas de cada instalação e ligar a integração numa delas, sem passar pelo Super Admin e por Integrações.

**Autenticação:** `Authorization: Bearer <CAPTADOR_FROTA_TOKEN>`.
- O token é aleatório, um por instalação, com no mínimo 32 caracteres, e fica no `.env` dela. A comparação é em tempo constante.
- Sem a variável, ou com menos de 32 caracteres, as duas rotas respondem `404`, como se não existissem.
- Token errado ou ausente: `401` sem corpo.
- Sem sessão de usuário e sem CSRF. O Rack::Attack limita a 30 pedidos por minuto por IP (`captador_frota/ip`).
- O token vale para a instalação inteira. O `shared_secret` de cada hook continua assinando o resto deste contrato.

### `GET /spx/captador/v1/frota/contas`

Todas as contas da instalação, em ordem de id. `servidor` é o host do `FRONTEND_URL`. Nunca sai o `shared_secret` nem token algum.

```json
200 { "servidor": "chat.simplexsolucoes.com.br",
      "contas": [
        { "id": 3, "nome": "Simplex", "status": "active", "criada_em": "2025-04-02T13:10:00Z", "usuarios": 12,
          "caixas": [ { "id": 2, "nome": "Comercial", "canal": "Channel::Whatsapp" } ],
          "admins": [ { "nome": "Maria", "email": "maria@…" } ],
          "captador": { "integracao_habilitada": true,
                        "hook": { "id": 7, "status": "enabled", "captador_url": "https://captador.spx.ia.br",
                                  "instance_key": "inst-1", "allowed_inbox_ids": [2], "allow_login": true } } } ] }
```

- `status`: `active` ou `suspended`.
- `usuarios`: quantos usuários a conta tem, de qualquer papel.
- `caixas`: todas, de qualquer canal. O hook só aceita `Channel::Whatsapp` e `Channel::Api`.
- `captador.integracao_habilitada` é a chave `accounts.settings.captador_integration`. `captador.hook` é `null` se a conta nunca teve o hook.

### `POST /spx/captador/v1/frota/contas/:id/ativar`

```json
{ "captador_url": "https://captador.spx.ia.br", "instance_key": "inst-1", "shared_secret": "…(32 ou mais)",
  "allowed_inbox_ids": [2, 5], "allow_login": true }
200 → o mesmo objeto de conta do GET, sem segredo
```

- Faz os passos 1 e 2 de "Ligar numa conta" numa transação: liga a chave da conta e cria o hook `captador` habilitado, ou atualiza o que já existe (a conta tem no máximo um).
- É idempotente: repetir o pedido deixa a conta no mesmo estado.
- Os campos passam pelo mesmo schema do `apps.yml` que a tela de Integrações usa: `captador_url` só `https://`, `instance_key` `[A-Za-z0-9_-]`, `shared_secret` com 32 ou mais caracteres e `allow_login` booleano.
- `allowed_inbox_ids` aceita uma lista de ids ou `"todas"`. `[]` libera nenhuma.
  - `"todas"` vira as caixas `Channel::Whatsapp` e `Channel::Api` da conta naquele momento.
  - Caixa criada depois não entra sozinha: é preciso ativar de novo.
- Campo ausente mantém o valor atual do hook.
  - Num hook que já existe, `shared_secret` ausente ou vazio mantém o segredo atual.
  - Hook novo exige `captador_url`, `instance_key` e `shared_secret`.
- Hook novo dispara o `Crm::SetupJob` (label `captador` e atributos), como na tela.

| HTTP | `error_code` | Quando |
|---|---|---|
| 404 | — | conta inexistente (ou a variável não está definida) |
| 422 | `configuracao_invalida` (+ `meta.erros`) | campo fora do schema; caixa de outra conta ou de outro canal; `allowed_inbox_ids` que não é lista nem `"todas"`; `shared_secret` que começa com o prefixo de valor cifrado. Nada é gravado. |

**Auditoria:**
- Cada ativação grava um registro em `audits`: `auditable_type` `Integrations::Hook`, `comment` `captador.frota.ativar`, o IP em `remote_address` e o estado do hook sem o segredo. A mudança na conta também gera o registro automático de sempre.
- No `production.log` fica a linha `[Captador][frota] ativar conta=… hook=… caixas=… allow_login=… ip=… agente=…`.
