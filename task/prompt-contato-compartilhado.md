# Prompt de execução — Visão rica de contatos recebidos no ChatSPX

> Cole este arquivo inteiro como prompt para executar a tarefa.

## 🎯 Objetivo
Ter uma **visão melhor dos contatos recebidos** dentro do chat do ChatSPX. Hoje, quando alguém
**compartilha um contato** numa conversa, ele aparece como uma bolha genérica de download
(`vcard-1.vcf`), sem nome, foto ou ações. O objetivo é exibir um **card rico** (avatar + nome +
empresa opcional + botões de ação), no estilo do card de contato do WhatsApp, para que o agente
entenda e aja sobre o contato sem precisar baixar e abrir o `.vcf`.

**Antes (atual):** bolha "Contato(s) compartilhado(s) → vcard-1.vcf" baixável.
**Depois (alvo):** card com avatar, nome em destaque, empresa (se houver), telefone formatado e
botões "Salvar contato" / "Conversar".

## 🔎 Causa-raiz (já investigada — não reinvestigar do zero)
- O Chatwoot **já possui** o card de contato pronto: `Contact.vue` → `BaseAttachment.vue`, acionado
  quando `attachment.file_type === 'contact'`.
  - Decisão de render: `app/javascript/dashboard/components-next/message/Message.vue:421-435`
  - Card: `app/javascript/dashboard/components-next/message/bubbles/Contact.vue`
  - Base visual: `app/javascript/dashboard/components-next/message/bubbles/BaseAttachment.vue`
- O canal **oficial** WhatsApp Cloud já produz `:contact` corretamente, mapeando pelo tipo da
  mensagem (`type == 'contacts'`): `app/services/whatsapp/incoming_message_base_service.rb:70-79` e
  `:198-215` (popula `meta: { firstName, lastName }` + `fallback_title: phone`).
- **O bug está no canal não-oficial (WAHA → API pública de mensagens):** o `.vcf` recebido é
  classificado apenas por content-type em `app/helpers/file_type_helper.rb:3-9`, que **NÃO** reconhece
  `text/vcard` / `text/x-vcard` / `.vcf` → cai em `:file` → renderiza a bolha de download.
  - Controller de ingestão: `app/controllers/public/api/v1/inboxes/messages_controller.rb:38-48`
    (`build_attachment` usa `helpers.file_type(content_type)`).
- **Não existe parser de vCard** no projeto (há apenas um *builder* ad-hoc em
  `app/services/waha/api_service.rb:146-157`). Nenhuma gem de vCard no Gemfile.
- Serializer que envia o contato ao frontend: `app/models/attachment.rb:157-167` (`contact_metadata`).

## 🛠️ Escopo da implementação (branch `nicolas`)

### 1. Parser de vCard (backend, sem gem)
- Criar `app/services/vcard/parser_service.rb` que recebe o texto de um `.vcf` e extrai:
  - `FN` / `N` → nome (firstName, lastName, full_name)
  - `TEL` → telefone (1º número; tolerar múltiplos `TEL`)
  - `ORG` → empresa (organization)
  - opcional: `EMAIL`, `PHOTO`
- Robusto a vCard **2.1 / 3.0 / 4.0**, quebras `\r\n`, separadores `;` em `N`, acentuação e
  parâmetros (`TEL;TYPE=CELL:` etc.). Cobrir com spec.

### 2. Ingestão — classificar vCard como contato (núcleo do fix)
- Em `app/controllers/public/api/v1/inboxes/messages_controller.rb:38-48` (`build_attachment`),
  detectar vCard por **content-type** (`text/vcard`, `text/x-vcard`, `application/vcard`) **ou**
  **extensão** `.vcf` no nome do arquivo (cobre o caso `application/octet-stream`).
- Quando for vCard: parsear e criar o attachment com:
  - `file_type: :contact`
  - `fallback_title: <telefone>`
  - `meta: { firstName, lastName, organization, full_name }`
- **Centralizar** a regra "vcf→contact" num único ponto reutilizável (helper/service) para não
  duplicar lógica entre canais.
- Manter o arquivo `.vcf` anexado como fallback de download apenas se for barato; o render principal
  passa a ser o card.
- **Não** alterar o canal oficial WhatsApp Cloud nem o Telegram (`incoming_message_service.rb:180-192`
  já mapeia `:contact`) — apenas validar que continuam funcionando.

### 3. Frontend — elevar o card ao visual alvo
- Em `bubbles/Contact.vue` e/ou `bubbles/BaseAttachment.vue` (ou um novo `RichContact.vue`):
  - **Avatar**: usar `PHOTO` do vCard se existir; senão inicial do nome / ícone atual.
  - **Nome** em destaque; **empresa** (`meta.organization`) como subtítulo quando presente.
  - **Telefone** formatado.
  - **Botões de ação** (padrão `action`/slots do `BaseAttachment`, 1–2 botões):
    - **Salvar contato** — já existe (`addContact`, cria/abre o contato).
    - **Conversar** — abrir/criar conversa com esse contato.
    - ("Mostrar empresa" só se houver `ORG`; tratar como opcional/condicional.)
  - Preservar tema (classes `n-*`) e acessibilidade.

### 4. i18n
- Reusar `CONVERSATION.SAVE_CONTACT` e `CONVERSATION.SHARED_ATTACHMENT.CONTACT`.
- Adicionar chaves novas (ex.: `CONVERSATION.START_CONVERSATION`) em **en** e **pt_BR**:
  `app/javascript/dashboard/i18n/locale/en/conversation.json` e `.../pt_BR/conversation.json`.

### 5. Testes
- Spec do parser de vCard: formatos 2.1/3.0/4.0, com/sem `ORG`, múltiplos `TEL`, acentos.
- Spec de ingestão: POST na API pública com `.vcf` em `text/vcard` **e** em
  `application/octet-stream` + nome `.vcf` → attachment `file_type: contact` com `meta` e
  `fallback_title` corretos.
- Fixtures de frontend: ajustar `fixtures/textWithMedia.js:103-117` (contact attachment) para incluir
  `meta.organization` e validar o novo render.

## ⚠️ Decisões a confirmar antes de codar
1. **Múltiplos contatos num único `.vcf`** (vários `BEGIN:VCARD`): criar 1 card por contato
   (consistente com o canal oficial, que gera 1 mensagem por telefone) **ou** 1 card por arquivo na v1?
2. **Foto (`PHOTO` base64)**: incluir no `meta` (pode inflar o JSON) ou ignorar fotos grandes na v1?

## 🚫 Fora de escopo
- **Backfill**: contatos já recebidos como `:file` continuam como download; não reprocessar.

## 🚀 Deploy (padrão staging `nicolas`)
- Build de assets (`assets:precompile`, zero-downtime) + `sudo /bin/systemctl restart chatwoot.target`.
- Validar com um contato real **recebido via WAHA** e também com o seletor de **compartilhar contato**
  (envio), confirmando que ambos renderizam o card rico.
