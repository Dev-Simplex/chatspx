# Prompt de implementação — "Mensagem apagada" no estilo "Editada"

## Objetivo
Quando um agente apaga uma mensagem (outgoing), ela deve ficar visualmente parecida com uma
mensagem **editada**: o balão mostra um placeholder ("Mensagem apagada", estilo atenuado/tachado)
com um **badge clicável "🗑 Apagada"**. Ao clicar no badge, abre um card popup
"MENSAGEM ORIGINAL" mostrando o conteúdo original + "Apagada por {nome}" + data — exatamente como
o card de edição já faz hoje.

Espelhar 1:1 a feature de **edição** que já existe. Além disso, o delete deve **propagar pro
WhatsApp (WAHA) como delete-for-everyone**, igual à edição propaga a edição.

## Decisões de produto (já confirmadas)
1. **Visibilidade:** todos os agentes que veem a conversa podem clicar e ver o original (igual ao Editado).
2. **Escopo:** apaga interno (soft-delete) **e** propaga pro WhatsApp via WAHA.
3. **Balão:** placeholder "Mensagem apagada" atenuado + badge "🗑 Apagada"; clicar revela o original.

## A peça central que muda hoje
Hoje o destroy **destrói** o conteúdo original:
`app/controllers/api/v1/accounts/conversations/messages_controller.rb` (~linha 73)
```ruby
message.update!(content: I18n.t('conversations.messages.deleted'),
                content_type: :text,
                content_attributes: { deleted: true }) # ← zera os outros atributos e perde o original
message.attachments.destroy_all
```
Precisamos **preservar** o original em `previous_content` e gravar `deleted_at`/`deleted_by`
(merge, sem zerar os outros atributos) — espelho do `UpdateContentService#persist_edit`.

---

## Backend

### 1. `Waha::ApiService` — adicionar `delete_message`
Arquivo: `app/services/waha/api_service.rb` (logo após `edit_message`, ~linha 56).
O helper `delete()` e o `encode_path_segment()` já existem.
```ruby
def delete_message(session_name, chat_id, message_id)
  delete("/api/#{session_name}/chats/#{encode_path_segment(chat_id)}/messages/#{encode_path_segment(message_id)}")
end
```
Endpoint WAHA (delete-for-everyone): `DELETE /api/{session}/chats/{chatId}/messages/{messageId}`.

### 2. Novo serviço `Messages::DeleteContentService`
Arquivo: `app/services/messages/delete_content_service.rb`.
**Clonar a estrutura de `Messages::UpdateContentService`** (mesmas validações, mesma resolução de
`waha_message_id` via `source_id` → fallback lookup, mesmo `chat_id`, mesmo tratamento de erro WAHA).
Reaproveitar o máximo possível — considere extrair os helpers comuns
(`resolve_waha_message_id`, `find_waha_message_id_from_api`, `chat_id`, `inbox`, `waha_inbox?`)
para um módulo concern compartilhado entre os dois serviços, evitando duplicação.

Diferenças do edit:
- Não recebe `new_content`.
- `validate!`: outgoing? + não já `deleted` + inbox WAHA + sender é o `Current.user`.
  (Manter o bloqueio de `input_nps`/`input_csat` que hoje vive no controller.)
- Chama `Waha::ApiService.new.delete_message(session, chat_id, waha_message_id)`.
- `persist_delete`:
```ruby
def persist_delete(waha_message_id)
  previous = @message.content
  actor = Current.user
  attrs = {
    content: I18n.t('conversations.messages.deleted'),
    content_type: :text,
    content_attributes: @message.content_attributes.merge(
      'previous_content' => previous,
      'deleted' => true,
      'deleted_at' => Time.zone.now.iso8601,
      'deleted_by' => actor ? { 'id' => actor.id, 'name' => actor.name } : nil
    )
  }
  attrs[:source_id] = waha_message_id if @message.source_id.blank? && waha_message_id.present?
  @message.update!(attrs)
  @message.attachments.destroy_all
end
```
Ordem do `perform`: `validate!` → `resolve_waha_message_id` → `delete_on_waha` → `persist_delete`.
Se a inbox **não** for WAHA (ou a mensagem não tiver chegado a ter id no WhatsApp), o serviço deve
ainda assim fazer o soft-delete local com a metadata nova — não quebrar canais não-WAHA.
(Decisão: para WAHA, propaga; para os demais canais, só local. Modelar como o edit faz a checagem
de canal, mas sem abortar o delete local em canais sem suporte.)

### 3. Controller `destroy`
Arquivo: `app/controllers/api/v1/accounts/conversations/messages_controller.rb` (~linha 73).
Substituir o corpo do `update!` inline pela chamada ao serviço, mantendo o guard de NPS/CSAT
e o rescue de erro WAHA (mesmo padrão `rescue ... render_could_not_create_error` do `update`).
```ruby
def destroy
  if message.content_type.in?(%w[input_nps input_csat])
    return render json: { error: I18n.t('conversations.messages.undeletable') }, status: :unprocessable_entity
  end
  Messages::DeleteContentService.new(message).perform
  @message = message
rescue ArgumentError => e
  render_could_not_create_error(e.message)
end
```
Conferir o template de resposta do destroy (jbuilder) — precisa renderizar o message atualizado com
`content_attributes` completo (igual ao update.json.jbuilder), para o front receber `deleted_by`,
`deleted_at`, `previous_content`.

### 4. i18n backend
`config/locales/{en,pt_BR}.yml` — a chave `conversations.messages.deleted` já existe; confirmar o
texto PT-BR ("Mensagem apagada").

---

## Frontend

### 5. Badge "🗑 Apagada" no balão
Arquivo: `app/javascript/dashboard/components-next/message/Message.vue`.
Hoje (~linhas 904-929) há o bloco do badge "Editado" com `v-if="contentAttributes.edited && !isEditing"`,
ícone `i-lucide-pencil-line`, texto `CONVERSATION.EDIT_HISTORY.BADGE`, que abre `MessageEditHistory`.
Já existe `isMessageDeleted` (~linha 497 = `contentAttributes?.deleted`).

Adicionar um badge irmão para deleção:
- `v-if="isMessageDeleted"`, ícone `i-lucide-trash-2` (ou `i-lucide-trash`).
- Texto `CONVERSATION.DELETE_HISTORY.BADGE` ("Apagada").
- Ao clicar, abrir o popup de histórico de deleção (passar o `getBoundingClientRect()` do trigger,
  mesma lógica de posicionamento do edit).
- O balão de texto já mostra o placeholder "Mensagem apagada" (vem do backend). Aplicar estilo
  atenuado/tachado ao conteúdo quando `isMessageDeleted` (cinza/itálico), seguindo o tom das imagens.

### 6. Novo popup `MessageDeleteHistory.vue`
Arquivo: `app/javascript/dashboard/components-next/message/MessageDeleteHistory.vue`.
**Clonar `MessageEditHistory.vue`** trocando os labels e as fontes de dado:
- Título: `CONVERSATION.DELETE_HISTORY.TITLE` ("Mensagem original").
- Conteúdo: `contentAttributes.previous_content` (fallback `NO_CONTENT`).
- Rodapé: `CONVERSATION.DELETE_HISTORY.DELETED_BY` ("Apagada por {name}") usando
  `contentAttributes.deleted_by.name`, e a data `contentAttributes.deleted_at`
  formatada `dd/MM/yyyy HH:mm` (mesmo helper do edit).
Mesma posição/estilo/clique-fora do popup de edição.

### 7. i18n frontend
`app/javascript/dashboard/i18n/locale/{en,pt_BR}/conversation.json`.
Espelhar o bloco `EDIT_HISTORY` com um novo `DELETE_HISTORY`:
```jsonc
// pt_BR
"DELETE_HISTORY": {
  "BADGE": "Apagada",
  "TITLE": "Mensagem original",
  "NO_CONTENT": "(sem conteúdo)",
  "DELETED_BY": "Apagada por {name}"
}
// en
"DELETE_HISTORY": {
  "BADGE": "Deleted",
  "TITLE": "Original message",
  "NO_CONTENT": "(no content)",
  "DELETED_BY": "Deleted by {name}"
}
```

### 8. Store / API
O fluxo `deleteMessage` (actions.js) já chama `MessageApi.delete` e faz `commit(ADD_MESSAGE, data)`
com o message atualizado — nada a mudar, desde que o backend retorne o message com a nova metadata.
Confirmar que o `DELETE_CONVERSATION_ATTACHMENTS` continua removendo os anexos da UI.

---

## Testes
- **`spec/services/messages/delete_content_service_spec.rb`** (novo): espelhar
  `spec/services/messages/update_content_service_spec.rb` — sucesso WAHA (espera
  `delete_message` com session/chat_id/message_id), persistência de
  `deleted/deleted_at/deleted_by/previous_content`, bloqueio de mensagem já apagada,
  bloqueio para não-sender, e soft-delete local em inbox não-WAHA.
- **Request spec** do `destroy` no messages_controller: garantir 200 + content_attributes corretos,
  e o guard NPS/CSAT (422).
- Front: build verde (`pnpm build` / vite). Validar visualmente no staging nicolas.

## Validação manual (staging nicolas)
1. Apagar uma mensagem outgoing de WhatsApp → balão vira "Mensagem apagada" atenuado + badge "🗑 Apagada".
2. Clicar no badge → card "MENSAGEM ORIGINAL" com o texto original, "Apagada por {nome}" e data.
3. Conferir no celular que a mensagem foi revogada (delete-for-everyone) no WhatsApp.
4. Inbox não-WAHA: apagar ainda funciona localmente (sem erro), com badge e card.

## Fora de escopo / cuidado
- Retroativo: mensagens já apagadas antes desta feature não têm `previous_content` → o card mostra
  `NO_CONTENT`. Não tentar recuperar.
- Não mexer no comportamento de apagar de outros tipos (activity/template) além do já existente.
- Seguir a diretriz de segurança: nada destrutivo na frota; validar no staging antes.
