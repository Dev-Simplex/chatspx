# SÍNTESE — Grupos de WhatsApp (WAHA) no ChatSPX

> Pesquisa multi-agente · 27/07/2026 · 6 workers em paralelo · somente pesquisa, nenhum código alterado
> Relatórios completos: `01-cadeia-ingestao.md` · `02-waha-api-grupos.md` · `03-auditoria-pipeline-lid.md`
> `04-diagnostico-empirico.md` · `05-modelagem-arquitetura.md` · `06-ux-frontend-grupos.md`

---

## O veredito em uma frase

**O `(229480102662169@lid)` não é bug do ChatSPX — é a app `chatwoot` que roda DENTRO da WAHA
concatenando o JID cru do participante ao nome, e gravando isso como TEXTO dentro de
`messages.content`. E somos nós que instalamos essa app, aceitando os templates default.**

---

## 1. Sintoma A — o LID colado no nome

### Quem monta

Código-fonte público da WAHA (`devlikeapro/waha`), `src/apps/chatwoot/consumers/waha/base.ts:375-390`:

```ts
let participant = toCusFormat(key.participant || payload._data.participant);
const contact = await this.session.getContact(participant);
const name = contact?.name || contact?.pushName;
if (name) {
  participant = `${name} (${participant})`;   // ← "Rogerio José Da Silva (229480102662169@lid)"
}
content = this.l.key(TKey.WHATSAPP_GROUP_MESSAGE).render({ text: content, participant });
```

Template `src/apps/chatwoot/i18n/locales/pt-BR.yaml`:

```yaml
whatsapp.group.message: |-
  👥 *{{{participant}}}*

  {{{text}}}
```

Isso reproduz o dump do usuário **caractere por caractere** — o `👥`, o negrito, a quebra de linha.

**Causa raiz precisa:** `toCusFormat()` (`src/core/utils/jids.ts:159-161`) converte
`@s.whatsapp.net` → `@c.us`, mas **preserva `@lid` intacto**. A app já busca o nome via
`getContact()` e nunca consulta o mapa LID→PN que a própria WAHA mantém.

### Nós instalamos essa app — e sem customizar

`app/services/waha/api_service.rb:221-233` faz `POST /api/apps` com `app: 'chatwoot'`, e
`app/controllers/api/v1/accounts/waha_connections_controller.rb:83-91` monta a config
**sem a chave `templates`** → herdamos 100% dos defaults.

Detalhe: outra sessão (`Simplex`) **já usa** `templates` customizados para o nome do agente. Ou
seja, o mecanismo de override está provado em campo aqui dentro, só não foi aplicado a este caso.

### Os outros elementos do dump, todos explicados

| String no dump | Origem | Chave |
|---|---|---|
| `👥 *Nome (…)*` | WAHA Chatwoot App | `whatsapp.group.message` |
| `✏️ Editado no WhatsApp` | WAHA Chatwoot App | `message.edited.in.whatsapp` |
| `Reagiu com 👍` | WAHA Chatwoot App | `whatsapp.reaction.added` |
| `(Grupo)` / `(Group)` | WAHA Chatwoot App | `whatsapp.contact.group.suffix` |
| **`(GROUP)` maiúsculo** | **Evolution API** | hardcoded `${group.subject} (GROUP)` |

⚠️ **Correção ao enunciado inicial:** `(GROUP)` em caixa alta **não é da WAHA**. É fóssil da
Evolution API (jul–ago/2025). Convivem 3 variantes na base — `(GROUP)`, `(Group)`, `(Grupo)` —
correspondendo à idade do contato. O contato `TI TOZI - Inovação (GROUP)` (id 24) é desse período.

### É regressão datada, não defeito eterno

Até ago/2025 o mesmo produtor gravava `**+55 (66) 9***-**22 - Vilso Tozi:**` — com telefone
formatado. A partir de dez/2025 virou `👥 *Nome (LID@lid)*`. O WhatsApp migrou para LID-first e o
plugin não acompanhou. Issue upstream [waha#1493](https://github.com/devlikeapro/waha/issues/1493)
**aberta desde 13/10/2025, sem fix**, bloqueada pela #993.

### O dado está GRAVADO, não é renderização

```
id                 | 34084
content            | 👥 *Walisson (6075*****0218@lid)*⏎⏎Vish⏎`🗓️ Hoje, 02 de mai. • 18:26 BRT`
sender_type        | Contact
sender_id          | 1963        ← o CONTATO-GRUPO, não a pessoa
content_attributes | {}          ← VAZIO: zero metadado do participante
source_id          |             ← VAZIO
```

**543–548 mensagens** nesta base. `grep` por `👥`, `(GROUP)` e `Reagiu com` em `app/ lib/
enterprise/` = **zero**. O Rails só persiste (`public/api/v1/inboxes/messages_controller.rb:78-88`);
o front só renderiza markdown.

---

## 2. Sintoma B — grupo não mostra os integrantes

### A WAHA já entrega tudo. Nós jogamos fora.

`GET /api/{session}/groups/{groupId}/participants` → **HTTP 200**, os 12 integrantes do TI TOZI:

| campo | preenchido? |
|---|---|
| `JID` | ✅ `2294*****2169@lid` |
| `PhoneNumber` | ✅ **`5566*****91@s.whatsapp.net`** |
| `LID` | ✅ |
| `IsAdmin` / `IsSuperAdmin` | ✅ |
| `DisplayName` | ❌ sempre vazio no GOWS |

Medição ao vivo: **598 de 598 participantes (100%) de 40 grupos têm telefone preenchido**, mesmo
com 100% dos JIDs em `@lid`. Existe ainda `/participants/v2` devolvendo `{id, pn, role}` — campo
`pn` que **nem está documentado**.

### O desperdício mais caro da pesquisa

`app/jobs/waha/refresh_groups_job.rb:18` chama `service.get_groups(session_name)` **sem atribuir a
resposta**. Essa resposta contém **932 pares LID→PN em 78 grupos**, medidos hoje. Pagamos a chamada
HTTP a cada 30 min e descartamos exatamente o dado que falta na tela. Depois o sistema paga um
round-trip por LID no `ResolveLidJob` — que no momento está em retry-loop por timeout.

E o mapa LID→PN da WAHA tem **2757 entradas**: os dois LIDs do dump do usuário resolvem
instantaneamente (`229480102662169` → `5566*****91`, `260330953380002` → `5566*****60`).

**O dado nunca faltou. Ele é ignorado por quem monta o texto.**

---

## 3. Por que a normalização de LID que já existe nunca roda em grupo

`app/controllers/public/api/v1/inboxes_controller.rb:37` — early-return:

```ruby
return { source_id:, phone_number: } unless waha_lid?(source_id)   # exige terminar em '@lid'
```

Mas **100% dos `contact_inboxes` de inboxes WAHA (30/30) têm `source_id` = UUID** — o produtor
externo nunca envia `source_id`, envia `identifier`. O controller nunca dispara.

Em grupo é pior e é estrutural: o contato-grupo tem `identifier = <id>@g.us`, e `waha_lid?`,
`whatsapp_user_jid?`, `needs_resolution?`, `stuck_contact_inboxes` e `waha_effective_phone_for`
filtram **exclusivamente** por `@lid`/`@c.us`. Nada olha para `@g.us`.

E o mais fundo: `messages_controller.rb:81` grava `sender: @contact_inbox.contact` — **o remetente
é sempre o contato-grupo**. O Chatwoot não tem onde guardar "quem falou", e é justamente por isso
que a WAHA resolveu concatenar no texto.

`git log -S "@g.us"` → **2 commits**, ambos alheios. **Nunca houve tentativa de tratar grupo.**

---

## 4. Estrago colateral já em curso (não é hipótese — está no banco)

| Problema | Evidência |
|---|---|
| **CSAT/NPS disparando em grupo** | 15 pesquisas CSAT + 2 NPS já enviadas dentro de conversas de grupo (uma com `external_error: 404`) |
| **Grupo fragmentado em N conversas** | `TI TOZI - Inovação` tem **9 contact_inboxes e 8 conversas** — 100% (114/114) dos contact_inboxes de grupo usam UUID em vez do JID `@g.us` |
| **Guard de grupo do Captain desligado** | `skip_groups` é config-gated e vem **desativado por padrão** |
| **Sem reply/editar/apagar** | mensagens do formato novo chegam **sem `source_id`** (as antigas tinham `WAID:…`) |
| **`RefreshGroupsJob` quebrado** | 422 + timeout nesta VM hoje |
| **Bolhas agrupam pessoas diferentes** | `MessageList.vue:265` agrupa por `senderId`, que é sempre o contato-grupo |
| **Reações viram mensagem de texto** | `MessageReactions.vue` existe pronto e **não é importado por ninguém** no fio |
| **Reply não mostra o autor citado** | `ReplyPreview.vue` não exibe autor |

---

## 5. O que o front tem hoje

- Conjunto ativo: **`components-next/message/`** (o antigo `widgets/conversation/bubble/` foi
  removido no upstream `24ea968b00`). Cadeia: `MessagesView.vue:637 → MessageList.vue:335 →
  Message.vue:929 → bubbles/Text/Index.vue → FormattedContent.vue → MessageFormatter.js:61`.
- **Ponto único de formatação de texto:** `shared/helpers/MessageFormatter.js:61` — bolha, preview
  da lista, busca, Kanban e copilot passam todos por ali.
- **Zero tratamento condicional de grupo** em `app/javascript/`: nenhuma ocorrência de `@g.us`,
  `isGroup` ou `is_group`.
- Infra visual pronta e subaproveitada: `Avatar.vue` (paleta dupla light/dark, prop `accent`),
  `colorHelper.js#adjustColorForContrast`, `_wa-skin.scss`.
- **Serialização é de graça:** `content_attributes` e `additional_attributes` já chegam ao front
  por REST (`_message.json.jbuilder:9,17`), websocket (`message.rb:161`) e webhook. Guardar o autor
  ali **não exige mexer em serializer nenhum**.
- **Mas a porta de entrada é fechada:** `messages_controller.rb:70-72` só permite
  `params.permit(:content, :echo_id, :source_id)`.

---

## 6. O que o upstream já decidiu (alinhar sai de graça)

PR [chatwoot#13361](https://github.com/chatwoot/chatwoot/pull/13361) — aberto, 51 arquivos,
+2244/−141, **parado desde jan/2026**:

- `conversations.group` (boolean), `group_title`, `group_source_id`
- tabela `group_contacts`
- `Message#sender` apontando para o **Contact do participante**, resolvido por um parâmetro novo
  `sender_identifier` na API pública

O co-fundador do Chatwoot publicou essa direção. **Recomendação forte: copiar o shape (nomes de
tabela e colunas) mesmo implementando por conta própria** — divergir custa merge caro para sempre.
Alinhar sim; esperar não.

---

## 7. Caminho recomendado (4 fases)

### Fase 0 — parar o sangramento · dias · custo baixo

> **Config sozinha NÃO resolve — verificado no código-fonte.** O template recebe `{{{participant}}}`
> **já concatenado** com o JID (`base.ts:385`). Um override de `config.templates` só reveste a
> string: **tira o `👥`, não tira o `(<lid>@lid)`**. Para o template resolver, a WAHA teria que
> expor nome e JID separados — e não expõe (issue #1493 aberta).

Portanto o menor caminho é **do nosso lado**, e é barato:

1. **Saneamento na ingestão** — em `Public::Api::V1::Inboxes::MessagesController#message_params`,
   para inbox WAHA em conversa de grupo, remover ` (\d+@lid)` do bloco de participante **e extrair
   esse LID para `content_attributes`**. É uma regex sobre uma string que já é nossa quando chega,
   não uma briga com o core — e de quebra cria o dado estruturado que hoje não existe.
2. Opcionalmente, override do template para tirar o `👥`.
3. Limpeza dos nomes fósseis `(GROUP)` → `(Grupo)`.
4. Quick win independente: `OutboundSpecialMessageService#chat_id` deve preferir
   `waha_whatsapp_chat_id`.

**Não resolve:** as ~548 mensagens já gravadas (ficam no histórico) nem a lista de integrantes.

**Bônus:** o LID extraído no passo 1 é a chave para resolver o telefone via
`Waha::ApiService#get_lid_phone_number` (já existe, `api_service.rb:92-95`) — o que emenda direto
na Fase 1.

### Fase 1 — autor estruturado por mensagem · 1–2 semanas · **zero migration**

- Predicado único `Conversation#group?` usado por **todos** os guards.
- `permit` de `content_attributes.group_sender` + strip do prefixo `👥 *…*` na ingestão.
- Resolver LID→telefone no caminho de grupo, **reusando** `Waha::ApiService#get_lid_phone_number`
  e `Contacts::ResolveLidJob`.
- Render: estender o ramo `additionalAttributes.senderName` de `Message.vue:750-757`.
- Guards em CSAT (`csat_survey_service.rb:26`), NPS (`nps_survey_listener.rb:4`), webhooks
  (`hook_execution_service.rb:26,42`), automações (`automation_rule_listener.rb:403`), e **ligar
  `skip_groups` do Captain por padrão**.
- `conversation_llm_formatter.rb:84` passa a emitir `"<Participante>: <texto>"` para a IA.

**Entrega ao usuário:** nome + avatar do participante na bolha, texto limpo, fim do CSAT em grupo.

### Fase 2 — identidade do grupo de primeira classe · ~1 semana · 1 migration pequena

- Copiar o DDL do upstream: `conversations.group` + `group_source_id` + `group_title`, com índice
  único parcial `(inbox_id, group_source_id)`. **Isso mata a fragmentação na raiz.**
- Novo `Waha::ApiService#get_group_participants` → snapshot dos integrantes em
  `conversation.additional_attributes['waha_group']` (serialização de graça).
- Backfill das 36 conversas-grupo existentes. **Consolidar as duplicadas é decisão de produto, não
  técnica — merge é destrutivo.**

**Entrega:** um grupo = uma conversa; header "Grupo · N membros"; painel com a lista de integrantes.

### Fase 3 — participante como Contact · 3–6 semanas · **só com gatilho**

Tabela `group_contacts` + `sender_identifier`, espelhando o PR 13361. Habilita busca por
participante, relatório e histórico unificado com o 1:1.

**Gatilho de GO:** só entrar se, ao fim da Fase 1, a taxa de LID→telefone for alta. Sem telefone,
cada participante vira um contato órfão que nunca consolida — **inflação da base de contatos com
impacto comercial, sem o benefício**. Foi exatamente o erro que a Evolution API cometeu.
**Irreversível na prática — por isso é a última.**

### O que NÃO fazer

- Pular direto para a Fase 3.
- Inventar naming próprio (`whatsapp_group_participants`) em vez de `group_contacts`.
- Usar `additional_attributes['type'] = 'group'` como sinal — o comentário em
  `router_service.rb:32` sugere que é padrão do Chatwoot; **não é**.
- Grupo como Inbox (bate em limite de plano).
- Esperar o upstream mergear.

---

## 8. Lacunas honestas

1. ~~Quais variáveis o template aceita~~ — **FECHADO durante a pesquisa**: o template recebe
   `participant` já concatenado (`base.ts:385`), então override de config tira o `👥` mas **não** o
   `(@lid)`. A Fase 0 é código (regex no ingest), não configuração.
2. **Todas as medições são de homologação (.232).** A instância WAHA aqui é
   `waha.simplexsolucoes.com.br` (a da Simplex) — **não existe sessão "Tozi" nela**. O grupo TI TOZI
   existe aqui porque a Simplex participa dele, o que permitiu o diagnóstico completo. Os números
   (548 msgs, 36 grupos, 15 CSAT) são **indicativos** para a produção da Tozi (.109), não medidos —
   por desenho, os workers foram proibidos de acessar produção.
3. **Última mensagem `👥` local: 02/05/2026.** O dump do usuário é de hoje (27/07) — vem de produção.
4. Sessão `spx` está configurada na inbox 42 mas **não existe na WAHA**; das 12 sessões, só
   `Simplex` está `WORKING`.
5. Não medido: custo de sincronização de participantes (chamadas/dia × N grupos) vs. o circuit
   breaker já existente.
6. Não avaliado: app móvel (consome os mesmos jbuilders, mas o render é outro código).
7. Não lido: o diff de front do PR 13361 (`GroupInfo.vue`, `GroupMembersModal.vue`) — ler antes de
   escrever qualquer coisa nossa na Fase 2/3 economiza dias.

---

## 9. Ambiente auditado

```
WAHA:  https://waha.simplexsolucoes.com.br
       versão 2026.4.2 · engine GOWS · tier PLUS
       (a partir de 2026.6.1 a WAHA é 100% grátis, sem separação Core/Plus)
Base:  homologação .232 · 543 msgs com 👥 · 542 com @lid · 24 contatos com (GROUP)
       inboxes WAHA afetadas: 17 (spx, 420 msgs), 43 (simplexteste, 98), 42 (16), 41 (8)
```
