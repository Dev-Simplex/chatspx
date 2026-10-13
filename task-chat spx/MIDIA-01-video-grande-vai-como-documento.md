# MIDIA-01 — Vídeo acima de 16 MB vai como documento (até 100 MB)

## O pedido
- Vídeo **até 16 MB** → vai como **vídeo** normal (toca no WhatsApp do cliente).
- Vídeo **de 16 MB a 100 MB** → vai como **documento** (o cliente baixa e abre).
- PDF e qualquer outro arquivo → documento, **até 100 MB** (já é assim hoje).
- Acima de 100 MB → continua bloqueado, com o aviso que já existe.

## Como está hoje (código da `homologacao`)

| Canal | Vídeo > 16 MB | Onde |
|---|---|---|
| **WhatsApp oficial (Meta Cloud)** | ✅ **já vai como documento** até 100 MB | `whatsapp_cloud_service.rb#resolve_media_type` + `FileHelper.js` libera 100 MB |
| **WhatsApp WAHA** (a maioria das caixas) | ❌ **bloqueado** na tela e no servidor | `FileHelper.js` `WAHA_VIDEO = 16` + `attachment.rb` `WAHA_MAX_SIZE_BY_CATEGORY['video'] = 16` |

Ou seja: o trabalho é **levar para o WAHA o que o oficial já faz**.

Detalhe que decide o desenho: no WAHA o Chatwoot **não envia** a mídia. Ele entrega o webhook ao
**app de Chatwoot que vem dentro do WAHA** (código do fornecedor), e é esse app que escolhe
`sendVideo`/`sendFile`. Não temos como mandar esse app enviar vídeo como documento.

## A solução (recomendada): o Rails envia direto o vídeo grande pelo `sendFile`

Já existe um caminho para isso: `Waha::OutboundSpecialMessageService` manda **localização, contato e
menus** direto ao WAHA (REST), e o `WebhookListener#waha_direct_case?` deixa de entregar o webhook ao
app nesses casos (sem envio duplicado). O vídeo grande entra nesse mesmo caminho.

### Backend
1. **`Waha::ApiService#send_file`**: `POST /api/sendFile` com `{ session, chatId, file: { url, filename, mimetype }, caption }`.
2. **`Waha::OutboundSpecialMessageService`**: novo caso "vídeo > 16 MB" → `send_file`, grava `source_id`
   (o `mark_sent` que já existe). Com o `source_id`, o status (enviado/entregue/lido), o **editar** e o
   **apagar** continuam funcionando como em qualquer mensagem.
   - Falha do WAHA → `failed` + `external_error` (já existe) → o atendente vê "Falha ao enviar" e o "Reenviar".
3. **`WebhookListener#waha_direct_case?`**: inclui "vídeo > 16 MB". Um único lugar decide (método na
   `Attachment`, ex.: `vai_como_documento?`), usado pelo listener e pelo serviço.
4. **`Attachment`**: `WAHA_MAX_SIZE_BY_CATEGORY['video']` 16 → 100. Imagem e áudio ficam em 16.
5. **Vídeo `.MOV`**: hoje ele espera virar `.mp4` antes do webhook (`MessageCreatedAposMp4Job`). Esse job
   precisa passar pelo mesmo desvio, senão o `.MOV` grande vai para o app e falha.
6. **Legenda**: mandar o texto da mensagem como `caption`, no mesmo formato do app (com o nome do
   atendente, se o app põe). **A confirmar no teste**: comparar com um PDF enviado pelo caminho normal.

### Tela (painel)
7. **`FileHelper.js`**: `WAHA_VIDEO` 16 → 100 (o teto de 100 MB já vale para todos).
8. **Aviso antes de enviar**: no anexo escolhido, um selo **"Vai como documento"** quando for vídeo
   > 16 MB numa caixa WhatsApp (WAHA ou oficial). O atendente sabe antes que o cliente vai baixar um
   arquivo, não ver um vídeo.
9. **Balão no chat**: o vídeo continua tocando no painel; abaixo, uma linha discreta **"Enviado como
   documento (acima de 16 MB)"**. Vale para os dois canais.
10. i18n só em `en.json` / `pt_BR` conforme o padrão.

### Fora do escopo (avisar, não fazer)
- Imagem > 16 MB (foto raramente passa disso; dá para incluir depois com a mesma regra).
- Áudio continua em 16 MB.
- Mídia **recebida** já aceita até 100 MB (N-02, PR #190).

## Alternativa considerada e descartada
Marcar o anexo como "arquivo" no Chatwoot para o app do WAHA usar `sendFile`. É menos código, mas
depende de como o app do fornecedor decide (não temos o código dele), e o vídeo deixaria de tocar no
painel. O envio direto é o mesmo padrão já usado para localização/contato e fica sob nosso controle.

## Riscos a provar no staging
- **O WAHA aceita baixar 100 MB pela URL?** É o primeiro teste: 20 MB, 50 MB e 99 MB.
- **Tempo**: 100 MB pode levar minutos para subir; o envio roda em job, o painel não trava.
- **Engine da sessão** (WEBJS/NOWEB/GOWS): `sendFile` precisa funcionar na engine das VMs.

## Roteiro de teste (no "meu chat" — nicolas.chatspx.app)
1. Caixa WAHA: vídeo de 10 MB → chega como **vídeo** que toca.
2. Vídeo de 20 MB, 50 MB e 99 MB → chegam como **documento**, com a legenda; status vira entregue/lido.
3. Vídeo de 101 MB → bloqueado com o aviso de 100 MB.
4. `.MOV` de 30 MB → vira `.mp4` e chega como documento.
5. PDF de 60 MB → documento (sem mudança).
6. Apagar e editar a legenda do vídeo enviado como documento → funciona no celular do cliente.
7. Sessão WAHA desligada → "Falha ao enviar" + "Reenviar".
8. Caixa oficial (Meta Cloud): vídeo de 20 MB → documento, com o mesmo selo e a mesma linha no balão.

## Fluxo
Implementar na `nicolas` → build/restart do staging → você testa → OK → PR para `homologacao`
(deploy em todas as VMs + .232 quando promover).
