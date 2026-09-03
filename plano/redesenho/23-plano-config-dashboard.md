# 23 — Plano de execução: as telas de configuração no dashboard

> **Escopo:** a superfície *de dentro* — onde o cliente configura o widget, em
> `app/javascript/dashboard/routes/dashboard/settings/inbox/` e no que sustenta essas telas no
> backend (leitura apenas).
> **Fase:** planejamento. **Nenhum arquivo de código deste repositório foi alterado por esta task.**
> Nada foi commitado, deployado, migrado ou reiniciado.
> **Base:** branch `homologacao`, HEAD `ee87f5e799`, fork ChatSPX sobre Chatwoot v4.12.1.
> **Data:** 12/08/2026.
>
> ---
>
> ## ⚠ DECISÕES DO PRODUTO — 13/08/2026: leia antes de executar qualquer tarefa deste plano
>
> **O `PLANO-MESTRE.md` é a fonte única da ordem e do escopo; este plano continua sendo a fonte do
> detalhe** — mas em seis pontos o detalhe daqui foi superado. Onde este arquivo e o mestre
> divergirem, **o mestre manda**.
>
> | Decisão | O que muda **neste** plano | Onde está o novo detalhe |
> |---|---|---|
> | **D1** — abordagem em três níveis | A **Tela 2** (§B.3) ganha o seletor Discreto/Chamativo/Agressivo, o interruptor de degradação e o aviso do auto-open — **sem mencionar penalização do Google**. A frase *"nenhum caminho da UI liga auto-open"* deixou de valer | Mestre blocos **3.20**, **4.04**, **4.20**, **4.21**; bloco `> DECISÃO` no topo da §B.3 |
> | **D5** — ícone do lançador | A **Tela 1** (§B.2) ganha `launcher_icon`; inbox nova nasce com **balão**; a tela sugere foto do time e **nunca** oferece banco de imagem | Mestre bloco **3.19**; bloco `> DECISÃO` no topo da §B.2 |
> | **D10** — campanhas legadas | A §B.3.2 ganha a **regra de precedência** que faltava: motor novo assume, legado continua listado numa seção "modo antigo" com importação, e conta só-legado **não muda de comportamento** | Mestre bloco **4.22**; bloco `> DECISÃO` no topo da §B.3.2 |
> | **D8** — instalação em WordPress, Wix e GTM | **Entra**: um caminho documentado por plataforma, com o snippet pronto (que a T1.14 já passa a servir do servidor) e a armadilha de cada uma escrita. **Atenção:** isto é a *documentação*; a **tela** de instalação com verificador ("o widget está no ar?") **continua sem decisão** — são coisas diferentes | Mestre bloco **5.22**; e a linha 30 da §8.1, ainda aberta |
> | **D9** — contexto do sistema externo (decisão **I5**) | **Entra na versão simples**: painel lateral na conversa com o que o site mandou (origem, atributos com selo, estado de identidade, lead incompleto). O **app embutido fica para depois** — o mecanismo de abas já existe (`ConversationBox.vue:150-151`), então adiar não custa arquitetura | Mestre bloco **5.23** |
> | **D7** — reordenação das ondas | **As ondas 1–4 deste plano não são mais a ordem de execução.** A configuração passou a ser a **3ª** onda do mestre (antes da captura e da atribuição), e o acabamento visual do widget foi para a 6ª. Os ids das tarefas (`T1.9`, `T3.4`…) continuam válidos | Mestre §2.1, §2.2 e **§2.6** |
> | **D14 · D11–D13 · D15** | Fixture anti-erro em todo E2E; **sem** Biome, TypeScript strict, Zod e Stryker (somos um fork); worktree por frente; autonomia até **commit local**; falha = 2 tentativas → revert → escalação | Mestre **§10** e **§11** |

Documentos irmãos desta onda, já escritos, com os quais este plano se encaixa sem sobreposição:

| Documento | O que cobre | Fronteira com este |
|---|---|---|
| `plano/redesenho/22-plano-widget.md` | O widget (iframe) e o SDK | Ele consome o que estas telas gravam |
| `plano/redesenho/25-plano-tracking-integracao.md` | Tracking C0–C9 e integração site↔chat | **§A.3 (C1) é o par da Tela 4** — ele especifica modelo/segredo/publicação; aqui especifico a UI |
| `plano/redesenho/shared/tokens.css` + `primitivos.css` (Task 21) | A fundação visual do widget | A Tela 1 (Aparência) é a UI que alimenta `--brand`, e o preview precisa consumir estes tokens |

---

## 0. Como ler

### 0.1 Marcadores de evidência

| Marcador | Significa |
|---|---|
| `[FATO]` | Trecho de código deste repositório, com `arquivo:linha` conferível no HEAD `ee87f5e799` |
| `[MEDIDO]` | Número obtido por execução de comando nesta task (o comando está no Anexo B) |
| `[INFERÊNCIA]` | Conclusão derivada de dois ou mais fatos. É leitura minha, não observação |
| `[NÃO VERIFICADO]` | Não comprovei. Está escrito assim de propósito |
| `[DECISÃO]` | Escolha deste plano, com a razão ao lado |
| `[DIVERGÊNCIA]` | Contraria algo do estudo. Vem com a medição própria que a sustenta |

### 0.2 O que este documento **não** faz

- **Não define schema.** Onde o plano precisa de campo novo no banco, ele diz *o que* precisa
  existir (nome lógico, semântica, quem escreve, quem lê, o que acontece com inbox antiga) e
  **para a análise ali**. A modelagem é da **task 24**. Toda dependência está consolidada na §C.2.
- **Não estima em horas.** Esforço é sempre relativo: **P** (pequeno), **M** (médio), **G** (grande).
- **Não reabre as decisões do Walisson.** Perfil por inbox, geometria mantida, escopo das duas
  superfícies e planejamento de todas as ondas entram como dados de entrada.

### 0.3 Ambiente das medições

Todas as medições de código foram feitas por leitura e por `git`/`grep`/`python3` no diretório
`/home/chatwoot/chatwoot`, na branch `homologacao`. **Não abri navegador nesta task** — onde precisei
de comportamento de tela, marquei `[NÃO VERIFICADO]` ou usei medição de outro relatório com a
âncora. As comparações com o upstream usam as tags locais `v4.12.1` e `v4.16.2`.

---

# PARTE A — RAIO-X: a configuração da inbox Website como ela é hoje

## A.1 O ponto de entrada

`app/javascript/dashboard/routes/dashboard/settings/inbox/inbox.routes.js:96-104` `[FATO]`:

```js
{
  path: ':inboxId/:tab?',
  name: 'settings_inbox_show',
  component: Settings,
  meta: { featureFlag: FEATURE_FLAGS.INBOX_MANAGEMENT, permissions: ['administrator'] },
}
```

Três coisas que isso já decide:

1. **A aba é segmento de URL** (`:tab?`), não query. Toda tela nova ganha uma URL própria de graça.
2. **A tela inteira é `administrator`**. Não existe granularidade por aba hoje.
3. A tela é gateada pela feature flag `inbox_management` da conta
   (`app/javascript/dashboard/featureFlags.js:13`) `[FATO]`.

O `Settings.vue` sincroniza o índice da aba com a URL por `window.history.replaceState`
(`Settings.vue:484-496`) — **não** por `router.push` `[FATO]`. É um detalhe que importa: a troca de
aba não passa pelo router, então guards de rota por aba não funcionariam sem mudar isso.

## A.2 As abas de uma inbox Website — quem renderiza o quê

O array de abas é montado em `Settings.vue:143-227` `[FATO]`. Para `isAWebWidgetInbox`, a lista
efetiva é:

| # | `key` | Rótulo (`INBOX_MGMT.TABS.*`) | Componente | Linhas | Tamanho |
|---|---|---|---|---|---:|
| 1 | `inbox-settings` | `SETTINGS` | **inline no `Settings.vue`** | `Settings.vue:683-1233` | — |
| 2 | `collaborators` | `COLLABORATORS` | `settingsPage/CollaboratorsPage.vue` | `Settings.vue:1235-1237` | — |
| 3 | `business-hours` | `BUSINESS_HOURS` | `components/WeeklyAvailability.vue` | `Settings.vue:1251-1253` | — |
| 4 | `csat` | `CSAT` | `settingsPage/CustomerSatisfactionPage.vue` | `Settings.vue:1245-1247` | 746 l. |
| 5 | `nps` | `NPS` | `settingsPage/NetPromoterScorePage.vue` | `Settings.vue:1254-1256` | 794 l. |
| 6 | `pre-chat-form` | `PRE_CHAT_FORM` | `PreChatForm/Settings.vue` | `Settings.vue:1248-1250` | 166 l. |
| 7 | `configuration` | `CONFIGURATION` | `settingsPage/ConfigurationPage.vue` | `Settings.vue:1238-1244` | 580 l. |
| 8 | `bot-configuration` | `BOT_CONFIGURATION` | `components/BotConfiguration.vue` | `Settings.vue:1257-1259` | — |

A aba 8 só aparece se a conta tiver `FEATURE_FLAGS.AGENT_BOTS` (`Settings.vue:201-211`) `[FATO]`.
As abas `whatsapp-health` e `message-templates` existem no mesmo componente mas são condicionadas a
`shouldShowWhatsAppConfiguration` (`Settings.vue:212-224`) — não aparecem em inbox Website `[FATO]`.

**`Settings.vue` tem 1.277 linhas** `[MEDIDO]`. Metade disso é a aba 1, escrita direto no template.
É o arquivo que mais dói mexer nesta superfície (ver §A.7).

## A.3 Inventário campo a campo — o que cada controle grava e onde

### A.3.1 Aba 1 — `inbox-settings`

Handler único de gravação: `Settings.vue:506-557` (`updateInbox()`). Um botão salva a aba inteira
(`Settings.vue:1191-1208`).

**Bloco superior (comum a canais):**

| Campo na tela | Controle | Linha do template | Vai no payload como | Destino final |
|---|---|---|---|---|
| Avatar | `next/avatar/Avatar.vue` (`allow-upload`) | `698-707` | `payload.avatar` (`:548-550`) | ActiveStorage no `inbox` |
| Nome da caixa | `woot-input` | `710-721` | `name` (`:520`) | `inboxes.name` |
| Domínio do site | `woot-input` | `753-761` | `channel.website_url` (`:539`) | `channel_web_widgets.website_url` |
| Central de Ajuda | `SelectInput` | `781-788` | `portal_id` (`:525-529`) | `inboxes.portal_id` |
| Nome do remetente | radio + input | `846-899` | `sender_name_type`, `business_name` (`:535-536`) | `inboxes.*` |
| Isolamento de time | `SettingsToggleSection` | `806-813` | `team_message_isolation` (`:531`) | `inboxes.*` |
| Isolamento de agente | idem | `815-822` | `agent_message_isolation` (`:532`) | `inboxes.*` |
| Isolamento de conversa | idem | `824-835` | `agent_conversation_isolation` (`:533`) | `inboxes.*` |
| Status pendente | idem | `837-844` | `pending_status_enabled` (`:534`) | `inboxes.*` |

**Acordeão "Recursos do widget"** (`INBOX_MGMT.WIDGET_FEATURES`, `Settings.vue:901-1114`):

| Campo na tela | Controle | Linha | Payload | Destino |
|---|---|---|---|---|
| Título de boas-vindas | `woot-input` | `913-921` | `channel.welcome_title` (`:541`) | `channel_web_widgets.welcome_title` |
| Frase de boas-vindas | `components-next/Editor/Editor.vue` (max 255) | `932-941` | `channel.welcome_tagline` (`:542`) | `channel_web_widgets.welcome_tagline` |
| **Cor do widget** | `components-next/colorpicker/ColorPicker.vue` | `948` | `channel.widget_color` (`:538`) | `channel_web_widgets.widget_color` |
| **Posição da bolha** | `SelectInput` (left/right) | `965-982` | **nenhum** | **`localStorage`** (`:507-512`) |
| **Tipo da bolha** | `SelectInput` (standard/expanded_bubble) | `993-1010` | **nenhum** | **`localStorage`** |
| **Título do lançador** | `woot-input` | `1022-1030` | **nenhum** | **`localStorage`** |
| Tempo de resposta | `SelectInput` (3 opções) | `1038-1060` | `channel.reply_time` (`:544`) | enum `reply_time` |
| Anexos / Emoji / Encerrar / Avatar do bot | 4 `<input type=checkbox>` | `1067-1112` | `channel.selectedFeatureFlags` (`:543`) | bitmask `feature_flags` |

**Acordeão "Preferências do canal"** (`Settings.vue:1116-1189`):

| Campo | Controle | Linha | Payload | Destino |
|---|---|---|---|---|
| Saudação (toggle + editor) | `SettingsToggleSection` + `GreetingsEditor` | `1120-1149` | `greeting_enabled`, `greeting_message` (`:523-524`) | `inboxes.*` |
| Coletar e-mail | toggle | `1151-1162` | `enable_email_collect` (`:521`) | `inboxes.*` |
| Permitir mensagem após resolver | toggle | `1164-1175` | `allow_messages_after_resolved` (`:522`) | `inboxes.*` |
| Continuidade por e-mail | toggle | `1177-1188` | `channel.continuity_via_email` (`:545`) | `channel_web_widgets.*` |

### A.3.2 Aba 7 — `configuration` (`ConfigurationPage.vue`)

Aqui **não há botão único**: cada controle salva sozinho, por `watch` (`:67-82`) `[FATO]`.

| Campo | Controle | Linha | Como salva | Destino |
|---|---|---|---|---|
| Domínios permitidos | `next/textarea/TextArea.vue` + botão | `300-315` | `updateAllowedDomains()` (`:180-201`), passa por `sanitizeAllowedDomains` (`helper/URLHelper.js:165-184`) | `channel_web_widgets.allowed_domains` |
| Permitir WebView mobile | toggle | `318-324` | `handleMobileWebviewFlag()` (`:160-179`) | bitmask `feature_flags` (`allow_mobile_webview`) |
| Chave HMAC | `woot-code` **somente leitura** | `342` | — | `channel_web_widgets.hmac_token` |
| Exigir identidade verificada | toggle | `359-369` | `handleHmacFlag()` → `updateInbox()` (`:142-159`) | `channel_web_widgets.hmac_mandatory` |
| Modo de fixar conversa | 2 radios | `515-563` | `updatePinMode()` (`:101-122`) | `inboxes.additional_attributes.pin_mode` |

`allowed_domains` não é decorativo: `widgets_controller.rb:79-86` usa o valor para montar
`Content-Security-Policy: frame-ancestors …`, e **remove** o `X-Frame-Options` quando o campo está
vazio `[FATO]`. Ou seja, **campo vazio = qualquer site pode embutir o widget da inbox**. Hoje a tela
não diz isso em lugar nenhum.

### A.3.3 Aba 6 — `pre-chat-form`

`PreChatForm/Settings.vue` (166 l.) + `PreChatForm/PreChatFields.vue` (107 l.) `[MEDIDO]`.

- Toggle "ativar" + editor da mensagem (`Settings.vue:98-111`).
- Tabela de campos com **7 colunas fixas** (`:38-46`): arrastar · ligado · nome · tipo · obrigatório
  · rótulo · placeholder.
- Reordenação por `vuedraggable` (`PreChatFields.vue:39-44`).
- Gravação: `updateInbox()` (`Settings.vue:69-87`) manda
  `channel.pre_chat_form_enabled` + `channel.pre_chat_form_options = { pre_chat_message, pre_chat_fields }`.

A lista de campos exibida é a união de **campos padrão** com **atributos personalizados da conta**:
`dashboard/helper/preChat.js:76-98` (`getPreChatFields`) mescla `pre_chat_form_options.pre_chat_fields`
com `attributes/getAttributes` do store `[FATO]`.

Duas coisas ali merecem registro:

- `preChat.js:1-4` faz `import i18n from 'widget/i18n/index'` e usa **só o `en`** para rotular os
  campos padrão `[FATO]`. Consequência: **o dashboard importa o pacote de i18n do widget** (40
  `import` estáticos de JSON, 205.494 bytes — medido em `15 §A5.1`) e o rótulo padrão do campo
  aparece em inglês independentemente do idioma do painel.
- `PreChatFields.vue:18-20` (`isFieldEditable`) desabilita rótulo/placeholder quando o campo está
  **desligado** — o nome da função diz o contrário do que ela faz `[FATO]`. É confuso de ler, não é
  bug de comportamento.

### A.3.4 O preview ao vivo

**Não é o `WidgetBuilder.vue`.** O preview que aparece hoje ao lado da aba 1 é
`dashboard/modules/widget-preview/components/Widget.vue` (330 l.), instanciado em
`Settings.vue:1218-1230` `[FATO]`, com `WidgetHead.vue` / `WidgetBody.vue` / `WidgetFooter.vue`.

Ele tem duas abas próprias (`Widget.vue:70-81`): **Prévia** e **Script**.

- A prévia reflete: título e frase de boas-vindas, nome do site, logo, tempo de resposta, cor
  (`:style="{ background: props.color }"` no launcher, `Widget.vue:208`), posição da bolha
  (`:126-128`), tipo da bolha e título do lançador (`:130-138`) `[FATO]`.
- A aba Script monta o snippet assim (`Widget.vue:94-101`) `[FATO]`:

```js
const script = props.webWidgetScript;          // vem do backend, web_widget.rb:64-82
return script.substring(0, 13)
     + t('INBOX_MGMT.WIDGET_BUILDER.SCRIPT_SETTINGS', { options: JSON.stringify(options) })
     + script.substring(13);
```

E a chave de tradução usada é literalmente **uma linha de código** `[MEDIDO]`:

```
INBOX_MGMT.WIDGET_BUILDER.SCRIPT_SETTINGS = "\n      window.chatwootSettings = {options};"
```

Ou seja: **JavaScript executável mora dentro de um arquivo de i18n**, e é injetado por corte de
string no byte 13. Qualquer tradutor que "melhore" essa string quebra o snippet do cliente.

### A.3.5 `WidgetBuilder.vue` — 443 linhas mortas que só nós carregamos

`[MEDIDO]` — `grep -rn "WidgetBuilder" app/javascript/` retorna **zero** ocorrências além do próprio
arquivo. Ele não é importado nem roteado.

E a história explica por quê `[MEDIDO]`:

```
$ git show --stat 7b2b3ac37d -- .../inbox/WidgetBuilder.vue
7b2b3ac37d feat(V5): Update settings pages UI (#13396)
 .../settings/inbox/WidgetBuilder.vue | 443 ---------------------
$ git merge-base --is-ancestor 7b2b3ac37d HEAD   → SIM
$ git cat-file -e v4.12.1:.../WidgetBuilder.vue  → não existe
$ git cat-file -e v4.16.2:.../WidgetBuilder.vue  → não existe
```

**O upstream apagou o arquivo no commit `7b2b3ac37d` (#13396), esse commit está na nossa história,
e o arquivo continua no disco com as 443 linhas.** `[INFERÊNCIA]` — a deleção foi desfeita numa
resolução de conflito de merge. Não reconstruí qual merge; o fato relevante é o estado: arquivo
órfão, ausente do upstream, com 219 linhas de divergência em relação à versão original de 2022
`[MEDIDO]`.

**Apagar não tem risco de merge nenhum** (o upstream já não o tem) e remove 443 linhas de ruído de
uma pasta que vamos reescrever.

## A.4 Como o dado sobe — o caminho completo

```
Settings.vue:551  this.$store.dispatch('inboxes/updateInbox', payload)
  → store/modules/inboxes.js:288-301
      formData ? buildInboxData(inboxParams) : inboxParams      ← multipart quando há avatar
  → InboxesAPI.update(id, ...)                                   PATCH /api/v1/accounts/:id/inboxes/:id
  → app/controllers/api/v1/accounts/inboxes_controller.rb:47-59  #update
      ├ permitted_params.except(:channel, :csat_config, :nps_config)   → @inbox.update!
      ├ additional_attributes: merge com o que já existe (:52-56, alteração DO FORK)
      ├ update_inbox_working_hours (:118-120)
      └ update_channel (:121-127) se channel_update_required? (:129-131)
            ├ @inbox.channel.update!(permitted_params(channel_attributes)[:channel])  (:145-148)
            └ update_channel_feature_flags (:151-157)   ← trata selected_feature_flags à parte
  → app/models/channel/web_widget.rb
      EDITABLE_ATTRS (:34-40)  ·  has_flags (:50-56)  ·  enum reply_time (:58)
      before_validation :validate_pre_chat_options (:42, :84-101)
```

**Os dois filtros que decidem o que é possível gravar:**

1. **`Channel::WebWidget::EDITABLE_ATTRS`** (`app/models/channel/web_widget.rb:34-40`) `[FATO]` —
   fecha os atributos do canal, **incluindo a forma de cada campo do pre-chat**:

```ruby
EDITABLE_ATTRS = [:website_url, :widget_color, :welcome_title, :welcome_tagline, :reply_time,
                  :pre_chat_form_enabled, :continuity_via_email, :hmac_mandatory, :allowed_domains,
                  { pre_chat_form_options: [:pre_chat_message, :require_email,
                     { pre_chat_fields: [:field_type, :label, :placeholder, :name, :enabled, :type,
                        :enabled, :required, :locale, { values: [] }, :regex_pattern, :regex_cue] }] },
                  { selected_feature_flags: [] }].freeze
```

   (`:enabled` aparece **duas vezes** na lista — inócuo, mas é sintoma de edição manual `[FATO]`.)

2. **`inbox_attributes`** (`app/controllers/api/v1/accounts/inboxes_controller.rb:210-218`) `[FATO]`
   — fecha os atributos da inbox, e o `additional_attributes` **é uma lista fechada**, linha `217`:

```ruby
{ additional_attributes: [:pin_mode, :agent_signature_enabled,
                          { pinned_conversation_ids: [], allowed_template_names: [] }] },
```

> ### `[DIVERGÊNCIA]` — "`additional_attributes` é jsonb livre, sem tocar em `EDITABLE_ATTRS`"
>
> O relatório `10 §4.1 (C1)` recomenda encaixar a configuração nova em
> `inbox.additional_attributes` descrevendo-o como *"jsonb livre, sem migration, sem tocar em
> `EDITABLE_ATTRS`"*, e a task 25 repete isso em **T-C1.1**.
>
> **A parte sobre `EDITABLE_ATTRS` está correta** — aquele é o filtro do *canal*, e
> `additional_attributes` é da *inbox*. **A parte "livre" não está.** Strong params rejeita chave
> não declarada: gravar `additional_attributes.tracking` exige **editar
> `inboxes_controller.rb:217`**.
>
> E esse arquivo não é neutro `[MEDIDO]`:
>
> ```
> git diff --numstat v4.12.1 v4.16.2 -- .../inboxes_controller.rb   → +53  −9   (upstream)
> git diff --numstat v4.12.1 HEAD    -- .../inboxes_controller.rb   → +87  −6   (fork)
> ```
>
> Os dois lados mexem. E o fork já mexeu **exatamente no `#update`** (`:52-56`, o merge de
> `additional_attributes`, com comentário em português).
>
> **Consequência para o plano:** toda configuração nova de inbox custa uma edição num arquivo 🔴.
>
> **ARBITRADO — PLANO-MESTRE §5 A1:** a mitigação **não** é um sub-hash único `widget_config`. São
> **três chaves de topo** — `widget_profile`, `widget_triggers`, `widget_tracking` — declaradas numa
> **única edição**, na primeira tarefa (bloco 3.01):
>
> ```ruby
> { additional_attributes: [:pin_mode, :agent_signature_enabled, :widget_profile,
>                           { pinned_conversation_ids: [], allowed_template_names: [],
>                             widget_triggers: {}, widget_tracking: {} }] },
> ```
>
> A preocupação legítima desta seção (não pagar N edições no arquivo 🔴 ao longo de meses) fica
> atendida do mesmo jeito — declaradas as três de uma vez, a evolução posterior acontece **dentro**
> dos jsonb, que são hash aberto (`{}`), sem tocar mais no controller. O que **não** funciona é a
> chave única: o `#update` faz `(@inbox.additional_attributes || {}).merge(…)` — **primeiro nível
> apenas** (`:52-56`) — então um `PATCH` parcial de gatilhos **apagaria** perfil e tracking.

## A.5 Os **três** lugares que montam a configuração do widget

O relatório `15 §A3.3` (e o `09 §6.2`, citado pelo `10 §4.1`) apontam **dois**: o ERB e o jbuilder.
Confirmo os dois e acrescento um terceiro.

| # | Arquivo | Formato | Chaves | Quem consome |
|---|---|---|---:|---|
| 1 | `app/views/widgets/show.html.erb:7-35` | `window.chatwootWebChannel` inline no HTML | **22** | O widget web, antes de qualquer bundle carregar |
| 2 | `app/views/api/v1/widget/configs/create.json.jbuilder:1-25` | JSON, `POST /api/v1/widget/config` (rota em `config/routes.rb:595`) | **23** | `[INFERÊNCIA]` clientes fora deste repositório (SDKs mobile) — `grep` por consumidor em `app/javascript/` retorna vazio `[MEDIDO]`. Quem exatamente consome: `[NÃO VERIFICADO]` |
| 3 | `app/javascript/dashboard/modules/widget-preview/components/Widget.vue:85-102` | String de snippet montada no front | 3 opções | O **cliente**, que cola no site dele |

**E os dois primeiros já divergem hoje** `[MEDIDO]` — comparação chave a chave, normalizando
camelCase/snake_case:

| Chave | ERB | jbuilder |
|---|:---:|:---:|
| `hasAConnectedAgentBot` | **sim** (`:10`) | **não** |
| `api_host` | **não** | **sim** (`:3`) |
| `auth_token` | fora do objeto (`window.authToken`, `:33`) | **sim, dentro** (`:4`) |
| `utcOffset` × `utc_off_set` | `utcOffset` (`:27`) | `utc_off_set` (`:17`) → camelizado vira `utcOffSet` |

O último é um `[FATO]` de nome divergente; se isso quebra o consumidor depende de como ele
normaliza — `[NÃO VERIFICADO]`.

**Isto não é curiosidade: é a regra de aceite da §C.3.** Toda chave nova de configuração tem de
entrar nos dois, e a única maneira de isso não se perder ao longo de quatro telas é um teste que
compare os dois conjuntos.

> **Nota de precisão de citação.** O briefing desta task remete a "`15 §A3.3`" para os dois lugares.
> A §A3.3 daquele relatório trata do bug `bg-n-brand` e cita `show.html.erb:16` de passagem; a
> afirmação sobre "dois lugares" aparece no `10 §4.1 (C1)`, atribuída a `09 §6.2`. Registro para
> quem for conferir e não achar no parágrafo citado. **O conteúdo está correto — e agora medido.**

## A.6 O que **não** está no banco: `chatwootSettings` e `localStorage`

Este é o achado estrutural desta task, e ele muda o desenho das quatro telas.

`app/javascript/entrypoints/sdk.js:58-83` monta `window.$chatwoot` a partir de
`window.chatwootSettings` — o objeto que o **cliente escreve no site dele** `[FATO]`. Os campos:

`hideMessageBubble` · `position` · `locale` · `useBrowserLanguage` · `type` · `launcherTitle` ·
`showPopoutButton` · `showUnreadMessagesDialog` · `widgetStyle` · `darkMode` · `welcomeTitle` ·
`welcomeDescription` · `availableMessage` · `unavailableMessage` · `enableFileUpload` ·
`enableEmojiPicker` · `enableEndConversation` · `baseDomain`

E todos eles chegam ao widget pelo evento `config-set`
(`app/javascript/sdk/IFrameHelper.js:163-179`) `[FATO]`.

**Do lado do dashboard, três desses campos têm controle na tela — e são gravados no `localStorage`
do navegador do administrador**, não no servidor:

```js
// Settings.vue:350-352
widgetBuilderStorageKey() { return `${LOCAL_STORAGE_KEYS.WIDGET_BUILDER}${this.inbox.id}`; }
// dashboard/constants/localStorage.js:3
WIDGET_BUILDER: 'widgetBubble_'
// Settings.vue:507-512  (dentro de updateInbox, antes do try)
LocalStorage.set(this.widgetBuilderStorageKey, { position, type, launcherTitle });
```

`[FATO]`. E são relidos em `Settings.vue:418-430`.

**As três consequências, todas verificáveis:**

1. **Posição, tipo de bolha e título do lançador não são configuração do produto.** São um
   rascunho local que só serve para montar o snippet. Trocar a posição do launcher exige que o
   cliente **edite o código do site**.
2. **Outro administrador, outro navegador, outros valores.** O segundo admin abre a tela e vê
   `right`/`standard`/vazio, independentemente do que o primeiro configurou e do que está rodando
   no site do cliente.
3. **A tela mente sobre o estado real.** O widget em produção pode estar `left`, e a tela mostrar
   `right`, porque a fonte de verdade é o snippet no site — que a tela não lê.

`[INFERÊNCIA]` — nenhum dos concorrentes medidos no estudo opera assim: o `14 §5.1` mostra a
Leadster resolvendo *tudo* no servidor num request só, e o `14 §5.2` mostra o Intercom devolvendo
`launcher_settings` do servidor. A decisão do Walisson — *"faça como as grandes empresas fazem"* —
aplicada aqui significa: **a configuração migra do snippet para o banco, e o snippet vira override
opcional.** Isso é a dependência **BE-2** da §C.2.

## A.7 Proatividade hoje: campanhas de chat ao vivo

Existe, e é menos do que parece.

- Modelo `Campaign` (`app/models/campaign.rb`), campo `trigger_rules` **jsonb** `[FATO]`.
- Formulário: `components-next/Campaigns/Pages/CampaignPage/LiveChatCampaign/LiveChatCampaignForm.vue`.
  O que ele grava (`:142-146`) `[FATO]`:

```js
trigger_rules: { url: state.endPoint, time_on_page: state.timeOnPage }
```

- Avaliação: **100% no cliente**, dentro do iframe. `widget/helpers/campaignHelper.js:33-46`
  (`filterCampaigns`) casa a URL com `URLPattern` e checa horário comercial; o disparo é por
  `campaignTimer` `[FATO]`. As campanhas são buscadas uma vez e **cacheadas por 1 hora**
  (`widget/store/modules/campaign.js:49-50`) `[FATO]`.
- Strong params: `campaigns_controller.rb:60` aceita `trigger_rules: {}` — **hash aberto** `[FATO]`.
  Diferente da inbox, aqui não há lista fechada.

Comparando com o que o estudo mediu na Leadster (`14 §5.1`): **1 gatilho contra 7**, **sem
separação desktop/mobile**, **sem cooldown por gatilho**, **sem seletor CSS**, e a única
segmentação é URL. O `14 §5.4` já registra isso na coluna "ChatSPX (hoje)".

## A.8 Tracking hoje: nada

`[FATO, 07 §6.2, reconfirmado por grep nesta task]` — zero ocorrências de `fbq`, `gtag` ou
`dataLayer` em `app/`. Não existe tela, campo, coluna ou endpoint. A Tela 4 é construção do zero,
e a §A.3 da task 25 é o par obrigatório dela.

## A.9 O que já existe em `components-next/` — usar, não reinventar

Levantei as props reais de cada um `[MEDIDO]` (o script está no Anexo B). **Nenhuma das quatro
telas precisa de um componente de formulário novo.**

| Componente | Caminho | Props principais | Onde uso no plano |
|---|---|---|---|
| `SettingsFieldSection` | `Settings/SettingsFieldSection.vue` | `label`, `helpText` + slots `default`/`extra` | Linha rótulo→controle das 4 telas |
| `SettingsToggleSection` | `Settings/SettingsToggleSection.vue` | `header`, `description`, `compact`, `hideToggle`, `v-model` Boolean + slot `editor` | Todo bloco liga/desliga com detalhe embaixo |
| `SettingsAccordion` | `Settings/SettingsAccordion.vue` | `title`, `defaultOpen` | Seções "Avançado" das 4 telas |
| `Input` | `input/Input.vue` | `modelValue`, `type`, `label`, `placeholder`, `message`, `messageType`, `min`, `max`, `disabled`; emite `blur`/`enter` | Campos de texto e número. **`message`+`messageType` são o canal de erro por campo** |
| `TextArea` | `textarea/TextArea.vue` | `maxLength`, `showCharacterCount`, `autoHeight`, `resize`, `message`, `messageType` | Texto do teaser (**contador de 90 caracteres sai de graça**) |
| `Select` | `select/Select.vue` | `options`, `groups`, `placeholder`, `error`, `v-model` | Enums curtos |
| `ComboBox` | `combobox/ComboBox.vue` | `options`, `searchPlaceholder`, `emptyState`, `hasError`, `creatable`; emite `search` | Listas longas e campos com criação (evento GA4, por ex.) |
| `TagInput` | `taginput/TagInput.vue` | `menuItems`, `allowCreate`, `mode`, `showDropdown` | UTMs, etiquetas, lista de URLs |
| `Switch` | `switch/Switch.vue` | `v-model` Boolean; emite `change` | Toggle isolado |
| `Checkbox` | `checkbox/Checkbox.vue` | `indeterminate`, `disabled` | Múltipla escolha (substitui os 4 `<input type=checkbox>` crus de `Settings.vue:1067-1112`) |
| `RadioCard` | `radioCard/RadioCard.vue` | `id`, `label`, `description`, `isActive`, `disabled`, `disabledLabel`, `disabledMessage`; emite `select` | **Seletor de perfil** e modo de tema |
| `DurationInput` | `input/DurationInput.vue` | `min`, `max`, `v-model` Number | Cooldown, tempo na página |
| `ChoiceToggle` | `input/ChoiceToggle.vue` | `v-model` Boolean | Alternância curta desktop/mobile |
| `ColorPicker` | `colorpicker/ColorPicker.vue` | `modelValue`; emite `update:modelValue` com `e.hex` | Cor da marca |
| `Editor` | `Editor/Editor.vue` | `maxLength`, `channelType` | Textos ricos |
| `TabBar` | `tabbar/TabBar.vue` | `tabs`, `initialActiveTab`; emite `tabChanged` | Sub-abas dentro de uma tela |
| `BaseTable` | `table/BaseTable.vue` | `headers`, `items`, `noDataMessage`, `loading` | Mapa de eventos, log de diagnóstico |
| `Dialog` | `dialog/Dialog.vue` | `type`, `title`, `description`, `confirmButtonLabel`, `isLoading`, `width` | Confirmações destrutivas |
| `Banner` | `banner/Banner.vue` | `color`, `actionLabel`; emite `action` | Avisos no topo da tela |
| `EmptyStateLayout` | `EmptyStateLayout.vue` | `title`, `subtitle`, `actionPerms`, `showBackdrop` | Estado vazio (nenhum gatilho, nenhum evento) |
| `Spinner` | `spinner/Spinner.vue` | `size` | Carregando |
| `Avatar` | `avatar/Avatar.vue` | `src`, `size`, `iconName`, `allowUpload`; emite `upload`/`delete` | Avatar da inbox e do teaser |

Duas bibliotecas já instaladas que o plano usa e **não precisam de dependência nova** `[MEDIDO]`,
`package.json`:

- **`color2k@^2.0.2`** (linha 74) — `getContrast`, `getLuminance`, `mix`, `toHex`. Já usado em
  `shared/helpers/colorHelper.js`. **É o motor do medidor de contraste da Tela 1.**
- **`company-email-validator@^1.1.0`** (linha 75) — hoje usado só em
  `v3/views/auth/signup/components/Signup/Form.vue:16,39` `[FATO]`. **É o validador de "e-mail
  corporativo" da Tela 3, de graça.**
- **`libphonenumber-js@^1.11.9`** (linha 93) — o widget já registra as regras `startsWithPlus` e
  `isValidPhoneNumber` no FormKit (`entrypoints/widget.js:32-40`) `[FATO]`.
- **`vuedraggable@^4.1.0`** (linha 128) — já usado na tabela do pre-chat.

**O que não existe e vai precisar ser escrito:** máscara e validação de **CPF, CNPJ, CEP e UF**.
Nenhuma biblioteca brasileira no `package.json` `[MEDIDO]`. `[DECISÃO]` — escrever helper próprio
(dígito verificador de CPF/CNPJ é aritmética de 20 linhas; máscara é regex) em vez de adicionar
dependência, porque o mesmo helper terá de rodar **dentro do widget**, onde cada KB é medido pelo
orçamento de bundle da task 22.

## A.10 i18n — o estado medido

`[MEDIDO]` — comparação chave a chave de `INBOX_MGMT` entre `en` e `pt_BR`:

```
total en 764  ·  total pt_BR 801
faltando em pt_BR:  0
faltando em en:    37   ← todas do bloco NPS
```

**As 37 chaves são todas de `NPS.*`** — a feature é do fork e foi escrita só em português. E a aba
NPS é renderizada com `$t('INBOX_MGMT.TABS.NPS')` (`Settings.vue:168`) `[FATO]`, chave que existe em
`pt_BR` e **não** em `en`: num painel em inglês, o rótulo da aba cai no fallback da chave crua.

Duas chaves órfãs, também medidas: `INBOX_MGMT.TABS.CAMPAIGN` e `INBOX_MGMT.TABS.WIDGET_BUILDER`
existem nos dois idiomas e **não têm um único uso** em `app/javascript/` `[MEDIDO]`.

`[DECISÃO]` que vale para as quatro telas: **pt-BR é a prioridade** (regra do projeto), mas **toda
chave nova nasce nos dois arquivos, no mesmo commit**. O que aconteceu com o NPS é a prova de que
"depois eu traduzo" não acontece. E o `en/inboxMgmt.json` é 🔴 de merge (§A.11) — cada bloco novo
deve ficar num objeto próprio de primeiro nível, longe das regiões que o upstream edita.

## A.11 Risco de merge — o mapa desta superfície

`[MEDIDO]` — `git diff --numstat` em duas direções. "Upstream" é `v4.12.1 → v4.16.2` (o que nos
espera no próximo merge); "fork" é `v4.12.1 → HEAD` (o que já divergimos).

| Arquivo | Upstream | Fork | Veredito |
|---|---:|---:|---|
| `settings/inbox/Settings.vue` | **+242 −24** | **+99 −18** | 🔴 **Campo minado dos dois lados** |
| `i18n/locale/en/inboxMgmt.json` | **+213 −12** | (só adições de NPS) | 🔴 Conflito por região |
| `settingsPage/ConfigurationPage.vue` | +63 −42 | **+108 −0** | 🔴 |
| `api/v1/accounts/inboxes_controller.rb` | **+53 −9** | **+87 −6** | 🔴 |
| `api/v1/models/_inbox.json.jbuilder` | +28 −5 | +7 −0 | 🟡 |
| `components-next/Settings/SettingsToggleSection.vue` | +5 −1 | +5 −5 | 🟡 |
| `components-next/colorpicker/ColorPicker.vue` | +1 −1 | 0 | 🟢 |
| `components-next/Settings/SettingsFieldSection.vue` | 0 | +5 −3 | 🟢 |
| `components-next/Settings/SettingsAccordion.vue` | 0 | +5 −1 | 🟢 |
| `PreChatForm/Settings.vue` | +2 −4 | 0 | 🟢 |
| `PreChatForm/PreChatFields.vue` | 0 | 0 | 🟢 |
| `modules/widget-preview/components/Widget.vue` | 0 | 0 | 🟢 |
| `modules/widget-preview/components/WidgetBody.vue` | 0 −2 | 0 | 🟢 |
| `models/channel/web_widget.rb` | **0** | **0** | 🟢 **Intocado dos dois lados** |
| `views/widgets/show.html.erb` | **0** | **0** | 🟢 |
| `views/api/v1/widget/configs/create.json.jbuilder` | **0** | **0** | 🟢 |
| `settingsPage/NetPromoterScorePage.vue` | — | +794 (novo) | 🟢 Arquivo só nosso |
| `settings/inbox/WidgetBuilder.vue` | **removido** (`7b2b3ac37d`) | +443 (ressuscitado) | ⚫ Morto — apagar |

**Três conclusões que estruturam o plano inteiro:**

1. **O backend do widget é zona segura.** `web_widget.rb`, `show.html.erb` e o jbuilder de config do
   widget tiveram **zero** mudanças do upstream em quatro minors. Ampliar `EDITABLE_ATTRS` e as duas
   folhas de config é barato — ao contrário do que o instinto sugere.
2. **`Settings.vue` é o pior arquivo desta superfície.** Os dois lados o reescrevem. **Nada de
   redesenho deve entrar por dentro dele.** Vale a mesma regra que o `15 §B12.4` deu para o widget:
   arquivos novos em pastas novas, e `Settings.vue` reduzido a um roteador de abas que delega.
3. **Os componentes de `components-next/Settings/` são estáveis.** Construir as telas sobre eles
   (em vez de sobre HTML solto) é a defesa mais barata que existe aqui.

## A.12 Defeitos e dívidas verificados nesta task

Numerados para poderem ser referenciados nas tarefas da Parte C. Nenhum depende de decisão de
escopo — todos são estado atual, em produção.

| # | Defeito | Prova | Esforço |
|---|---|---|---|
| **D1** | **Posição, tipo de bolha e título do lançador vivem no `localStorage` do admin.** Não são configuração; a tela mostra um valor que pode não ser o do site | `Settings.vue:350-352, 418-430, 507-512`; `constants/localStorage.js:3` | M (depende de BE-2) |
| **D2** | **O `ColorPicker` muta o store direto.** `v-model="inbox.widget_color"` onde `inbox` é o getter `inboxes/getInbox` (`Settings.vue:231-233`). Mexer no seletor altera o objeto do Vuex antes de qualquer `dispatch`; sair sem salvar deixa o store sujo até um refetch | `Settings.vue:948` × `:231-233` × `:538` | P |
| **D3** | **`window.chatwootSettings` é montado por corte de string no byte 13, e o código mora no i18n** | `widget-preview/Widget.vue:94-101`; chave `INBOX_MGMT.WIDGET_BUILDER.SCRIPT_SETTINGS` | P |
| **D4** | **O preview duplica a paleta do widget em SCSS literal** — ~74 declarações de custom property hardcoded, em dois blocos (claro e escuro). Quando os tokens do widget mudarem (Task 21/22), o preview dessincroniza **em silêncio** | `widget-preview/Widget.vue:254-328` | M |
| **D5** | **`WidgetBuilder.vue`: 443 linhas órfãs, ausentes do upstream** | §A.3.5 | P |
| **D6** | **37 chaves de i18n só existem em pt-BR**; a aba NPS usa uma delas | §A.10 | P |
| **D7** | **Duas chaves de i18n órfãs** (`TABS.CAMPAIGN`, `TABS.WIDGET_BUILDER`) | §A.10 | P |
| **D8** | **`allowed_domains` vazio remove o `X-Frame-Options`** e a tela não avisa | `widgets_controller.rb:79-86` | P |
| **D9** | **ERB e jbuilder de config já divergem** em 4 chaves | §A.5 | P |
| **D10** | **O dashboard importa o i18n do widget** para rotular o pre-chat, e usa só `en` | `dashboard/helper/preChat.js:1-4, 24-33` | P |
| **D11** | **Default de cor divergente:** a tela de criação nasce `#2dc46f` (`channels/Website.vue:21`, literal do fork — a única linha que o fork mudou nesse arquivo `[MEDIDO]`), o banco tem `default: "#1f93ff"` (`db/schema.rb:754`). Inbox criada por API nasce azul; pela tela, verde | `Website.vue:21` × `schema.rb:754` | P |

---

# PARTE B — O PLANO DAS QUATRO TELAS

## B.0 A arquitetura comum, antes das telas

### B.0.1 Estrutura de arquivos — a defesa de merge

Mesma regra que o `15 §B12.4` estabeleceu para o widget, aplicada aqui: **o redesenho mora em
pastas que o upstream não tem.**

```
app/javascript/dashboard/routes/dashboard/settings/inbox/
├─ Settings.vue                    ← 🔴 SÓ ganha 4 linhas: os 4 novos `v-if` de aba
└─ widget/                         ← 🟢 PASTA NOVA — tudo do redesenho mora aqui
   ├─ WidgetProfileSelector.vue        (§B.1)
   ├─ appearance/
   │   ├─ AppearancePage.vue
   │   ├─ BrandColorField.vue
   │   ├─ ContrastReadout.vue
   │   ├─ ThemeModeField.vue
   │   └─ LauncherField.vue
   ├─ triggers/
   │   ├─ TriggersPage.vue
   │   ├─ TriggerRow.vue
   │   ├─ TeaserComposer.vue
   │   └─ SegmentationField.vue
   ├─ prechat/
   │   ├─ PreChatPage.vue
   │   ├─ PreChatStepList.vue
   │   ├─ PreChatFieldEditor.vue
   │   └─ ConditionEditor.vue
   ├─ tracking/
   │   ├─ TrackingPage.vue
   │   ├─ DestinationCard.vue
   │   ├─ EventMapTable.vue
   │   └─ DiagnosticsPanel.vue
   └─ composables/
       ├─ useInboxWidgetConfig.js   ← leitura/escrita/dirty/salvar (uma vez, para as 4)
       ├─ useContrast.js            ← color2k, os 4 pares (§B.2.3)
       └─ useProfileVisibility.js   ← qual seção aparece em qual perfil
```

`app/javascript/dashboard/i18n/locale/{pt_BR,en}/inboxWidget.json` — **arquivo de i18n novo**, não
um bloco dentro de `inboxMgmt.json` (que é 🔴, §A.11). Registrar o namespace onde os outros são
registrados.

**Regra verificável por lint, no espírito do `15 §B8.3`:** nenhum arquivo em `inbox/widget/` importa
de `settings/inbox/*.vue` do upstream, e nenhum contém cor literal — só token ou classe `n-*`.

### B.0.2 O contrato de salvamento

Hoje há **duas** convenções conflitantes na mesma superfície: aba 1 salva tudo num botão
(`Settings.vue:506`), aba 7 salva a cada toggle (`ConfigurationPage.vue:67-82`) `[FATO]`.

`[DECISÃO]` — as quatro telas novas usam **rascunho explícito**:

- Toda edição vai para um estado local; nada vai ao servidor sozinho.
- Barra fixa no rodapé aparece quando há alteração pendente: `N alterações não salvas` ·
  **Descartar** · **Salvar**.
- Sair da aba com alteração pendente pede confirmação (`Dialog`).
- **Razão:** três das quatro telas têm campos interdependentes (a cor muda o contraste calculado; o
  perfil muda quais seções existem; um gatilho tem 6 subcampos). Salvamento automático em campo
  interdependente grava estado inconsistente — e no caso dos gatilhos, um estado que **dispara
  para visitante real** enquanto o admin ainda está editando.

`useInboxWidgetConfig.js` centraliza: carrega do `inboxes/getInbox`, mantém a cópia editável,
calcula `isDirty`, monta o payload e despacha `inboxes/updateInbox` com `formData: false`.
**Nunca muta o objeto do store** — o que corrige **D2** por construção.

### B.0.3 Estados obrigatórios em cada tela

| Estado | Como | Componente |
|---|---|---|
| Carregando | Enquanto `uiFlags.isFetching` | `spinner/Spinner.vue` (o `Settings.vue:604-610` já faz assim) |
| Vazio | Nenhum gatilho / nenhum destino / nenhum evento | `EmptyStateLayout.vue` com ação primária |
| Erro de campo | `message` + `messageType="error"` no próprio `Input`/`TextArea` | nativo do componente |
| Erro de gravação | `useAlert()` **e** faixa persistente na tela — o toast some e o usuário não sabe o que falhou | `Banner.vue` |
| Salvo | Barra some, toast de sucesso, `updated_at` visível na tela | — |
| Sem permissão | Aba não renderiza; se acessada por URL direta, `EmptyStateLayout` explicando | — |

**Erro de gravação merece nota:** hoje as telas usam só `useAlert(error.message || …)`
(`Settings.vue:554-556`, `ConfigurationPage.vue:156-158`) `[FATO]`. Um toast que some não é
suficiente para uma tela onde o usuário acabou de configurar dez campos.

### B.0.4 Permissão

Hoje: `administrator` para a tela inteira (`inbox.routes.js:101`) `[FATO]`, e existe
`helper/permissionsHelper.js` com `hasPermissions`/`getUserRole`, incluindo `custom_role` `[FATO]`.

`[DECISÃO]` — manter `administrator` como piso das quatro telas na primeira entrega. **Uma exceção
a considerar depois:** a Tela 4 (tracking) contém segredos (access token, api_secret) e é a única
que justificaria uma permissão própria. Registro como decisão futura, não faço agora.

### B.0.5 Responsividade e acessibilidade — o piso das quatro

O `SettingsFieldSection` já usa `grid-cols-1 lg:grid-cols-8` `[FATO]`, então a coluna única em
telas estreitas vem de graça. O que **não** vem e é obrigatório:

- Todo controle com `<label for>` real, ou `aria-label`. Os checkboxes de
  `Settings.vue:1067-1112` têm `<label for="attachments">` sem `id` correspondente no input
  `[FATO]` — o clique no rótulo não foca o campo. Não repetir.
- Erro de campo referenciado por `aria-describedby`, e o campo com `aria-invalid`.
- A barra de salvar é `role="region"` com `aria-live="polite"` anunciando "N alterações não salvas".
- Contraste do próprio painel: os textos de ajuda usam `text-n-slate-10`; o `13 §3.3` fixa 4,5:1
  para texto normal. **`[NÃO VERIFICADO]`** — não medi o contraste do dashboard nesta task. Fica
  como item de aceite (§C.3), não como afirmação.
- Ordem de foco: a barra de salvar entra **depois** do conteúdo, não antes.

---

## B.1 Tela 0 — o seletor de perfil (marketing × suporte)

> Decisão do Walisson, já tomada. O que segue é **onde fica, o que muda e como não quebrar quem já
> está em produção** — não se é para fazer.

### B.1.1 Onde fica

**No topo da aba `inbox-settings`**, antes de qualquer outro campo — dois `RadioCard` lado a lado
(`components-next/radioCard/RadioCard.vue`, props `id`/`label`/`description`/`isActive`, emite
`select`) `[FATO]`.

`[DECISÃO]` — **não** é uma aba própria. O perfil não é uma configuração entre outras: ele
determina **quais** configurações existem. Precisa estar visível antes das outras escolhas, e
precisa ser o primeiro campo que alguém vê ao abrir a caixa.

Trocar o perfil abre um `Dialog` de confirmação listando, nominalmente, o que vai ser escondido e o
que continua gravado. **Nada é apagado na troca** — as configurações do perfil anterior ficam no
banco, inertes, e voltam se o perfil voltar. `[DECISÃO]` — perda silenciosa de configuração é a
falha mais cara que uma tela de settings pode ter.

### B.1.2 O que cada perfil significa

| | **Suporte** | **Marketing** |
|---|---|---|
| Pergunta que responde | "meu cliente precisa de ajuda" | "esse visitante pode virar cliente" |
| Postura do widget | Reativo — espera o clique | Convidativo — teaser com gatilho |
| Pré-chat | Curto (nome + e-mail), pula se já identificado | Multi-etapa, qualificação, telefone obrigatório |
| Destino da conversa | Fila de atendimento no ChatSPX | Pode terminar em WhatsApp |
| Fecho do ciclo | CSAT / NPS | Evento de conversão (Tela 4) |
| Continuidade | Por e-mail, histórico visível | Por WhatsApp |
| Base de conhecimento | Central de Ajuda no painel inicial | Desligada por padrão |

### B.1.3 Matriz de visibilidade — o que aparece em qual perfil

`[DECISÃO]` — a coluna "sempre" é o que não muda, e é maior do que parece. O perfil esconde
**seções**, nunca campos soltos no meio de uma seção.

| Seção | Suporte | Marketing | Observação |
|---|:---:|:---:|---|
| **Tela 1 — Aparência** | | | |
| Cor, tema, avatar, textos, posição, offsets | ✅ | ✅ | |
| Bolha "expandida" com texto no lançador | — | ✅ | Convite; em suporte polui |
| Branding "Powered by" | ✅ | ✅ | |
| **Tela 2 — Gatilhos** | | | |
| Gatilhos e teaser | **oculto** | ✅ | Em suporte, teaser é interrupção |
| Segmentação por URL/UTM/dispositivo | **oculto** | ✅ | |
| **Tela 3 — Pré-chat** | | | |
| Modo simples (até 3 campos) | ✅ | ✅ | |
| Construtor multi-etapa + condicionais | **oculto** | ✅ | |
| Máscaras BR (CPF/CNPJ/CEP…) | ✅ | ✅ | Suporte também precisa de CPF |
| Lead incompleto | **oculto** | ✅ | Conceito de marketing |
| Vínculo com Flows | ✅ | ✅ | |
| **Tela 4 — Tracking** | | | |
| Pixel/GA4/GTM + eventos | **oculto** por padrão, destravável | ✅ | Suporte pode querer medir CSAT no GA4 |
| **Abas existentes** | | | |
| CSAT | ✅ | oculto por padrão | |
| NPS | ✅ | oculto por padrão | |
| Continuidade por e-mail | ✅ (ligada) | ✅ (desligada) | Só muda o default |
| Central de Ajuda na inbox | ✅ | ✅ (vazio por padrão) | |

**Regra dura:** perfil **esconde**, não **remove**. Toda seção oculta ganha um link discreto
"mostrar configurações de {outro perfil}" no rodapé da tela. Um cliente de suporte que queira medir
conversão não pode ficar refém do rótulo.

### B.1.4 O que o perfil muda no widget

> **ARBITRADO — PLANO-MESTRE §5 A3: o widget recebe o perfil já resolvido em flags planas
> (`profileConfig`), e nunca ramifica pelo nome do perfil.** A afirmação original desta seção — *"o
> perfil não é lido pelo widget, vive só no dashboard"* — **não vale mais**: o servidor resolve
> (`WidgetProfile.resolve`) e entrega as 11 flags no payload de boot. O que continua verdadeiro, e é
> o ponto que esta seção acertou, é que **não existe `if (profile === 'marketing')` dentro do
> widget** — é o que impede a matriz de teste de dobrar (16 snapshots, não 32) e o que mantém
> possível o híbrido que o cliente sempre pede (marketing **com** base de conhecimento).

**A lista de flags é canônica e mora num lugar só:** `22-plano-widget.md` §B.3. Esta tela consome
aquela lista; quem precisar acrescentar, remover ou renomear flag muda **lá**, não aqui.

E o perfil governa **três regimes distintos** (A3) — a tabela abaixo é o regime 2, e só ele:

1. **Inbox nova** — o perfil **semeia** os defaults na criação (serviço de seed, plano 24 §9.4). Zero
   risco: não há valor a preservar.
2. **Inbox existente** — trocar o perfil **propõe**: abre um diálogo listando nominalmente cada
   mudança, com caixas marcáveis, e grava **só o que o administrador confirmar**. Nada é escrito em
   silêncio e nada é apagado — a configuração do perfil anterior fica no banco, inerte, e volta se o
   perfil voltar (garantia do `22` §B.1).
3. **Campos que só nascem agora** (teaser, base de conhecimento no widget, `homeLayout`,
   `captureFlow`, `primaryExit`) — não têm valor gravado, então são **resolvidos em runtime** pelo
   perfil até o cliente sobrescrever.

| O que o perfil **propõe** (regime 2: só grava com confirmação) | Suporte (`support`) | Marketing (`marketing`) |
|---|---|---|
| `pre_chat_form_enabled` | `false` | `true` |
| Gatilhos ativos | nenhum | preset composto (8 s + 30% de rolagem) |
| `continuity_via_email` | `true` | `false` |
| `csat_survey_enabled` | `true` | `false` |
| Central de Ajuda no painel inicial | ligada se houver portal | desligada |
| Tema padrão | `auto` (decisão F6 do `DECISOES.md`) | `auto` |

Valores gravados em **inglês** (`support` | `marketing`, **A2**); o rótulo que o administrador lê é
pt-BR, e vive no i18n.

### B.1.5 Compatibilidade com quem já está em produção

> **ARBITRADO — PLANO-MESTRE §5 A4: sem backfill.** Toda inbox Website existente fica **sem** a
> chave `widget_profile` gravada, e a **leitura** trata `nil` como `support` — que é literalmente o
> comportamento de hoje. Escrever `"support"` em toda inbox da frota é uma varredura de escrita para
> produzir **zero** diferença de comportamento, e toda escrita em massa na frota é risco sem
> contrapartida. **A tarefa T1.4 sai do plano.**

Razão de `support` ser a leitura padrão: é o comportamento de hoje (sem gatilho, sem teaser, CSAT
disponível, continuidade por e-mail ligada — que é o default da coluna, `web_widget.rb` /
`schema.rb:763`). Marcar como `marketing` mudaria comportamento de cliente em produção sem ninguém
pedir.

**Inbox nova**, criada em `channels/Website.vue`: o wizard pergunta, com os dois `RadioCard`, **sem
default pré-selecionado**. É uma pergunta de uma linha e evita a inbox nascer errada.

`[NÃO VERIFICADO]` — quantas inboxes Website existem na frota e como estão configuradas. Continua
valendo medir (é a verificação **V6** da §7 do mestre), mas **não** como pré-requisito de um backfill
que deixou de existir: serve para dimensionar o esforço de adoção e para saber quantos clientes veem
a tela nova.

### B.1.6 Componentes e tarefas

| Componente | Novo? | Base |
|---|---|---|
| `WidgetProfileSelector.vue` | novo | `RadioCard` ×2 + `Dialog` de confirmação |
| `composables/useProfileVisibility.js` | novo | mapa perfil → seções, consumido pelas 4 telas |

Depende de: **BE-1** (as três chaves de topo aceitas pelo strong params, numa edição só) e **BE-3**
(perfil no modelo, **sem backfill** — A4).

---

## B.2 Tela 1 — Aparência e tema

**Rota:** `…/inboxes/:inboxId/aparencia` · **Componente raiz:** `inbox/widget/appearance/AppearancePage.vue`

> **DECISÃO DO PRODUTO — 13/08/2026 (D5). Esta tela ganha o campo do ícone do lançador e um aviso.**
> Ver `PLANO-MESTRE` §2.2 bloco **3.19** (nove asserções) e §4 Onda 2 item 5c.
>
> - **Campo `launcher_icon` com três modos**: `default` (balão), `image` (upload) e `agent_photo`
>   (reusa o avatar da inbox). Ele mora em `widget_appearance` (bloco 3.18), que é a chave que a
>   auditoria mostrou faltar (bloqueador **B2**) e que o bloco 3.01 passou a declarar.
> - **Toda inbox nova nasce com `default`** — o balão na cor da marca, **em qualquer perfil**. O
>   padrão por perfil (foto no marketing) **caiu**. E o aceite verifica isso criando inbox **pela
>   tela e pela API**, que é onde o default costuma divergir (é o mesmo defeito que a dívida **D11**
>   deste plano descreve para a cor).
> - **Enquanto o modo for `default`, a tela mostra um aviso** recomendando subir a foto de alguém do
>   time, com a razão escrita ("rosto converte mais"). O aviso **não oferece nem linka banco de
>   imagem** — **nunca foto genérica**, em nenhum caminho da tela.
> - **Registro da engenharia, sem reabrir a decisão:** o corpus não traz teste comparando foto e
>   balão (9 dos 13 lançadores são balão em círculo; só a Leadster usa fotografia). A frase do aviso
>   é [INFERÊNCIA] de mercado; o bloco 4.21 e o A/B do 6.05 são o caminho para medi-la, e o texto é
>   uma string de i18n.

### B.2.1 Layout

Duas colunas em `lg`, empilhadas abaixo — o mesmo arranjo que a aba 1 já usa
(`Settings.vue:683-1232`), que é o que o usuário conhece:

```
┌───────────────────────────────┬──────────────────────┐
│ MARCA                         │                      │
│  Cor · [medidor de contraste] │   PREVIEW AO VIVO    │
│  Avatar · Nome exibido        │   [claro|escuro]     │
│                               │   [desktop|mobile]   │
│ TEMA                          │   [fechado|aberto]   │
│  claro | escuro | automático  │                      │
│                               │   ·······            │
│ LANÇADOR                      │   sticky top-4       │
│  posição · offsets · tipo     │                      │
│  título · esconder bolha      │                      │
│                               │                      │
│ TEXTOS                        │                      │
│  título · frase · resposta    │                      │
│                               │                      │
│ ▸ Avançado                    │                      │
│   branding · estilo do painel │                      │
└───────────────────────────────┴──────────────────────┘
```

### B.2.2 Campos

| Campo | Controle | Tipo/validação | Destino | Hoje |
|---|---|---|---|---|
| Cor da marca | `ColorPicker` + `Input` hex | `/^#[0-9a-f]{6}$/i`, obrigatório | `channel.widget_color` | existe (`Settings.vue:948`) |
| Avatar | `Avatar` (`allow-upload`) | imagem ≤ limite da conta | `inbox.avatar` | existe |
| Nome exibido | `Input` | 1–60 caracteres | `inbox.name` | existe |
| Modo de tema | 3 `RadioCard` | `light|dark|auto` | **novo** — BE-2 | **só via snippet** (`darkMode`) |
| Posição | 2 `RadioCard` (esq./dir.) | enum | **novo** — BE-2 | **`localStorage`** (D1) |
| Distância da borda | 2 `DurationInput` (px) | 0–120, padrão 20/20 | **novo** — BE-2 | inexistente (`sdk.js` fixo em 20) |
| Formato do lançador | 2 `RadioCard` | `standard|expanded_bubble` | **novo** — BE-2 | **`localStorage`** |
| Texto do lançador | `Input` | ≤ 40 caracteres, só se `expanded` | **novo** — BE-2 | **`localStorage`** |
| Esconder a bolha | `Switch` | booleano | **novo** — BE-2 | só via snippet (`hideMessageBubble`) |
| Título de boas-vindas | `Input` | ≤ 80 | `channel.welcome_title` | existe |
| Frase de boas-vindas | `Editor` | ≤ 255 | `channel.welcome_tagline` | existe |
| Tempo de resposta | `Select` | enum de 3 | `channel.reply_time` | existe |
| Anexos / emoji / encerrar / avatar do bot | 4 `Checkbox` | booleanos | `channel.selectedFeatureFlags` | existe (checkbox cru) |
| Mostrar "Powered by" | `Switch` | booleano | flag `disable_branding` da conta | hoje é da conta, não da inbox |
| Estilo do painel | `Select` | `standard|flat` | **novo** — BE-2 | só via snippet (`widgetStyle`) |

**Geometria fica de fora de propósito.** Largura do painel, altura, raio e tamanho do launcher **não
são configuráveis**. `[DECISÃO]` — o `11 §C7/C8` mediu que nossos valores já são a moda/mediana do
mercado, e a decisão do Walisson mantém a geometria. Expor esses campos convida o cliente a
quebrar o que já está certo.

### B.2.3 O medidor de contraste — o coração desta tela

**O problema, medido:** com `widget_color = #2DC46F`, o header verde com texto branco dá **2,25:1**
`[MEDIDO — 15 §A5.4 / 16 §2.5.2]`. Reprova AA (4,5:1) e reprova até o mínimo de componente (3:1). Com
`#009CE0`, o balão do visitante dá **3,07:1**. **Hoje o cliente escolhe a cor e não tem como saber.**

`ContrastReadout.vue` calcula e **exibe** quatro razões, com `getContrast` do `color2k` — mesma
biblioteca e mesma fórmula que o servidor usará para derivar os tokens, o que evita o painel dizer
uma coisa e o widget fazer outra:

| # | Par | Alvo | Token correspondente (Task 21) |
|---|---|---:|---|
| 1 | Texto sobre a cor da marca | **4,5:1** | `--w-on-brand` |
| 2 | Marca como texto, fundo claro | **4,5:1** | `--w-brand-readable` (claro) |
| 3 | Marca como texto, fundo escuro | **4,5:1** | `--w-brand-readable` (escuro) |
| 4 | Marca como borda / anel de foco | **3:1** | `--w-brand-border` |

**Como aparece na tela** — três estados, nunca um bloqueio:

```
Cor da marca   [■ #2DC46F]

  Texto sobre a marca        preto   9,35:1   ✔ AA
  Marca como texto (claro)   ajustada 4,52:1  ⚠ ajustamos
  Marca como texto (escuro)  original 6,01:1  ✔ AA
  Borda e foco               ajustada 3,11:1  ⚠ ajustamos

  ⚠ Em fundo claro, #2DC46F como texto dá 2,25:1 — abaixo do mínimo legível.
    Links e rótulos usarão #1B7A43 (4,52:1). O preenchimento continua #2DC46F.
    [ver a diferença]
```

`[DECISÃO]` — **o medidor informa, nunca impede o salvamento.** É a etapa 3 do `16 §2.5.2`: *"a
liberdade fica na marca, a garantia fica no token"*. O cliente escolhe a cor da marca dele; nós
garantimos que ninguém fique com texto ilegível.

**Regra C10 do `16 §2.5.1` aplicada à UI:** o medidor **nunca** usa `opacity` para simular estado —
mostra a cor cheia e a cor misturada, porque `opacity` muda a luminância e invalidaria justamente a
conta que a tela está exibindo.

Uma nota de honestidade: `useContrast.js` roda no navegador; os tokens finais são calculados no
servidor (`16 §2.5.2`). Se as duas implementações divergirem, a tela mente. `[DECISÃO]` — a
derivação canônica é a do servidor, e o aceite (§C.3) inclui um teste que compara os dois resultados
para um conjunto fixo de cores. É a mesma preocupação que o `15 §B7.4` levanta ao recomendar que o
SDK **receba** os tokens prontos em vez de recalculá-los.

### B.2.4 O que muda no preview

O `widget-preview/Widget.vue` precisa de quatro mudanças, e três delas são pré-requisito para a tela
ser honesta:

| # | Mudança | Por quê | Esforço |
|---|---|---|---|
| **P1** | **Consumir os tokens de `plano/redesenho/shared/tokens.css`** em vez das ~74 custom properties literais de `Widget.vue:254-328` | Corrige **D4**: hoje o preview e o widget podem divergir sem ninguém perceber | M |
| **P2** | Aplicar os **7 tokens derivados** da marca (`--w-brand`, `--w-on-brand`, `--w-brand-readable`, `--w-brand-border`, `--w-brand-hover`, `--w-brand-subtle`, `--w-focus-ring`) num wrapper com escopo | Hoje só o `background` do launcher recebe a cor (`Widget.vue:208`) — o preview reproduz o próprio bug que estamos corrigindo | M |
| **P3** | Toggle **claro/escuro próprio**, independente do tema do dashboard | Hoje o dark do preview vem de `.dark .widget-wrapper` (`:294`), ou seja, do tema do painel do agente — o cliente não consegue ver o widget escuro sem trocar o próprio painel | P |
| **P4** | Toggle **desktop/mobile** e estado **fechado/aberto**, com o teaser quando houver | O launcher e o teaser são o que o visitante vê primeiro, e são justamente o que o preview quase não mostra | M |

**O que o preview passa a refletir ao vivo:** cor e todos os derivados · tema · avatar · nome ·
textos · posição · offsets · tipo e texto do lançador · bolha escondida · teaser (Tela 2) · primeira
etapa do pré-chat (Tela 3).

**O que o preview não deve tentar reproduzir:** conversa real, anexos, CSAT. `[DECISÃO]` — preview
que tenta ser o widget inteiro vira um segundo widget para manter. O `22-plano-widget.md` já trata do
widget real; o preview é uma maquete fiel nos tokens, não um clone.

### B.2.5 Componentes

| Componente | Novo? | Base |
|---|---|---|
| `AppearancePage.vue` | novo | `SettingsFieldSection`, `SettingsAccordion`, `Banner` |
| `BrandColorField.vue` | novo | `ColorPicker` + `Input` hex + `ContrastReadout` |
| `ContrastReadout.vue` | novo | `color2k`, sem dependência nova |
| `ThemeModeField.vue` | novo | 3 `RadioCard` |
| `LauncherField.vue` | novo | `RadioCard`, `DurationInput`, `Input`, `Switch` |
| `useContrast.js` | novo | `getContrast`, `getLuminance`, `mix`, `toHex` |

---

## B.3 Tela 2 — Gatilhos e proatividade

**Rota:** `…/inboxes/:inboxId/gatilhos` · **Só no perfil marketing** (§B.1.3)

> **DECISÃO DO PRODUTO — 13/08/2026 (D1). Esta tela ganhou um seletor que ela não tinha: a
> intensidade da abordagem.** Ver `PLANO-MESTRE` §2.2 blocos **3.20** e **4.04**, arbitragem
> **A15**, e §4 Onda 3 itens 2 e 3. O que muda nesta tela:
>
> 1. **Um seletor de três níveis**, com o que cada um faz escrito ao lado, **Chamativo
>    pré-selecionado**: **Discreto** (teaser pequeno, só texto) · **Chamativo** (teaser grande com
>    foto — o padrão) · **Agressivo** (abre o painel sozinho).
> 2. **Um interruptor de degradação por familiaridade**, ligado por padrão, com uma frase explicando
>    o que vai acontecer com o visitante que voltar sem ter convertido.
> 3. **O nível Agressivo é oferecido a todas as contas**, sem gate de plano, e escolher **abre um
>    aviso antes de salvar**. **O texto do aviso não menciona penalização do Google** — é decisão do
>    dono do produto, e o aceite é `grep` por `Google` nas strings de i18n desta tela devolvendo
>    **vazio**.
> 4. **Em celular ele não liga.** `approach_mobile` **recusa** `aggressive` com **422** no schema
>    (bloco 3.20) — a tela avisa, o schema impede. Nesta tela isso significa: o seletor de mobile
>    **não oferece** a terceira opção.
> 5. **A frase do plano anterior *"nenhum caminho da UI liga auto-open, e a tela explica por quê"*
>    deixou de valer.** O caminho existe, é opt-in, e a tela explica o que ele faz — não por que ele
>    não existe.
> 6. **Os três níveis são instrumentados** (bloco 4.21): exibição, dispensa, abertura e conversão
>    carregam o nível **e** o nível configurado, para separar o efeito da degradação do efeito do
>    nível. A pergunta "qual converte mais" passa a ser respondida por dado desta frota.

### B.3.1 A decisão de arquitetura, primeiro

**Onde a regra é avaliada?** O `14 §5.1` mediu a Leadster resolvendo **qual** fluxo no servidor (um
request com `host`+`path`+`query`) e executando **quando** no cliente (7 classes de gatilho). O
`14 §5.2` mediu o Intercom mandando as regras e deixando o cliente avaliar. O `20` e o `14`
recomendam servidor.

> **ARBITRADO — PLANO-MESTRE §5 A5: na v1 a configuração de gatilhos vai no payload de boot e a
> avaliação é do SDK.** O híbrido "modelo Leadster" (servidor devolvendo a lista já filtrada) **não
> entra na v1**; entra quando — e só quando — a segmentação usar dado que o navegador não tem.

**A razão que decide:** todos os critérios da v1 são **observáveis pelo próprio navegador do
visitante**. URL, query string, UTM, dispositivo e "visitante novo ou recorrente" (cookie do host) já
estão na máquina dele. Não há segredo a proteger — proteger a lista de URLs de uma campanha do
visitante que **está naquela URL** é cerimônia, não segurança. O custo do endpoint (rota, policy,
cache, mais um lugar para divergir) não se paga contra esse ganho.

`[DECISÃO — v1]`:

- **Servidor entrega a configuração:** `inbox.additional_attributes['widget_triggers']` (jsonb
  validado por JSON Schema, plano 24 §10.2) vai inteiro no payload de boot, pelos **dois** montadores
  (`show.html.erb` e `configs/create.json.jbuilder`).
- **Cliente decide o quê e o quando:** os 7 gatilhos e a segmentação (host, path, query/UTM,
  dispositivo, visitante novo/recorrente) rodam no SDK, fora do iframe — o teaser vive no `document`
  do host, como o launcher (`15 §B7.2`).

**Consequência para esta tela, e é a única:** tudo que o administrador escreve aqui é **público** —
fica legível no `view-source` do site do cliente. A tela precisa dizer isso onde a segmentação é
configurada, em uma linha, sem drama: *"estas regras ficam visíveis para quem inspecionar o site"*.
Nada de segredo, nome de cliente ou valor de contrato em critério de gatilho.

**Quando a segmentação passar a usar dado de servidor** (é cliente, plano contratado, valor de
carteira), o desenho muda para o que o plano 24 já deixou escrito: o widget **pergunta** "posso
disparar o gatilho X?" e o servidor responde sim/não **sem revelar o critério** — melhor que devolver
a regra filtrada, porque não vaza nem a existência do critério.

*Registro do que a versão anterior desta seção argumentava, para quem reabrir a discussão:* mudar
segmentação sem deploy de front (continua verdadeiro — o jsonb é dado, não código, e muda por
`PATCH`); a regra não ficar no `view-source` (foi o ponto vencido pela arbitragem); e o cache de 1
hora das campanhas (`widget/store/modules/campaign.js:45-47`) `[FATO]`, que continua sendo a razão
para **não** duplicar o motor de campanhas (§B.3.2).

### B.3.2 Relação com as campanhas de chat ao vivo

> **DECISÃO DO PRODUTO — 13/08/2026 (D10). O que faltava aqui era a regra de precedência, e ela
> agora existe.** Esta seção decidia corretamente *não reescrever o motor de campanhas*, mas deixava
> em aberto o que a auditoria apontou (linha 34 da §8.1 do mestre): **hoje o widget já busca
> campanhas com `trigger_rules` e cacheia por 1 h** — `app/javascript/widget/store/modules/campaign.js:48-52`,
> `CACHE_EXPIRY = 60 * 60 * 1000`, e `:67` regrava o cache [FATO, conferido em 13/08/2026]. Quando
> `widget_triggers` entrar, uma conta com campanha ativa passa a ter **dois caminhos** mostrando
> mensagem proativa, sem nada que os concilie. **A regra decidida:**
>
> 1. **O motor novo tem precedência.** Se um gatilho novo está ativo **e apto a disparar**, a
>    campanha legada **não dispara na mesma sessão**.
> 2. **A campanha legada continua viva** — listada, editável e funcionando — enquanto não houver
>    gatilho novo apto. Desligar o gatilho faz a campanha voltar **sem republicar nada**.
> 3. **A tela ganha uma seção "modo antigo"**, com as campanhas legadas e um botão de **importar
>    para gatilho**. Importar cria o gatilho equivalente **e desativa** a campanha — nunca as duas
>    ligadas. É rampa, não corte; é o mesmo padrão já usado na tela de Automações.
> 4. **Conta que só tem campanha legada não muda de comportamento.** É o teste que impede a
>    regressão silenciosa na frota, e é aceite do bloco.
>
> Detalhe completo: `PLANO-MESTRE` §2.2 bloco **4.22** e §4 Onda 3 item 3c.

`[DECISÃO]` — **não reescrever o motor de campanhas.** A campanha continua sendo a **mensagem**
(tem título, texto, remetente, horário comercial, `enabled` — tudo já existe e funciona). O que é
novo é a **regra**:

```
Campanha (existe)              Gatilho (novo)
─────────────────              ──────────────
o QUE dizer                    QUANDO dizer
mensagem, remetente,           7 tipos × desktop/mobile,
horário comercial              cooldown, segmentação
                    └─ vínculo opcional ─┘
```

Na tela, a campanha aparece como o **conteúdo do teaser**: quem escreve o texto do teaser está
editando (ou criando) uma campanha vinculada ao gatilho. Isso preserva o backend existente e evita
duas listas concorrentes de "mensagem proativa" no produto.

`trigger_rules` já é hash aberto no strong params (`campaigns_controller.rb:60`) `[FATO]` — o que
significa que a parte de campanha desta tela **não** tem o problema de lista fechada da §A.4.

### B.3.3 Os sete gatilhos

Derivados do contrato `triggerSettings` medido em `14 §5.1`, com os nossos nomes:

| # | Gatilho | Parâmetro | Referência medida | Superamos? |
|---|---|---|---|---|
| 1 | **Tempo na página** | segundos | `screen_time`, valor 10 na Leadster; disparo medido em 10,6 s | — |
| 2 | **Rolagem** | % da página | `page_scroll`, 60% | — |
| 3 | **Inatividade** | segundos sem interação | `inactivity_time`, 40 | — |
| 4 | **Intenção de saída** | — (só desktop) | `cursor_outside` | — |
| 5 | **Cliques na página** | contagem | `page_click`, 10 desktop / 20 mobile | — |
| 6 | **Páginas na sessão** | contagem | `page_access`, 4 | — |
| 7 | **Clique em elemento** | **seletor CSS completo** | `clicked_at` (Leadster) / `pointer_selector` (Intercom, `14 §5.2`) | **sim** — a Leadster aceita **uma classe**; nós aceitamos qualquer seletor válido (`[data-cta]`, `#orcamento .btn`) |

**Cada gatilho tem, separadamente para desktop e mobile:** ligado/desligado · valor · cooldown (em
minutos). Exatamente o formato que o `14 §5.1` mediu (`cooldownPeriod` por dispositivo) e que o
`14 §5.4` registra como "ChatSPX hoje: **Não**".

**`openMode` não existe na nossa versão.** O `16 §3.2` é categórico: *"nunca vira auto-open"* — toda
reclamação documentada de usuário final é contra auto-open, nenhuma é contra teaser, e há
consequência de SEO (painel que cobre conteúdo em mobile, penalizado pelo Google desde 10/01/2017,
`13 §7.2`). `[DECISÃO]` — o gatilho abre o **teaser**, nunca o painel. Não expomos a opção. A tela
diz isso em uma frase, com o motivo, para o cliente que vem da concorrência não achar que faltou.

### B.3.4 Layout

```
MODO
 ( ) Recomendado  — teaser após 8 s de permanência E 30% de rolagem
 ( ) Avançado     — configurar os 7 gatilhos

TEASER
 avatar · nome · papel
 texto  [___________________________]  62/90
 chips de intenção  [+ adicionar]  (0 a 4)
 ▸ prévia ao vivo no painel da direita

FREQUÊNCIA
 [x] uma vez por sessão
 [x] não repetir por  [ 7 ] dias após dispensa
 [ ] um novo convite se o visitante ficar em silêncio por [ 60 ] s

QUANDO NÃO APARECER
 [x] com banner de cookies visível
 [x] em telas abaixo de [ 768 ] px          (segue o corte único da spec)
 [x] fora do horário comercial

ONDE APARECER
 páginas       [URLPattern ▾]  /planos/*  /precos
 UTM           [source=google] [medium=cpc]
 dispositivo   [x] desktop  [x] mobile
 visitante     ( ) qualquer  ( ) novo  ( ) recorrente

▸ AVANÇADO — os 7 gatilhos
   ┌────────────────────┬─────────┬──────────┬───────────┐
   │ Gatilho            │ Desktop │ Mobile   │ Cooldown  │
   ├────────────────────┼─────────┼──────────┼───────────┤
   │ Tempo na página    │ ⏻  10 s │ ⏻  10 s │  30 min   │
   │ Rolagem            │ ⏻  30 % │ ⏻  30 % │  30 min   │
   │ Inatividade        │ ○  40 s │ ○  40 s │  —        │
   │ Intenção de saída  │ ⏻      │ n/d      │  60 min   │
   │ Cliques na página  │ ○  10   │ ○  20   │  —        │
   │ Páginas na sessão  │ ○   4   │ ○   4   │  —        │
   │ Clique em elemento │ ○ [seletor CSS…]   │  —        │
   └────────────────────┴─────────┴──────────┴───────────┘
```

**O modo "Recomendado" é o default e não é enfeite:** o `16 §3.2` prescreve **gatilho composto,
nunca só tempo** — mínimo 8 s de permanência **E** 30% de rolagem, com a faixa de mercado medida em
6–10 s (tawk.to 6,4 s; Leadster 10,0 s, `12 §4`). Quem escolher "Avançado" recebe um aviso ao ligar
apenas tempo.

### B.3.5 Campos, tipos e validação

| Campo | Controle | Validação |
|---|---|---|
| Modo | 2 `RadioCard` | — |
| Texto do teaser | `TextArea` `maxLength=90` `showCharacterCount` | 1–90; ≤ 90 é do `16 §3.2` (limite de leitura, não de layout) |
| Nome / papel | `Input` | ≤ 40 cada |
| Chips de intenção | `TagInput` `allowCreate` | 0 a 4, ≤ 24 caracteres cada |
| Uma vez por sessão | `Switch` | — |
| Dias de dispensa | `DurationInput` | 1–90, padrão **7** |
| Re-ping | `Switch` + `DurationInput` | 30–600 s. **`[NÃO VERIFICADO]`** — o `16 §3.2` registra que a frequência de reaparição **não foi medida em nenhum fornecedor**. É parâmetro nosso, sem referência externa. A tela deve dizer isso ao usuário |
| Páginas | `TagInput` de padrões | cada entrada tem de construir um `URLPattern` válido — a validação já existe em `LiveChatCampaignForm.vue:56-68` e é reaproveitável |
| UTM | `TagInput` `chave=valor` | chave em `utm_source|medium|campaign|term|content|id` |
| Dispositivo | 2 `Checkbox` | ao menos um |
| Visitante | 3 `RadioCard` | — |
| Por gatilho: ligado | `Switch` ×2 (desktop/mobile) | — |
| Por gatilho: valor | `DurationInput` | faixas por tipo: tempo 1–600 s · rolagem 1–100% · cliques 1–50 · páginas 1–20 |
| Por gatilho: cooldown | `DurationInput` (min) | 0–43.200 (30 dias) — o valor medido na Leadster é 43.800 min `[MEDIDO — 14 §5.1]` |
| Seletor CSS | `Input` | tem de passar em `document.querySelector` sem lançar; a tela testa e mostra "N elementos encontrados" **[só valida a sintaxe — o seletor é do site do cliente, não temos o DOM dele]** |

### B.3.6 Componentes

| Componente | Novo? | Base |
|---|---|---|
| `TriggersPage.vue` | novo | `SettingsAccordion`, `EmptyStateLayout` |
| `TriggerRow.vue` | novo | `Switch`, `DurationInput`, `Input` |
| `TeaserComposer.vue` | novo | `TextArea`, `TagInput`, `Avatar` |
| `SegmentationField.vue` | novo | `TagInput`, `Checkbox`, `RadioCard` |

Depende de: **BE-4** (armazenamento em `widget_triggers` + entrega no payload de boot — **sem
endpoint filtrado**, A5) e do teaser no SDK, que é escopo do
`22-plano-widget.md` (§Fase 3 do `16`).

---

## B.4 Tela 3 — Pré-chat e fluxo de captura

**Rota:** `…/inboxes/:inboxId/pre-chat` (substitui a aba `pre-chat-form`)

### B.4.1 Dois modos

| Modo | Quando | O que é |
|---|---|---|
| **Simples** | Default em suporte | O que existe hoje: até 3 campos, uma etapa, sem condicional |
| **Construtor** | Default em marketing | Etapas, condicionais, máscaras, teto de 8 campos |

A troca Simples → Construtor é sem perda (os campos viram a etapa 1). O caminho inverso avisa
quais etapas serão ignoradas, sem apagar nada.

### B.4.2 O que cabe em `pre_chat_form_options` e o que não cabe

O campo **já é jsonb** (`db/schema.rb:761`, `pre_chat_form_options` default `{}`) `[FATO]`. **O
limite não é o banco, é o strong params:** `Channel::WebWidget::EDITABLE_ATTRS`
(`web_widget.rb:36-39`) declara a forma de cada campo do pre-chat e rejeita o resto.

| Precisa gravar | Cabe hoje? | O que fazer |
|---|:---:|---|
| `pre_chat_message` | ✅ | — |
| `name`, `label`, `placeholder`, `type`, `enabled`, `required`, `field_type`, `locale`, `values[]` | ✅ | — |
| `regex_pattern`, `regex_cue` | ✅ | Já aceito **e já consumido pelo widget** (`PreChat/Form.vue:178-190` monta `['matches', regex]` via `getRegexp`, `shared/helpers/Validators.js:96-102`) `[FATO]` |
| Ordem explícita (`position`) | ❌ | Hoje a ordem é a do array. Funciona, mas é implícita |
| Etapa (`step`) | ❌ | **Ampliar `EDITABLE_ATTRS`** |
| Condicional (`show_if`) | ❌ | idem |
| Máscara (`mask`) e validador nomeado (`validator`) | ❌ | idem |
| Texto de ajuda (`help_text`) | ❌ | idem |
| Mensagem de erro própria (`error_message`) | ❌ | idem |
| Lead incompleto (salvar parcial) | ❌ | **Não é forma de campo** — é comportamento. Dependência **BE-5** |

**A boa notícia, medida:** `app/models/channel/web_widget.rb` teve **+0 −0 do upstream** entre
v4.12.1 e v4.16.2 e **+0 −0 do fork** `[MEDIDO]`. **É o arquivo de backend mais seguro de toda esta
superfície.** Ampliar `EDITABLE_ATTRS` é barato — ao contrário de mexer no `inboxes_controller.rb`
(§A.4).

### B.4.3 As máscaras brasileiras

| Tipo | Máscara | Validação | Base |
|---|---|---|---|
| CPF | `000.000.000-00` | dígito verificador **+ dígitos repetidos** | **escrever** (helper próprio) |
| CNPJ | `00.000.000/0000-00` | dígito verificador **+ dígitos repetidos** | **escrever** |
| CPF ou CNPJ | alterna por comprimento | ambos | **escrever** |
| CEP | `00000-000` | 8 dígitos | **escrever** |
| UF + cidade | `Select` de 27 UF → `ComboBox` de cidade | par consistente | **escrever** (lista de UF é estática; cidades: ver abaixo) |
| Telefone | por país, DDI | `libphonenumber-js` | **já instalado** e já registrado no FormKit do widget (`entrypoints/widget.js:36-38`) |
| E-mail | — | RFC + MX opcional | FormKit `email` já usado (`PreChat/Form.vue:181`) |
| E-mail corporativo | — | rejeita provedor gratuito | **`company-email-validator` já instalado** (`package.json:75`) |
| Anti-lixo | — | heurística | **escrever** |

> **A armadilha do CPF, verificada nesta task** `[MEDIDO]`. O dígito verificador **não** rejeita
> `111.111.111-11`. Rodando o algoritmo oficial sobre `111111111`: a soma ponderada dá 54,
> `11 − 54 % 11 = 1` → primeiro dígito **1**; repetindo com `1111111111` a soma dá 65,
> `11 − 65 % 11 = 1` → segundo dígito **1**. O par calculado é `11`, exatamente o informado —
> **o CPF passa**. O mesmo vale para as outras nove sequências de dígito único e para
> `11.111.111/1111-11` no CNPJ.
>
> Uma implementação que faça só o dígito verificador aceita o CPF de teste mais óbvio que existe.
> `[DECISÃO]` — a checagem de dígitos repetidos é **parte da validação de CPF e de CNPJ**, não da
> heurística anti-lixo, e portanto não é desligável. Reproduzir com o comando 10 do Anexo B.

**"Anti-lixo" precisa de definição, senão vira campo mágico.** `[DECISÃO]` — três regras explícitas,
cada uma com toggle próprio na tela, nunca uma caixa-preta:

1. Nome com menos de 2 caracteres, ou sem vogal, ou com 3+ caracteres idênticos seguidos.
2. Telefone com todos os dígitos iguais, ou sequência trivial (`123456789`).
3. E-mail em lista de domínios descartáveis (lista embarcada, atualizável).

Cada regra tem **mensagem de erro própria e editável**. `[DECISÃO]` — o bloqueio é **suave**: o
campo mostra o aviso, mas o visitante consegue seguir. Um filtro rígido de lead em formulário de
captura descarta cliente real (o `06 §9.1` cataloga fricção excessiva como anti-padrão de conversão).

`[NÃO VERIFICADO]` — de onde virá a lista de cidades por UF. Três caminhos (tabela embarcada do
IBGE, API externa, ou campo livre com sugestão) com custos diferentes de peso no bundle do widget.
**Fica como pergunta aberta**, não como decisão silenciosa.

### B.4.4 Regras do construtor

- **Teto de 8 campos**, total, somando todas as etapas. A tela mostra `5/8` e desabilita "adicionar"
  no limite, com a razão à vista. Base: o `06` cataloga formulário longo como principal causa de
  abandono, e o `16 §2.7.6` mede que o painel de 400 px comporta ~35 caracteres por linha — não é
  superfície para formulário longo.
- **Validação no blur**, não a cada tecla. Erro que aparece enquanto se digita o próprio e-mail é
  anti-padrão conhecido. (`Input` e `TextArea` já emitem `blur` `[FATO]`.)
- **Condicional** só sobre campo de etapa anterior, operadores `é`/`não é`/`contém`/`preenchido`.
  Sem `E`/`OU` aninhado na primeira entrega — `[DECISÃO]`, porque condicional aninhada em construtor
  visual é uma tela inteira por si só, e o `14 §5.2` mostra que nem o Intercom expõe isso ao cliente
  final (os predicados aninhados são internos).
- **Campo obrigatório** por campo, com o mesmo toggle de hoje.
- **Ordem** por arrastar, `vuedraggable` (já usado em `PreChatFields.vue:39-44`).

### B.4.5 Relação com o motor Flows

Decisão **N3** do `DECISOES.md`: *híbrido, Flows como fonte de verdade*.

`[DECISÃO]` para esta tela, no espírito de N3:

- O construtor de pré-chat **grava em `pre_chat_form_options`** e continua sendo o caminho simples.
- Um terceiro modo, **"Fluxo"**, delega para Automações/Flows: a tela mostra qual fluxo está
  vinculado, um resumo dos primeiros passos e um link para o construtor de Flows. **Não replicamos
  o editor de fluxo aqui.**
- Quando o modo é "Fluxo", o pré-chat vira o **passo 1** do fluxo, e a tela diz isso.

**Por que não migrar tudo para Flows já:** o pré-chat roda **antes** de existir conversa; o Flows
opera sobre conversa. Fazer os dois no mesmo motor exige mudar o momento de criação da conversa —
que é a dependência **BE-5** (lead incompleto) e não é decisão desta tela.

### B.4.6 Componentes

| Componente | Novo? | Base |
|---|---|---|
| `PreChatPage.vue` | novo | `SettingsToggleSection`, `RadioCard` (3 modos) |
| `PreChatStepList.vue` | novo | `vuedraggable` |
| `PreChatFieldEditor.vue` | novo | `Input`, `Select`, `Switch`, `ComboBox` |
| `ConditionEditor.vue` | novo | `Select` ×3 |
| `helpers/brMasks.js` | novo | sem dependência nova |

O `PreChatForm/Settings.vue` e o `PreChatFields.vue` atuais (🟢 nos dois lados, §A.11) ficam como
**modo Simples**, praticamente intocados — o que preserva a zona segura em vez de gastá-la.

---

## B.5 Tela 4 — Rastreio e conversões (Pixel, GA4, GTM)

**Rota:** `…/inboxes/:inboxId/rastreio`

> **Divisão de trabalho com a task 25.** O `25-plano-tracking-integracao.md §A.3` já especifica
> **T-C1.1** (modelo), **T-C1.2** (segredo), **T-C1.4** (publicação nos dois lugares), **T-C1.7**
> (OAuth) e a lista de campos com quais são públicos. **Este documento não repete nada disso.**
> Aqui: como a tela se organiza, o que é por conta × por inbox, e como é o diagnóstico — que é a
> camada **C8** e que o `10 §4.1` descreve mas nenhum documento desenhou ainda.

### B.5.1 O que é por conta e o que é por inbox

`[DECISÃO]`, ancorada em `10 §4.1 C1` (*"por inbox, não por conta — agências e clientes multi-site
precisam de pixels diferentes por site"*) e no que é ou não segredo:

| Configuração | Escopo | Por quê |
|---|---|---|
| Meta Pixel ID | **inbox** | Um pixel por site |
| Meta Access Token | **inbox** (segredo) | Vinculado ao pixel |
| `test_event_code` | **inbox** | Modo teste é por site |
| GA4 Measurement ID | **inbox** | Uma propriedade por site |
| GA4 API Secret | **inbox** (segredo) | Vinculado à propriedade |
| Google Ads `send_to` | **inbox** | `AW-XXXX/label` por site |
| Mapa de eventos | **inbox** com **default por conta** | Padroniza a agência, permite exceção |
| Valor do lead | **inbox** | Ticket varia por site |
| **Modo de consentimento** | **conta** (com override por inbox) | LGPD é da empresa, não do site |
| **Conexão OAuth do Google Ads** | **conta** | A conta de anúncios é da empresa |
| **Kill switch** | **conta e inbox** | Precisa dos dois: incidente derruba tudo, teste derruba um |
| **Retenção do log** | **conta** | Política de dados é da empresa |
| **Aceite de DPA** | **conta** | É contrato |

O bloco "conta" aparece na tela da inbox como **cartão somente leitura** com link para as
configurações da conta — quem configura pixel precisa ver o modo de consentimento vigente, mesmo
sem poder mudá-lo ali.

### B.5.2 Layout

```
[ Meta ]  [ Google ]  [ Eventos ]  [ Diagnóstico ]      ← TabBar

── Meta ────────────────────────────────────────────
 Pixel ID           [ 123456789012345 ]      ● ativo
 Conexão            [ Conectar com a Meta ]  (OAuth — T-C1.7)
 Access Token       ●●●●●●●● (definido em 03/08)  [substituir]
 Modo teste         [ ⏻ ]  código [ TEST12345 ]
                    ⚠ desliga sozinho em 7 dias

── Google ──────────────────────────────────────────
 GA4 Measurement ID [ G-XXXXXXX ]  [detectar no site]
 API Secret         ●●●●●●●●
 Ads send_to        [ AW-000000000/AbCdEf ]
 GTM                dataLayer sempre ligado ⓘ

── Eventos ─────────────────────────────────────────
  Evento ChatSPX          → Meta          → GA4              on
  conversa_iniciada       Contact          conversation_start ⏻
  prechat_enviado         CompleteRegistr. prechat_submit     ⏻
  lead                    Lead             generate_lead      ⏻
  lead_qualificado        QualifiedLead    qualify_lead       ○
  …                                                       [12 linhas]
 Valor do lead   ( ) desligado  ( ) fixo [ R$ ___ ]  ( ) por regra

── Diagnóstico ─────────────────────────────────────
 [ Enviar evento de teste ]
  hora     evento             destino  status  event_id      EMQ
  14:32:10 lead               Meta     200 ✔   a1b2…         8,1
  14:32:10 lead               GA4      204 ✔   a1b2…          —
  14:29:02 prechat_enviado    Meta     400 ✘   c3d4…          —
           └ "Invalid parameter: em must be hashed"
```

### B.5.3 Diagnóstico — a camada C8, e por que ela vem junto e não depois

O `10 §4.1 C8` pede log por evento com destino, nome, **lista de nomes dos campos** (não os valores),
timestamp, status HTTP, erro e EMQ. E o `10 §4.1 C6` observa que a deduplicação por `event_id` é
*"verificável pelo cliente em 30 segundos no Events Manager dele"*.

`[DECISÃO]` — o diagnóstico entra **na mesma entrega** da configuração, não depois. Razão prática: uma
tela que aceita um Pixel ID e não mostra se algo chegou transfere 100% do suporte para o nosso time.
O `10 §4.1 C8` registra que *"o ponto fraco documentado da Leadster é a documentação"*; a nossa
vantagem barata é o cliente conseguir **ver** o evento saindo.

**Regra dura de privacidade na UI:** o log mostra **os nomes** dos campos enviados, nunca os
valores. Nem em claro, nem hasheado. `[DECISÃO]` — um painel de diagnóstico que exibe e-mail de lead
é um vazamento com interface.

### B.5.4 Componentes

| Componente | Novo? | Base |
|---|---|---|
| `TrackingPage.vue` | novo | `TabBar` |
| `DestinationCard.vue` | novo | `SettingsFieldSection`, `Input`, `Switch`, `Banner` |
| `EventMapTable.vue` | novo | `BaseTable`, `ComboBox`, `Switch` |
| `DiagnosticsPanel.vue` | novo | `BaseTable`, `EmptyStateLayout` |
| `SecretField.vue` | novo | `Input` mascarado + "substituir"; **nunca** re-exibe o valor |

`SecretField.vue` merece existir como componente próprio porque o repositório já tem o antipadrão
oposto documentado: `webhooks/_webhook.json.jbuilder:6` devolve segredo em texto claro
(`[R18 §D.10.3]`, citado na task 25 T-C1.2).

---

# PARTE C — EXECUÇÃO

## C.1 Ondas e tarefas

Esforço relativo: **P** / **M** / **G**. Risco de merge conforme o mapa da §A.11.

### Onda 0 — Terreno limpo

Nada aqui é redesenho. Tudo aqui é o que torna o redesenho barato. Alinhada com a **Fase 1** do
`16 §7` e com o pré-requisito do `16 §6.2` (rodar o merge da v4.16.2 sozinho, antes).

| ID | Tarefa | Arquivo | Esforço | Depende | Risco |
|---|---|---|:---:|---|---|
| **T0.1** | Rodar o merge da `v4.16.2` isolado, sem nenhuma mudança nossa junto | — | **G** | — | 🔴 (é o ponto) |
| **T0.2** | Apagar `WidgetBuilder.vue` (**D5**) | `settings/inbox/WidgetBuilder.vue` | P | T0.1 | 🟢 upstream já não tem |
| **T0.3** | Remover chaves i18n órfãs `TABS.CAMPAIGN`, `TABS.WIDGET_BUILDER` (**D7**) | `i18n/{pt_BR,en}/inboxMgmt.json` | P | T0.1 | 🟡 |
| **T0.4** | Traduzir as 37 chaves `NPS.*` para `en` (**D6**) | `i18n/en/inboxMgmt.json` | P | T0.1 | 🟡 |
| **T0.5** | Corrigir a mutação do store pelo `ColorPicker` (**D2**) — cópia local + payload explícito | `Settings.vue:948, 538` | P | T0.1 | 🔴 |
| **T0.6** | Unificar o default de cor (**D11**): a tela de criação passa a ler o default do backend | `channels/Website.vue:22` | P | — | 🟢 |
| **T0.7** | Aviso na tela quando `allowed_domains` está vazio (**D8**), citando a consequência | `settingsPage/ConfigurationPage.vue` | P | — | 🔴 |
| **T0.8** | Teste que compara chave a chave `show.html.erb` × `configs/create.json.jbuilder` (**D9**) e falha na divergência | `spec/` (novo) | M | — | 🟢 arquivo novo |
| **T0.9** | Registrar o namespace i18n `inboxWidget` e criar os dois arquivos vazios | `i18n/{pt_BR,en}/inboxWidget.json` | P | — | 🟢 |
| **T0.10** | Cortar o `import 'widget/i18n/index'` do dashboard (**D10**): rótulos padrão do pré-chat passam a sair do i18n do dashboard | `dashboard/helper/preChat.js:1-4` | M | — | 🟡 |

### Onda 1 — Perfil + Aparência

| ID | Tarefa | Arquivo | Esforço | Depende | Risco |
|---|---|---|:---:|---|---|
| **T1.1** | `useInboxWidgetConfig.js` — carga, rascunho, `isDirty`, payload, salvar (§B.0.2) | `inbox/widget/composables/` | M | BE-1 | 🟢 novo |
| **T1.2** | Barra de salvar + confirmação ao sair com pendência | `inbox/widget/` | M | T1.1 | 🟢 |
| **T1.3** | `WidgetProfileSelector.vue` + `useProfileVisibility.js` | `inbox/widget/` | M | T1.1, BE-1 | 🟢 |
| ~~**T1.4**~~ | ~~Backfill: toda inbox Website existente vira `suporte`~~ — **REMOVIDA (ARBITRADO §5 A4: sem backfill; `nil` é lido como `support`)**. Não substituir por nada: a leitura derivada resolve | — | — | — | — |
| **T1.5** | Perfil no wizard de criação, sem default pré-selecionado | `channels/Website.vue` | P | T1.3 | 🟢 fork já mexeu 1 linha |
| **T1.6** | `useContrast.js` — os 4 pares com `color2k` | `inbox/widget/composables/` | M | — | 🟢 |
| **T1.7** | `ContrastReadout.vue` — razões, veredito, cor ajustada, explicação | `appearance/` | M | T1.6 | 🟢 |
| **T1.8** | `BrandColorField.vue` | `appearance/` | P | T1.7 | 🟢 |
| **T1.9** | `ThemeModeField.vue` + `LauncherField.vue` (posição, offsets, tipo, título, esconder) | `appearance/` | M | BE-2 | 🟢 |
| **T1.10** | `AppearancePage.vue` — junta tudo, textos, recursos, avançado | `appearance/` | M | T1.8, T1.9 | 🟢 |
| **T1.11** | Preview **P1**: consumir os tokens da Task 21 (**D4**) | `widget-preview/Widget.vue:254-328` | M | Task 21 | 🟢 |
| **T1.12** | Preview **P2**: aplicar os 7 tokens derivados | `widget-preview/` | M | T1.11 | 🟢 |
| **T1.13** | Preview **P3+P4**: toggles claro/escuro, desktop/mobile, fechado/aberto | `widget-preview/` | M | T1.11 | 🟢 |
| **T1.14** | Substituir o snippet montado por corte de string (**D3**): backend devolve o script completo, com opções | `widget-preview/Widget.vue:94-101` + BE-2 | M | BE-2 | 🟢 / 🟡 |
| **T1.15** | Ligar a aba nova no roteador de abas (4 linhas) | `Settings.vue:143-227, 1233+` | P | T1.10 | 🔴 mínimo possível |
| **T1.16** | i18n pt-BR **e** en da tela | `i18n/*/inboxWidget.json` | M | T1.10 | 🟢 |

### Onda 2 — Pré-chat

| ID | Tarefa | Arquivo | Esforço | Depende | Risco |
|---|---|---|:---:|---|---|
| **T2.1** | Ampliar `EDITABLE_ATTRS` para `step`, `show_if`, `mask`, `validator`, `help_text`, `error_message`, `position` | `models/channel/web_widget.rb:34-40` | P | BE-6 | 🟢 **0 mudança dos dois lados** |
| **T2.2** | `helpers/brMasks.js` — CPF, CNPJ, CPF-ou-CNPJ, CEP, UF | `dashboard/helper/` + espelho no widget | M | — | 🟢 |
| **T2.3** | Validadores: e-mail corporativo (`company-email-validator`), telefone (`libphonenumber-js`), anti-lixo (3 regras) | idem | M | T2.2 | 🟢 |
| **T2.4** | `PreChatFieldEditor.vue` — tipo, máscara, rótulo, ajuda, obrigatório, erro próprio | `prechat/` | M | T2.1 | 🟢 |
| **T2.5** | `PreChatStepList.vue` — etapas, arrastar, teto de 8 com contador | `prechat/` | M | T2.4 | 🟢 |
| **T2.6** | `ConditionEditor.vue` — campo/operador/valor, só etapa anterior | `prechat/` | M | T2.5 | 🟢 |
| **T2.7** | `PreChatPage.vue` com os 3 modos (Simples / Construtor / Fluxo) | `prechat/` | M | T2.5 | 🟢 |
| **T2.8** | Modo Fluxo: vínculo, resumo e link para Automações | `prechat/` | M | T2.7 | 🟢 |
| **T2.9** | Prévia da etapa 1 dentro do preview | `widget-preview/` | M | T1.13 | 🟢 |
| **T2.10** | O widget passa a honrar `mask`/`validator`/`step`/`show_if` | `widget/components/PreChat/Form.vue` | **G** | T2.1 | 🔴 **16 commits upstream, +39 −33 desde a base** — entrar por delegação (casca fina), conforme `15 §B12.4` |
| **T2.11** | i18n das mensagens de erro, pt-BR e en | `i18n/*/inboxWidget.json` | M | T2.4 | 🟢 |

### Onda 3 — Gatilhos e teaser

| ID | Tarefa | Arquivo | Esforço | Depende | Risco |
|---|---|---|:---:|---|---|
| **T3.1** | `TriggerRow.vue` — 7 gatilhos × desktop/mobile × cooldown | `triggers/` | M | BE-4 | 🟢 |
| **T3.2** | `SegmentationField.vue` — URL (`URLPattern`), UTM, dispositivo, visitante | `triggers/` | M | BE-4 | 🟢 |
| **T3.3** | `TeaserComposer.vue` — avatar, nome, papel, texto ≤ 90, chips | `triggers/` | M | — | 🟢 |
| **T3.4** | Frequência e dispensa (uma vez por sessão, N dias, re-ping) | `triggers/` | P | T3.3 | 🟢 |
| **T3.5** | "Quando não aparecer": cookies, largura mínima, fora do horário | `triggers/` | P | T3.3 | 🟢 |
| **T3.6** | `TriggersPage.vue` — modo Recomendado × Avançado, vazio, aviso de gatilho só por tempo | `triggers/` | M | T3.1–T3.5 | 🟢 |
| **T3.7** | Vínculo teaser ↔ campanha existente (§B.3.2) | `triggers/` + `campaigns` | M | BE-4 | 🟡 |
| **T3.8** | Teaser no preview, com o gatilho simulado | `widget-preview/` | M | T1.13 | 🟢 |
| **T3.9** | i18n pt-BR e en | `i18n/*/inboxWidget.json` | M | T3.6 | 🟢 |

Os 7 gatilhos **executando** no SDK e o teaser **renderizando** no host são escopo do
`22-plano-widget.md` (Fase 3 do `16 §7`). Esta onda entrega a configuração e a prévia.

> **ARBITRADO — §5 A5, sobre as dependências desta onda:** T3.1, T3.2 e T3.7 dependem de **BE-4 na
> sua forma nova** — o **schema do jsonb `widget_triggers` + a entrega no payload de boot** (bloco
> **3.02** do mestre) — e **não** de um endpoint que devolve gatilhos filtrados, que não existe na
> v1. O ID da dependência não muda; a natureza dela sim.

### Onda 4 — Rastreio

| ID | Tarefa | Arquivo | Esforço | Depende | Risco |
|---|---|---|:---:|---|---|
| **T4.1** | `SecretField.vue` — mascarado, substituível, nunca re-exibido | `tracking/` | P | T-C1.2 (task 25) | 🟢 |
| **T4.2** | `DestinationCard.vue` ×2 (Meta, Google) | `tracking/` | M | T-C1.1 | 🟢 |
| **T4.3** | `EventMapTable.vue` — 12 eventos com defaults preenchidos | `tracking/` | M | T-C1.5 | 🟢 |
| **T4.4** | Valor do lead: desligado / fixo / por regra | `tracking/` | M | T-C1.6 | 🟢 |
| **T4.5** | Cartão somente-leitura do que é da conta (consentimento, DPA, retenção) | `tracking/` | P | — | 🟢 |
| **T4.6** | `DiagnosticsPanel.vue` — últimos N eventos, status, erro, EMQ, **nomes** de campo | `tracking/` | M | T-C1.8 + C8 | 🟢 |
| **T4.7** | "Enviar evento de teste" com retorno visível | `tracking/` | M | T4.6 | 🟢 |
| **T4.8** | Modo teste com aviso persistente e desligamento automático | `tracking/` | P | T-C1.8 | 🟢 |
| **T4.9** | `TrackingPage.vue` com as 4 sub-abas | `tracking/` | M | T4.2–T4.7 | 🟢 |
| **T4.10** | i18n pt-BR e en | `i18n/*/inboxWidget.json` | M | T4.9 | 🟢 |

### C.1.1 Ordem e por que ela é essa

```
Onda 0  ─────────────────────────────────────────────►  todas dependem
   │
   ├── Onda 1 (perfil + aparência)  ──►  desbloqueia o preview,
   │                                     que as ondas 2 e 3 usam
   ├── Onda 2 (pré-chat)  ── independente da 3
   ├── Onda 3 (gatilhos)  ── independente da 2
   └── Onda 4 (rastreio)  ── independente das três, mas depende da task 25
```

**A Onda 1 vem primeiro** porque entrega o `useInboxWidgetConfig`, a barra de salvar, o seletor de
perfil e o preview corrigido — as quatro coisas que as outras três consomem. Fazer o pré-chat antes
significa construir a mesma infraestrutura duas vezes.

**As Ondas 2 e 3 podem correr em paralelo** — não se tocam.

**A Onda 4 é a única que depende de outro documento.** Se a task 25 escorregar, ela espera; as
outras três não.

## C.2 O que depende do backend — para a task 24

Cada item diz **o que precisa existir e por quê**, não como modelar. `[DECISÃO]` de fronteira: a
task 24 escolhe entre coluna, jsonb ou tabela; este plano só declara a necessidade e a restrição.

| ID | Precisa existir | Quem escreve | Quem lê | Restrição que este plano descobriu |
|---|---|---|---|---|
| **BE-1** | **Três chaves de topo** em `inbox.additional_attributes` — `widget_profile`, `widget_triggers`, `widget_tracking` — declaradas **numa única edição** do strong params (**A1**) | Tela (dashboard) | Dashboard + os 2 montadores de config | `inboxes_controller.rb:217` é lista fechada e o arquivo é 🔴 nos dois lados (§A.4) — por isso **uma edição só**, na primeira tarefa (bloco 3.01). **Não** é um sub-hash único (`widget_config`): o update faz merge **de primeiro nível apenas** (`inboxes_controller.rb:52-56`), então um `PATCH` parcial de gatilhos apagaria perfil e tracking. Com três chaves de topo, cada `PATCH` preserva as outras, e a evolução posterior acontece **dentro** dos jsonb, sem tocar mais no controller |
| **BE-2** | Configuração de **apresentação** hoje presa ao snippet: tema, posição, offsets, tipo e texto do lançador, esconder bolha, estilo do painel | Tela | ERB + jbuilder + `config-set` | Hoje vive em `localStorage` (**D1**). Precisa de precedência definida: **banco é o padrão; `chatwootSettings` no site sobrescreve** — e a tela precisa poder dizer ao cliente que há um override ativo |
| **BE-3** | Perfil da inbox em `inbox.additional_attributes['widget_profile']`, valores `support`/`marketing` (**A2**), **sem backfill** (**A4**): `nil` é lido como `support` | Tela | Dashboard **e** widget — o servidor resolve o perfil nas 11 flags planas de `profileConfig` (`22` §B.3, lista canônica) e as entrega no boot (**A3**); o widget **nunca** vê o nome do perfil | Sem migration (**A1**). Verificação **V6** (quantas inboxes Website ativas existem) continua valendo para dimensionar adoção, mas **não bloqueia** — não há backfill a dimensionar |
| **BE-4** | Gatilhos por inbox: 7 tipos × desktop/mobile × valor × cooldown, + segmentação (URL, UTM, dispositivo, visitante) + config do teaser, em `inbox.additional_attributes['widget_triggers']` — jsonb validado por **JSON Schema** (`json_schemer`, `Gemfile:37`) | Tela | **Payload de boot**, pelos dois montadores (`show.html.erb` e `configs/create.json.jbuilder`); a avaliação é do SDK | **ARBITRADO §5 A5: não existe endpoint que devolve filtrado na v1.** BE-4 é *schema + entrega no boot*, não rota nova. Reusar `campaigns` para a **mensagem** e não duplicar o motor (§B.3.2); `campaigns_controller.rb:60` já aceita `trigger_rules: {}` aberto. Tudo que estiver aqui é **público** |
| **BE-5** | **Lead incompleto**: persistir resposta parcial de pré-chat antes da conversa existir | Widget | Painel, relatórios | É mudança de **momento de criação da conversa**, não de forma de campo (§B.4.2). É o que também destrava unificar pré-chat com Flows (§B.4.5) |
| **BE-6** | Ampliar `EDITABLE_ATTRS` do pré-chat com `step`, `show_if`, `mask`, `validator`, `help_text`, `error_message`, `position` | Tela | Widget | `web_widget.rb` teve **+0 −0 dos dois lados** `[MEDIDO]` — é a alteração de backend mais barata do plano |
| **BE-7** | Derivação canônica dos 7 tokens de marca **no servidor**, entregue pronta ao widget e ao SDK | Servidor | Widget (`show.html.erb`) e SDK (`config-set`) | `16 §2.5.2` e `15 §B7.4`. O medidor da Tela 1 tem de bater com essa derivação (§B.2.3) |
| **BE-8** | Configuração de tracking + segredos + log de eventos | Tela | SDK, jobs server-side | **Já especificado** em `25-plano-tracking-integracao.md §A.3` (T-C1.1, T-C1.2, T-C1.4, T-C1.7). Aqui só a UI |

**Uma verificação que precede BE-2 e vale a pena fazer antes de escrever código:** quantas inboxes
da frota têm um `chatwootSettings` diferente do default no site do cliente? Não temos como saber
pelo banco `[FATO]` — a informação está no HTML de sites de terceiros. `[NÃO VERIFICADO]`, e é o
que determina se a migração snippet→banco pode assumir defaults ou precisa de um período de
convivência com aviso na tela.

## C.3 Critérios de aceite

Cada item passa ou falha. Nada aqui é "está bonito".

### Transversal (vale para as quatro telas)

1. Editar qualquer campo e sair da aba sem salvar: o `inboxes/getInbox` do store devolve **os
   valores originais** (o teste que falha hoje por causa de **D2**).
2. Editar e sair: aparece a confirmação; "Descartar" restaura; "Salvar" grava e a barra some.
3. Toda configuração nova aparece **nos dois** montadores — o teste **T0.8** compara chave a chave
   `show.html.erb` × `configs/create.json.jbuilder` e falha na divergência.
4. Toda chave de i18n usada existe em `pt_BR` **e** em `en` — teste que varre os `$t()` das telas
   novas e falha em chave faltante em qualquer um dos dois.
5. `axe-core` sem violação crítica ou séria nas quatro telas, nos dois temas do dashboard.
6. Em 1280 px de largura, nenhuma tela tem scroll horizontal; em 768 px, todas colapsam para coluna
   única.
7. Usuário `agent` que acessa a URL direta de qualquer das quatro telas vê o estado "sem permissão",
   não um erro.

### Tela 1 — Aparência

8. Com `widget_color = #2DC46F`, o medidor exibe **2,25:1** para "marca como texto em fundo claro" e
   marca como reprovado — é o número medido em `15 §A5.4` / `16 §2.5.2`.
9. Com `#009CE0`, o medidor escolhe **preto** para `--w-on-brand` (6,85:1) e não branco (3,07:1).
10. Para um conjunto fixo de 20 cores, a derivação do navegador (`useContrast.js`) e a do servidor
    (**BE-7**) produzem **o mesmo hex** em todos os 7 tokens.
11. Trocar a cor atualiza o preview **sem recarregar** e sem tocar no store até o "Salvar".
12. O toggle claro/escuro do preview funciona **independentemente** do tema do dashboard.
13. Mudar a posição para "esquerda", salvar e recarregar: a tela continua mostrando "esquerda"
    **em outro navegador e para outro administrador** (o teste que falha hoje por **D1**).
14. Nenhuma custom property de cor literal permanece em `widget-preview/` (busca por
    `--slate-`/`--solid-` no arquivo retorna vazio) — fecha **D4**.

### Tela 2 — Gatilhos

15. Nenhum caminho da UI permite configurar abertura automática do painel; a tela explica por quê.
16. Ligar só "tempo na página" mostra o aviso de gatilho composto, com a referência do estudo.
17. Um seletor CSS inválido é rejeitado no `blur` com a mensagem do erro real do parser.
18. Um padrão de URL inválido é rejeitado — mesma validação de `LiveChatCampaignForm.vue:56-68`.
19. O teaser configurado aparece no preview com o texto, o avatar e os chips reais.
20. Numa inbox de perfil `support`, a aba de gatilhos **não aparece por padrão** — mas continua
    alcançável pelo link "mostrar configurações de marketing" (§B.1.3: perfil **esconde**, não
    remove). A API **não** rejeita `widget_triggers` por causa do perfil: o `permit` aceita as três
    chaves independentemente dele (**A1**, plano 24 §9.4) e trocar de perfil **não apaga**
    configuração (**A3**) — o que garante o comportamento é a resolução, com `teaserEnabled: false`
    fazendo o SDK não disparar. O que a API rejeita é `widget_triggers` **fora do JSON Schema** (422).

### Tela 3 — Pré-chat

21. Adicionar o 9º campo é impossível: o botão está desabilitado e o contador mostra `8/8`.
22. CPF `529.982.247-25` é aceito; `529.982.247-26` é rejeitado pelo dígito verificador; e
    **`111.111.111-11` é rejeitado pela regra de dígitos repetidos** — ver a armadilha na §B.4.3.
23. CNPJ inválido rejeitado, válido aceito; `11.111.111/1111-11` rejeitado pela mesma regra do
    item 22.
24. E-mail `fulano@gmail.com` com "e-mail corporativo" ligado é rejeitado; `fulano@empresa.com.br`
    é aceito.
25. Telefone sem DDI é rejeitado com a mensagem certa (as regras `startsWithPlus` e
    `isValidPhoneNumber` já existem no widget).
26. Validação dispara no `blur`, **não** a cada tecla — verificável contando renders de mensagem
    de erro durante a digitação.
27. Um campo condicional só aparece no widget quando a condição é satisfeita, e a etapa 2 só carrega
    depois da 1.
28. Migrar de Simples para Construtor e voltar **não perde campo**.

### Tela 4 — Rastreio

29. Configurar Pixel ID numa inbox e não em outra: o `window.chatwootWebChannel` da primeira traz o
    ID e o da segunda não — conferido no HTML servido (é o mesmo aceite da task 25 T-C1.3).
30. Nenhum segredo aparece em: HTML do widget, resposta do endpoint de config do widget, `index` da
    API de inboxes, ou log. Verificado por busca no corpo das respostas.
31. O painel de diagnóstico mostra **nomes** de campo e nunca valores — busca por `@` no corpo
    renderizado retorna vazio.
32. Modo teste ligado exibe aviso persistente e desliga sozinho no prazo.
33. "Enviar evento de teste" produz uma linha no diagnóstico com status HTTP real em ≤ 10 s.

## C.4 O que este plano deliberadamente **não** faz

| Não faremos | Por quê |
|---|---|
| Expor largura, altura, raio do painel ou tamanho do launcher | `11 §C7/C8` mediu que os nossos valores já são a moda/mediana do mercado; a decisão do Walisson mantém a geometria. Expor convida a quebrar o que está certo |
| Auto-open do painel por gatilho | `16 §3.2` + `06 §2.4` + penalização de SEO desde 10/01/2017 (`13 §7.2`). Não é omissão — é decisão, e a tela explica |
| Editor de CSS livre para o widget | Iframe existe para isolar. CSS livre transforma cada cliente num fork visual impossível de suportar |
| Condicional aninhada (`E`/`OU`) na primeira entrega do pré-chat | É uma tela inteira por si só; nem o Intercom expõe isso ao cliente final (`14 §5.2`) |
| Reescrever o motor de campanhas | Ele funciona. A tela nova é dona da **regra**, a campanha continua dona da **mensagem** (§B.3.2) |
| Redesenhar CSAT, NPS, horário comercial e colaboradores | Fora do escopo aprovado (as 4 telas). Elas continuam onde estão e o perfil só ajusta a visibilidade |
| Permissão granular por aba | `administrator` é o piso hoje e resolve. A exceção (tracking) fica registrada como decisão futura (§B.0.4) |
| Instalar tag no site do cliente por padrão | Decisão **N5** do `DECISOES.md`. Se existir, é opt-in explícito, e nunca um GA4 nosso |

## C.5 Divergências declaradas

1. **`additional_attributes` não é "jsonb livre"** — §A.4. Contraria `10 §4.1 (C1)` e a task 25
   **T-C1.1**. Medição: `inboxes_controller.rb:217` é lista fechada; o arquivo teve **+53 −9** do
   upstream e **+87 −6** do fork entre v4.12.1 e HEAD/v4.16.2.
2. **São três lugares que montam a config do widget, não dois** — §A.5. O terceiro é o snippet
   montado no front (`widget-preview/Widget.vue:85-102`), que é o único que o cliente realmente cola
   no site. E os dois primeiros **já divergem** em 4 chaves.
3. **Nem toda mudança de backend nesta superfície é cara.** O instinto (e o tom do `15 §B12`) sugere
   que backend = risco de merge. Medido: `web_widget.rb`, `show.html.erb` e
   `configs/create.json.jbuilder` tiveram **zero** mudança dos dois lados em quatro minors. Os
   arquivos caros aqui são de **front** (`Settings.vue`, +242 −24 do upstream) e o
   `inboxes_controller.rb`.

---

## Anexo A — Tabela de referência: arquivo → o que faz → risco

| Arquivo | Papel hoje | O plano faz | Risco |
|---|---|---|---|
| `settings/inbox/Settings.vue` | Roteador de abas + aba 1 inteira | Ganha 4 `v-if`. **Nada mais** | 🔴 |
| `settings/inbox/inbox.routes.js` | Rota `:inboxId/:tab?` | Não muda (a aba é segmento) | 🟢 |
| `settingsPage/ConfigurationPage.vue` | Domínios, HMAC, webview, pin | Ganha o aviso de **D8** | 🔴 |
| `PreChatForm/Settings.vue` + `PreChatFields.vue` | Pré-chat atual | Vira o "modo Simples", quase intocado | 🟢 |
| `modules/widget-preview/*` | Preview + snippet | **P1–P4** (§B.2.4) | 🟢 |
| `settings/inbox/WidgetBuilder.vue` | Nada (órfão) | **Apagar** | ⚫ |
| `components-next/Settings/*` | Primitivos de settings | Consumir, não alterar | 🟢/🟡 |
| `components-next/colorpicker/ColorPicker.vue` | Seletor de cor | Consumir; a correção de **D2** é no chamador | 🟢 |
| `models/channel/web_widget.rb` | `EDITABLE_ATTRS`, flags, enum | Ampliar `EDITABLE_ATTRS` (**BE-6**) | 🟢 |
| `api/v1/accounts/inboxes_controller.rb` | Strong params da inbox | **Uma** extensão declarada (**BE-1**) | 🔴 |
| `views/widgets/show.html.erb` | Montador 1 | Ganha as chaves novas + tokens (**BE-7**) | 🟢 |
| `api/v1/widget/configs/create.json.jbuilder` | Montador 2 | Idem, no mesmo commit | 🟢 |
| `api/v1/models/_inbox.json.jbuilder` | Inbox para o dashboard | Ganha as chaves novas | 🟡 |
| `i18n/{pt_BR,en}/inboxMgmt.json` | i18n atual | Só **T0.3** e **T0.4** | 🔴 |
| `i18n/{pt_BR,en}/inboxWidget.json` | — | **Arquivo novo**, todo o i18n das 4 telas | 🟢 |

## Anexo B — Como reproduzir as medições desta task

```bash
cd /home/chatwoot/chatwoot

# 1. WidgetBuilder.vue é órfão e não existe no upstream
grep -rn "WidgetBuilder" app/javascript/ | grep -v node_modules        # → vazio
git cat-file -e v4.12.1:app/javascript/dashboard/routes/dashboard/settings/inbox/WidgetBuilder.vue
git cat-file -e v4.16.2:app/javascript/dashboard/routes/dashboard/settings/inbox/WidgetBuilder.vue
git show --stat 7b2b3ac37d -- app/javascript/dashboard/routes/dashboard/settings/inbox/WidgetBuilder.vue
git merge-base --is-ancestor 7b2b3ac37d HEAD && echo "a delecao esta na nossa historia"

# 2. Risco de merge das telas de config (as duas direcoes)
git diff --numstat v4.12.1 v4.16.2 -- \
  app/javascript/dashboard/routes/dashboard/settings/inbox/ \
  app/javascript/dashboard/modules/widget-preview/ \
  app/javascript/dashboard/components-next/Settings/ | sort -k1 -rn
git diff --numstat v4.12.1 HEAD -- \
  app/controllers/api/v1/accounts/inboxes_controller.rb \
  app/models/channel/web_widget.rb \
  app/views/widgets/show.html.erb \
  app/views/api/v1/widget/configs/create.json.jbuilder

# 3. Diff de chaves i18n en x pt_BR em INBOX_MGMT
python3 - <<'EOF'
import json
def flat(o,p=''):
    r={}
    for k,v in o.items():
        kk=f'{p}.{k}' if p else k
        r.update(flat(v,kk)) if isinstance(v,dict) else r.update({kk:v})
    return r
en=flat(json.load(open('app/javascript/dashboard/i18n/locale/en/inboxMgmt.json'))['INBOX_MGMT'])
pt=flat(json.load(open('app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json'))['INBOX_MGMT'])
print('en',len(en),'pt',len(pt))
print('falta em pt:',sorted(set(en)-set(pt)))
print('falta em en:',len(sorted(set(pt)-set(en))))
EOF

# 4. Chaves i18n orfas
grep -rn "TABS.CAMPAIGN\|TABS.WIDGET_BUILDER" app/javascript/ | grep -v node_modules  # → vazio

# 5. Os dois montadores de config, lado a lado
sed -n '7,35p'  app/views/widgets/show.html.erb
sed -n '1,25p'  app/views/api/v1/widget/configs/create.json.jbuilder

# 6. A lista fechada de additional_attributes
sed -n '210,225p' app/controllers/api/v1/accounts/inboxes_controller.rb

# 7. localStorage do widget builder
grep -n "widgetBuilderStorageKey\|LocalStorage.set\|LocalStorage.get" \
  app/javascript/dashboard/routes/dashboard/settings/inbox/Settings.vue
grep -n "WIDGET_BUILDER" app/javascript/dashboard/constants/localStorage.js

# 8. Bibliotecas ja instaladas que o plano usa
grep -nE '"(color2k|company-email-validator|libphonenumber-js|vuedraggable)"' package.json

# 9. Props reais dos componentes de components-next
python3 - app/javascript/dashboard/components-next/input/Input.vue <<'EOF'
import sys,re
s=open(sys.argv[1]).read()
m=re.search(r'defineProps\(\{(.*?)\n\}\)', s, re.S)
print(', '.join(re.findall(r'^\s{2}(\w+):', m.group(1), re.M)) if m else '(sem defineProps)')
EOF

# 10. A armadilha do CPF: 111.111.111-11 PASSA no digito verificador (§B.4.3)
python3 - <<'EOF'
def dv(c):
    s = sum(int(c[i]) * (len(c) + 1 - i) for i in range(len(c)))
    r = 11 - s % 11
    return 0 if r > 9 else r
for cpf in ('52998224725', '11111111111', '52998224726'):
    d1 = dv(cpf[:9]); d2 = dv(cpf[:9] + str(d1))
    print(cpf, '→ DV calculado', f'{d1}{d2}', '| informado', cpf[9:],
          '| passa no DV:', f'{d1}{d2}' == cpf[9:],
          '| digitos repetidos:', len(set(cpf)) == 1)
EOF
# → 52998224725 passa   ·   11111111111 PASSA no DV (rejeitar por digitos repetidos)
# → 52998224726 falha no DV
```

---

**Estado desta task.** Planejamento encerrado. **Nenhum arquivo de código foi alterado.** O único
arquivo escrito é este. As dependências de backend estão consolidadas na §C.2 para a **task 24**; a
Tela 4 se encaixa em `25-plano-tracking-integracao.md §A.3` sem duplicar; a Tela 1 consome a fundação
de tokens da Task 21 (`plano/redesenho/shared/tokens.css`).

---

## Correções aplicadas em 12/08/2026 (pós-auditoria)

Edição cirúrgica para propagar as arbitragens do `PLANO-MESTRE.md` §5 (bloqueador **B1** do
`auditoria/35-VEREDITO.md`). Onde o texto antigo mandava fazer o contrário da decisão arbitrada, ele
**saiu** — não ficou como alternativa embaixo do aviso.

| Onde (linha atual) | O que mudou | Origem |
|---|---|---|
| `:306` — §A.4 | A mitigação **não** é um sub-hash único `widget_config`: são **três chaves de topo** (`widget_profile`, `widget_triggers`, `widget_tracking`) numa **edição única** do `permit`. Com chave única, um `PATCH` parcial apagaria as outras — o merge do `#update` é de **primeiro nível apenas** (`inboxes_controller.rb:52-56`). Inclui o trecho de `permit` já no formato correto | §5 **A1** |
| `:733` — §B.1.4 | *"O perfil não é lido pelo widget, vive só no dashboard"* **não vale mais**: o servidor resolve e entrega **flags planas** (`profileConfig`) no boot. Acrescentados os **três regimes** de A3, e a tabela virou explicitamente "o que o perfil **propõe**" (regime 2, grava só com confirmação). A lista de flags **não é repetida aqui** — aponta para a canônica em `22-plano-widget.md` §B.3 | §5 **A3** · `auditoria/31-planos.md` §6 itens 1 e 2 |
| `:770` — §B.1.5 | *"Toda inbox Website existente nasce `suporte`"* → **sem backfill**; `nil` é lido como `support`. A verificação de quantas inboxes existem (V6) continua, mas deixou de ser pré-requisito de um backfill que não existe mais | §5 **A4**, **A2** |
| `:797` | Dependências da §B.1.6: BE-1 = as três chaves numa edição; BE-3 = perfil **sem backfill** | §5 **A1**, **A4** |
| `:946` — §B.3.1 | O híbrido "modelo Leadster" (endpoint devolvendo gatilhos **já filtrados**) **não entra na v1**: a configuração vai no payload de boot e a avaliação é do SDK. Acrescentada a consequência para esta tela — **tudo que o administrador escreve ali é público**, e a tela precisa dizer isso. Os três argumentos antigos ficaram registrados como histórico, marcados pelo que venceu e pelo que caiu | §5 **A5** |
| `:1104` | §B.3.4: BE-4 = armazenamento + entrega no boot, **sem endpoint filtrado** | §5 **A5** |
| `:1367` — **T1.4** | **Tarefa removida** (riscada, com o motivo na própria célula, para não renumerar T1.5–T1.16) | §5 **A4** |
| `:1414` | Nota após a Onda 3: T3.1, T3.2 e T3.7 dependem de **BE-4 na forma nova** — schema do jsonb + entrega no boot (bloco **3.02**) —, não de um endpoint | §5 **A5** · `auditoria/31-planos.md` §6 item 3 |
| `:1462` — **BE-1** | Reescrito: três chaves de topo, edição única, com o porquê do merge raso | §5 **A1** |
| `:1464` — **BE-3** | Reescrito: valores `support`/`marketing`, **sem backfill**, e o widget **recebe** as flags resolvidas (não o nome do perfil) | §5 **A1**, **A2**, **A3**, **A4** |
| `:1465` — **BE-4** | Reescrito: jsonb `widget_triggers` validado por JSON Schema e entregue no boot pelos dois montadores; **não é rota nova** | §5 **A5** |
| `:1517` — aceite 20 | Deixou de dizer que a API **rejeita** gatilhos por causa do perfil (contradizia `24` §9.4 e A3, e apagaria configuração do cliente). Agora: a aba fica oculta mas alcançável, a API aceita as três chaves independentemente do perfil, e o que rejeita (422) é `widget_triggers` fora do JSON Schema | §5 **A1**, **A3** |

**Verificações próprias feitas nesta correção** (leitura, sem escrita, HEAD `ee87f5e799`):
`inboxes_controller.rb:217` é a linha do `permit` de `additional_attributes` e `:52-56` é o merge
**raso**; `app/models/inbox.rb:50` tem o `store_accessor`; `Gemfile:37` tem `json_schemer`;
`widget/store/modules/campaign.js:45-47` é o cache de 1 hora citado na §B.3.1.

