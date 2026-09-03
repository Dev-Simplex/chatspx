# 17 — Handshake site → chat: passar parâmetros e identificar o visitante

> **Onda:** Estudo do chat de site — Integração
> **Data da apuração:** 12/08/2026
> **Escopo:** como o site do cliente diz ao chat *quem é a pessoa* e *o que ela está fazendo*, e
> como o chat recebe isso sem que um terceiro consiga forjar.
> **Status:** fase de estudo. Nenhuma linha de código do repositório foi alterada.

---

## Legenda de marcação

Toda afirmação neste documento carrega uma marca. Não há adjetivo sem origem.

| Marca | Significado |
|---|---|
| **[FATO]** | Copiado da documentação oficial do fornecedor, com URL. |
| **[CÓDIGO]** | Lido no repositório `/home/chatwoot/chatwoot`, com `arquivo:linha`. |
| **[MEDIDO]** | Observado em execução real (Playwright / `curl`), com o comando que produziu o número. |
| **[INFERÊNCIA]** | Dedução minha a partir de fatos marcados acima. Explicito a base. |
| **[NÃO VERIFICADO]** | Não consegui confirmar. Fica registrado como lacuna, não como afirmação. |

**Aviso de rigor.** Distingo em todo o texto três coisas que se parecem e não são: (a) o que a
documentação do fornecedor *promete*, (b) o que o objeto global *expõe em runtime*, (c) o que o
*servidor* aceita. Onde só verifiquei uma das três, digo qual.

---

## 0. Sumário executivo — os oito achados

1. **[CÓDIGO] O `window.$chatwoot` expõe 13 métodos e 23 propriedades de configuração.** Medi
   em runtime contra o SDK servido pela homologação: `toggle`, `toggleBubbleVisibility`,
   `popoutChatWindow`, `setUser`, `setCustomAttributes`, `deleteCustomAttribute`,
   `setConversationCustomAttributes`, `deleteConversationCustomAttribute`, `setLabel`,
   `removeLabel`, `setLocale`, `setColorScheme`, `reset`. Isso é **mais superfície pública que
   Leadster, Tidio, JivoChat e tawk.to** no quesito de dados. Não é aqui que perdemos.

2. **[CÓDIGO] Perdemos na profundidade do payload, não na quantidade de métodos.** O `setUser`
   aceita 12 campos, mas **nenhum objeto de empresa/conta** (`company` / `companies` do
   Intercom), **nenhum `created_at` do cadastro**, **nenhum evento tipado** (`trackEvent`), e
   **nenhum campo de conversa no boot** (só depois que a conversa existe). Detalhe em §4.5.

3. **[CÓDIGO] `setConversationCustomAttributes` chamado antes de existir conversa é perdido em
   silêncio.** O controller responde `404` quando não há conversa
   (`app/controllers/api/v1/widget/conversations_controller.rb:93-95`) e o store do widget
   engole o erro com um `// IgnoreError`
   (`app/javascript/widget/store/modules/conversation/actions.js:183-189`). O site não recebe
   sinal nenhum. Este é o bug de integração mais provável em produção hoje.

4. **[CÓDIGO] O enforcement de HMAC tem duas portas abertas.** `hmac_mandatory` só é checado na
   ação `set_user` (`app/controllers/api/v1/widget/contacts_controller.rb:4`). A ação `update`
   (`PATCH /api/v1/widget/contact`) aceita `email`, `name` e `phone_number` **sem qualquer
   verificação**, e dispara o mesmo `ContactIdentifyAction` que faz merge por e-mail. Além
   disso, dentro do próprio `set_user` há um *early return* que desliga a verificação quando
   `custom_attributes` está presente e `identifier` está ausente
   (`contacts_controller.rb:59`). Detalhe e consequências em §3.5.

5. **[CÓDIGO] Nenhum dos dois lados da ponte `postMessage` valida a origem.** O SDK no site
   escuta `window.onmessage` sem checar `e.origin` (`app/javascript/sdk/IFrameHelper.js:104-117`)
   e o widget dentro do iframe também não (`app/javascript/widget/helpers/utils.js:18-21`,
   consumido em `app/javascript/widget/App.vue:260-264`). Qualquer script de terceiro já
   presente na página pode falar com o widget como se fosse o site. Detalhe em §4.3.

6. **[FATO] O mercado migrou de HMAC para JWT.** Intercom recomenda parar de gerar `user_hash`
   e usar `intercom_user_jwt`; Zendesk messaging nasceu em JWT; Drift usa JWT; LiveChat usa
   token opaco com ciclo de vida. Só Crisp e tawk.to continuam em HMAC puro. Nós estamos em
   HMAC puro **sem expiração** — o `identifier_hash` do Chatwoot não tem `exp`. §3.1 e §3.6.

7. **[FATO + MEDIDO] A Leadster não tem nada disso — e o que ela tem é por URL, não por API.**
   Confirmei no bundle público deles: **zero** ocorrências de `setUser`, `identify`,
   `setContactInfo`, `setVisitorData`, `hmac`, `signature`. A única forma de o site passar dado
   para o fluxo é **regex sobre a URL** (`metadata.urlData`) configurada no painel deles, mais
   os UTMs da query string. §2.11.

8. **[CÓDIGO] Nosso pre-chat não pré-preenche: ele esconde.** Quando o site já mandou e-mail via
   `setUser`, o formulário pré-chat **remove o campo** em vez de preenchê-lo
   (`app/javascript/widget/components/PreChat/Form.vue:83-105`). Funciona, mas o visitante perde
   a chance de corrigir. §5.2.

---

## 1. Metodologia e reprodutibilidade

### 1.1 O que fiz

| Técnica | Alvo | Saída |
|---|---|---|
| Leitura de documentação oficial | 11 fornecedores | assinaturas literais, §2 |
| Playwright — enumeração de globais | 10 sites de fornecedores | superfície JS real em runtime, §2.12 |
| Playwright — enumeração do nosso SDK | `hmlchat.simplexsolucoes.com.br` | inventário `$chatwoot`, §4.1 |
| `curl` + parser estático | bundle público da Leadster | ausência de API de identificação, §2.11 |
| Leitura de código | `/home/chatwoot/chatwoot` | §4 inteira, com `arquivo:linha` |

### 1.2 Comandos que produziram os números

**Enumeração da superfície pública dos widgets dos concorrentes** (Playwright, headless
Chromium, `--no-sandbox --disable-dev-shm-usage`, viewport 1440×900, espera de 9 s após
`domcontentloaded`; segunda passada com `load` + scroll + 12 s para widgets *lazy*):

```
python3 probe_api.py    # 10 alvos, 1 passada
python3 probe_api2.py   # 6 alvos, espera longa + scroll
```

O probe lê `window[<nome>]`, percorre a cadeia de protótipos até 3 níveis e lista
`nome:tipo` de cada propriedade própria. Não faz login, não envia dado nenhum, não interage com
formulário. É leitura passiva de superfície pública.

**Enumeração do nosso SDK** (`probe_chatspx.py`): página HTML local que carrega
`https://hmlchat.simplexsolucoes.com.br/packs/js/sdk.js` e chama
`chatwootSDK.run({websiteToken:'PROBE_INVALID_TOKEN', baseUrl: ...})`. O token é inválido de
propósito: o objeto `$chatwoot` é montado **sincronamente** dentro de `runSDK`
(`app/javascript/entrypoints/sdk.js:58-211`), antes de qualquer resposta do servidor, então a
superfície pública é observável sem sessão real e sem tocar em dado de cliente.

**Bundle da Leadster:**

```
curl -sS -A "Mozilla/5.0" https://cdn.leadster.com.br/neurolead/debug-production/neurolead.js -o nld.js
# http=200  bytes=1036439
```

**Tamanho do nosso loader:**

```
curl -sS -o /dev/null -w "http=%{http_code} size=%{size_download}\n" https://hmlchat.simplexsolucoes.com.br/packs/js/sdk.js
# http=200 size=28834
```

### 1.3 O que NÃO fiz — e por quê

- **Não testei o handshake contra o servidor de nenhum fornecedor.** Isso exigiria conta e
  credencial. Onde a documentação afirma um comportamento de servidor, marquei **[FATO]** com a
  URL, não **[MEDIDO]**.
- **Não executei ataque nenhum** contra o nosso backend, nem em homologação. As consequências de
  segurança descritas em §3.5 vêm de **leitura de código** e estão marcadas como
  **[INFERÊNCIA]**, com o caminho exato para quem quiser confirmar depois em ambiente isolado.
- **Não inspecionei widget da Leadster ao vivo.** [MEDIDO] O site `leadster.com.br` **não roda
  o próprio widget** — nem na home nem em `/como-funciona/`. Os globais `neurolead`,
  `neuroleadId`, `neuroleadLanguage` e `ll` estavam **todos ausentes** nas duas páginas; o que
  há em `/como-funciona/` são globais do **HubSpot** (`__PRIVATE__HubspotCtaClient`,
  `HubSpotCallsToActions`). Por isso a análise da Leadster é estática, sobre o bundle público
  deles.

---

## 2. PARTE A — Como o mercado faz

Ordem: do mais completo para o mais pobre.

### 2.1 Intercom

**Documentação:** [developers.intercom.com/installing-intercom/web/methods](https://developers.intercom.com/installing-intercom/web/methods),
[.../attributes-objects](https://developers.intercom.com/installing-intercom/web/attributes-objects)

#### Assinatura literal — os três verbos do ciclo de vida

```javascript
// [FATO] boot — abre a sessão com identidade
Intercom('boot', {
  app_id: 'abc12345',
  email: 'john.doe@example.com',
  created_at: 1234567890,
  name: 'John Doe',
  user_id: '9876'
});

// [FATO] update — atualiza campos e registra impressão na URL atual
Intercom('update');
Intercom('update', { plan: 'pro', last_order_value: 450 });

// [FATO] shutdown — encerra a sessão e limpa as conversas
Intercom('shutdown');
```

**[FATO]** Sobre o `update`: *"trigger[s] the JavaScript to look for new messages that should be
displayed"* e *"will update those fields on the current user in addition to logging an impression
at the current URL"*. **Tem limite de 20 chamadas a cada 30 minutos.** Este número importa para
SPA: quem chama `update` a cada troca de rota estoura o teto num fluxo de navegação normal.

**[FATO]** Sobre o `shutdown`: *"clear[s] your users' conversations anytime they logout"*. Sem
ele, *"the cookie we use to track who was most recently logged in"* mantém as conversas visíveis
**por uma semana**. Para dispositivo compartilhado, a doc recomenda **também apagar manualmente
os cookies com prefixo `intercom-`** — ou seja, o próprio `shutdown` não é suficiente.

#### O objeto de settings — campos aceitos

**[FATO]** Dados da pessoa:

| Campo | Tipo | Observação |
|---|---|---|
| `email` | string | só para *users*, não para *leads* |
| `user_id` | string | identificador do usuário logado; só para *users* |
| `name` | string | usuário ou lead |
| `phone` | string | usuário ou lead |
| `created_at` | timestamp | *"Unix timestamp (in seconds) when the user signed up"* |
| `unsubscribed_from_emails` | boolean | status de descadastro |
| `language_override` | string | idioma do messenger |
| `utm_campaign` / `utm_content` / `utm_medium` / `utm_source` / `utm_term` | string | atribuição |
| `avatar` | objeto | `{ type: 'avatar', image_url: '<https>' }` |
| `user_hash` | string | *"Used for identity verification"* (legado, ver §3.1) |
| `intercom_user_jwt` | string | JWT de sessão (modelo atual) |
| `company` | objeto | empresa do usuário |
| `companies` | array | várias empresas |

**[FATO]** O objeto `company`:

| Campo | Tipo |
|---|---|
| `company_id` / `id` | string (obrigatório) |
| `name` | string (obrigatório) |
| `created_at` / `remote_created_at` | timestamp |
| `plan` | string |
| `monthly_spend` | integer |
| `user_count` | integer (somente leitura) |
| `size` | integer |
| `website` | string |
| `industry` | string |

**[FATO]** Configuração do messenger, no mesmo objeto: `app_id`, `custom_launcher_selector`,
`alignment`, `horizontal_padding` (mín. 20 px), `vertical_padding` (mín. 20 px), `z_index`,
`hide_default_launcher`, `hide_notifications`, `theme_mode` (`light`/`dark`/`system`),
`messenger_style_id`, `session_duration` (ms), `action_color`, `background_color`, `link_color`.

#### Custom attributes — regras e limites

**[FATO]** *"Qualquer atributo não listado será tratado como custom user attribute."* Strings
vazias, `"undefined"` ou `"null"` aparecem como **"Unknown"**. Atributos configurados no painel
para impedir atualização pelo Messenger são **ignorados silenciosamente**.

**[FATO]** Limites, da central de ajuda: **250 CDAs de People + Company por workspace**
(arquiváveis para liberar espaço); atributos do tipo lista com **35 opções no máximo** (limite
que *"can't be lifted"*); **255 caracteres por atributo**, com truncamento acima disso.
Fonte: [intercom.com/help/.../send-custom-user-attributes-to-intercom](https://www.intercom.com/help/configure-intercom-for-your-product-or-site/customize-intercom-to-be-about-your-users/send-custom-user-attributes-to-intercom)

#### O resto da API

**[FATO]** `hide`, `show`, `showMessages`, `showNewMessage` (aceita conteúdo pré-preenchido:
`Intercom('showNewMessage', 'pre-populated content')`), `trackEvent('invited-friend')`,
`getVisitorId()`, `startTour(123)`, `showArticle(123)`, `showSpace('home'|'messages'|'help'|'news'|'tasks'|'tickets')`,
`onHide(fn)`, `onShow(fn)`, `onUnreadCountChange(fn)`, `onUserEmailSupplied(fn)`.

**[MEDIDO]** Em `https://www.intercom.com/`, `window.Intercom` existe como `function` com a
propriedade própria `booted: boolean`; `window.intercomSettings` é objeto com as chaves
`app_id`, `hide_default_launcher`, `language_override`, `api_base`, `installation_type`. O
próprio site deles **não** boota com identidade — é visitante anônimo.

---

### 2.2 Zendesk messaging

**Documentação:** [developer.zendesk.com/api-reference/widget-messaging/web/core](https://developer.zendesk.com/api-reference/widget-messaging/web/core/),
[.../authentication](https://developer.zendesk.com/api-reference/widget-messaging/web/authentication/),
[support.zendesk.com/.../4411666638746](https://support.zendesk.com/hc/en-us/articles/4411666638746-Authenticating-end-users-in-messaging-for-the-Web-Widget-and-mobile-SDK)

#### Identificação — assinatura literal

```javascript
// [FATO] login: você entrega uma FUNÇÃO que busca o JWT, não o JWT
zE("messenger", "loginUser", jwtCallback<function>, loginCallback<function>)

zE("messenger", "loginUser", function (callback) {
  fetch('/api/jwt-token')
    .then(response => response.json())
    .then(data => callback(data.token));
});

// [FATO] logout
zE("messenger", "logoutUser")
```

**Este é o desenho mais maduro do mercado** e vale destacar por quê: o Zendesk **não recebe um
token**, ele recebe **um jeito de conseguir um token**. **[FATO]** *"É necessário fornecer uma
função que busque dinamicamente um novo token JWT cada vez que o widget encontrar um erro 401."*
Isso resolve de raiz o problema de token expirado em página cacheada (§3.6).

#### O JWT

**[FATO]** Payload mínimo:

```json
{
    "external_id": "12345678",
    "scope": "user",
    "name": "Jane Soap"
}
```

**[FATO]** Com identidade de e-mail:

```json
{
    "external_id": "12345678",
    "email": "janes@soap.com",
    "email_verified": true,
    "name": "Jane Soap",
    "scope": "user"
}
```

**[FATO]** `external_id` é obrigatório, **255 caracteres no máximo**, e é *"the primary
identifier for users authenticating over messaging"*. `scope` é obrigatório e o **único valor
válido é `"user"`**. `email_verified: true` indica propriedade comprovada do endereço; sem a
flag, o e-mail é tratado como não verificado. O header do JWT carrega `kid` identificando a
chave de assinatura, que *"is created by a Zendesk admin in Admin Center and shared with a
developer"*.

**[FATO]** *"A propriedade `exp` de um payload JWT é honrada pelo messaging Web Widget. Uma
requisição feita com um JWT que possui um `exp` no passado é rejeitada."*

**[FATO — importante para o nosso desenho]** *"When an unauthenticated user on the Web Widget or
Mobile SDK authenticates... a user merge will occur"*, consolidando a conversa anterior. Ou
seja: o Zendesk resolve explicitamente o caso "o visitante conversou anônimo e só depois fez
login".

#### Dados de contexto — o que dá para passar sem ser identidade

```javascript
// [FATO] campos tipados da conversa, definidos no admin
zE("messenger:set", "conversationFields", [{ id: "123456789", value: 100.5 }])

// [FATO] tags livres
zE("messenger:set", "conversationTags", ["sales", "computer_accessories"])

// [FATO] atributos do usuário pós-login
zE("messenger", "updateUser", { name: "Jane Doe", plan: "enterprise" }, function() {
  console.log("User updated");
})
```

**[FATO]** Após `logoutUser`, *"todos os dados de tags de conversa e campos de conversa são
limpos"*.

#### Ganchos que nós não temos

```javascript
// [FATO] injeta metadados em TODA mensagem enviada
zE("messenger:set", "beforeMessageSent", function(message, data) {
  message.metadata = { timestamp: Date.now() };
  return message;
});

// [FATO] reescreve mensagem antes de exibir
zE("messenger:set", "beforeMessageDisplay", function(message, data) {
  if (message.author.role === 'agent') message.author.displayName = "Support Team";
  return message;
});
```

**[MEDIDO]** Em `https://www.zendesk.com/` e em `https://support.zendesk.com/hc/en-us`, os
globais `zE` e `zESettings` estavam **ausentes** após carga + scroll + 12 s. Em
`support.zendesk.com` existe `ZendeskWidgetInit`, o que sugere carregamento sob demanda.
**[INFERÊNCIA]** O widget deles é *lazy* por clique; não confirmei porque não interagi.

---

### 2.3 HubSpot

**Documentação:** [developers.hubspot.com/docs/reference/api/conversations/chat-widget-sdk](https://developers.hubspot.com/docs/reference/api/conversations/chat-widget-sdk),
[.../visitor-identification/guide](https://developers.hubspot.com/docs/api-reference/legacy/conversations/visitor-identification/guide),
[.../analytics-and-events/tracking-code](https://developers.hubspot.com/docs/reference/api/analytics-and-events/tracking-code)

O HubSpot é o caso mais instrutivo porque tem **dois caminhos separados** — e um deles é
frouxo de propósito.

#### Caminho 1 — `identify` do código de rastreamento (sem verificação)

```javascript
// [FATO]
_hsq.push(['identify', emailAddress]);
```

**[FATO]** *"The `identify` function only sets the identities in the tracker. The identities do
not get passed to HubSpot until you make a separate `trackPageView` or
`trackCustomBehavioralEvent` call."* Ou seja: `identify` sozinho não faz nada.

**[FATO]** *"Only use the `identify` method when you know the email address."* E o aviso
explícito: usar e-mail de placeholder para visitante desconhecido **cria registros de contato
indesejados**.

#### Caminho 2 — Visitor Identification API (com verificação)

```javascript
// [FATO] tem que ser setado ANTES do widget carregar
window.hsConversationsSettings = {
  loadImmediately: false,
  identificationEmail: "visitor-email@example.com",
  identificationToken: "<TOKEN FROM API>"
};
window.HubSpotConversations.widget.load();
```

**[FATO]** O token vem de `POST https://api.hubapi.com/visitor-identification/v3/tokens/create`
com corpo `{ "email": "gob@bluth.com", "firstName": "Gob", "lastName": "Bluth" }` — e-mail
obrigatório, nome opcional. Exige o escopo
`conversations.visitor_identification.tokens.create`, private app, e **assinatura Professional
ou Enterprise**.

**[FATO]** *"Tokens are temporary and will expire after 12 hours"*, cacheáveis desde que
renovados dentro da janela.

**[FATO — a armadilha]** *"The token and email must be set on the `hsConversationsSettings`
object on the window **every time the page loads** for an authenticated visitor, as this context
will not be carried across page loads automatically if these parameters are no longer set."*
E: *"`hsConversationsSettings` can only be used **before** the Conversations API has loaded"* —
o que quebra o caso do SPA em que o login acontece depois do widget já ter inicializado.

#### Resto do SDK

**[FATO]** `window.hsConversationsSettings`: `loadImmediately` (bool, default `true`),
`inlineEmbedSelector` (string), `enableWidgetCookieBanner`, `disableAttachment`,
`disableInitialInputFocus`, `avoidInlineStyles`, `hideNewThreadLink`.

**[FATO]** `window.HubSpotConversations.widget`: `load()` (limitado a 1×/segundo), `refresh()`
(re-renderiza — é o caminho para SPA), `open()`, `close()`, `remove()`, `status()` →
`{loaded: boolean}`.

**[FATO]** Eventos via `.on()` / `.off()`: `conversationStarted`, `conversationClosed`,
`userSelectedThread`, `unreadConversationCountChanged`, `contactAssociated` (visitante vinculado
ao contato do CRM), `userInteractedWithWidget`, `widgetLoaded`, `quickReplyButtonClick`,
`widgetClosed`.

**[FATO]** `window.HubSpotConversations.clear()` remove os cookies de chat;
`clear({resetWidget: true})` remove também o widget e cria instância nova.

**[MEDIDO]** Em `https://www.hubspot.com/`, `window.HubSpotConversations` existe com as chaves
`debug`, `on`, `off`, `clear`, `resetAndReloadWidget`, `widget`. Note o
**`resetAndReloadWidget`**, que não aparece na página de referência que li — a superfície real é
maior que a documentada. `window.hsConversationsSettings` estava **ausente** (visitante
anônimo), e `window._hsq` existe como Array.

---

### 2.4 Drift / Salesloft

**Documentação:** [devdocs.drift.com/docs/user-identification](https://devdocs.drift.com/docs/user-identification),
[.../securing-drift-on-your-site-using-signed-identities](https://devdocs.drift.com/docs/securing-drift-on-your-site-using-signed-identities),
[.../contact-properties](https://devdocs.drift.com/docs/contact-properties)

```javascript
// [FATO]
drift.identify('userId', { userAttributes: 'data' })

// [FATO] com identidade assinada — JWT como TERCEIRO argumento
drift.identify(userId, {}, { userJwt: <seu JWT> })

// [FATO] atributos sem identificar
drift.api.setUserAttributes({ chave: 'valor' })

// [FATO] evento
drift.track(...)
```

**[FATO]** *"Drift will merge attributes collected from a site visitor during an anonymous
session with the identified contact record when `drift.identify()` is called."*

**[FATO — pegadinha]** `setUserAttributes` *"relies on the presence of an identifying cookie, or
the use of `drift.identify` in order to update an existing Drift contact record, and may lead to
**duplicate contact records** if the site visitor is anonymous."*

**[FATO]** JWT em **HMAC256**; claim obrigatório `sub` = userId; `exp` opcional (epoch em
segundos); chave secreta guardada no backend, *"securely stored on your application's backend and
kept secret"*.

**[FATO]** Atributos são **case-sensitive**, e o objeto de `drift.track()` deve ser *flat* —
sem objeto aninhado nem array.

**[NÃO VERIFICADO]** A lista fechada de atributos padrão e os limites de quantidade/tamanho do
Drift. A página `contact-properties` não os publica; apenas recomenda *"setting up your custom
attributes first"* e avisa que atributos são criados automaticamente se não declarados.

---

### 2.5 Crisp

**Documentação:** [docs.crisp.chat/guides/chatbox-sdks/web-sdk/dollar-crisp](https://docs.crisp.chat/guides/chatbox-sdks/web-sdk/dollar-crisp/),
[.../identity-verification](https://docs.crisp.chat/guides/chatbox-sdks/web-sdk/identity-verification/)

```javascript
// [FATO] identidade
$crisp.push(["set", "user:email",    [email]])
$crisp.push(["set", "user:phone",    [phone]])
$crisp.push(["set", "user:nickname", [nickname]])
$crisp.push(["set", "user:avatar",   [avatarUrl]])
$crisp.push(["set", "user:company",  [name, options]])
//   options: { url, description, employment, geolocation }

// [FATO] dados arbitrários da sessão — pares chave/valor
$crisp.push(["set", "session:data", [[[key_1, value_1], [key_2, value_2]]]])
//   valores aceitos: string, boolean ou number

// [FATO] segmentos (equivalente a labels)
$crisp.push(["set", "session:segments", [[segment_1, segment_2], overwrite?]])

// [FATO] eventos com cor
$crisp.push(["set", "session:event", [[[text_1, data_1, color_1]]]])

// [FATO] logout
$crisp.push(["do", "session:reset", [reload?]])
```

#### Verificação de identidade — o modelo mais simples que existe

```javascript
// [FATO] a assinatura viaja no MESMO array do e-mail
$crisp.push(["set", "user:email", [
  "user@gmail.com",
  "cd7cc422ea97c82d844b2373fdcd6259c9ee6e135af65ab6fe6ca85e3f07abb1"
]]);
```

**[FATO]** HMAC-SHA256 sobre **o e-mail**. Exemplo publicado por eles: segredo
`0fd72e0ff53b274293029fd1f3f40c92` + e-mail `user@gmail.com` → o hash acima. **[FATO]** *"You
must generate signatures with the HMAC-SHA256 algorithm. Any other HMAC digest is not accepted
and will be refused."* E o aviso: *"never use your verification secret key to generate
signatures in your front-end directly."* A chave fica em Settings → Workspace Settings →
Advanced configuration → Identity Verification.

**[FATO]** Assinatura inválida **não bloqueia**: a conversa aparece como *"Unverified"* no
dashboard. **[NÃO VERIFICADO]** Se existe modo obrigatório por website — a página de identity
verification não menciona enforcement, o que é diferente de afirmar que não existe.

**[MEDIDO]** Em `https://crisp.chat/en/`: `window.$crisp` existe com os métodos `push`, `get`,
`set`, `is`, `on`, `off`, `do`, `config`, `safe`, `help`, `__init`, mais os internos `__spool` e
`__debug`. Também expostos: `CRISP_WEBSITE_ID` (string), `CRISP_RUNTIME_CONFIG` (`{locale}`),
`CRISP_READY_TRIGGER`, `$__CRISP_INCLUDED`, `$__CRISP_INSTANCE`. **A superfície real (`get`,
`is`, `config`, `safe`, `help`) é maior que a documentada na página de identificação.**

---

### 2.6 LiveChat (Text Platform)

**Documentação:** [platform.text.com/docs/extending-chat-widget/javascript-api](https://platform.text.com/docs/extending-chat-widget/javascript-api),
[.../custom-identity-provider](https://platform.text.com/docs/extending-chat-widget/custom-identity-provider)

```javascript
// [FATO] as quatro funções base
LiveChatWidget.call("method", data);
LiveChatWidget.get("method");
LiveChatWidget.on("event", callback);
LiveChatWidget.off("event", callback);

// [FATO] dados do visitante
LiveChatWidget.call("set_customer_name",  "John Doe");
LiveChatWidget.call("set_customer_email", "john@example.com");

// [FATO] variáveis de sessão — criar/substituir
LiveChatWidget.call("set_session_variables", { username: "john.doe", cart_value: "450" });
// [FATO] atualizar sem substituir as existentes
LiveChatWidget.call("update_session_variables", { cart_value: "400" });

// [FATO] leitura de volta
LiveChatWidget.get("customer_data");
// → { id, name, email, isReturning, status, sessionVariables }
```

**Duas coisas que só eles têm e que valem para o nosso redesenho:**

1. **[FATO] `update_session_variables` faz merge; `set_session_variables` substitui.** Dois
   verbos distintos e nomeados. Nós temos essa distinção **acidental e invertida** entre contato
   (merge) e conversa (substitui), sem nome que a comunique — §4.4.
2. **[FATO] `get("customer_data")` devolve o estado.** O site consegue **ler de volta** o que o
   chat sabe. Nenhum outro fornecedor da lista faz isso tão diretamente, e nós não fazemos.

#### Custom Identity Provider — o modelo de token com ciclo de vida

```javascript
// [FATO]
window.__lc.custom_identity_provider = function () {
    return {
        getToken: ...,       // resolve o token (pode vir do cache)
        getFreshToken: ...,  // SEMPRE busca token novo
        hasToken: ...,       // resolve boolean
        invalidate: ...      // remove o token atual
    }
}
```

**[FATO]** O token traz `accessToken`, `entityId` (o ID do cliente), `expiresIn`
(**em milissegundos**), `tokenType: 'Bearer'`, `creationDate` (unix) e `licenseId`. É obtido em
`https://accounts.livechat.com/customer/token`, tipicamente pelo servidor do cliente.

**[FATO]** Exemplo publicado com cache e expiração:

```javascript
const isExpired = ({ creationDate, expiresIn }) => Date.now() >= creationDate + expiresIn
```

**[MEDIDO]** Em `https://www.livechat.com/`: `window.LiveChatWidget` com `_q`, `_h`, `_v`, `on`,
`once`, `off`, `get`, `call`, `init`, `scriptTagVersion`, `diagnose`. `window.__lc` com
`license` (number) e `ga_version` (string) — sem `custom_identity_provider`, o que é coerente
com visitante anônimo.

---

### 2.7 Freshchat

**Documentação:** [developers.freshchat.com/web-sdk/v2](https://developers.freshchat.com/web-sdk/v2/)

```javascript
// [FATO] propriedades do usuário
window.fcWidget.user.setProperties({ plan: "Pro", status: "Active" });
window.fcWidget.user.setFirstName("John");
window.fcWidget.user.setEmail("john.doe@gmail.com");

// [FATO] identificação entre dispositivos
window.fcWidget.setExternalId("john.doe1987");

// [FATO] logout
window.fcWidget.user.clear().then(function() { console.log('User cleared'); });

// [FATO] autenticação
window.fcWidget.authenticate(signedUUID);

// [FATO] observar o estado de autenticação
window.fcWidget.on("user:statechange", function(data) {
  if (userData.userState === "authenticated") { console.log("User Authenticated"); }
});
```

**[FATO — e é o ponto fora da curva]** O Freshchat usa **RS256**, não HMAC. O JWT exige
`iat`, `reference_id` e `freshchat_uuid` no payload, e chave gerada com
`ssh-keygen -t rsa -b 2048`. É o único da lista com **assinatura assimétrica** — a chave privada
fica só no cliente, o Freshchat guarda a pública. **[INFERÊNCIA]** Vazamento do lado do
fornecedor não permite forjar identidade, o que é uma propriedade que HMAC compartilhado não tem.

**[FATO]** `restoreId` + `externalId` juntos restauram a conversa entre navegadores.

**[MEDIDO]** Em `https://www.freshworks.com/`, a propriedade `fcWidget` **aparece na lista de
propriedades próprias de `window`, mas `typeof window.fcWidget === 'undefined'`**. Também
existem `_q_widgetInitializedAt` e `_q_widgetInitialized`. **[INFERÊNCIA]** É um *placeholder*
declarado antes da inicialização real. Registro isso porque é exatamente o tipo de detalhe que
gera falso negativo em auditoria: "o global existe" e "o global tem valor" são coisas diferentes.

---

### 2.8 tawk.to

**Documentação:** [developer.tawk.to/jsapi](https://developer.tawk.to/jsapi/)

```javascript
// [FATO] identidade — tem que ser definida ANTES do widget carregar
window.Tawk_API = window.Tawk_API || {};
window.Tawk_API.visitor = {
    name  : 'Name',
    email : 'email@email.com',
    hash  : '<calculate-hash>'
};

// [FATO] atributos depois da carga
Tawk_API.setAttributes({ chave: 'valor' }, callback);

// [FATO] evento, tags, login/logout
Tawk_API.addEvent(name, metadata, callback);
Tawk_API.addTags(tags, callback);
Tawk_API.removeTags(tags, callback);
Tawk_API.login(data, callback);
Tawk_API.logout(callback);
```

**[FATO] — os limites mais bem documentados do mercado:**

| Limite | Valor |
|---|---|
| Atributos customizados | **50** (nome/e-mail/hash não contam) |
| Formato da chave | apenas alfanuméricos + hífen, convertida para minúscula |
| Tamanho do valor | **255 caracteres** |
| Tags por chat | **10** |
| Telefone | formato E.164 obrigatório |

**[FATO]** Secure Mode: hash gerado via HMAC-SHA256 sobre **e-mail + API key**.

**[MEDIDO]** Em `https://www.tawk.to/`, `window.Tawk_API` expõe 27 membros:
`maximize`, `minimize`, `toggle`, `popup`, `getWindowType`, `showWidget`, `hideWidget`,
`toggleVisibility`, `getStatus`, `isChatMaximized`, `isChatMinimized`, `isChatHidden`,
`isChatOngoing`, `isVisitorEngaged`, `endChat`, `addEvent`, `setAttributes`, `addTags`,
`removeTags`, `widgetPosition`, `login`, `logout`, `switchWidget`, `shutdown`, `start`, e as
flags `onBeforeLoaded`/`onLoaded`. **Confere com a documentação** — raro.

---

### 2.9 Tidio

**Documentação:** [developers.tidio.com/docs/widget-visitor-identification](https://developers.tidio.com/docs/widget-visitor-identification)

```javascript
// [FATO] antes da carga
document.tidioIdentify = {
    distinct_id: 'unique_id',      // string ou number, recomendam UUIDv4
    email: 'contact@mail',
    name: 'John Doe',
    phone: '+44 2032897807'        // com código de área
};

// [FATO] depois da carga
tidioChatApi.setVisitorData({ email: '...', city: 'Denver', country: 'US', tags: ['tag1','tag2'] });
tidioChatApi.addVisitorTags(['tag1', 'tag2']);
tidioChatApi.setContactProperties({ company_name: '...' });
tidioChatApi.setVisitorCurrency({ code: 'EUR', exchangeRate: 1.25 });
```

**[FATO]** Todos os campos de `tidioIdentify` são opcionais. Para `setContactProperties`, *"você
precisa criar a definição da propriedade de contato antes"* — igual ao nosso
`CustomAttributeDefinition`.

**[FATO]** *"If the email defined in `document.tidioIdentify` differs from the one triggered
through `tidioChatApi.setVisitorData`, the system will replace the first one after refreshing the
page."* — conflito resolvido por *último a escrever ganha*, mas só depois do reload.

**[FATO]** *"no mention of hash, HMAC, JWT, or identity verification"* na documentação de
identificação. **Sem verificação criptográfica.**

**[MEDIDO]** Em `https://www.tidio.com/`, `window.tidioChatApi` expõe: `popUpOpen`, `popUpHide`,
`chatDisplay`, `setColorPallete` *(sic, com o erro de grafia)*, `open`, `close`, `display`,
`show`, `hide`, `setColorPalette`, `track`, `messageFromVisitor`, `messageFromOperator`,
`setVisitorData`, `addVisitorTags`, `setContactProperties`, `setFeatures`, `adjustStyles`,
`removeStyles`, `setVisitorCurrency`, `setDeviceType`, `on`, `trigger`, `method`, `_addToQueue`,
`_flushAllFromQueue`, além de `eventPrefix`, `readyEventWasFired` e `queue`.
`document.tidioIdentify` estava ausente (visitante anônimo).

Vale registrar `messageFromVisitor` / `messageFromOperator`: **o site consegue injetar mensagem
na conversa** dos dois lados. Nós não temos nada equivalente.

---

### 2.10 JivoChat

**Documentação:** [jivochat.com/docs/widget](https://www.jivochat.com/docs/widget/)

```javascript
// [FATO]
jivo_api.setContactInfo({ name: string, email: string, phone: string, description: string });
jivo_api.setUserToken(token: string);
jivo_api.setCustomData([{ content: string, title: string, key: string, link: string }]);
jivo_api.open({ start: 'call' | 'menu' | 'chat' });
jivo_api.close();
function jivo_onLoadCallback() { }
```

**[FATO]** `setUserToken` *"sends it in Webhook events"* — é um identificador opaco repassado ao
CRM, **sem validação criptográfica**. A doc **recomenda** usar um identificador difícil de
adivinhar *"to avoid spoofing"*. **[INFERÊNCIA]** Isso é segurança por obscuridade: o segredo
está no navegador do visitante, então qualquer um consegue ler o próprio e forjar o de outro se
o esquema for previsível.

**[FATO]** Limite documentado: `setClientAtributes` *(sic)* — *"The method can be called no more
than 10 times per hour"*. Sem limite publicado para `setContactInfo`, `setUserToken` ou
`setCustomData`. **[NÃO VERIFICADO]** Tamanho máximo dos campos.

**[MEDIDO]** Em `https://www.jivochat.com/`, `window.jivo_onLoadCallback` existe como
`function`; `jivo_api` e `jivo_config` estavam ausentes na primeira passada, e a segunda passada
**falhou por timeout de 60 s no `load`** do próprio site deles. Registro como observação, não
como conclusão sobre o widget.

---

### 2.11 Leadster — confirmação do que já sabíamos, com evidência nova

O relatório `02-leadster-tecnico.md` já havia concluído que não existe API pública de
identificação. **Confirmei e aprofundei**, e o resultado é mais forte do que "pobre": é
**inexistente**, e o substituto deles é estruturalmente diferente.

#### Confirmação por busca no bundle

**[MEDIDO]** Sobre `debug-production/neurolead.js` (1.036.439 bytes, `http=200`):

| Termo buscado | Ocorrências |
|---|---|
| `setUser` | **0** |
| `identify` | **0** |
| `setCustomAttributes` | **0** |
| `setContactInfo` | **0** |
| `setVisitorData` | **0** |
| `user_hash` | **0** |
| `identifier_hash` | **0** |
| `setEmail` | **0** |
| `setName` | **0** |
| `hmac` | **0** |
| `signature` | **0** |
| `jwt` | 1 — **falso positivo**, é fragmento de fonte embutida em base64 |

Busca case-insensitive sobre o bundle inteiro. Zero.

#### O que o site consegue passar — a superfície real

**[MEDIDO]** Globais lidos pelo bundle (contagem de referências a `window.<nome>`):

| Global | Refs | Direção | Documentado? |
|---|---|---|---|
| `window.neurolead` | 10 | widget → host | a instância interna; só `open()` é documentado |
| `window.neuroleadId` | 6 | host → widget | **sim** — é o snippet de instalação |
| `window.neuroleadLanguage` | 6 | ambos | não |
| `window.neuroleadDefaultScript` | 3 | host → widget | não |
| `window.neuroleadPSId` | 1 | host → widget | não |
| `window.neuroleadLeadDemoMode` | 1 | host → widget | não |
| `window.neuroleadEventDevMode` | 1 | host → widget | não |
| `window.nldAPI_Neurologic_OnClose` | 1 | host → widget | não |
| `window.disableLeadsterGa4` | 1 | host → widget | não |

**[MEDIDO]** O único gancho de callback do host encontrado no bundle inteiro é
`nldAPI_Neurologic_OnClose`, chamado assim:

```javascript
if (window.nldAPI_Neurologic_OnClose) nldAPI_Neurologic_OnClose();
```

Um gancho. De fechamento. Sem dados.

**[FATO]** A base de conhecimento deles documenta **um único método público**:

```html
<button onclick="event.stopPropagation();window.neurolead.open();">Quero abrir o assistente</button>
```

Fonte: [help.leadster.com.br/article/46](https://help.leadster.com.br/article/46-como-inserir-o-chat-em-um-botao-popup-no-seu-site)

#### O substituto deles: regex sobre a URL

Este é o achado novo e é o que responde de verdade à pergunta do Walisson sobre a Leadster.

**[MEDIDO]** Método `getAlwaysFields()` da classe `Chat`, copiado do bundle de debug:

```javascript
getAlwaysFields() {
    const url = window.location.href || document.URL;
    let fields = {
      '9999::URL': url
    };
    for (let key of Object.keys(this.metadata.urlData)) {
      let regexp = this.metadata.urlData[key];
      let match = new RegExp(regexp, 'g').exec(url);
      fields[key] = match[1];
    }
    let names = this.getAllFieldNames(this.convoScript.script);
    names.forEach(name => {
      let split = name.split('::');
      if (split[0] === 'always' && split.length > 1) {
        let clearedName = split.slice(2, split.length).join('::');
        fields[clearedName] = split[1];
      }
    });
    return fields;
}
```

E `this.metadata.urlData = convoScript.urlData || {}` — ou seja, **o mapa `campo → regex` vem da
configuração do fluxo, baixada do servidor deles**, não do site.

**[MEDIDO]** Além disso, `getUtms()`:

```javascript
getUtms() {
    const query = this.parseQueryString(location.search.substring(1));
    return {
      utm_content:  query['utm_content']  || null,
      utm_medium:   query['utm_medium']   || null,
      utm_source:   query['utm_source']   || null,
      utm_campaign: query['utm_campaign'] || null,
      ...
    };
}
```

**[MEDIDO]** Higienização aplicada aos valores da URL:

```javascript
sanitizeValue(value) {
    if (typeof value !== 'string') return value;
    return value.replace(/[\u0000-\u001F\u007F-\u009F<>\\'"]/g, '').trim();
}
```

**Conclusão sobre a Leadster** — as três únicas formas de o site passar dado para o chat deles:

1. **Regex sobre `window.location.href`**, com o par campo↔regex configurado no painel da
   Leadster (`urlData`). O site "passa parâmetro" **colocando na URL**.
2. **Campos fixos `always::<valor>::<nome>`** definidos no próprio fluxo. Constante, não
   dinâmico.
3. **UTMs da query string**, lidos automaticamente.

**[INFERÊNCIA]** Isso significa que, na Leadster, **um usuário logado no site do cliente não pode
ser identificado no chat sem expor os dados dele na barra de endereço** — que é justamente onde
eles vão parar no histórico do navegador, no `Referer` de terceiros e nos logs. Nós já fazemos
melhor hoje. Este é um ponto onde ganhamos por larga margem, e o gap não é de UI: é de arquitetura.

---

### 2.12 Tabela comparativa — o que dá para passar

Legenda: ✅ suportado com método próprio · 🟡 possível de forma indireta · ❌ não existe ·
*(itálico)* = medido em runtime além da doc.

| Capacidade | Intercom | Zendesk msg | HubSpot | Drift | Crisp | LiveChat | Freshchat | tawk.to | Tidio | Jivo | Leadster | **ChatSPX hoje** |
|---|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| ID interno do sistema do cliente | ✅ `user_id` | ✅ `external_id` | 🟡 e-mail | ✅ `userId` | 🟡 e-mail | 🟡 | ✅ `externalId` | 🟡 | ✅ `distinct_id` | ✅ `setUserToken` | ❌ | ✅ `identifier` |
| Nome | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ |
| E-mail | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ |
| Telefone | ✅ | ❌ | 🟡 | 🟡 | ✅ | ❌ | ✅ | 🟡 E.164 | ✅ | ✅ | ❌ | ✅ |
| Avatar | ✅ | ❌ | ❌ | 🟡 | ✅ | ❌ | 🟡 | ❌ | ❌ | ❌ | ❌ | ✅ `avatar_url` |
| **Data de cadastro** | ✅ `created_at` | ❌ | ❌ | 🟡 | ❌ | ❌ | 🟡 | 🟡 | ❌ | ❌ | ❌ | ❌ |
| **Empresa / conta** | ✅ `company` | ❌ | 🟡 CRM | 🟡 | ✅ `user:company` | ❌ | 🟡 | 🟡 | 🟡 | ❌ | ❌ | 🟡 `company_name` (string) |
| **Várias empresas** | ✅ `companies` | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Atributos livres no contato | ✅ | ✅ `updateUser` | 🟡 CRM | ✅ | ✅ `session:data` | ✅ `session_variables` | ✅ `setProperties` | ✅ 50 máx. | ✅ | ✅ `setCustomData` | ❌ | ✅ |
| Atributos livres na conversa | 🟡 | ✅ `conversationFields` | ❌ | ❌ | 🟡 | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ *(mas ver §0.3)* |
| Merge vs substituição, explícito | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ **2 verbos** | ❌ | ❌ | ❌ | ❌ | ❌ | 🟡 acidental |
| Tags / segmentos | 🟡 | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ 10 máx. | ✅ | ❌ | ❌ | ✅ `setLabel` |
| **Eventos tipados** | ✅ `trackEvent` | ❌ | ✅ | ✅ `track` | ✅ `session:event` | ❌ | ❌ | ✅ `addEvent` | ✅ `track` | ❌ | ❌ | ❌ *(só interno)* |
| **Ler o estado de volta** | ✅ `getVisitorId` | ✅ `messenger:get` | ✅ `status()` | ❌ | ✅ `get` | ✅ `customer_data` | ❌ | ✅ `getStatus` | ❌ | ❌ | ❌ | ❌ |
| Injetar mensagem na conversa | ✅ `showNewMessage` | ✅ `sendMessage` | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| Encerrar sessão / logout | ✅ `shutdown` | ✅ `logoutUser` | ✅ `clear` | ❌ | ✅ `session:reset` | ✅ `invalidate` | ✅ `user.clear` | ✅ `logout` | ❌ | ❌ | ❌ | ✅ `reset` |
| **Verificação criptográfica** | ✅ JWT (HS256) | ✅ JWT | ✅ token 12 h | ✅ JWT | ✅ HMAC | ✅ token | ✅ **JWT RS256** | ✅ HMAC | ❌ | ❌ | ❌ | ✅ HMAC |
| **Enforcement obrigatório** | ✅ 3 modos | ✅ | 🟡 | ✅ 3 modos | ❌ | 🟡 | 🟡 | 🟡 | — | — | — | 🟡 **com furo** §3.5 |

**Leitura honesta desta tabela:** nós estamos **no meio do pelotão, não atrás**. Perdemos em
cinco colunas específicas — data de cadastro, objeto de empresa, eventos tipados, leitura de
volta, injeção de mensagem — e temos um problema de **qualidade** no enforcement, não de
ausência.

---

## 3. PARTE B — Verificação de identidade

Esta é a parte que não admite aproximação. Trato com rigor.

### 3.1 HMAC vs JWT — o que muda de fato

| Dimensão | HMAC (`user_hash` / `identifier_hash`) | JWT (HS256) |
|---|---|---|
| O que é assinado | **só o identificador** | **um objeto inteiro** (id, e-mail, atributos, validade) |
| Expiração | **não existe** — o hash vale para sempre | `exp` no payload, honrado pelo servidor |
| Atributos autenticados | ❌ nenhum: nome/e-mail viajam **fora** da assinatura | ✅ o que estiver no payload vai assinado |
| Revogação | só trocando o segredo (invalida **todos** os usuários) | expira sozinho |
| Tamanho | 64 hex | algumas centenas de bytes |
| Onde é calculado | servidor do cliente | servidor do cliente |

**[FATO]** O Intercom foi explícito nessa migração: *"we recommend stopping the generation of
HMAC-SHA256 signatures (aka user_hashes)"*, e *"we don't support sending both the user_hash and
the intercom_user_jwt"*. O `user_hash` continua aceito, mas em modo legado.
Fonte: [intercom.com/help/.../10807823](https://www.intercom.com/help/en/articles/10807823-migrating-from-identity-verification-to-messenger-security-with-jwts)

**A consequência prática do "só o identificador" é o ponto que mais importa para nós.** No modelo
HMAC — o nosso — o `identifier_hash` prova que **este identificador foi emitido pelo servidor do
cliente**. Ele **não prova nada** sobre o `name`, `email`, `phone_number` e `custom_attributes`
que viajam ao lado dele no mesmo payload. Esses campos são *dados não autenticados anexados a uma
credencial autenticada*. Um JWT elimina essa categoria inteira de problema porque os atributos
ficam **dentro** do que foi assinado.

### 3.2 Onde o segredo mora — e o que acontece se vazar

**[FATO]** Todos os fornecedores que oferecem verificação dizem a mesma coisa, com palavras
diferentes:

- Crisp: *"never use your verification secret key to generate signatures in your front-end
  directly"*
- Drift: chave *"securely stored on your application's backend and kept secret"*
- Intercom: **Messenger API Secret**, em Settings → Workspace → Security → Messenger
- Zendesk: *"A signing key is created by a Zendesk admin in Admin Center and shared with a
  developer"*

**[CÓDIGO]** No nosso caso, o segredo é `channel_web_widgets.hmac_token`
(`app/models/channel/web_widget.rb`, coluna no schema em `db/schema.rb:759`, índice único em
`:765`), gerado por `has_secure_token :hmac_token`. Atenção ao ler o schema: existe um
`hmac_token`/`hmac_mandatory` **homônimo** na tabela `channel_api` (`db/schema.rb:609-610`) —
é outro canal, não o widget.

**Se o segredo vazar** — em HMAC simétrico, quem tem o segredo pode assinar qualquer
identificador. **[INFERÊNCIA]** Com o nosso desenho, a única remediação é **rotacionar o
`hmac_token`**, o que invalida a assinatura de **todos** os usuários daquele widget de uma vez —
não há revogação granular nem expiração automática. Com JWT curto, o dano de um vazamento é
limitado pela janela de validade dos tokens já emitidos. Com RS256 (o caminho do Freshchat), o
vazamento do lado **do fornecedor** não permite forjar nada.

### 3.3 O ataque que a verificação previne — cenário concreto

Descrevo o cenário canônico e depois **onde ele para no nosso código**. Não generalizo de um para
o outro.

**O cenário genérico (vale para qualquer chat sem verificação):**

1. A vítima é cliente do site `loja.com.br` e conversou com o suporte pelo chat. Nessa conversa
   ela mandou o número do pedido, o endereço e um print da fatura.
2. O atacante abre `loja.com.br` em aba anônima. O widget carrega e cria uma sessão nova, de
   visitante anônimo.
3. O atacante abre o console e chama o método de identificação do widget passando **o e-mail da
   vítima** — `setUser`, `$crisp.push(["set","user:email",...])`, `tidioIdentify`, o que o
   fornecedor oferecer.
4. Se o servidor **aceitar o e-mail sem prova**, ele vincula a sessão do atacante ao registro de
   contato da vítima.
5. Dependendo de como o fornecedor delimita o histórico, o atacante **lê a conversa anterior** —
   pedido, endereço, fatura.

O passo que a verificação quebra é o 4: com HMAC/JWT obrigatório, o servidor exige uma prova que
só o backend de `loja.com.br` sabe produzir, e o atacante não tem como fabricá-la no navegador.

**Onde isso para no ChatSPX — sendo preciso:**

**[CÓDIGO]** O passo 5 **não acontece** hoje pelo caminho óbvio, e a razão está em
`app/controllers/api/v1/widget/base_controller.rb:10-17`:

```ruby
def conversations
  if @contact_inbox.hmac_verified?
    verified_contact_inbox_ids = @contact.contact_inboxes.where(inbox_id: auth_token_params[:inbox_id], hmac_verified: true).map(&:id)
    @conversations = @contact.conversations.where(contact_inbox_id: verified_contact_inbox_ids)
  else
    @conversations = @contact_inbox.conversations.where(inbox_id: auth_token_params[:inbox_id])
  end
end
```

O escopo de leitura é **do `contact_inbox`** (a sessão), não do contato — **a menos que**
`hmac_verified` esteja marcado. A sessão do atacante é um `contact_inbox` novo, sem conversas.
Então **o histórico da vítima não é servido**.

**Isto é uma proteção real e vale registrar como ponto forte do desenho.** Mas ela tem um preço e
um limite:

- **O preço:** é exatamente por isso que, **sem** HMAC, o mesmo cliente que troca de navegador
  **não vê a própria conversa anterior**. A continuidade de histórico entre dispositivos é o
  prêmio que a verificação libera. Isso não é detalhe: é o motivo comercial de existir o HMAC,
  não só o motivo de segurança.
- **O limite:** o passo 4 **acontece**. O `ContactIdentifyAction` faz merge por e-mail
  (`app/actions/contact_identify_action.rb:17`, que chama `:36-38`), então a sessão do atacante passa a apontar
  para o **registro de contato da vítima**. **[INFERÊNCIA]** As consequências disso — poluir o
  cadastro da vítima com dados forjados, herdar os `custom_attributes` dela, e fazer a próxima
  mensagem do atacante chegar ao atendente **com o nome e o histórico de cadastro da vítima na
  ficha lateral** — são reais e não dependem de ler a conversa antiga.

**Registro explícito da distinção:** *ler a conversa alheia* está bloqueado pelo escopo do
`contact_inbox`; *assumir o registro de contato alheio* **não está**, quando o enforcement não
pega — e §3.5 mostra dois caminhos em que ele não pega.

### 3.4 Modos de enforcement — quem oferece o quê

| Fornecedor | Modos | Fonte |
|---|---|---|
| **Drift** | **`DISABLED` / `ENABLED` / `REQUIRED`** — em `ENABLED` faz *"fall back to the unsigned identity"* se o JWT for inválido; em `REQUIRED` identidades não assinadas são ignoradas | [devdocs.drift.com](https://devdocs.drift.com/docs/securing-drift-on-your-site-using-signed-identities) |
| **Intercom** | **Desativado / Opcional / Obrigatório**, configurável **por plataforma** (Web, iOS, Android) em Settings → Channels → Messenger → Install | [intercom.com/help/.../10589769](https://www.intercom.com/help/en/articles/10589769-authenticating-users-in-the-messenger-with-json-web-tokens-jwts) |
| **Zendesk** | ativado/desativado por marca, com chave de assinatura emitida no Admin Center | [support.zendesk.com/.../4411666638746](https://support.zendesk.com/hc/en-us/articles/4411666638746-Authenticating-end-users-in-messaging-for-the-Web-Widget-and-mobile-SDK) |
| **Crisp** | **[NÃO VERIFICADO]** — a doc não menciona enforcement; assinatura inválida apenas marca a conversa como *"Unverified"* | [docs.crisp.chat](https://docs.crisp.chat/guides/chatbox-sdks/web-sdk/identity-verification/) |
| **Tidio / JivoChat / Leadster** | não existe verificação, logo não existe enforcement | — |
| **ChatSPX** | booleano `hmac_mandatory` **por inbox** — sem modo global, sem modo "avisa mas não bloqueia" | `db/schema.rb:762`, `app/models/channel/web_widget.rb:35` |

**O modelo de três estados do Drift é o melhor desenho da lista**, e a razão é operacional: o
estado `ENABLED` permite **ligar a verificação e observar** antes de bloquear. Com um booleano,
a migração de um cliente que já tem tráfego é um salto no escuro — ou passa a rejeitar tudo que
não estiver assinado, ou não protege nada.

**O que acontece com visitante anônimo quando o enforcement está ligado?**

**[CÓDIGO]** No nosso caso, **nada muda para o visitante anônimo que nunca chama `setUser`**. O
`hmac_mandatory` só é consultado dentro de `should_verify_hmac?`
(`app/controllers/api/v1/widget/contacts_controller.rb:55-62`), que roda no `before_action` da
ação `set_user`. Quem nunca chama `setUser` nunca passa por lá: abre o widget, preenche o
pre-chat, conversa. Isso está **correto** — o modo obrigatório protege a *identificação*, não
proíbe o *anonimato*.

**[FATO]** No Intercom o comportamento é o mesmo em espírito: com JWT expirado e sem token novo,
*"the user's session will end. The user will see a fresh Messenger as a logged-out website
visitor."* Degrada para anônimo, não para erro.

### 3.5 As duas portas abertas no nosso enforcement

Este é o achado de segurança desta task. **Tudo aqui é [CÓDIGO]** — leitura, com linha. As
consequências são **[INFERÊNCIA]** e **não foram exploradas**.

**[CÓDIGO]** `app/controllers/api/v1/widget/contacts_controller.rb`:

```ruby
class Api::V1::Widget::ContactsController < Api::V1::Widget::BaseController
  before_action :validate_hmac, only: [:set_user]        # ← linha 4

  def update                                              # ← linha 8
    identify_contact(@contact)
  end
  ...
  def should_verify_hmac?                                 # ← linha 55
    return false if params[:identifier_hash].blank? && !@web_widget.hmac_mandatory
    # Taking an extra caution that the hmac is triggered whenever identifier is present
    return false if params[:custom_attributes].present? && params[:identifier].blank?   # ← linha 59
    true
  end

  def permitted_params                                    # ← linha 72
    params.permit(:website_token, :identifier, :identifier_hash, :email, :name, :avatar_url,
                  :phone_number, custom_attributes: {}, additional_attributes: {})
  end
end
```

#### Porta 1 — a ação `update` não passa por verificação nenhuma

**[CÓDIGO]** `before_action :validate_hmac, only: [:set_user]` (linha 4). A rota
`PATCH /api/v1/widget/contact` → `#update` (`config/routes.rb:608`) chama `identify_contact` com
`permitted_params`, que inclui **`email`, `name` e `phone_number`**. Não há verificação.

**[CÓDIGO]** `identify_contact` instancia `ContactIdentifyAction`, cujo `perform` executa
`merge_if_existing_email_contact` (`app/actions/contact_identify_action.rb:36-38`) — merge por
e-mail.

**[INFERÊNCIA]** Com `hmac_mandatory: true` ligado, uma chamada a `PATCH /api/v1/widget/contact`
com `{ email: "<vítima>" }` não é bloqueada. O caminho existe no código; **não o executei**.

**[CÓDIGO]** A superfície do widget que usa essa rota é
`app/javascript/widget/api/contacts.js:9-11` (`update`) e `:18-22` (`setCustomAttributes`) —
esta última também usa `PATCH /widget/contact`, ou seja, o `$chatwoot.setCustomAttributes()`
**não passa por HMAC nunca**, por construção.

#### Porta 2 — o *early return* da linha 59

**[CÓDIGO]** `return false if params[:custom_attributes].present? && params[:identifier].blank?`

Lido literalmente: se a requisição a `set_user` trouxer `custom_attributes` **e não trouxer**
`identifier`, a verificação é **desligada** — inclusive quando `hmac_mandatory` é `true`, porque
este `return` vem **depois** da checagem de `hmac_mandatory` (linha 56) e **antes** do `true`
final.

**[INFERÊNCIA]** Como `permitted_params` aceita `:email` na mesma ação, um payload
`{ email: "<vítima>", custom_attributes: { qualquer: 1 } }` sem `identifier` atravessa o
`validate_hmac` mesmo com o modo obrigatório ligado. O comentário no código
(*"Taking an extra caution that the hmac is triggered whenever identifier is present"*) mostra a
intenção — dispensar HMAC quando não há identidade a provar — mas o filtro olha só para
`identifier` e ignora que `email` é, ele também, um identificador que dispara merge.

**Não classifico isso como vulnerabilidade confirmada.** Classifico como **desenho que não
sustenta a promessa do toggle**: quem liga `hmac_mandatory` acredita ter fechado a porta da
identificação não verificada, e o código deixa duas frestas. A verificação empírica exige
ambiente isolado e está fora do escopo desta task de estudo.

**[CÓDIGO]** O mesmo padrão de `should_verify_hmac?` aparece na API pública em
`app/controllers/public/api/v1/inboxes/contacts_controller.rb:45-53`, com a diferença de que lá
`permitted_params` **não inclui** `additional_attributes` e o `identifier_hash` é excluído dos
atributos gravados (linha 14).

### 3.6 Rotação, expiração e o token em página cacheada/CDN

**O problema:** um token de identidade renderizado no HTML de uma página que a CDN cacheia vira
**um token público** — servido a todo mundo que pedir aquela URL. É a falha clássica desse
handshake.

**[FATO] Como cada um lida:**

| Fornecedor | Validade | Estratégia contra cache |
|---|---|---|
| **Zendesk** | `exp` honrado, requisição com `exp` no passado é **rejeitada** | **Callback**: o widget pede um token novo ao site *"cada vez que encontrar um erro 401"*. O token nunca precisa estar no HTML. |
| **LiveChat** | `expiresIn` em ms + `creationDate` | `getToken` / `getFreshToken` / `invalidate` — ciclo de vida explícito no cliente |
| **Intercom** | recomenda **mínimo de 5 minutos**; *"If the web page is often reloaded, the JWT should be short-lived"*; cookie de sessão curto de **1 hora** para não degradar a experiência durante atividade | JWT curto + `boot` a cada carga |
| **HubSpot** | **12 horas**, cacheável | *"must be set... every time the page loads"* — assume geração no servidor a cada render |
| **Drift** | `exp` opcional | — |
| **Crisp / tawk.to** | **sem expiração** (HMAC puro) | — |
| **ChatSPX** | **[CÓDIGO] sem expiração** — `identifier_hash` é `HMAC(hmac_token, identifier)` e nada mais (`contacts_controller.rb:64-70`) | nenhuma |

**[INFERÊNCIA]** O desenho do Zendesk é o único que resolve o problema da CDN **na raiz**, porque
inverte a direção: o widget **pede** o token quando precisa, em vez de o HTML **carregar** o
token. Um HTML cacheado com um callback dentro não vaza nada — o callback bate no endpoint
autenticado do site do cliente, que responde de acordo com a sessão de quem está pedindo.

**[INFERÊNCIA] Para nós, o risco de cache é diferente e menor em um aspecto, maior em outro.**
Menor porque o nosso `identifier_hash` só é útil junto com o `identifier` correspondente — um
hash vazado sozinho não abre a conta de outra pessoa, abre a **daquele** identificador. Maior
porque, **sem expiração**, um par `(identifier, identifier_hash)` que vaze uma vez — em HTML
cacheado, em log de servidor, em print de tela, no `Referer` — vale **para sempre**, até que o
`hmac_token` do widget inteiro seja rotacionado.

---

## 4. PARTE C — O nosso estado, com arquivo:linha

**Leitura apenas.** Nenhum arquivo do repositório foi modificado nesta task.

### 4.1 Inventário do `window.$chatwoot`

**[MEDIDO]** Enumeração em runtime contra o SDK servido por
`https://hmlchat.simplexsolucoes.com.br/packs/js/sdk.js` (`http=200`, **28.834 bytes**), via
`probe_chatspx.py`. **13 métodos, 23 propriedades.** Sem erro nem aviso no console.

#### Os 13 métodos

Fonte de verdade: `app/javascript/entrypoints/sdk.js`. As colunas *Valida?* e *Erro ao site?*
são o que mais importa para o redesenho.

| # | Método | Assinatura | Linha | Valida? | Mensagem `postMessage` | Erro chega ao site? |
|:--:|---|---|:--:|---|---|---|
| 1 | `toggle` | `toggle(state?: 'open'\|'close')` | `sdk.js:83-85` | não | — (local) | — |
| 2 | `toggleBubbleVisibility` | `toggleBubbleVisibility('hide'\|'show')` | `:87-102` | não | `SDK_SET_BUBBLE_VISIBILITY` | — |
| 3 | `popoutChatWindow` | `popoutChatWindow()` | `:104-110` | não | — (abre janela) | — |
| 4 | **`setUser`** | `setUser(identifier: string\|number, user: object)` | `:112-137` | **sim, 2 checagens** | `set-user` | **sim** — `chatwoot:error` |
| 5 | `setCustomAttributes` | `setCustomAttributes(attrs: object)` | `:139-145` | 1 checagem | `set-custom-attributes` | **não** |
| 6 | `deleteCustomAttribute` | `deleteCustomAttribute(key: string)` | `:147-155` | 1 checagem | `delete-custom-attribute` | **não** |
| 7 | `setConversationCustomAttributes` | `setConversationCustomAttributes(attrs: object)` | `:157-165` | 1 checagem | `set-conversation-custom-attributes` | **não** |
| 8 | `deleteConversationCustomAttribute` | `deleteConversationCustomAttribute(key: string)` | `:167-175` | 1 checagem | `delete-conversation-custom-attribute` | **não** |
| 9 | `setLabel` | `setLabel(label = '')` | `:177-179` | **nenhuma** | `set-label` | **não** |
| 10 | `removeLabel` | `removeLabel(label = '')` | `:181-183` | **nenhuma** | `remove-label` | **não** |
| 11 | `setLocale` | `setLocale(locale = 'en')` | `:185-187` | **nenhuma** | `set-locale` | — |
| 12 | `setColorScheme` | `setColorScheme(darkMode = 'light')` | `:189-193` | normaliza | `set-color-scheme` | — |
| 13 | `reset` | `reset()` | `:195-210` | — | — (recria o iframe) | — |

**Validação real do `setUser`** — **[CÓDIGO]** `sdk.js:113-121`:

```javascript
if (typeof identifier !== 'string' && typeof identifier !== 'number') {
  throw new Error('Identifier should be a string or a number');
}
if (!hasUserKeys(user)) {
  throw new Error('User object should have one of the keys [avatar_url, email, name]');
}
```

**[CÓDIGO]** `hasUserKeys` (`app/javascript/sdk/cookieHelpers.js:23-24`) exige **pelo menos uma**
de `avatar_url`, `email`, `name`. Note: **`phone_number` sozinho não passa** — quem só tem
telefone do visitante não consegue chamar `setUser`.

**Deduplicação por hash** — **[CÓDIGO]** `sdk.js:123-127` + `cookieHelpers.js:13-21`:

```javascript
const hashToBeStored = computeHashForUserData({ identifier, user });
if (hashToBeStored === existingCookieValue) { return; }
```

O hash é **MD5** sobre a concatenação de `avatar_url`, `email`, `name`, `identifier_hash` e
`identifier`, guardado no cookie `cw_user_<websiteToken>`. **[CÓDIGO — importante]**
`ALLOWED_USER_ATTRIBUTES` inclui só esses cinco campos (`cookieHelpers.js:4-5`), então
**`phone_number`, `company_name`, `city`, `country_code`, `description` e `custom_attributes`
NÃO entram no hash**. **[INFERÊNCIA]** Consequência: se o site mudar só o telefone ou só um
`custom_attribute` do usuário e chamar `setUser` de novo com os mesmos nome/e-mail/identifier, a
chamada é **descartada silenciosamente** pelo *early return* e o dado novo nunca chega ao
servidor.

#### As 23 propriedades

**[MEDIDO]** Valores observados no probe (settings do teste entre parênteses onde aplicável):

`baseUrl`, `baseDomain`, `hasLoaded`, `hideMessageBubble`, `isOpen`, `position` *(right)*,
`websiteToken`, `locale`, `useBrowserLanguage`, `type` *(standard)*, `launcherTitle`,
`showPopoutButton`, `showUnreadMessagesDialog` *(true)*, `widgetStyle` *(standard)*,
`resetTriggered`, `darkMode` *(light)*, `welcomeTitle`, `welcomeDescription`, `availableMessage`,
`unavailableMessage`, `enableFileUpload`, `enableEmojiPicker` *(true)*, `enableEndConversation`
*(true)*.

**[CÓDIGO]** Todas vêm de `window.chatwootSettings` em `sdk.js:50-81`. Ou seja: o objeto de
settings do host é **só de aparência e comportamento** — não há um único campo de **dado do
visitante** ali. Diferente do Intercom, onde `boot` mistura identidade e aparência no mesmo
objeto; diferente do Tidio, onde `document.tidioIdentify` existe antes da carga.

**[CÓDIGO]** O `setUser` chamado antes do widget carregar **é reaplicado** depois: em
`app/javascript/sdk/IFrameHelper.js:185-187`, no evento `loaded`:

```javascript
if (window.$chatwoot.user) {
  IFrameHelper.sendMessage('set-user', window.$chatwoot.user);
}
```

**[CÓDIGO — assimetria no reenvio]** As duas chamadas de `set-user` não têm o mesmo formato.

- **Chamada direta** — `sdk.js:132`: `IFrameHelper.sendMessage('set-user', { identifier, user })`.
- **Reenvio pós-`loaded`** — `IFrameHelper.js:186`: `IFrameHelper.sendMessage('set-user', window.$chatwoot.user)`.

E `sendMessage(key, value)` serializa `{ event: key, ...value }` (`IFrameHelper.js:94-103`) —
**espalha** o segundo argumento no topo do objeto. Logo:

| Caminho | Payload que chega ao widget |
|---|---|
| direta | `{ event:'set-user', identifier: '...', user: {...} }` |
| reenvio | `{ event:'set-user', email:'...', name:'...', ... }` — **sem `identifier` e sem `user`** |

**[CÓDIGO]** Do outro lado, `App.vue:293` faz `dispatch('contacts/setUser', message)` e o store
desestrutura `{ identifier, user: userObject }`
(`app/javascript/widget/store/modules/contacts.js:45`), e em seguida desestrutura `userObject`
(`:47-59`). **[INFERÊNCIA]** No caminho de reenvio, `userObject` chega `undefined` e a segunda
desestruturação lança `TypeError` — capturado pelo `catch` da própria action (`:85-88`), que
despacha `chatwoot:error` com `SET_USER_ERROR`. Ou seja: falha, mas falha *ruidosa*.

Este caminho só é exercido quando `setUser` é chamado **antes** do evento `loaded` — que é
justamente a rede de segurança para o site que identifica cedo. **Não executei**; a conclusão vem
da leitura das linhas citadas. Merece teste dirigido antes do redesenho.

#### Os 7 eventos de `window`

**[CÓDIGO]** `app/javascript/widget/constants/sdkEvents.js:1-7`:

```javascript
export const CHATWOOT_ERROR              = 'chatwoot:error';
export const CHATWOOT_ON_MESSAGE         = 'chatwoot:on-message';
export const CHATWOOT_ON_START_CONVERSATION = 'chatwoot:on-start-conversation';
export const CHATWOOT_POSTBACK           = 'chatwoot:postback';
export const CHATWOOT_READY              = 'chatwoot:ready';
export const CHATWOOT_OPENED             = 'chatwoot:opened';
export const CHATWOOT_CLOSED             = 'chatwoot:closed';
```

Despachados via `dispatchWindowEvent` (`app/javascript/shared/helpers/CustomEventHelper.js:12-15`),
com o dado em `event.detail`. Origem de cada um: `CHATWOOT_READY` e `CHATWOOT_ERROR` em
`IFrameHelper.js:196` e `:200`; `CHATWOOT_POSTBACK` em `:222`; `CHATWOOT_OPENED`/`CHATWOOT_CLOSED`
em `app/javascript/sdk/bubbleHelpers.js:78` e `:80`; `CHATWOOT_ON_MESSAGE` em
`app/javascript/widget/helpers/actionCable.js:67` e `:83`; `CHATWOOT_ON_START_CONVERSATION` em
`app/javascript/widget/components/ChatFooter.vue:86` e
`app/javascript/widget/components/TeamAvailability.vue:21`.

**Isto é bom e é diferencial.** Nenhum evento equivalente existe na Leadster
(§2.11). **[FATO]** O relatório `02-leadster-tecnico.md` já havia registrado o mesmo:
*"não há eventos `CustomEvent` no `window`"* do lado deles.

### 4.2 O que o widget faz com cada mensagem — a cadeia de `else if`

**[CÓDIGO]** `app/javascript/widget/App.vue:258-344`. Registro a cadeia inteira porque é o
contrato real entre site e widget:

| Evento recebido | Linha | Ação disparada |
|---|:--:|---|
| `config-set` | 265 | locale, bubble label, conversas antigas, agentes, config, `contacts/get`, campanhas |
| `widget-visible` | 273 | scroll para o fim |
| `change-url` | 275 | campanhas por URL + `window.referrerURL` + `setReferrerHost` |
| `toggle-close-button` | 284 | `isMobile` |
| `push-event` | 286 | `events/create` |
| `set-label` | 288 | `conversationLabels/create` |
| `remove-label` | 290 | `conversationLabels/destroy` |
| **`set-user`** | 292 | `contacts/setUser` |
| **`set-custom-attributes`** | 294 | `contacts/setCustomAttributes` |
| `delete-custom-attribute` | 299 | `contacts/deleteCustomAttribute` |
| **`set-conversation-custom-attributes`** | 304 | `conversation/setCustomAttributes` |
| `delete-conversation-custom-attribute` | 309 | `conversation/deleteCustomAttribute` |
| `set-locale` | 314 | locale + bubble label |
| `set-color-scheme` | 317 | tema |
| `toggle-open` | 319 | roteamento home/messages, `setUserLastSeen`, reset de campanha |
| `SDK_SET_BUBBLE_VISIBILITY` | 341 | visibilidade da bolha |

**16 eventos.** Note que **não há `default`**: uma mensagem com `event` desconhecido é ignorada
em silêncio — o que é razoável, mas significa que erro de digitação no nome do evento não produz
diagnóstico nenhum.

### 4.3 O canal `postMessage` — nenhum dos dois lados valida a origem

**[CÓDIGO]** Lado do site — `app/javascript/sdk/IFrameHelper.js:104-117`:

```javascript
initPostMessageCommunication: () => {
  window.onmessage = e => {
    if (typeof e.data !== 'string' || e.data.indexOf('chatwoot-widget:') !== 0) {
      return;
    }
    const message = JSON.parse(e.data.replace('chatwoot-widget:', ''));
    if (typeof IFrameHelper.events[message.event] === 'function') {
      IFrameHelper.events[message.event](message);
    }
  };
},
```

**Não há checagem de `e.origin`.** O único filtro é o prefixo da string — que é público e está no
bundle. Além disso, o handler é atribuído com `window.onmessage = ...`, o que **sobrescreve**
qualquer handler `onmessage` que o site já tenha.

**[CÓDIGO]** Lado do widget — `app/javascript/widget/helpers/utils.js:18-21`, consumido em
`App.vue:260-264`:

```javascript
isAValidEvent: e => {
  const isDataAString = typeof e.data === 'string';
  return isDataAString && e.data.indexOf(WOOT_PREFIX) === 0;
},
```

Também **sem `e.origin`**.

**[CÓDIGO]** E na saída do widget — `app/javascript/widget/helpers/utils.js:8-13`:

```javascript
export const sendMessage = msg => {
  window.parent.postMessage(`chatwoot-widget:${JSON.stringify({ ...msg })}`, '*');
};
```

`targetOrigin` é `'*'`. **[CÓDIGO]** No sentido oposto, o SDK **faz** a coisa certa
(`IFrameHelper.js:94-103`): calcula `new URL(element.src).origin` e usa como `targetOrigin`.

**[INFERÊNCIA] O que isso permite.** Qualquer script já em execução na página do cliente — tag
manager, pixel de mídia, plugin de CMS, outro widget — tem referência a `window` e ao
`contentWindow` do iframe, e pode:

- enviar `chatwoot-widget:{"event":"set-user", ...}` para o **iframe**, identificando o visitante
  com dados que o site não autorizou; e
- enviar `chatwoot-widget:{"event":"setAuthCookie","data":{"widgetAuthToken":"..."}}` para o
  **parent**, que executa `updateAuthCookie` (`IFrameHelper.js:213-215`) e **grava o cookie
  `cw_conversation`** com o valor recebido.

O segundo é o mais sério: é o formato clássico de *session fixation*. **Não testei.** Registro
como leitura de código e caminho a verificar, não como exploração confirmada.

**Contexto de risco:** isso não é atacável de fora — exige código já rodando na página do
cliente. Mas "código de terceiro rodando na página do cliente" é a situação **normal** de
qualquer site comercial com GTM, e o modelo de ameaça de um widget de chat precisa contá-lo.

### 4.4 HMAC no nosso lado — onde é verificado e o que muda

**[CÓDIGO]** `app/controllers/api/v1/widget/contacts_controller.rb:64-70`:

```ruby
def valid_hmac?
  params[:identifier_hash] == OpenSSL::HMAC.hexdigest(
    'sha256',
    @web_widget.hmac_token,
    params[:identifier].to_s
  )
end
```

**[FATO]** Confere exatamente com a documentação pública do Chatwoot, que publica o mesmo cálculo
em Python, Node, Ruby e PHP:
[chatwoot.com/docs/product/channels/live-chat/sdk/identity-validation](https://www.chatwoot.com/docs/product/channels/live-chat/sdk/identity-validation).
O token HMAC é **único por widget**, em Inboxes → Settings → Configuration → Identity Validation.
**[FATO]** A documentação **não menciona** enforcement obrigatório nem descreve o que acontece
sem validação — a página é só o "como fazer".

**O que muda quando `hmac_verified` é `true`:**

| Comportamento | `hmac_verified: false` | `hmac_verified: true` |
|---|---|---|
| Escopo do histórico no widget | conversas **deste `contact_inbox`** | **todas as conversas do contato** nos `contact_inbox` verificados — `base_controller.rb:10-17` |
| API pública de conversas | conversas do `contact_inbox` | conversas do contato — `public/api/v1/inboxes/conversations_controller.rb:6` |
| Broadcast em tempo real | só o `pubsub_token` da sessão | **todos** os `pubsub_token` verificados do contato — `app/listeners/action_cable_listener.rb:333` |
| Ferramentas do Captain | recebem `hmac_verified` no estado | idem — `enterprise/app/services/captain/assistant/agent_runner_service.rb:19` |
| Webhook de tool do Captain | `X-Chatwoot-Contact-Inbox-Verified: false` | `: true` — `enterprise/app/models/concerns/toolable.rb:97` |
| Payload de eventos | `hmac_verified` presente | idem — `app/presenters/conversations/event_data_presenter.rb:36` |

**Este último grupo é subestimado e merece destaque no redesenho:** o `hmac_verified` **já
atravessa até a camada de IA**. O Captain sabe se o contato está verificado, e a tool externa
recebe isso num header. É a base pronta para uma política do tipo *"só executa ação sensível se
o contato for verificado"* — sem construir nada novo no transporte.

**[CÓDIGO]** Marcação da flag: `contacts_controller.rb:22` —
`@contact_inbox.update(hmac_verified: true) if should_verify_hmac?`.

### 4.5 Onde os atributos passados pelo site vão parar

Quatro destinos distintos. A confusão entre eles é a maior fonte de erro de integração.

#### Destino 1 — `contacts.custom_attributes` (jsonb)

**Caminho:** `$chatwoot.setUser(id, {custom_attributes: {...}})` **ou**
`$chatwoot.setCustomAttributes({...})` → `set-user`/`set-custom-attributes` → `contacts/setUser`
ou `contacts/setCustomAttributes` → `PATCH /api/v1/widget/contact[/set_user]` →
`ContactIdentifyAction`.

**[CÓDIGO]** Semântica de escrita — **merge profundo**
(`app/actions/contact_identify_action.rb:128-132`, método `custom_attributes`):

```ruby
(@contact.custom_attributes || {}).deep_merge(params[:custom_attributes].stringify_keys)
```

**[CÓDIGO]** Coluna `jsonb default {}` (`db/schema.rb`, tabela `contacts`). **Sem validação de
tipo, sem limite de quantidade, sem limite de tamanho.** Compare com tawk.to (50 atributos,
255 caracteres) e Intercom (250 CDAs, 255 caracteres).

**Visibilidade para o atendente:** aparece na ficha do contato **se existir um
`CustomAttributeDefinition` com `attribute_model: contact_attribute` e o mesmo
`attribute_key`**. **[CÓDIGO]** `app/models/custom_attribute_definition.rb` — a chave precisa
casar o formato `/\A[\p{L}\p{N}_.\-]+\z/`, e os tipos de exibição possíveis são
`text, number, currency, percent, link, date, list, checkbox`. Sem definição, o dado **é gravado
mas não é exibido** — fica invisível.

#### Destino 2 — `contacts.additional_attributes` (jsonb)

**[CÓDIGO]** `app/javascript/widget/store/modules/contacts.js:60-74` — o store **remonta** o
objeto do usuário e move cinco campos para `additional_attributes`:

```javascript
const user = {
  email, name, avatar_url,
  identifier_hash: identifierHash,
  phone_number,
  additional_attributes: { company_name, city, description, country_code, social_profiles },
  custom_attributes,
};
```

Ou seja: **`company_name`, `city`, `description`, `country_code` e `social_profiles` são campos
de topo no `setUser` do site, mas viram `additional_attributes` no servidor.** Não há
documentação disso no código; é preciso ler o store para descobrir.

**[CÓDIGO]** Mesma semântica de merge profundo no `ContactIdentifyAction`. **[CÓDIGO]**
`additional_attributes` também é usado pelo próprio sistema para `created_at_ip`
(`app/controllers/widgets_controller.rb:67-73`, quando o `ip_lookup` está ligado) e é ordenável
por `company_name`, `city` e `country` no dashboard (`app/models/contact.rb:95,105,115`).

**Visibilidade:** `company_name` e `city` aparecem na ficha; os demais dependem da tela.
**[NÃO VERIFICADO]** Não auditei a renderização da ficha lateral no dashboard nesta task.

#### Destino 3 — `conversations.custom_attributes` (jsonb)

**Caminho:** `$chatwoot.setConversationCustomAttributes({...})` →
`set-conversation-custom-attributes` → `POST /api/v1/widget/conversations/set_custom_attributes`.

**[CÓDIGO — assimetria crítica]**
`app/controllers/api/v1/widget/conversations_controller.rb:66-68`:

```ruby
def set_custom_attributes
  conversation.update!(custom_attributes: permitted_params[:custom_attributes])
end
```

**Isto SUBSTITUI o objeto inteiro.** O do contato faz `deep_merge`; o da conversa **sobrescreve**.
Dois métodos com nomes irmãos (`setCustomAttributes` / `setConversationCustomAttributes`) e
semânticas opostas, sem nada na assinatura que avise. O LiveChat resolveu isso com dois verbos
nomeados (`set_session_variables` vs `update_session_variables`) — §2.6.

**[CÓDIGO — o silêncio]** `before_action :render_not_found_if_empty` (linha 3) +
`render_not_found_if_empty` (linhas 93-95) fazem o endpoint devolver **404 quando ainda não
existe conversa**. E o store engole:

```javascript
// app/javascript/widget/store/modules/conversation/actions.js:183-189
setCustomAttributes: async (_, customAttributes = {}) => {
  try {
    await setCustomAttributes(customAttributes);
  } catch (error) {
    // IgnoreError
  }
},
```

**Resultado:** o site chama o método, nada acontece, nenhum erro é lançado, nenhum evento
`chatwoot:error` é disparado. **Este é o achado #3 do sumário e, na minha leitura, o problema
mais provável de estar mordendo integrações hoje** — porque a ordem natural que qualquer
desenvolvedor escreve é "carrego a página → passo os dados → o visitante conversa", e nessa
ordem a conversa ainda não existe.

#### Destino 4 — `conversations.additional_attributes` (jsonb) — **o site não escreve aqui**

**[CÓDIGO]** `app/controllers/api/v1/widget/base_controller.rb:31-46` — preenchido **só pelo
servidor**, na criação da conversa:

```ruby
additional_attributes: {
  browser_language: browser.accept_language&.first&.code,
  browser: browser_params,          # nome/versão do browser, device, plataforma
  initiated_at: timestamp_params,
  referer: permitted_params[:message][:referer_url]
}
```

Não há caminho do `$chatwoot` para cá. É onde o `referer` e o navegador vivem.

#### Resumo dos quatro destinos

| Destino | Quem escreve | Semântica | Tipado? | Visível ao atendente |
|---|---|---|---|---|
| `contacts.custom_attributes` | site (`setUser`, `setCustomAttributes`) | **merge** | via `CustomAttributeDefinition` | só se houver definição |
| `contacts.additional_attributes` | site (5 campos remapeados) + servidor (`created_at_ip`) | **merge** | não | parcialmente |
| `conversations.custom_attributes` | site (`setConversationCustomAttributes`) + pre-chat | **substitui** | via `CustomAttributeDefinition` | só se houver definição |
| `conversations.additional_attributes` | **só o servidor** | escrita única | não | sim (browser, referer) |

### 4.6 O que NÃO dá para passar hoje — específico

Cada item abaixo tem um par no mercado (§2.12), e o que falta é dito com precisão.

1. **Data de cadastro do usuário.** Intercom tem `created_at` (*"Unix timestamp (in seconds) when
   the user signed up"*). Nós não temos campo de topo; caberia em `custom_attributes`, mas aí é
   string sem semântica e não alimenta segmentação por antiguidade.

2. **Objeto de empresa estruturado.** Intercom aceita `company` com `id`, `name`, `created_at`,
   `plan`, `monthly_spend`, `user_count`, `size`, `website`, `industry` — e `companies` para
   várias. Nós aceitamos **uma string** `company_name`, que vira `additional_attributes`. Existe
   `contacts.company_id` no schema (`db/schema.rb`, tabela `contacts`), mas **[CÓDIGO]** não há
   caminho do widget até ele.

3. **Eventos tipados vindos do site.** Intercom `trackEvent`, Drift `track`, Crisp
   `session:event`, tawk.to `addEvent`, Tidio `track`. **[CÓDIGO]** O nosso `pushEvent`
   (`IFrameHelper.js:298-300`) **não está exposto no `$chatwoot`** — é interno, usado só para
   `webwidget.triggered` (`IFrameHelper.js:253`). O site **não consegue** registrar
   "adicionou_ao_carrinho" ou "cancelou_assinatura".

4. **Ler o estado de volta.** LiveChat `get("customer_data")`, Intercom `getVisitorId()`,
   HubSpot `status()`, Crisp `$crisp.get(...)`. Nosso `$chatwoot` **não tem nenhum getter** — as
   23 propriedades são a configuração que o site mesmo mandou, não o estado do chat.

5. **Injetar mensagem na conversa.** Intercom `showNewMessage('texto')`, Zendesk
   `sendMessage`, Tidio `messageFromVisitor`/`messageFromOperator`. Não temos.

6. **Confirmação de que o dado chegou.** Só `setUser` produz `chatwoot:error`
   (`IFrameHelper.js:199-205`). Os outros seis métodos de dados falham em silêncio. Nenhum
   método tem callback de sucesso — enquanto tawk.to (`setAttributes(attrs, callback)`), Zendesk
   (`updateUser(..., callback)`) e JivoChat têm.

7. **Distinção explícita entre substituir e mesclar.** §4.5, destino 3.

8. **Passar dado *antes* de o widget existir.** Tidio tem `document.tidioIdentify`, tawk.to tem
   `Tawk_API.visitor`, HubSpot tem `hsConversationsSettings` — todos definidos **antes** da
   carga. **[CÓDIGO]** Nosso `chatwootSettings` (`sdk.js:50-81`) só aceita aparência e
   comportamento; identidade exige esperar o SDK montar `window.$chatwoot`.

9. **Expiração da credencial.** §3.6.

10. **Modo de enforcement observável (o `ENABLED` do Drift).** §3.4.

---

## 5. PARTE D — Formas de passagem além da API JS

### 5.1 As cinco vias, e quem usa cada uma

#### Via 1 — atributos `data-*` na tag do script

**[FATO]** O exemplo mais completo que encontrei é o Dynamics 365 Customer Service, que expõe
**dez** data tags no próprio `<script>`:

```html
<script id="Microsoft_Omnichannel_LCWidget" src="<valid-src>"
        data-app-id="<valid-app-id>" data-org-id="<valid-org-id>" data-org-url="<valid-org-url>"
        data-hide-chat-button="true"></script>
```

Lista completa: `data-hide-chat-button`, `data-hide-minimize-button`, `data-disable-telemetry`,
`data-render-mobile`, `data-font-family-override`, `data-open-in-window`,
`data-suggested-action-layout`, `data-enable-lcw-autofill`, `data-custom-close-button-text`,
`data-enable-sso-magic-code`.
Fonte: [learn.microsoft.com/.../customize-chat-widget](https://learn.microsoft.com/en-us/dynamics365/customer-service/develop/customize-chat-widget)

**Observe o padrão:** são todos de **aparência e comportamento**, nenhum de **identidade**.
**[INFERÊNCIA]** Faz sentido: `data-*` fica no HTML servido, logo é cacheável e visível — é o
lugar errado para credencial, e o lugar certo para configuração. Quem for desenhar isso no
ChatSPX deve manter a mesma fronteira.

**[CÓDIGO]** Hoje nós temos **zero** `data-*`: a configuração inteira é
`window.chatwootSettings` + os dois argumentos de `chatwootSDK.run({baseUrl, websiteToken})`
(`sdk.js:21`, `:50`, `:219-221`).

#### Via 2 — parâmetros na URL da página

É a via **exclusiva** da Leadster (§2.11) e a **mais frágil** de todas.

**[INFERÊNCIA]** Riscos, todos consequência direta de o dado estar na barra de endereço:
vaza no histórico do navegador; vaza no cabeçalho `Referer` para todo domínio de terceiro
carregado na página; vaza em log de servidor, de CDN e de proxy; é compartilhável por copiar e
colar. Para dado pessoal (e-mail, telefone, CPF), é inadequado. Para dado de **contexto não
sensível** (`?plano=pro`, `?origem=campanha-x`), é aceitável e é o que os UTMs já fazem há vinte
anos.

**[CÓDIGO]** Nós usamos a URL internamente de dois jeitos, ambos não-identitários:
`buildUrl` anexa `window.location.search` a **toda** chamada de API do widget
(`app/javascript/widget/api/contacts.js:3`), e o `change-url` propaga `referrerURL`/`referrerHost`
para o motor de campanhas (`App.vue:275-283`).

#### Via 3 — `postMessage` do parent

**[CÓDIGO]** É o transporte que o próprio SDK usa (§4.2). Um site **pode** falar direto com o
iframe sem passar pelo `$chatwoot` — e, como §4.3 mostra, **nada o impede**. Não é uma via
recomendável enquanto a origem não for validada; é a via que precisa ser **fechada**, não
promovida.

#### Via 4 — GTM / dataLayer

**[FATO]** Não encontrei **nenhum** fornecedor que consuma `dataLayer` **nativamente**. O padrão
real do mercado, documentado em vários guias de implementação, é o inverso: **uma tag de HTML
customizado no GTM que chama a API JS do widget**, e/ou um *listener* que empurra eventos do
widget **para** o `dataLayer`. Fonte:
[analyticsmania.com/post/track-chat-with-google-tag-manager-and-google-analytics-4](https://www.analyticsmania.com/post/track-chat-with-google-tag-manager-and-google-analytics-4/)

**[INFERÊNCIA]** Isso é relevante porque muda a natureza do pedido do Walisson: "receber
parâmetros do site" via GTM **não exige** que o chat leia o `dataLayer` — exige que a API JS
seja **chamável de dentro de uma tag do GTM**, o que impõe requisitos concretos: (a) tolerar
chamada antes de o widget carregar (fila), (b) ser idempotente, porque o GTM pode disparar a
mesma tag mais de uma vez, (c) não lançar exceção não capturada, porque uma exceção dentro de
uma tag do GTM quebra as tags seguintes. **[CÓDIGO]** Hoje o nosso `setUser` **lança
`Error`** (`sdk.js:113-121`) — quem colar isso numa tag do GTM sem `try/catch` derruba o resto
do contêiner.

#### Via 5 — o site que não pode rodar JS custom (CMS travado)

O caso real: Wix, cliente em plano baixo, loja em plataforma fechada, time de marketing sem
acesso a desenvolvedor.

**[FATO]** A Leadster documenta **quatro** métodos de instalação, e o snippet do Wix que consta
no relatório `02-leadster-tecnico.md` reduz tudo a **uma linha**: `window.neuroleadId = 68742`.

**[INFERÊNCIA]** Para esse público, as vias 1 (`data-*`) e 2 (URL) são as **únicas** viáveis,
porque não exigem escrever JavaScript — só colar um snippet e montar links. A via 4 (GTM) é
intermediária: muitos CMS travados permitem GTM mesmo proibindo `<script>` arbitrário.

### 5.2 Pré-preenchimento do pre-chat

**A regra que todos seguem:** não perguntar o que o site já sabe.

**[CÓDIGO] Como fazemos hoje** — `app/javascript/widget/components/PreChat/Form.vue:83-105`:

```javascript
filteredPreChatFields() {
  const isUserEmailAvailable = this.currentUser.has_email;
  const isUserPhoneNumberAvailable = this.currentUser.has_phone_number;
  const isUserIdentifierAvailable = !!this.currentUser.identifier;
  const isUserNameAvailable = !!(isUserIdentifierAvailable || isUserEmailAvailable || isUserPhoneNumberAvailable);
  return this.preChatFields.filter(field => {
    if (isUserEmailAvailable && field.name === 'emailAddress') return false;
    if (isUserPhoneNumberAvailable && field.name === 'phoneNumber') return false;
    if (isUserNameAvailable && field.name === 'fullName') return false;
    return true;
  });
}
```

**Nós ESCONDEMOS o campo, não o pré-preenchemos.** A diferença importa para o redesenho:

- **A favor de esconder:** menos fricção, formulário mais curto, e é impossível o visitante
  "corrigir" para um e-mail que não é o dele — o que preservaria a verificação de identidade.
- **Contra:** o visitante **não vê** com que identidade está falando. Se o site errou o
  `setUser` — sessão compartilhada, cache, usuário errado — não há como perceber nem corrigir.
  E a ausência do campo pode confundir quem esperava preenchê-lo.

**[CÓDIGO]** Repare também na regra do nome (linha 88-92): `fullName` some se **qualquer** um
entre identifier, e-mail ou telefone estiver presente — mesmo que o nome em si **não** tenha sido
informado. **[INFERÊNCIA]** É possível terminar com contato sem nome e sem oportunidade de pedir
um. **[NÃO VERIFICADO]** Não confirmei em execução; é leitura da condição.

**[FATO] Como o mercado faz:** Zendesk **oculta** os campos de nome/e-mail quando o usuário está
autenticado (parte do fluxo de `loginUser`); Intercom pré-popula o **corpo da mensagem**, não o
formulário (`showNewMessage('pre-populated content')`); HubSpot dispensa o formulário quando o
`identificationToken` é válido, porque já tem contato no CRM. **[NÃO VERIFICADO]** Não encontrei
fornecedor que exiba o campo **preenchido e editável** — pode existir; não localizei.

**[CÓDIGO]** Um segundo caminho existe e é diferente: os campos do pre-chat marcados como
`contact_attribute` / `conversation_attribute` viram `custom_attributes` na criação da conversa
(`Form.vue:117-140`). Ou seja, o pre-chat **também é** um canal de entrada de atributos — e esse
não tem como ser pré-preenchido pelo site de jeito nenhum hoje.

### 5.3 SPA — quando chamar o quê

**[FATO] O que o mercado prescreve:**

| Fornecedor | Troca de rota | Login | Logout |
|---|---|---|---|
| **Intercom** | `Intercom('update')` — **teto de 20 por 30 min** | `boot` com identidade + JWT | **`shutdown`** (+ apagar cookies `intercom-` em dispositivo compartilhado) |
| **HubSpot** | `widget.refresh()` | `hsConversationsSettings` **antes** do `load()` — e *"only... before the Conversations API has loaded"* | `clear({resetWidget: true})` |
| **Zendesk** | — | `loginUser(jwtCallback)` — provoca **merge** com a sessão anônima | `logoutUser` — limpa tags e campos de conversa |
| **Crisp** | — | `$crisp.push(["set","user:email",[email, sig]])` | `$crisp.push(["do","session:reset"])` |
| **Freshchat** | — | `authenticate(signedUUID)` | `user.clear()` |
| **Leadster** | **[FATO, do relatório 02]** destrói e remonta o widget inteiro | — | — |

**A limitação do HubSpot é a mais instrutiva.** *"`hsConversationsSettings` can only be used
before the Conversations API has loaded"* significa que, num SPA onde o login acontece **depois**
do widget montar, é preciso `remove()` + `load()`. É exatamente a armadilha que um desenho
"configuração só no boot" cria.

**[CÓDIGO] O que nós fazemos hoje:**

- **Troca de rota:** detectada por `MutationObserver` sobre `document.body` comparando
  `document.location.href` (`app/javascript/sdk/DOMHelpers.js:49-75`). Dispara `change-url`, que
  serve **só ao motor de campanhas** e ao `referrerURL` (`App.vue:275-283`). **Nenhum dado de
  usuário é reenviado.** **[INFERÊNCIA]** O `MutationObserver` sobre `body` com
  `subtree: true` roda o callback a cada mutação do DOM da aplicação inteira — em SPA pesado, é
  muito trabalho para detectar uma mudança de URL que a History API notificaria de graça.
- **Login:** `setUser` a qualquer momento; o `sdk.js:123-127` deduplica por hash — mas com a
  lacuna dos campos fora do hash descrita em §4.1.
- **Logout:** `reset()` (`sdk.js:195-210`) remove `cw_conversation` e `cw_user_<token>` e
  **recria o iframe** com `iframe.src = getUrl(...)`. É o equivalente funcional do `shutdown` do
  Intercom. **[CÓDIGO]** Note que `reset()` seta `resetTriggered = true`, e `IFrameHelper.js:195-197`
  usa essa flag para **não** disparar `chatwoot:ready` no recarregamento seguinte — o que
  significa que **o site não recebe evento nenhum confirmando que o reset terminou**.
- **Turbo / Turbolinks / Astro:** tratados explicitamente (`sdk.js:26-48` +
  `DOMHelpers.js:15-28`), restaurando `cw-bubble-holder`, `cw-widget-holder` e
  `cw-widget-styles` no novo `body`. **Isto é bem-feito e é mais do que a Leadster faz** — eles
  destroem e remontam.

---

## 6. O QUE FALTA NO CHATSPX — e o que isso significa para o redesenho

Recomendação, sem código de implementação. Ordenado por camada, com prioridade sugerida.

**A leitura de uma frase, antes das tabelas.** O handshake do ChatSPX **não é pobre em
superfície** — 13 métodos, 7 eventos, HMAC e um escopo de histórico que efetivamente barra o
ataque clássico. Ele é **frágil em contrato**: os métodos não confirmam nada, falham em silêncio,
têm semânticas opostas com nomes irmãos, e o toggle de segurança promete mais do que entrega. Um
redesenho de front que só troque a aparência do widget deixa tudo isso de pé. As camadas 1, 2 e 3
abaixo **não são trabalho de UI** e podem — devem — andar em paralelo ao visual.

### Camada 1 — API JS pública (`window.$chatwoot`)

| # | Gap | Evidência | Prioridade |
|:--:|---|---|:--:|
| 1.1 | **Nenhum retorno de sucesso/erro em 6 dos 7 métodos de dados** | §4.1, tabela; `IgnoreError` em `contacts.js:90-103` e `conversation/actions.js:183-197` | **Alta** |
| 1.2 | **`setConversationCustomAttributes` se perde antes de existir conversa** | §4.5 destino 3; `conversations_controller.rb:93-95` | **Alta** |
| 1.3 | Semântica merge vs substituição não é comunicada pela assinatura | §4.5; contraste com LiveChat §2.6 | **Alta** |
| 1.4 | `setUser` deduplica por hash que ignora `phone_number` e `custom_attributes` | §4.1; `cookieHelpers.js:4-5` | **Alta** |
| 1.5 | Reenvio pós-`loaded` manda `user` sem `identifier` | §4.1; `IFrameHelper.js:186` vs `contacts.js:45` | **Alta** |
| 1.6 | Sem evento tipado do site (`track`) | §4.6 item 3; `pushEvent` existe mas não é exposto | Média |
| 1.7 | Sem getter de estado | §4.6 item 4 | Média |
| 1.8 | Sem objeto de empresa/conta estruturado | §4.6 item 2 | Média |
| 1.9 | Sem `created_at` do cadastro | §4.6 item 1 | Baixa |
| 1.10 | `setUser` lança exceção — hostil ao GTM | §5.1 via 4; `sdk.js:113-121` | Média |
| 1.11 | Identidade não pode ser declarada antes da carga | §4.6 item 8 | Média |

**Recomendação de forma.** Antes de somar métodos, **estabilizar o contrato dos que existem**:
toda chamada de dado deve (a) devolver `Promise` ou aceitar callback, (b) enfileirar quando o
widget ainda não estiver pronto, (c) disparar `chatwoot:error` com o motivo em vez de engolir,
(d) nunca lançar exceção não capturada. Isso resolve 1.1, 1.2, 1.10 e 1.11 de uma vez, e é
pré-requisito para qualquer método novo — sem isso, cada método novo herda os mesmos quatro
defeitos.

**Sobre 1.3, uma escolha a fazer:** ou dois verbos explícitos no estilo LiveChat
(`set...` substitui, `update...` mescla), ou um verbo só com semântica única e documentada. O que
não pode continuar é **dois métodos irmãos com semânticas opostas e nomes que não avisam**.

### Camada 2 — Verificação de identidade

| # | Gap | Evidência | Prioridade |
|:--:|---|---|:--:|
| 2.1 | **`hmac_mandatory` não cobre `PATCH /widget/contact`** | §3.5 porta 1; `contacts_controller.rb:4,8,72` | **Crítica** |
| 2.2 | **Early return da linha 59 desliga a verificação** | §3.5 porta 2 | **Crítica** |
| 2.3 | Atributos viajam **fora** da assinatura | §3.1 | Alta |
| 2.4 | Credencial **sem expiração** | §3.6 | Alta |
| 2.5 | Sem modo intermediário observável (`ENABLED` do Drift) | §3.4 | Média |
| 2.6 | Sem enforcement global de conta (só por inbox) | §3.4 | Baixa |

**Recomendação.** 2.1 e 2.2 são correções de coerência, não features: o toggle `hmac_mandatory`
promete uma garantia que o código não entrega, e isso é pior do que não ter o toggle. Devem ser
tratadas **antes** de qualquer trabalho de front, porque não dependem dele.

Para 2.3/2.4, o caminho que o mercado inteiro tomou é **JWT como formato adicional**, mantendo o
`identifier_hash` aceito por compatibilidade — exatamente a transição que o Intercom
documentou. Um JWT com `sub` (identifier), `exp` e os atributos dentro do payload resolve 2.3 e
2.4 simultaneamente, e a infraestrutura já existe: **[CÓDIGO]** `Widget::TokenService`
(`app/services/widget/token_service.rb`) já faz `JWT.encode/decode` no projeto, com expiração
configurável via `InstallationConfig['WIDGET_TOKEN_EXPIRY']`, default **180 dias**.

Para 2.5, o modelo de três estados do Drift (`DISABLED` / `ENABLED` / `REQUIRED`) é o que permite
migrar cliente com tráfego sem apagar a luz — vale copiar a ideia, não só o comportamento final.

### Camada 3 — Transporte (`postMessage`)

| # | Gap | Evidência | Prioridade |
|:--:|---|---|:--:|
| 3.1 | **SDK não valida `e.origin`** | §4.3; `IFrameHelper.js:104-117` | **Crítica** |
| 3.2 | **Widget não valida `e.origin`** | §4.3; `widget/helpers/utils.js:18-21` | **Crítica** |
| 3.3 | Widget responde com `targetOrigin: '*'` | §4.3; `utils.js:8-13` | Alta |
| 3.4 | `window.onmessage =` sobrescreve handler do site | §4.3 | Média |
| 3.5 | Evento desconhecido é ignorado sem diagnóstico | §4.2 | Baixa |

**Recomendação.** 3.1 e 3.2 são de baixo custo e alto retorno: o SDK já sabe a origem correta —
ele a calcula em `IFrameHelper.js:96-98` para **enviar** — e simplesmente não a usa para
**receber**. O caminho de `setAuthCookie` (§4.3) é o que mais preocupa, porque escreve cookie de
sessão a partir de mensagem não autenticada.

### Camada 4 — Modelo de dados e visibilidade

| # | Gap | Evidência | Prioridade |
|:--:|---|---|:--:|
| 4.1 | Atributo sem `CustomAttributeDefinition` é gravado mas invisível | §4.5 destino 1 | Alta |
| 4.2 | Cinco campos do `setUser` viram `additional_attributes` sem aviso | §4.5 destino 2; `contacts.js:60-74` | Média |
| 4.3 | Sem limite de quantidade/tamanho em `custom_attributes` | §4.5; contraste com tawk.to (50/255) e Intercom (250/255) | Média |
| 4.4 | `contacts.company_id` existe no schema mas é inalcançável pelo widget | §4.6 item 2 | Baixa |

**Recomendação sobre 4.1.** O comportamento "grava mas não mostra" é um sumidouro de dados que
custa horas de depuração — o site jura que mandou, o atendente jura que não vê, e os dois estão
certos. A saída mais barata não é criar definições automaticamente (isso poluiria o cadastro do
cliente), e sim **tornar o sumiço visível**: sinalizar no retorno da chamada quais chaves não têm
definição correspondente. Isso depende de 1.1 estar feito.

### Camada 5 — Vias alternativas de passagem

| # | Gap | Evidência | Prioridade |
|:--:|---|---|:--:|
| 5.1 | Zero atributos `data-*` no script de embed | §5.1 via 1 | Média |
| 5.2 | Sem caminho para CMS travado sem JS | §5.1 via 5 | Média |
| 5.3 | Pre-chat esconde em vez de pré-preencher | §5.2 | Média |
| 5.4 | Campos custom do pre-chat não são pré-preenchíveis pelo site | §5.2 | Baixa |
| 5.5 | Detecção de rota em SPA via `MutationObserver` sobre o `body` | §5.3 | Baixa |
| 5.6 | `reset()` não confirma conclusão ao site | §5.3; `IFrameHelper.js:195-197` | Baixa |

**Recomendação sobre 5.1.** Seguir a fronteira do Dynamics: `data-*` só para **configuração**,
nunca para **identidade**. `data-position`, `data-locale`, `data-hide-bubble` sim; `data-email`
não — porque `data-*` vive no HTML, e HTML é cacheado.

### O que já está bom e não deve ser quebrado no redesenho

Registro explícito, porque num redesenho de front é fácil derrubar coisa que funciona:

1. **[CÓDIGO]** O escopo de histórico por `contact_inbox` quando não há HMAC
   (`base_controller.rb:10-17`) — é a proteção que faz o cenário de §3.3 parar no passo 5.
2. **[CÓDIGO]** O `hmac_verified` propagado até o Captain e até o header de webhook das tools
   (`toolable.rb:97`) — infraestrutura pronta para política de ação por confiança.
3. **[CÓDIGO]** Os 7 eventos de `window` — a Leadster tem zero.
4. **[CÓDIGO]** O suporte a Turbo/Turbolinks/Astro com restauração de nós (`sdk.js:26-48`).
5. **[MEDIDO]** O loader de **28.834 bytes** contra os **456.101** da Leadster (medido no
   relatório 02) — **16× menor**, porque o peso vive dentro do iframe.
6. **[CÓDIGO]** O `targetOrigin` correto na direção site → widget (`IFrameHelper.js:96-98`).

---

## 7. Lacunas desta apuração

Registro o que **não** foi verificado, para que ninguém tome ausência de dado por ausência de
problema:

1. **Não testei o handshake contra servidor de fornecedor nenhum.** Tudo em §2 que descreve
   comportamento de servidor é **[FATO]** documental.
2. **Não explorei as portas de §3.5.** São leitura de código. Confirmação exige ambiente
   isolado, e a task é de estudo.
3. **Não confirmei enforcement no Crisp, LiveChat, Freshchat e tawk.to.** Marquei
   **[NÃO VERIFICADO]** onde a documentação silencia.
4. **Não inspecionei o widget da Leadster em execução** — o site deles não o carrega (§1.3). A
   análise é estática sobre o bundle público.
5. **Não auditei a renderização da ficha lateral do atendente** — a afirmação sobre visibilidade
   de `additional_attributes` está marcada **[NÃO VERIFICADO]**.
6. **Não medi nada de mobile.** Tudo aqui é desktop. O `toggleCloseButton`
   (`IFrameHelper.js:341-347`) usa `matchMedia('(max-width: 668px)')`, mas **não testei**
   nenhum comportamento de handshake em viewport móvel — e não afirmo nada sobre ele.
7. **Não verifiquei os limites de tamanho/quantidade** de JivoChat, Tidio, Crisp, LiveChat e
   Freshchat: a documentação deles não publica.
8. **Não testei o caminho de `setUser` chamado antes do `loaded`** (§4.1, bug de simetria 1.5).
   A conclusão vem da leitura de duas linhas; merece teste dirigido.

---

## Anexo — scripts de reprodução

Ficaram no scratchpad da sessão
(`/tmp/claude-1001/-home-chatwoot-chatwoot/2f313253-.../scratchpad/`), fora do repositório:

| Arquivo | O que faz |
|---|---|
| `probe_api.py` | enumera globais de 10 sites de fornecedores, 1 passada |
| `probe_api2.py` | idem, com `load` + scroll + 12 s, para widgets *lazy* |
| `probe_chatspx.py` | enumera `window.$chatwoot` contra o SDK da homologação |
| `nld.js` | bundle de debug público da Leadster (1.036.439 bytes) |

Todos usam `args=['--no-sandbox','--disable-dev-shm-usage']`. Nenhum faz login, envia dado ou
interage com formulário de terceiro.

---

*Fim do relatório 17.*
