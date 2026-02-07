# Normalização LID WAHA (WhatsApp)

Quando o Chatwoot usa uma inbox conectada via **WAHA** (WhatsApp HTTP API), as mensagens do usuário podem chegar com identificador **LID** (`@lid`) em vez do número de telefone (`@c.us`). O sistema normaliza LID para número para evitar conversas e contatos duplicados.

## O que é LID

O WhatsApp passou a usar **LID** (Linked ID) para privacidade. Um mesmo contato pode aparecer como número (`5511999999999@c.us`) ou como LID (ex.: `12345@lid`). O Chatwoot usa a API WAHA para obter o número a partir do LID e manter uma única conversa por contato.

## Requisitos para a normalização funcionar

1. **Variáveis de ambiente**
   - `WAHA_API_URL`: URL base da API WAHA (ex.: `http://localhost:3000`).
   - `WAHA_API_KEY`: Chave de API, se a WAHA exigir autenticação.

2. **Inbox**
   - A inbox do tipo API deve ter **`waha_session_name`** preenchido (nome da sessão WAHA vinculada à caixa). Isso é configurado ao criar/conectar uma conexão WAHA no Chatwoot.

3. **Mapeamento LID → número na WAHA**
   - A WAHA precisa conhecer o mapeamento LID → número. Ele é populado conforme o uso (conversas, grupos, contatos).
   - Na documentação da WAHA, **"Get all groups"** / **"Refresh groups"** podem ajudar a popular o mapeamento de LIDs.
   - Referência: [WAHA – Contacts / LIDs](https://waha.devlike.pro/docs/how-to/contacts/).

## Comportamento no Chatwoot

- Ao receber `contact_id` ou `source_id` terminando em `@lid`, o controller público chama a WAHA:
  1. **GET /api/{session}/lids/{lid}** para obter o número (`pn`) do LID.
  2. Se `pn` vier vazio, é usada a lista **GET /api/{session}/lids** como fallback para localizar o LID no array.
- Se o número for encontrado:
  - O contato/conversa é identificado pelo número (e pelo 9 adicional para números brasileiros, quando aplicável).
  - Se já existir um contact_inbox com esse LID (conversa “órfã”), ele é unificado ao contato por número (atualização ou merge).
- Se o número **não** for encontrado (WAHA retorna `pn: null` ou erro):
  - Um aviso é registrado em log: `"WAHA LID resolved to null for ..."`.
  - O contato/conversa segue com o LID; pode aparecer “sem número” e, em alguns casos, duplicar se o mesmo cliente já tiver conversa pelo número.

## Número brasileiro (9)

O Chatwoot aplica `Contacts::BrazilPhoneNormalizer` aos números obtidos da WAHA, incluindo a adição do nono dígito quando for número móvel brasileiro (+55).

## Arquivos principais

- **Serviço WAHA:** `app/services/waha/api_service.rb`  
  - `get_lid_phone_number(session_name, lid)`  
  - `get_lids_list(session_name, limit:, offset:)` (fallback)
- **Controller público:** `app/controllers/public/api/v1/inboxes_controller.rb`  
  - `normalize_waha_contact_params`  
  - `resolve_lid_to_pn`  
  - `merge_waha_lid_contact_inbox_to_pn`
