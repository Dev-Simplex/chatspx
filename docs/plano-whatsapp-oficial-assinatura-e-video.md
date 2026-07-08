# Plano - WhatsApp API oficial (Meta Cloud): assinatura do agente + video/arquivo >16MB como documento

**Status:** planejamento (nada aplicado)
**Data:** 2026-07-07
**Escopo:** APENAS canal oficial (Channel::Whatsapp / Meta Cloud). Cliente so tem oficial, sem WAHA. WAHA nao e alterado.

> Documento em ASCII de proposito (sem acentos/simbolos) para exibir correto quando servido como texto.

---

## Contexto (o que a auditoria achou)
- **Assinatura:** o nome do agente aparece no WAHA porque o BRIDGE EXTERNO do WAHA prefixa "*Nome*:\n". O caminho nativo (Cloud) manda `outgoing_content` cru, sem nome. Logo a oficial nao mostra o nome.
- **Tamanho:** na API oficial o Meta trava video em 16 MB, imagem 5, audio 16, documento 100 (limites HARD do Meta). Video de 60 MB so passa se enviado como DOCUMENTO (limite 100 MB). Trade-off aceito: chega como arquivo pra baixar, nao toca inline.

---

## PARTE 1 - Assinatura do agente na API oficial

### Mudanca (codigo)
1. **Helper compartilhado** em `app/services/whatsapp/providers/base_service.rb` (vale p/ Cloud e 360dialog; NAO afeta WAHA, que nao e provider):
   ```ruby
   # Opcao B (decisao 2): so prefixa quando HA conteudo -> midia sem legenda fica limpa (sem nome).
   def with_agent_prefix(message, content)
     return content if content.blank?
     return content unless agent_signature_enabled? && message.sender_type == 'User' && message.sender.present?
     name = message.sender.available_name.to_s.strip   # nome COMPLETO (decisao 3), igual WAHA
     name.present? ? "*#{name}*:\n#{content}" : content
   end
   # Toggle por inbox (decisao 1), default OFF
   def agent_signature_enabled?
     inbox.additional_attributes&.dig('agent_signature_enabled') == true
   end
   ```
2. **Texto** - `whatsapp_cloud_service.rb#send_text_message` (linha ~135):
   - de: `text: { body: message.outgoing_content }`
   - para: `text: { body: with_agent_prefix(message, message.outgoing_content) }`
3. **Midia (caption)** - `whatsapp_cloud_service.rb#send_attachment_message` (linha 207):
   - de: `type_content['caption'] = message.outgoing_content unless %w[audio sticker].include?(type)`
   - para (Opcao B - so poe legenda se houver texto; midia pelada fica sem nome):
     ```ruby
     unless %w[audio sticker].include?(type)
       cap = with_agent_prefix(message, message.outgoing_content)
       type_content['caption'] = cap if cap.present?
     end
     ```

### Por que so no provider (nao no outgoing_content)
Se prefixar no `outgoing_content` (compartilhado), o WAHA DUPLICARIA (o bridge ja prefixa). Colocando so no provider Cloud/360, o WAHA fica intacto.

### Toggle por inbox (decisao 1)
Novo setting booleano por inbox: `additional_attributes['agent_signature_enabled']` (sem migration) OU coluna dedicada `agent_signature_enabled`. Checkbox nas Configuracoes da inbox (aba WhatsApp): "Assinar mensagens com o nome do agente". **Default OFF** -> nao muda o comportamento atual ate o cliente ligar.
Obs: NAO usamos `sender_name_type` (friendly/professional) -> a decisao 3 e sempre nome COMPLETO.

### Decisoes (RESOLVIDAS)
1. **Toggle por inbox** (on/off), default OFF -> `agent_signature_enabled?`.
2. **Midia sem legenda: NAO prefixa** (Opcao B). So texto e midia-com-legenda recebem o nome -> guarda `content.blank?`.
3. **Nome COMPLETO** do agente, igual WAHA -> `available_name` (sem friendly/professional).

### Teste
Enviar 1 texto + 1 midia pelo inbox 91 (oficial) -> conferir que chega "*Atendente*:" no WhatsApp, igual ao WAHA.

---

## PARTE 2 - Video/arquivo >16 MB como documento (oficial)

### Regra final
- Video **<=16 MB** -> `type: video` (inline, como hoje).
- Video **>16 MB** (ate 60/100) -> `type: document` (arquivo pra baixar).
- Idem imagem >5 MB e audio >16 MB -> document (consistencia; foco e video).
- Documento continua document (ja e).

### Mudancas (3 camadas)

**1. Backend - envio** (`whatsapp_cloud_service.rb#send_attachment_message`, linha 203):
   - de: `type = %w[image audio video].include?(attachment.file_type) ? attachment.file_type : 'document'`
   - para:
     ```ruby
     META_INLINE_LIMITS_MB = { 'image' => 5, 'audio' => 16, 'video' => 16 }.freeze
     def resolve_media_type(attachment)
       base = %w[image audio video].include?(attachment.file_type) ? attachment.file_type : 'document'
       lim = META_INLINE_LIMITS_MB[base]
       (lim && attachment.file_size.to_i > lim.megabytes) ? 'document' : base
     end
     # type = resolve_media_type(attachment)
     ```
   - Ao virar document, `filename` (linha 208) e `caption` (207) ja sao setados -> chega arquivo nomeado com legenda. Zero trabalho extra.

**2. Frontend - liberar o upload** (`app/javascript/shared/helpers/FileHelper.js#getMaxUploadSizeByChannel`):
   - Hoje: canal oficial (INBOX_TYPES.WHATSAPP) usa o limite upstream (@chatwoot/utils) = 16 p/ video -> BLOQUEIA o video grande antes de subir.
   - Novo: p/ INBOX_TYPES.WHATSAPP, devolver o limite de DOCUMENTO (100), pois >16 vira document no envio. Espelhar o override que ja existe p/ Channel::Api (WAHA):
     ```js
     if (channelType === INBOX_TYPES.WHATSAPP) {
       // videos/imagens grandes viram documento no envio -> teto = documento (100),
       // ainda limitado pelo installationLimit (min aplicado em useFileUpload).
       return 100;
     }
     ```
   - `useFileUpload.js` ja faz `min(channelLimit, installationLimit)` -> com installation=60, o efetivo vira 60.

**3. Backend - limite geral** (`InstallationConfig` `MAXIMUM_FILE_UPLOAD_SIZE`): **40 -> 60** (por-VM).
   - Necessario: `attachment.rb#validate_file_size` usa `max_upload_size_mb = GlobalConfigService.load('MAXIMUM_FILE_UPLOAD_SIZE', 40)` (cap em HARD=100). Com 40, qualquer arquivo >40 e cortado no backend antes de enviar.
   - Config-only, sem restart (lido do banco). E a Fase 0.

### Nao afeta o WAHA
`attachment.rb#validate_waha_category_size` so roda p/ Channel::Api (WAHA) -> video no WAHA continua 16. E o override de frontend/backend acima e so p/ INBOX_TYPES.WHATSAPP.

### Riscos / atencao
- **Meta busca a midia por LINK** (`attachment.download_url`). 60 MB por link deve funcionar (documento=100 MB), mas confirmar: URL publica + HTTPS + content-type correto.
- **UI mostra video pro agente, mas o cliente recebe documento** -> considerar aviso na composer ("videos acima de 16 MB sao enviados como arquivo na API oficial").
- **Subir backend p/ 60** afeta todos os uploads da VM (ok: os limites por-canal continuam valendo; WAHA video segue 16 pela category validation).
- **HARD cap = 100** (frontend e backend) -> teto absoluto 100 MB, dentro do limite de documento do Meta.

### Teste (o que vale de verdade)
- Video ~60 MB pelo inbox 91 -> deve chegar como DOCUMENTO baixavel (sem erro do Meta).
- Video ~10 MB pelo inbox 91 -> deve continuar INLINE (type video).
- Documento ~60 MB -> deve passar (ja era document; so precisava do backend em 60).
- (Nao testar video 60 MB inline na oficial: o Meta REJEITA >16 -> e justamente por isso que convertemos p/ document.)

---

## Plano por fases
- **Fase 0 - config (imediato, por-VM, sem codigo):** `MAXIMUM_FILE_UPLOAD_SIZE` 40 -> 60 na(s) VM(s) do cliente. Ja libera arquivo/documento ate 60.
- **Fase 1 - codigo:** Parte 1 (assinatura no provider Cloud/360) + Parte 2 (video>16->document no backend + liberar frontend). SDC completo: story -> validacao -> dev -> QA.
- **Fase 2 - teste end-to-end:** inbox 91 (assinatura em texto+midia; video 60MB->documento; video 10MB->inline).

## Resumo do parecer
- **Assinatura:** viavel e barato, sem pegadinha do Meta (e texto). Recomendo fazer.
- **60 MB:** video puro inline e impossivel na oficial (teto Meta=16). A opcao A (>16MB -> documento) e o caminho certo e passa 60 MB integro. E ~1 linha no backend + 1 override no frontend + subir o limite backend. Testar so o fluxo de documento (o inline >16 e falha garantida do Meta, por isso convertemos).

## Referencias
- WhatsApp Cloud API - limites de midia (video 16 / documento 100): https://developers.facebook.com/docs/whatsapp/cloud-api/messages/interactive-list-messages/ (media size na doc de media messages)
- Codigo: whatsapp_cloud_service.rb (send_text_message ~135, send_attachment_message 201-222), base_service.rb, attachment.rb (validate 195-219, max_upload_size_mb 233), FileHelper.js (getMaxUploadSizeByChannel), inbox.rb (sender_name_type 81).
