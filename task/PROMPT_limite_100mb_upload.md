# Prompt: erro visível ao tentar enviar mídia acima de 100MB

## Objetivo
Hoje, quando um usuário tenta enviar uma mídia maior que 100MB numa conversa, o envio
**falha silenciosamente** (sem feedback). Quero que apareça um **erro claro e visível** para
o usuário, e que o limite de **100MB seja um teto rígido** (hard cap) aplicado em **todos os
canais** e em **todos os pontos de entrada** de anexo, tanto no frontend quanto no backend.

## Contexto / causa-raiz (já investigado — confirme antes de mexer)
1. **Backend só valida tamanho no WebWidget.** Em `app/models/attachment.rb`, o método
   `should_validate_file?` (≈ linha 169) retorna cedo a menos que
   `message.inbox.channel_type == 'Channel::WebWidget'`. Para WhatsApp/WAHA/API **não há
   validação de tamanho nenhuma** → o anexo é salvo e o envio falha depois, sem erro pro usuário.
   Essa é a principal causa da falha silenciosa.
2. **Frontend valida, mas o teto é o limite da instalação/canal.**
   - `app/javascript/dashboard/composables/useFileUpload.js` → `maxSizeFor()` /
     `checkFileSizeLimit()` / `alertOverLimit()`.
   - `app/javascript/dashboard/mixins/fileUploadMixin.js` (implementação paralela legada —
     **precisa ser corrigida junto**, há componentes usando cada uma).
   - Default `MAXIMUM_FILE_UPLOAD_SIZE = 40` (`config/installation_config.yml` ≈ linha 92).
     Se a instalação subiu esse valor acima de 100MB, arquivos grandes passam no frontend e
     caem na falha silenciosa do backend.
3. **Pontos de entrada de anexo no `ReplyBox.vue`** (todos roteiam para `onFileUpload`, confirmar):
   - file picker (`ReplyBottomPanel.vue` → input `#conversationAttachment`)
   - drag-drop: `handleGlobalDroppedFile()` (≈ linha 891)
   - paste: `onPaste()` (≈ linha 1206)
   - gravador de áudio: `onFinishRecorder()` (≈ linha 2028)
4. Helpers/constantes: `app/javascript/shared/helpers/FileHelper.js`
   (`DEFAULT_MAXIMUM_FILE_UPLOAD_SIZE`, `checkFileSizeLimit`, `formatBytes`, `fileSizeInMegaBytes`).
5. Padrão de erro ao usuário: `useAlert()` (toast) — `app/javascript/dashboard/composables/index.js`.
6. i18n: `app/javascript/dashboard/i18n/locale/en/conversation.json`
   (`FILE_SIZE_LIMIT`, `FILE_TYPE_NOT_SUPPORTED` ≈ linhas 447-448).

## Requisitos
1. **Teto rígido de 100MB** aplicado independentemente do canal e do `maximumFileUploadSize`
   configurado. O limite efetivo do frontend deve ser `min(limite_atual, 100MB)`.
   - Crie uma constante única e reutilizável (ex.: `HARD_MAXIMUM_FILE_UPLOAD_SIZE = 100` em
     `FileHelper.js`) e use nos dois caminhos (composable + mixin). Não duplicar o número “100”
     espalhado pelo código.
2. **Erro visível e claro** quando o arquivo exceder o teto, em **todos** os pontos de entrada
   (picker, drag-drop, paste, áudio). Reutilize o padrão `useAlert` já existente; a mensagem deve
   dizer o limite (100 MB) e, idealmente, o tamanho do arquivo (use `formatBytes`).
   - Use uma nova chave i18n (ex.: `FILE_SIZE_LIMIT_HARD` ou reutilize `FILE_SIZE_LIMIT` com o
     valor 100) — adicione a string em `en/conversation.json` e, **na mesma chave**, em
     `pt_BR/conversation.json` (o produto é PT-BR). Mantenha o padrão de interpolação existente.
3. **Backend defensivo (defesa em profundidade):** valide o tamanho do anexo **para todos os
   canais**, não só WebWidget. Ajuste `app/models/attachment.rb`:
   - Mantenha a validação de **tipo** restrita ao WebWidget como hoje (não mexer nisso).
   - Mas a validação de **tamanho** deve rodar sempre que houver arquivo anexado, com teto rígido
     de 100MB (ou `min(MAXIMUM_FILE_UPLOAD_SIZE, 100)` se quiser respeitar config menor).
   - A mensagem de erro deve subir como `ActiveRecord::RecordInvalid` e ser tratada/renderizada
     pelo `messages_controller.rb` (`create`) para retornar um erro HTTP claro (não 500 silencioso).
   - Garanta que o frontend **mostre** esse erro de validação do backend caso ele chegue (hoje o
     `error` do `DirectUpload`/save pode estar sendo engolido).
4. **Não regredir** o comportamento atual de canais com limite menor que 100MB (ex.: SMS) — o
   `min(...)` cuida disso.

## Implementação sugerida (siga os padrões existentes; não reescreva o que já funciona)
1. `FileHelper.js`: adicionar `HARD_MAXIMUM_FILE_UPLOAD_SIZE = 100` e exportar. Opcional: um helper
   `effectiveMaxUploadSize(channelLimit)` que devolve `min(channelLimit, 100)`.
2. `useFileUpload.js` e `fileUploadMixin.js`: aplicar o teto em `maxSizeFor()` e melhorar a
   mensagem de `alertOverLimit()` (incluir tamanho do arquivo via `formatBytes`).
3. `ReplyBox.vue`: confirmar que **todos** os 4 pontos de entrada passam por `onFileUpload`
   (e portanto pela validação). Se algum caminho (ex.: áudio) não valida tamanho, corrigir.
4. `attachment.rb`: separar `should_validate_file?` (tipo) de uma nova checagem de tamanho que
   roda para qualquer canal; manter default/teto coerente com o frontend (100MB).
5. i18n: nova chave em `en/conversation.json` **e** `pt_BR/conversation.json`.

## Testes (obrigatório — o projeto tem specs para isso)
- Frontend (Vitest): atualizar/expandir
  `app/javascript/dashboard/composables/spec/useFileUpload.spec.js`,
  `app/javascript/dashboard/mixins/specs/fileUploadMixin.spec.js` e
  `app/javascript/shared/helpers/specs/FileHelper.spec.js` cobrindo:
  arquivo > 100MB sempre bloqueado mesmo com `maximumFileUploadSize` alto; canal com limite < 100MB
  continua respeitado; mensagem de erro disparada.
- Backend (RSpec): `spec/models/attachment_spec.rb` — anexo > 100MB inválido em canal **não**
  WebWidget (WhatsApp/API) e em WebWidget; anexo válido < limite continua salvando.
- Rodar: `pnpm test` (ou o runner Vitest do repo) nos arquivos tocados e
  `bundle exec rspec spec/models/attachment_spec.rb`.

## Restrições / segurança (diretrizes do usuário)
- **NÃO** rodar git destrutivo amplo (`checkout/restore/reset -- .`): a árvore tem muito trabalho
  não-commitado.
- **NÃO** aplicar migrations nem deploy à frota sem confirmação — esta tarefa não deve precisar de
  migration. Validar no staging `nicolas.chatspx.app` (build via `assets:precompile` +
  `sudo /bin/systemctl restart chatwoot.target`) só depois da minha aprovação.
- Mostre o diff e o resultado dos testes antes de qualquer commit/deploy.

## Critério de aceite
- Tentar enviar mídia > 100MB (picker, drag-drop, paste, áudio) → erro visível imediato, anexo
  **não** é enviado.
- Backend rejeita > 100MB em qualquer canal com erro tratado (sem 500 silencioso).
- Canais com limite menor continuam funcionando como antes.
- Specs novos/atualizados passando.
