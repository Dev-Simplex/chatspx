# 20 — Especificação de integração site ↔ chat

> **Onda:** Estudo do chat de site — trilha Integração (síntese)
> **Data:** 12/08/2026
> **Repositório:** `/home/chatwoot/chatwoot`, branch `homologacao`, HEAD `ee87f5e799`
> **Escopo:** a resposta de ponta a ponta para a frase do Walisson — *"o site precisa conseguir
> se vincular ao chat e passar parâmetros"*.
> **Estado:** FASE DE ESTUDO. Nenhum arquivo de código do repositório foi alterado por esta task.
> Nenhum comando de escrita foi executado contra banco, fila, serviço ou ambiente.

---

## 0. Como ler este documento

### 0.1 Estado das entradas

As três entradas obrigatórias existem e foram lidas **na íntegra**, não por amostragem:

| Relatório | Linhas | Lido | Papel nesta síntese |
|---|---:|:---:|---|
| `integracao/17-handshake-parametros.md` | 1.933 | integral | o handshake do lado do navegador: API JS, HMAC, `postMessage`, destinos de atributo |
| `integracao/18-webhooks-apis.md` | 1.456 | integral | o handshake do lado do servidor: webhooks de saída, API de entrada, canal API, bots |
| `integracao/19-contexto-na-pratica.md` | 1.060 | integral | o **quê** e o **para quê**: catálogo por vertical, painel do agente, IA, PII |

Pano de fundo, lido em profundidade nas seções relevantes (não integralmente — declaro isto de
propósito, porque a diferença importa):

| Relatório | Seções lidas | Para quê |
|---|---|---|
| `07-tracking-pixel-ga4.md` | §6.1, §6.2, §6.3, §7.1–§7.6 | origem/UTM/pixel, contrato de eventos, decisões de projeto |
| `09-nosso-widget-auditoria.md` | §4 (API pública), §11 (tracking hoje), §15 (pontos de extensão) | superfície pública atual e onde encaixar código com menos atrito de merge |
| `frontend/14-logica-concorrentes.md` | §5 (segmentação), §11 (API pública), §15.4–§15.6 (decisões) | bootstrap, segmentação, fila pré-boot, o que não copiar |
| `10-gap-analysis.md` | §2 blocos G/H, §4 inteira (C0–C9), §7 (perguntas) | a frente de tracking e as decisões já colocadas ao Walisson |

**Nenhuma entrada obrigatória faltou.** As três estavam completas e datadas de 12/08/2026.

### 0.2 Marcação de procedência

| Marca | Significado |
|---|---|
| **[CÓDIGO]** | Lido por mim **nesta task**, no repositório, com `arquivo:linha`. Verificação de primeira mão. |
| **[R17]** / **[R18]** / **[R19]** | Vem de um relatório de entrada, com a seção. Herda a marcação de lá. |
| **[R07]** / **[R09]** / **[R10]** / **[R14]** | Vem de um relatório de pano de fundo, com a seção. |
| **[FATO]** | Documentação oficial de fornecedor, com URL — repassado dos relatórios de origem. |
| **[INFERÊNCIA]** | Conclusão minha, com a base explícita ao lado. |
| **[NÃO VERIFICADO]** | Buraco declarado. Não é ausência de problema. |

**Aviso de rigor aplicado neste documento.** Mantenho separadas, o tempo todo, quatro superfícies
que se parecem e não são:

1. **Widget** (`/api/v1/widget/...`, autenticado por `website_token` + cookie `cw_conversation`)
   ≠ **canal API público** (`/public/api/v1/inboxes/...`, autenticado pelo `inbox_identifier`)
   ≠ **Application API** (`/api/v1/accounts/...`, autenticado por `api_access_token`).
   As três têm regras de HMAC diferentes. "Tem HMAC" numa **não** significa "tem HMAC" na outra.
2. **Webhook de conta** ≠ **webhook de inbox (canal API)** ≠ **webhook de agent bot** ≠ **webhook
   de automação/macro/flow**. Quatro caminhos, quatro conjuntos de garantias **[R18 §A.2]**.
3. **Contato** ≠ **conversa**, e dentro de cada um, `custom_attributes` ≠ `additional_attributes`.
   Quatro destinos com semânticas de escrita distintas **[R17 §4.5]**.
4. **O que o backend grava** ≠ **o que o painel do agente renderiza** ≠ **o que entra no prompt
   da IA**. São três coisas diferentes neste produto, e é exatamente aí que mora o maior gap
   **[R19 §D.3]**.

Onde eu observei, digo que observei. Onde eu deduzi, digo que deduzi. Onde um relatório de entrada
observou e eu apenas repassei, a marca é do relatório.

### 0.3 Divergências entre os relatórios de entrada — declaradas, não resolvidas em silêncio

A regra desta task é apontar divergência, não escolher escondido. Encontrei **cinco**. Em três
delas fui ao código nesta sessão para arbitrar; nas outras duas registro que não arbitrei.

---

**D1 — O que acontece quando o site chama `setUser` antes de o widget carregar.**

- **[R14 §15.4, D12]** afirma: *"chamar `$chatwoot.setUser()` antes do `chatwoot:ready`
  simplesmente perde a chamada"*, e recomenda fila pré-boot.
- **[R17 §4.1]** afirma o contrário parcial: **existe** um reenvio no evento `loaded`, mas com
  payload em formato **diferente** do da chamada direta, o que provavelmente resulta em erro.

**Arbitragem por leitura de código nesta task.** Os dois estão parcialmente certos, e a diferença
importa para a spec:

- **[CÓDIGO]** `app/javascript/entrypoints/sdk.js:112-137` — a chamada direta faz
  `IFrameHelper.sendMessage('set-user', { identifier, user })`.
- **[CÓDIGO]** `app/javascript/sdk/IFrameHelper.js:185-187` — no evento `loaded`, se
  `window.$chatwoot.user` existir, faz `IFrameHelper.sendMessage('set-user', window.$chatwoot.user)`.
- **[CÓDIGO]** `IFrameHelper.js:94-103` — `sendMessage(key, value)` serializa
  `{ event: key, ...value }`, ou seja **espalha** o segundo argumento no topo do objeto.
- **[CÓDIGO]** `app/javascript/widget/store/modules/contacts.js:45-59` — o consumidor desestrutura
  `{ identifier, user: userObject }` e em seguida desestrutura `userObject`.

**[INFERÊNCIA]** Logo: existe **rede de segurança** (contra o R14), mas ela entrega
`{event:'set-user', email:…, name:…}` sem `identifier` e sem `user`, e a segunda desestruturação
recebe `undefined`. O `catch` da action (`contacts.js:85-88`) despacha `chatwoot:error` com
`SET_USER_ERROR`. Ou seja: **falha, mas falha ruidosa** — não é o silêncio que o R14 descreve, nem
o funcionamento que a existência do reenvio sugere. **[NÃO VERIFICADO]** Não executei. Isto é o
caminho exercido por **todo cliente que identifica cedo**, que é justamente o caso do GTM, e por
isso está listado como teste dirigido obrigatório na Fase 1 (§6).

---

**D2 — O hash de deduplicação do `setUser`: quatro campos ou cinco?**

- **[R17 §4.1]** diz: MD5 sobre `avatar_url`, `email`, `name`, `identifier_hash` **e** `identifier`
  — cinco.
- **[R09 §4.3]** diz: *"as 4 chaves de `ALLOWED_USER_ATTRIBUTES` (`avatar_url`, `email`, `name`,
  `identifier_hash`)"* — quatro.

**Arbitragem por leitura de código nesta task.** **[CÓDIGO]**
`app/javascript/sdk/cookieHelpers.js:4-19`:

- `REQUIRED_USER_KEYS = ['avatar_url','email','name']`;
- `ALLOWED_USER_ATTRIBUTES = [...REQUIRED_USER_KEYS, 'identifier_hash']` → **4 chaves**;
- `getUserString` concatena essas 4 do objeto `user` **e depois** anexa a string literal
  `identifier` seguida do valor do identificador → **5 valores no material do hash**.

**Não é contradição:** os dois descrevem coisas diferentes com precisão. A consequência prática é
idêntica nos dois relatórios e é o que importa para a spec: **`phone_number`, `company_name`,
`city`, `country_code`, `description`, `social_profiles` e `custom_attributes` ficam FORA do
hash**. Mudar só o telefone e rechamar `setUser` com o mesmo nome/e-mail/identifier é descartado
pelo *early return* (`sdk.js:123-127`) e **o dado novo nunca sai do navegador**.

---

**D3 — Os métodos de dados "lançam erro" ou "falham em silêncio"?**

- **[R09 §4.3]** diz que `setCustomAttributes`, `deleteCustomAttribute`,
  `setConversationCustomAttributes` e `deleteConversationCustomAttribute` **lançam `Error`**.
- **[R17 §4.1, tabela]** marca, para esses mesmos métodos, "Erro chega ao site? **não**".

**Arbitragem por leitura de código nesta task.** **[CÓDIGO]** `sdk.js:139-175` — cada um desses
métodos lança `Error` **apenas na validação local do argumento** (objeto vazio / string vazia),
antes de qualquer ida ao servidor. **[CÓDIGO]** `app/javascript/widget/store/modules/contacts.js:88-103`
e `app/javascript/widget/store/modules/conversation/actions.js:183-197` — o resultado da chamada
HTTP é engolido por `catch { // Ignore error }`.

**Os dois estão certos, sobre coisas diferentes**, e a spec precisa dizer as duas em uma frase:
**o SDK valida a forma do argumento de modo ruidoso e o resultado da operação de modo mudo.** Um
erro de digitação no nome do método derruba a tag do GTM; um erro de 404, 401 ou 422 do servidor
não produz sinal nenhum.

---

**D4 — O placar de enforcement de identidade na matriz do relatório 10.**

- **[R10 §2, bloco H, linha 65]** marca ChatSPX como 🟡 em "enforcement só usuários verificados",
  com a nota *"temos `hmac_mandatory`; falta a coexistência clara com anônimo"*.
- **[R17 §3.5]** mostra **dois caminhos** em que o `hmac_mandatory` não é aplicado.

**Não arbitrei por execução** — nenhum dos dois testou. Mas registro que a linha 65 do R10 está
**otimista demais à luz do R17**, e que a leitura de código que fiz nesta task (§4.2) sustenta o
R17. Quem usar a matriz do R10 para decidir prioridade precisa corrigir essa linha de 🟡 para
"🟡 com dois furos conhecidos".

---

**D5 — A recomendação de HMAC → JWT aparece em três relatórios com escopos diferentes.**

- **[R17 §3.1, §6 camada 2]** recomenda JWT como formato **adicional**, mantendo o
  `identifier_hash` por compatibilidade, e aponta que `Widget::TokenService` já existe.
- **[R19 §3 recomendações]** recomenda *"avaliar JWT"* — mais fraco, no contexto de proteção de
  atributo.
- **[R10 §7, Q6]** não trata de JWT: trata do **toggle de enforcement**, e recomenda "(a) toggle
  por inbox com modo somente-aviso agora, (b) ligado por padrão depois".

**Não é contradição, é escopo diferente** — mas juntar as três sem cuidado produz a conclusão
errada "trocar HMAC por JWT resolve o enforcement". **Não resolve**: os dois furos do §4.2 são de
*roteamento de `before_action`*, não de formato de credencial. Trocar o formato sem fechar os
furos deixa as duas portas abertas com um token mais bonito. Registro isso porque é exatamente o
tipo de achatamento que a advertência de rigor desta onda pede para evitar.

### 0.4 O que esta síntese não faz

- **Não executei nada.** Não abri navegador, não chamei endpoint, não subi ambiente. As
  verificações que fiz nesta task são **leitura de código-fonte**, marcadas **[CÓDIGO]**.
- **Não capturei screenshots.** Esta task não tem superfície visual própria. As capturas da frente
  estão em `plano/estudo-chat-web/integracao/shots/` (inventariadas em **[R19 §Screenshots]**) e em
  `plano/estudo-chat-web/frontend/shots/`.
- **Não reabri as medições dos relatórios de entrada.** Onde repasso um número deles, a marca é
  deles. Onde eu mesmo fui ao código para arbitrar divergência ou fundamentar uma cláusula do
  contrato, a marca é **[CÓDIGO]**.
- **Não escrevo código de implementação.** As assinaturas que aparecem em §2 são **contrato**
  (nome, aridade, tipos, semântica), não implementação.

---

## 1. Resumo executivo

### 1.1 O que o mercado entrega nessa área

Onze fornecedores foram levantados nos relatórios de entrada. Resumo do que é **padrão de 2026**
nesta frente específica:

1. **Três verbos de ciclo de vida, não um.** `boot`/`identify` → `update` → `shutdown`. Todo
   fornecedor sério tem um verbo explícito de **encerrar sessão**, porque dispositivo compartilhado
   e logout são casos reais. O Intercom chega a avisar que o `shutdown` **não basta** e que é
   preciso apagar os cookies com prefixo `intercom-` **[FATO, R17 §2.1]**.
2. **Identidade assinada com validade.** O mercado migrou de HMAC para JWT: Intercom recomenda
   textualmente *"stopping the generation of HMAC-SHA256 signatures (aka user_hashes)"*; Zendesk
   nasceu em JWT; Drift usa JWT; Freshchat usa **RS256** (assimétrico). Só Crisp e tawk.to
   continuam em HMAC puro **[FATO, R17 §3.1]**.
3. **O melhor desenho de token é o do Zendesk, e é uma inversão de direção.** Ele não recebe um
   token: recebe **uma função que busca um token** (`loginUser(jwtCallback)`), chamada de novo a
   cada 401. Isso resolve na raiz o problema de token em página cacheada por CDN — o HTML cacheado
   carrega o *callback*, não a credencial **[FATO, R17 §2.2, §3.6]**.
4. **Enforcement em três estados, não em booleano.** O Drift tem `DISABLED` / `ENABLED` /
   `REQUIRED`; o Intercom tem Desativado / Opcional / Obrigatório **por plataforma**. O estado do
   meio é o que permite ligar a verificação e **observar** antes de bloquear **[FATO, R17 §3.4]**.
5. **Confirmação de recebimento.** tawk.to (`setAttributes(attrs, callback)`), Zendesk
   (`updateUser(..., callback)`) e JivoChat devolvem resultado. LiveChat vai além e devolve
   **estado**: `get("customer_data")` **[FATO, R17 §2.6, §2.8]**.
6. **Distinção explícita entre mesclar e substituir.** Só o LiveChat nomeia os dois verbos
   (`set_session_variables` × `update_session_variables`) **[FATO, R17 §2.6]**.
7. **Eventos tipados vindos do site.** Intercom `trackEvent`, Drift `track`, Crisp `session:event`,
   tawk.to `addEvent`, Tidio `track` **[FATO, R17 §2.12]**.
8. **Limites publicados.** tawk.to é o mais explícito: 50 atributos, 255 caracteres por valor, 10
   tags por chat, telefone em E.164. Intercom: 250 CDAs por workspace, 255 caracteres, listas com
   no máximo 35 opções **[FATO, R17 §2.1, §2.8]**.
9. **Do lado servidor, retry é universal.** As janelas vão de ~1 minuto (LiveChat) a 24 horas
   (HubSpot), passando por 12 horas (tawk.to) e ~4h45 (Tidio). **Ordem nunca é garantida** por
   ninguém — isso é consenso, não gap **[R18 §A.2]**.
10. **Idempotência é sempre delegada ao consumidor, mas os bons entregam a chave.** O tawk.to é o
    mais explícito: *"The event Id will remain the same in case of retries"* **[FATO, R18 §A.2]**.
11. **Controle de escrita por atributo.** O Intercom tem um toggle **"Require verified updates"**
    por atributo: sem JWT válido, a escrita vinda do Messenger é **ignorada** — *"The data is
    ignored"* **[FATO, R19 §C.3.2]**.
12. **A Leadster, específicamente, não joga esse jogo.** Busca no bundle público de 1.036.439
    bytes: **zero** ocorrências de `setUser`, `identify`, `setContactInfo`, `setVisitorData`,
    `hmac`, `signature`, `user_hash`. A única forma de o site passar dado é **regex sobre a URL**
    (`metadata.urlData`, configurado no painel deles) mais os UTMs da query string, e há **um**
    gancho de callback no bundle inteiro (`nldAPI_Neurologic_OnClose`) **[R17 §2.11]**.

### 1.2 Onde estamos

A leitura honesta, que contraria a expectativa comum dentro de casa:

> **Não perdemos em superfície. Perdemos em contrato.**

**Superfície pública que já temos** — 13 métodos em `window.$chatwoot`, 7 eventos de `window`,
HMAC-SHA256 por inbox com toggle, e um escopo de leitura de histórico que barra o ataque clássico
de personificação. Isso é **mais** do que Leadster, Tidio, JivoChat e tawk.to entregam no quesito
de dados **[R17 §0.1, §2.12]**. Do lado servidor, assinamos o webhook de conta com HMAC-SHA256 com
timestamp no material assinado — o **grupo mais forte** do mercado, ao lado de Zendesk, HubSpot v3,
Tidio e Crisp **[R18 §A.2, §D.12]**. E expomos `meta.hmac_verified` no payload do webhook, coisa
que **nenhum concorrente medido faz** **[R18 §D.12]**.

**O que está quebrado é o contrato**, e são sete defeitos concretos:

| # | Defeito | Evidência |
|---:|---|---|
| 1 | Seis dos sete métodos de dados **não confirmam nada** — nem sucesso, nem erro | **[R17 §4.1]**; `// IgnoreError` em `contacts.js:88-103` e `conversation/actions.js:183-197` **[CÓDIGO]** |
| 2 | `setConversationCustomAttributes` **antes de existir conversa** devolve 404 e o widget engole | **[R17 §0.3]**; `conversations_controller.rb:3, 93-95` **[CÓDIGO]** |
| 3 | Dois métodos irmãos com semânticas **opostas**: contato faz merge, conversa **substitui** | **[R17 §4.5]**; `contact_identify_action.rb:128-132` × `conversations_controller.rb:67-69` **[CÓDIGO]** |
| 4 | O toggle `hmac_mandatory` **não cobre** dois caminhos de escrita de identidade | **[R17 §3.5]**; `contacts_controller.rb:4, 8, 59, 73` **[CÓDIGO]** |
| 5 | **Nenhum dos dois lados** do `postMessage` valida `e.origin` | **[R17 §4.3]**; `IFrameHelper.js:104-117`, `widget/helpers/utils.js:8-21` |
| 6 | Atributo sem `CustomAttributeDefinition` prévia: **grava, entra no prompt da IA, e some do painel** | **[R19 §D.3]**; `CustomAttributes.vue:76-89` |
| 7 | Webhook de conta e de inbox: **zero retentativa**, em qualquer tipo de falha | **[R18 §D.10.4]**, provado com o arquivo real e stubs |

**[INFERÊNCIA]** Estes sete não são "features que faltam". São **promessas que o produto faz e não
cumpre**. Um método que existe e falha em silêncio é pior que um método ausente: o ausente o
integrador contorna; o mudo ele confia. Um toggle de segurança que não trava é pior que a ausência
do toggle: quem liga acredita ter fechado a porta.

### 1.3 A tese

> **O site já consegue se vincular ao chat e passar parâmetros. O que ele não consegue é saber se
> deu certo, saber quem garante que o dado é verdadeiro, e ver o resultado na tela do atendente.
> A entrega desta frente não é "mais métodos" — é transformar sete chamadas mudas em um contrato
> com resposta, prova e destino visível.**

Três consequências práticas dessa tese, que organizam o resto do documento:

1. **Estabilizar antes de somar.** Cada método novo adicionado hoje herda os quatro defeitos de
   contrato (sem retorno, sem fila, sem erro, exceção não capturada). O trabalho de estabilização
   é pré-requisito, não fase paralela **[R17 §6, camada 1]**.
2. **Segurança é coerência, não feature.** Os furos 4 e 5 são de roteamento e de validação
   ausente, não de criptografia faltando. São correções pequenas de superfície grande, e **não
   dependem de nenhuma decisão de front** — podem e devem andar antes do redesenho visual.
3. **Integração que não aparece na tela não existe.** O gap 6 é o que faz o cliente concluir "não
   funcionou" quando tudo funcionou. É o item de maior retorno percebido de toda a frente, e é
   trabalho de painel do agente, não de widget **[R19 §D.3, §recomendação 1]**.

---

## 2. O contrato de integração proposto

Esta é a seção central. Ela especifica **o que** o site pode passar, **como**, **com que prova**,
**onde isso mora**, **o que volta** e **o que o backend do cliente pode fazer**. Cada bloco
declara o que **já existe hoje** e o que é **novo**.

### 2.0 Os cinco princípios do contrato

Antes das tabelas, as regras que decidem todo caso omisso:

**P1 — Nenhuma chamada é muda.** Toda chamada de dado devolve resultado (`Promise` ou callback) e,
em caso de falha, dispara `chatwoot:error` com motivo legível. Isto vale inclusive para as chamadas
que hoje funcionam.

**P2 — Chamar cedo é legítimo.** Chamada feita antes de o widget existir entra em fila e é drenada
no boot, com o **mesmo formato** da chamada tardia. É o padrão de Crisp (`window.$crisp = []`),
Intercom (`i.q = []`) e Tidio (`tidioChatApi.queue`) **[FATO, R14 §11.3]**, e é a lacuna mais
barata de fechar **[R14 §15.4, D12]**.

**P3 — O verbo diz a semântica.** `set…` substitui, `update…` mescla. Sem exceção, sem par de
irmãos com comportamentos opostos. É o desenho do LiveChat **[FATO, R17 §2.6]**.

**P4 — Credencial nunca viaja por canal cacheável.** Identidade e prova de identidade só passam
por API JS. **Nunca** por `data-*` (vive no HTML, e HTML é cacheado), **nunca** por URL (vaza no
histórico, no `Referer` de terceiros e em log de CDN). É a fronteira que o Dynamics 365 respeita
com dez `data-*` — todos de aparência e comportamento, nenhum de identidade **[FATO, R17 §5.1]**.

**P5 — Confiança é uma propriedade do dado, não do endpoint.** Todo atributo carrega a origem
(verificado / declarado pelo site / preenchido pela IA / digitado pelo agente), e essa origem
governa três decisões a jusante: se pode sobrescrever, se aparece com selo no painel, e se entra
no prompt da IA. Hoje **[R19 §D.1]** não existe nenhuma coluna que expresse isso.

---

### 2.1 O que o site pode passar — dicionário de campos

Legenda de estado: **HOJE** = já existe e funciona; **HOJE⚠** = existe com defeito documentado;
**NOVO** = não existe.

#### 2.1.1 Identidade — mora no **contato**

| Campo proposto | Tipo | Limite proposto | Estado | Observação |
|---|---|---|:---:|---|
| `identifier` | string | 255 (limite do Zendesk `external_id` **[FATO, R17 §2.2]**) | **HOJE** | chave de identidade; é o que o HMAC assina |
| `email` | string | 255 | **HOJE** | dispara merge por e-mail no `ContactIdentifyAction` |
| `name` | string | 255 | **HOJE** | |
| `phone_number` | string, **E.164** | 20 | **HOJE⚠** | **[CÓDIGO]** `cookieHelpers.js:23-24` — `phone_number` sozinho **não passa** na validação do `setUser`, que exige uma de `avatar_url`/`email`/`name`. Quem só tem telefone não consegue identificar. tawk.to exige E.164 **[FATO, R17 §2.8]** |
| `avatar_url` | string (https) | 512 | **HOJE** | |
| `language` | string (BCP-47 / `pt_BR`) | 10 | **HOJE⚠** | hoje só via `setLocale`, separado da identidade |
| `signed_up_at` | inteiro (unix, segundos) | — | **NOVO** | é o `created_at` do Intercom **[FATO, R17 §2.1]**. Habilita segmentação por antiguidade, que hoje é impossível |
| `company` | objeto (ver 2.1.2) | — | **NOVO** | hoje só `company_name` string |
| `custom_attributes` | objeto plano | ver 2.1.6 | **HOJE** | merge profundo **[R17 §4.5]** |

**Campos que hoje são de topo no `setUser` e viram `additional_attributes` sem aviso**
**[CÓDIGO]** `app/javascript/widget/store/modules/contacts.js:60-74`: `company_name`, `city`,
`description`, `country_code`, `social_profiles`. **Não há documentação disso em lugar nenhum** —
é preciso ler o store para descobrir. A spec proposta mantém a compatibilidade e **documenta**
o remapeamento (§2.4).

#### 2.1.2 Empresa / conta — **NOVO**

O Intercom aceita um objeto `company` com `company_id`, `name`, `created_at`, `plan`,
`monthly_spend`, `user_count`, `size`, `website`, `industry`, e um array `companies` para múltiplas
**[FATO, R17 §2.1]**. Nós aceitamos **uma string**.

**[CÓDIGO]** Existe `contacts.company_id` no schema, mas **[R17 §4.6]** não há caminho do widget
até ele.

| Campo proposto | Tipo | Estado |
|---|---|:---:|
| `company.id` | string (obrigatório se `company` presente) | **NOVO** |
| `company.name` | string | **NOVO** (hoje: `company_name` string solta) |
| `company.plan` | string | **NOVO** |
| `company.size` | inteiro | **NOVO** |
| `company.industry` | string | **NOVO** |
| `company.website` | string | **NOVO** |
| `company.signed_up_at` | inteiro (unix) | **NOVO** |

**Recomendação de escopo:** **um** objeto `company`, não o array `companies` do Intercom. B2B
multi-conta é caso raro no nosso ICP e o custo de modelagem é desproporcional.
**[INFERÊNCIA]** — base: o ICP descrito em **[R18 §"O que falta"]** é PME brasileira com ERP/CRM
próprio ou de prateleira, e as verticais fortes levantadas em **[R19 §A.3]** (imobiliária,
automotivo, educação) são B2C.

#### 2.1.3 Contexto de sessão / intenção — mora na **conversa**

A distinção vem de **[R19 §A.0]**, e é a que decide onde o dado mora:

| Tipo | O que é | Onde mora | Quem escreve |
|---|---|---|---|
| **Identidade** | quem a pessoa é; atravessa conversas | contato | backend autenticado |
| **Estado** | como a conta/pedido está **agora**; muda sozinho | **não se copia — se busca na hora** | sistema de origem |
| **Intenção** | o que a pessoa está fazendo nesta visita; morre com a conversa | conversa | front do site |

**A regra que sai daí, e que é a mais importante de todo o §2.1:** contexto de **estado** (saldo,
status de entrega, fatura vencida) é o que mais tenta as pessoas a copiar para dentro do chat, e é
justamente o que **nunca** deve ser copiado. *"Saldo copiado às 14h e lido pelo agente às 16h é
pior que saldo ausente: parece verdade e não é"* **[R19 §A.0]**. E não é teoria: o Gorgias
**removeu** a visão de carrinho ao vivo do sidebar do agente por custo e fragilidade **[FATO,
R19 §A.1]**.

| Campo proposto | Tipo | Estado | Observação |
|---|---|:---:|---|
| `page_url` | string | **HOJE⚠** | hoje só a URL do **momento do envio da primeira mensagem**, gravada como `additional_attributes.referer` **[R07 §6.1]** |
| `page_title` | string | **NOVO** | |
| `landing_page` | string | **NOVO** | a primeira página da sessão — é o que conserta a atribuição (§5) |
| `entry_referrer` | string | **NOVO** | o `document.referrer` de verdade, que hoje **não capturamos** **[R09 §11]** |
| atributos livres de conversa | objeto plano | **HOJE⚠** | hoje **substitui** o objeto inteiro e se perde antes de existir conversa |

**Catálogo por vertical:** os campos concretos (e-commerce, SaaS, imobiliária, automotivo,
educação, B2B) estão tabelados em **[R19 §A.1–§A.4]** e **não** vou reproduzi-los aqui. Eles são
o rascunho do material de onboarding recomendado em **[R19 §recomendação 8]**, e a spec só define
o **transporte** e o **critério de admissão**, que é o filtro de quatro perguntas de
**[R19 §A.0]**:

1. Muda a primeira frase do atendente? Se não, é ruído.
2. É estado ou é foto? Se muda sozinho, não copia — busca.
3. O que quebra se estiver errado? Se direciona ação, exige origem autenticada.
4. Precisa do valor, ou o derivado basta? (`faixa_etaria` em vez de `nascimento`.)

#### 2.1.4 Eventos de negócio — **NOVO**

Intercom `trackEvent`, Drift `track`, Crisp `session:event`, tawk.to `addEvent`, Tidio `track`
**[FATO, R17 §2.12]**. Nós **não temos**: **[R17 §4.6, item 3]** o `pushEvent`
(`IFrameHelper.js:298-300`) existe mas **não está exposto** no `$chatwoot` — é interno, usado só
para `webwidget.triggered`.

| Campo | Tipo | Limite proposto |
|---|---|---|
| `name` | string, `snake_case` | 40 caracteres (limite do GA4 **[R07 §7.2]**) |
| `properties` | objeto **plano** (sem aninhamento, sem array) | 20 chaves; valores string / número / booleano |
| `value` / `currency` | número / ISO-4217 | opcional; é o que destrava campanha por ROAS **[R07 §7.5, decisão 8]** |

O Drift exige objeto *flat* e atributos **case-sensitive** **[FATO, R17 §2.4]** — copiar as duas
regras evita a classe inteira de bug "por que meu atributo apareceu duplicado".

**[INFERÊNCIA]** Este é o campo de maior alavancagem cruzada do contrato inteiro, porque é o mesmo
objeto que a frente de tracking precisa (§5). Um `track()` bem definido serve simultaneamente à
integração com o CRM do cliente **e** ao pixel — e é preciso desenhá-lo uma vez só.

#### 2.1.5 Origem e atribuição

Detalhado em §5. Fica aqui a nota de fronteira: **o site não deveria precisar passar isso à mão**.
A camada C2 **[R10 §4.1]** coleta no SDK e o site só precisa passar o que ele sabe e o navegador
não (por exemplo, o `id` de campanha interno do CRM dele).

#### 2.1.6 Limites, tipos e a lista negativa

**O que existe hoje** — e é o desenho mais frouxo do levantamento:

| Onde | Limite hoje | Evidência |
|---|---|---|
| `conversations.custom_attributes` | 1500 caracteres por chave (string) / 9.999.999.999 (inteiro). **Sem limite de número de chaves** | **[R19 §C.3.3, elo 6]** `jsonb_attributes_length_validator.rb:14-22` + `conversation.rb:80-81` |
| `contacts.custom_attributes` | **nenhum** — a validação de comprimento não existe no contato | **[R19 §C.3.3]** |
| chave | formato `/\A[\p{L}\p{N}_.\-]+\z/` **apenas na definição**, não no valor gravado | **[R17 §4.5]** `custom_attribute_definition.rb` |

**Limites propostos**, ancorados no mercado:

| Regra | Valor proposto | Fonte da âncora |
|---|---|---|
| Nº de chaves vindas do widget, por modelo | **50** | tawk.to publica exatamente 50 **[FATO, R17 §2.8]** |
| Tamanho do valor (string) | **1500** (manter o nosso) | nosso limite atual é mais generoso que os 255 de tawk.to/Intercom; não há motivo para apertar |
| Formato da chave | `/\A[\p{L}\p{N}_.\-]+\z/`, minúsculas | já é o formato da `CustomAttributeDefinition`; tawk.to converte para minúscula **[FATO, R17 §2.8]** |
| Tags/labels por conversa | **10** | tawk.to **[FATO, R17 §2.8]** |
| Aninhamento | proibido — objeto plano | Drift **[FATO, R17 §2.4]** |

**A lista negativa** — o que **nunca** deve ser aceito como atributo, transcrita de
**[R19 §A.5]** porque é a parte da spec que protege o cliente de si mesmo:

| Nunca passar | Por quê | O que passar no lugar |
|---|---|---|
| Cartão, CVV, validade | PCI-DSS. Um jsonb não é ambiente de cartão | nada — cobrança fora do chat |
| Senha, token, API key, session ID | credencial em texto puro | nada |
| CPF/CNPJ completo | identificador nacional, dado de fraude | hash ou máscara |
| RG, CNH, RENAVAM, passaporte | documento | só flag de verificação |
| Saúde, biometria, religião, política, orientação, origem racial | **dado sensível — LGPD art. 5º II** | não passar |
| Endereço completo | excesso para atender | cidade/UF |
| Data de nascimento exata | reidentifica quando combinada com nome | faixa etária |
| Saldo, limite, valor exato de dívida | financeiro | faixa ou flag |

**[R19 §A.3]** registra o agravante que torna isto operacional e não retórico: no **automotivo**, o
padrão do setor é coletar **CPF e RENAVAM** no chat para simulação de financiamento; na
**educação**, `ja_e_aluno = true` pode significar **menor de idade**. O produto precisa
**dificultar a coisa errada**, e o Zendesk mostra como: em vez de proibir, oferece um tipo nativo
**`credit card`** que mascara e trata adequadamente **[FATO, R19 §B.1]**.

---

### 2.2 Como o site passa — as cinco vias e quando cada uma se aplica

| Via | Pode carregar | Quando usar | Estado hoje |
|---|---|---|:---:|
| **1. API JS** (`window.$chatwoot`) | **tudo**, inclusive identidade e credencial | caso geral | **HOJE⚠** — 13 métodos, sem fila, sem retorno |
| **2. `data-*` na tag do script** | **só configuração** (posição, locale, esconder bolha, cor) | CMS travado; time de marketing sem dev | **NOVO** — hoje temos **zero** `data-*` **[R17 §5.1]** |
| **3. Parâmetros na URL** | **só contexto não sensível** (`?plano=pro`, `?origem=x`) e UTMs | landing pages; CMS travado | **HOJE⚠** — `buildUrl` já anexa `window.location.search` a toda chamada de API do widget **[CÓDIGO]** `widget/api/contacts.js:3`, mas nada é parseado |
| **4. GTM / `dataLayer`** | o que a API JS aceitar — via **tag de HTML customizado que chama a API** | cliente com GTM e sem dev no site | **HOJE⚠** — funciona, mas é hostil (ver abaixo) |
| **5. `postMessage` direto ao iframe** | — | **nunca** | **HOJE** — funciona e **não deveria**; é a via a fechar, não a promover **[R17 §5.1]** |

**Sobre a via 4, o achado que muda o pedido.** **[FATO, R17 §5.1]** Não existe **nenhum**
fornecedor que consuma `dataLayer` nativamente. O padrão real do mercado é o inverso: uma tag de
HTML customizado no GTM **chama a API JS do widget**. Isso muda a natureza do requisito: "receber
parâmetros via GTM" **não exige** que o chat leia o `dataLayer` — exige que a API JS seja
**chamável de dentro de uma tag do GTM**, o que impõe três requisitos concretos:

- **(a) tolerar chamada antes do boot** (fila) — porque a ordem de disparo das tags não é
  controlável;
- **(b) ser idempotente** — porque o GTM pode disparar a mesma tag mais de uma vez;
- **(c) nunca lançar exceção não capturada** — porque uma exceção dentro de uma tag do GTM
  **quebra as tags seguintes do contêiner**.

**[CÓDIGO]** Hoje falhamos em (a) e em (c): `sdk.js:113-121` e `:139-175` lançam `Error`. Quem
colar isso numa tag do GTM sem `try/catch` derruba o resto da medição do cliente.

**A fronteira dura entre as vias**, que resolve todo caso omisso:

> **Configuração pode viajar por qualquer via. Identidade e credencial só pela via 1.**

Motivo, em uma frase **[INFERÊNCIA]**, base em **[FATO, R17 §5.1]** e **[R17 §3.6]**: `data-*` vive
no HTML servido e HTML é cacheado; URL vaza no histórico, no `Referer` de terceiros e no log de
CDN. Um par `(identifier, identifier_hash)` que vaze uma vez vale **para sempre**, porque o nosso
hash **não tem expiração**.

**A via 5 precisa ser fechada, não documentada.** **[R17 §4.3]** Nenhum dos dois lados valida
`e.origin`, e o handler do lado do site inclui `setAuthCookie`, que **grava o cookie
`cw_conversation`** com o valor recebido. Detalhe em §4.

---

### 2.3 Autenticação e enforcement

#### 2.3.1 O que existe hoje

**[CÓDIGO]** `app/controllers/api/v1/widget/contacts_controller.rb:64-70`:

```
identifier_hash == HMAC-SHA256(web_widget.hmac_token, identifier)
```

Só o identificador é assinado. `name`, `email`, `phone_number` e `custom_attributes` viajam **ao
lado** da assinatura, **fora** dela **[R17 §3.1]**. Não há `exp`. O segredo é
`channel_web_widgets.hmac_token`, único por widget, `has_secure_token`.

**O que muda quando `hmac_verified` é `true`** — e este é o ativo subestimado da casa
**[R17 §4.4]**:

| Comportamento | `false` | `true` |
|---|---|---|
| Escopo do histórico no widget | conversas **deste `contact_inbox`** | todas as conversas do contato nos `contact_inbox` verificados — **[CÓDIGO]** `base_controller.rb:10-17` |
| API pública de conversas | do `contact_inbox` | do contato |
| Broadcast em tempo real | só o `pubsub_token` da sessão | todos os `pubsub_token` verificados do contato |
| Estado das ferramentas do Captain | recebe `hmac_verified` | idem |
| Header do webhook de tool do Captain | `X-Chatwoot-Contact-Inbox-Verified: false` | `: true` |
| Payload de eventos / webhook | `hmac_verified` presente | idem |

**[INFERÊNCIA]** Isto é infraestrutura pronta para uma política do tipo *"só executa ação sensível
se o contato for verificado"* — atravessando até a camada de IA — sem construir nada novo no
transporte. É um diferencial que **nenhum concorrente medido expõe** **[R18 §D.12]** e que hoje
não é vendido nem documentado.

#### 2.3.2 Os dois furos do enforcement

Confirmei os dois **[CÓDIGO]** nesta task, lendo o arquivo:

**Furo 1 — a ação `update` não passa por verificação nenhuma.**
`contacts_controller.rb:4` — `before_action :validate_hmac, only: [:set_user]`. A rota
`PATCH /api/v1/widget/contact` → `#update` (**[CÓDIGO]** `config/routes.rb:609`) chama `identify_contact` com
`permitted_params` (`:72-75`), que inclui **`email`, `name` e `phone_number`**. O
`ContactIdentifyAction` faz merge por e-mail. **E o `$chatwoot.setCustomAttributes()` usa
exatamente essa rota** — **[CÓDIGO]** `widget/api/contacts.js:18-22` — ou seja, **por construção,
nunca passa por HMAC**.

**Furo 2 — o *early return* da linha 59.**
`return false if params[:custom_attributes].present? && params[:identifier].blank?` — este `return`
vem **depois** da checagem de `hmac_mandatory` (linha 56) e **antes** do `true` final. Lido
literalmente: uma requisição a `set_user` com `custom_attributes` e sem `identifier` **desliga a
verificação, inclusive com o modo obrigatório ligado**. E `permitted_params` aceita `:email` na
mesma ação.

**[INFERÊNCIA]** — **não executei, não explorei**. O comentário no próprio código
(*"Taking an extra caution that the hmac is triggered whenever identifier is present"*) mostra a
intenção — dispensar HMAC quando não há identidade a provar. O filtro olha só para `identifier` e
ignora que **`email` também é um identificador**, porque dispara merge.

**Classificação honesta:** não chamo isto de vulnerabilidade confirmada. Chamo de **desenho que
não sustenta a promessa do toggle**. Quem liga `hmac_mandatory` acredita ter fechado a porta da
identificação não verificada; o código deixa duas frestas. Confirmação empírica exige ambiente
isolado e está fora do escopo de uma task de estudo.

#### 2.3.3 JWT vale a pena? — recomendação

**Sim, como formato adicional. Não como substituto, e não antes de fechar os furos.**

O que o JWT resolve que o HMAC não resolve **[R17 §3.1]**:

| Dimensão | HMAC (hoje) | JWT |
|---|---|---|
| O que é assinado | **só o identificador** | o objeto inteiro (id, e-mail, atributos, validade) |
| Expiração | **não existe** | `exp` no payload |
| Atributos autenticados | **nenhum** | os que estiverem no payload |
| Revogação | só rotacionando o segredo — invalida **todos** os usuários | expira sozinho |

**Três argumentos a favor, nesta ordem de peso:**

1. **É o único caminho para "atributo confiável".** O toggle "Require verified updates" do
   Intercom **[FATO, R19 §C.3.2]** só faz sentido se houver o que verificar no atributo — e com
   HMAC os atributos estão fora da assinatura. Sem JWT, "atributo verificado" é impossível por
   construção, e o item de segurança mais valioso da frente (§4, ameaça T3) fica sem solução.
2. **A infraestrutura já existe.** **[CÓDIGO]** `app/services/widget/token_service.rb` já faz
   `JWT.encode` com `exp` e `iat`, com expiração configurável por
   `InstallationConfig['WIDGET_TOKEN_EXPIRY']`, default **180 dias**. Não é biblioteca nova, não é
   dependência nova.
3. **É a direção declarada do mercado**, com o caminho de migração já documentado por quem já
   fez: o Intercom aceita os dois, recusa os dois juntos, e mantém o `user_hash` em modo legado
   **[FATO, R17 §3.1]**.

**Dois argumentos de cautela, que a recomendação incorpora:**

- **JWT não conserta os furos.** Os furos são de `before_action` e de `permitted_params`. Trocar o
  formato sem fechá-los deixa as duas portas abertas com credencial mais bonita (divergência D5).
- **O modelo do Zendesk (callback) é melhor que o modelo do token no HTML**, e é a diferença entre
  resolver e mitigar o problema de CDN **[FATO, R17 §2.2, §3.6]**. Recomendo desenhar a API já
  aceitando **uma função** que resolve a credencial, não só a string — mesmo que a primeira versão
  só aceite a string.

**Recomendação concreta:** aceitar **três formatos** no mesmo campo de autenticação, com precedência
declarada — (1) função assíncrona que resolve credencial (modelo Zendesk); (2) JWT HS256 com `sub`
= identifier, `exp` obrigatório, atributos no payload; (3) `identifier_hash` HMAC, aceito em modo
legado e **marcado como legado no painel**. Recusar (2) e (3) juntos, como o Intercom faz.

#### 2.3.4 O modelo de enforcement

**Hoje:** booleano `hmac_mandatory` por inbox, sem estado intermediário **[R17 §3.4]**.

**Proposto:** três estados, copiando o Drift **[FATO, R17 §3.4]**:

| Estado | Comportamento | Para quê serve |
|---|---|---|
| `desativado` | identificação aceita sem prova | default de inbox existente |
| `observado` | aceita sem prova, **mas registra** e sinaliza no painel qual identificação veio sem verificação | **o estado que hoje não existe e que viabiliza a migração** |
| `obrigatório` | identificação sem prova válida é **ignorada** (não é erro fatal) | banco, saúde, jurídico |

**Por que o estado do meio não é luxo [INFERÊNCIA]:** com um booleano, migrar um cliente que já
tem tráfego é um salto no escuro — ou passa a rejeitar tudo que não está assinado, ou não protege
nada. É a mesma conclusão de **[R10 §7, Q6]**, que recomenda "(a) toggle por inbox com modo
somente-aviso agora".

**O que NÃO muda com o enforcement ligado, e precisa estar escrito na spec:** o visitante **anônimo
continua funcionando**. **[CÓDIGO]** `hmac_mandatory` só é consultado dentro de
`should_verify_hmac?`, que roda no `before_action` da ação `set_user`. Quem nunca chama `setUser`
nunca passa por lá **[R17 §3.4]**. O modo obrigatório protege a **identificação**, não proíbe o
**anonimato** — e o Intercom faz igual: com JWT expirado, *"the user will see a fresh Messenger as
a logged-out website visitor"* **[FATO, R17 §3.4]**. Degrada para anônimo, não para erro.

#### 2.3.5 Nível de confiança exigido por campo

Esta tabela é o coração do modelo P5, e é o que hoje não existe em lugar nenhum do produto:

| Categoria de campo | Confiança mínima proposta | Se vier abaixo disso |
|---|---|---|
| `identifier`, `email`, `phone_number` (identidade) | **verificada** quando o enforcement estiver em `obrigatório` | ignorado silenciosamente (comportamento do Intercom: *"The data is ignored"*) |
| Atributo marcado como **"exige origem verificada"** na definição | **verificada** | ignorado, e registrado |
| Atributo de negócio comum | declarada pelo site | aceito, exibido com selo de origem |
| Contexto de página / intenção | declarada pelo site | aceito |
| Atributo preenchido pela IA | origem `ia` | aceito, exibido com selo distinto |

**[R19 §C.3.3]** registra que hoje **não existe nenhuma coluna** em `CustomAttributeDefinition` que
expresse origem, confiança ou visibilidade — as colunas são `attribute_description`,
`attribute_display_name`, `attribute_display_type`, `attribute_key`, `attribute_model`,
`attribute_values`, `default_value`, `regex_cue`, `regex_pattern`. Este é o item de modelagem que
destrava simultaneamente a mitigação de duas ameaças (§4, T3 e T5) e o selo de origem no painel
(**[R19 §recomendação 2]**).

---

### 2.4 Onde cada coisa é persistida — e por quê

#### 2.4.1 Os quatro destinos que existem hoje

**[R17 §4.5]** — e a confusão entre eles é a maior fonte de erro de integração:

| Destino | Quem escreve | Semântica | Tipado? | Visível ao atendente |
|---|---|---|---|---|
| `contacts.custom_attributes` | site (`setUser`, `setCustomAttributes`), API, agente, Copilot | **merge profundo** | via `CustomAttributeDefinition` | **só se houver definição** |
| `contacts.additional_attributes` | site (5 campos remapeados) + servidor (`created_at_ip`, `city`, `country`) | **merge profundo** | não | parcialmente |
| `conversations.custom_attributes` | site (`setConversationCustomAttributes`) + pre-chat + IA | **SUBSTITUI** | via `CustomAttributeDefinition` | **só se houver definição** |
| `conversations.additional_attributes` | **só o servidor**, na criação | escrita única | não | sim (navegador, SO, referer, idioma) |

**[CÓDIGO]** Confirmei a assimetria de semântica nesta task:
`app/controllers/api/v1/widget/conversations_controller.rb:67-69` faz
`conversation.update!(custom_attributes: permitted_params[:custom_attributes])` — substituição
total. O do contato faz `deep_merge` (`contact_identify_action.rb:128-132`, via **[R17 §4.5]**).
Dois métodos com nomes irmãos e semânticas opostas, sem nada na assinatura que avise.

> **Nota de precisão de citação.** R17 §4.5 e R19 §C.3.3 citam este método como `:66-68` e `:68`.
> Medi `:67-69` no HEAD `ee87f5e799` (`grep -n "def set_custom_attributes"`). É deslocamento de uma
> linha na mesma função — registro para quem for conferir e não achar no número citado. O conteúdo
> descrito pelos dois relatórios está correto.

**[CÓDIGO]** E confirmei o silêncio: `conversations_controller.rb:3` declara
`before_action :render_not_found_if_empty, only: [..., :set_custom_attributes, ...]`, e o método
(`:93-95`) devolve **404 quando ainda não existe conversa**. O store engole com
`catch { // IgnoreError }`. **[R17 §0.3]** classifica isto como *"o problema mais provável de estar
mordendo integrações hoje"*, e a razão é convincente: a ordem natural que qualquer desenvolvedor
escreve é "carrego a página → passo os dados → o visitante conversa", e nessa ordem **a conversa
ainda não existe**.

#### 2.4.2 A regra de roteamento proposta

| O que o site passa | Onde deve morar | Por quê |
|---|---|---|
| Identidade (`identifier`, `email`, `name`, `phone_number`, `avatar_url`) | colunas nativas do **contato** | são campos de primeira classe; duplicar em atributo espalha PII **[R19 §A.1]** |
| `signed_up_at`, `company.*` | **contato** — `custom_attributes` com definição provisionada | atravessa conversas |
| Atributo de perfil estável (`plano`, `cliente_desde`, `ltv_faixa`) | **contato** | identidade, não intenção |
| Atributo desta visita (`produto_atual`, `carrinho_valor`, `imovel_codigo`) | **conversa** | morre com a conversa; **[R19 §A.0]** |
| Origem/atribuição (`first_utm_*`, `gclid`, `fbclid`) | **os dois** — `first_*` write-once no contato, `last_*` na conversa | §5, e **[R07 §7.3]** |
| Estado (saldo, entrega, fatura) | **em lugar nenhum** — busca sob demanda | **[R19 §A.0]**; o Gorgias recuou disso **[FATO, R19 §A.1]** |
| Eventos de negócio | linha de evento própria, **não** atributo | atributo é foto, evento é linha do tempo |

**Regra de escrita proposta (P3):** `updateContact` e `updateConversation` fazem **merge**;
`setConversationAttributes` **substitui** e é o nome explícito para quem quer o comportamento atual.
Compatibilidade: `setConversationCustomAttributes` continua existindo com a semântica de hoje
(substitui) e é marcado como legado na documentação — trocar a semântica de um método existente
quebraria integração em produção em silêncio, que é exatamente o pecado que a spec combate.

#### 2.4.3 O gap que anula tudo: grava, alimenta a IA, e some do painel

**[R19 §D.3]** é o achado mais consequente da frente inteira, e não é de transporte — é de painel:

- **[R19]** `customAttributes/CustomAttributes.vue:76-89` — a iteração é sobre as **definições
  cadastradas**, não sobre os valores efetivamente gravados.
- Consequência exata: `setCustomAttributes({ carrinho_valor: 4200 })` sem definição prévia é
  **gravado no banco**, **injetado no prompt do Captain** e **invisível no painel**. Sem aviso,
  sem estado vazio, sem contador de "N não mapeados".
- E não para no painel: **[R19 §D.3]** sem definição **não dá para filtrar**
  (`custom_attribute_filter_helper.rb:40-46`), e atributos **não entram em relatório**
  (`grep custom_attributes` em `app/services/reports/` retorna vazio).
- **[R19 §A.3]** dá o caso real interno: a tool `enviar_fotos_imovel_tool.rb` (integração Vista, em
  produção) grava `fotos_ultimo_envio_at`, `codigos_buscados` e `property_code` na conversa. Como
  não há seed de definição no repositório, **a IA sabe quais imóveis mandou e o corretor que assume
  a conversa, não**.

**[INFERÊNCIA]** Este é o item de maior retorno percebido de toda a frente de integração, e não
tem nada a ver com o widget. Enquanto ele existir, **toda** melhoria de transporte descrita neste
documento chega ao cliente como "não funcionou". A recomendação de **[R19 §recomendação 1]** —
auto-provisionar a definição como `text` marcada "não confiável" **e** renderizar os órfãos numa
seção separada "Dados recebidos do site (N)" — é a que eu subscrevo, e ela é pré-requisito
comercial de tudo o mais.

---

### 2.5 O contrato de saída — o que volta para o site

#### 2.5.1 O que existe hoje

**[CÓDIGO]** `app/javascript/widget/constants/sdkEvents.js` — **7 eventos**, exatamente:
`chatwoot:error`, `chatwoot:on-message`, `chatwoot:on-start-conversation`, `chatwoot:postback`,
`chatwoot:ready`, `chatwoot:opened`, `chatwoot:closed`.

**Isto é diferencial e precisa ser dito:** a Leadster tem **zero** eventos de `window`
**[R17 §2.11, §4.1]**. O Intercom tem 4 **[FATO, R14 §11.2]**.

**Os defeitos conhecidos do contrato de saída atual:**

| # | Defeito | Evidência |
|---:|---|---|
| 1 | `chatwoot:on-start-conversation` é **intenção**, não conclusão — dispara no clique, não na criação | **[R09 §4.5]** |
| 2 | Não existe evento de **conversa criada** com `conversation_id` | **[R09 §4.5]** |
| 3 | Não existe evento de **pre-chat submetido**, de **mensagem enviada pelo visitante**, de **CSAT respondido** nem de **campanha exibida** | **[R09 §4.5]** |
| 4 | `chatwoot:postback` é **handler órfão** — nenhum caminho do widget o emite hoje | **[R09 §4.5]** |
| 5 | `chatwoot:error` só é usado para `SET_USER_ERROR` | **[R09 §4.5]** |
| 6 | `reset()` **não confirma conclusão**: seta `resetTriggered` e **[CÓDIGO]** `IFrameHelper.js:195-197` suprime o `chatwoot:ready` seguinte | **[R17 §5.3]** |
| 7 | Nenhum **getter**: `$chatwoot.isOpen` é propriedade, não método — o site lê um campo, o que impede trocar a implementação sem quebrar integração | **[R14 §11.1, §11.3]** |

#### 2.5.2 O contrato de saída proposto

**Camada A — retorno das chamadas (novo, e é o item nº 1 da frente).** Toda chamada de dado
devolve `Promise` com resultado tipado: aceito / rejeitado por confiança / rejeitado por limite /
enfileirado / chaves sem definição correspondente. Este último caso é o que torna o gap §2.4.3
**visível para quem integra**, e é a mitigação barata que **[R17 §6, camada 4]** recomenda.

**Camada B — eventos de `window`.** Manter os 7, corrigir o `on-start-conversation` e adicionar os
que a frente de tracking exige de qualquer forma (§5): conversa **criada** com id, pre-chat
submetido, mensagem enviada pelo visitante, CSAT respondido, campanha exibida, reset concluído.

**[R09 §15.1]** registra o ponto de extensão: adicionar constante em `sdkEvents.js` e enviar
`IFrameHelper.sendMessage({ event: 'onEvent', eventIdentifier: …, data: … })`. **O SDK repassa
automaticamente** — não precisa tocar no SDK. Risco de merge **muito baixo**: o arquivo tem 7
linhas e raramente muda upstream.

**Camada C — getters (novo).** `get('state')`, `get('unread_count')`, `get('contact')`. LiveChat
(`get("customer_data")`), Intercom (`getVisitorId`), HubSpot (`status()`), Crisp (`$crisp.get`) e
tawk.to (`getStatus`) todos têm; nós não temos nenhum **[FATO, R17 §2.12]**.

**O que NÃO recomendo copiar:** injetar mensagem na conversa pelo site (Intercom
`showNewMessage`, Tidio `messageFromVisitor`/`messageFromOperator`). **[INFERÊNCIA]** É poder de
escrita no conteúdo da conversa concedido a qualquer script da página do cliente — inclusive um de
terceiro. Com o `postMessage` sem validação de origem (§4, T1), isso vira injeção de mensagem
falsa atribuída ao operador. Se um dia entrar, entra **depois** da validação de origem e **atrás**
do nível de confiança verificada.

---

### 2.6 O que o backend do cliente pode fazer — API e webhooks

#### 2.6.1 De entrada: o backend age no chat

**[R18 §B.4]** mostra que empatamos ou ganhamos em quase toda a matriz de capacidade REST: criar
contato, criar conversa, enviar mensagem como agente **e** como contato, nota privada, atualizar
atributos, etiquetar, atribuir, resolver. Tudo em `/api/v1/accounts/{id}/...` com header
`api_access_token`.

**As três lacunas reais, em ordem de impacto:**

1. **Mensagem proativa exige 3 chamadas** (achar contato → achar/criar conversa → mandar mensagem)
   contra **1** do Intercom (`POST /messages`) **[R18 §D.13]**. É açúcar sobre o que já existe, e
   é exatamente o que o integrador PME consegue implementar sem ler o modelo de dados inteiro.
2. **Autenticação sem escopo, sem expiração, sem OAuth de terceiros** — `AccessToken` polimórfico
   com dono `User` ou `AgentBot` **[R18 §D.11.1]**. O agent bot é a exceção elogiável: a jaula
   `BOT_ACCESSIBLE_ENDPOINTS` **[R18 §D.11.4]** é uma trava que a maioria dos concorrentes não tem.
3. **O agent bot não pode ler.** `messages#index` não está na jaula. Combinado com "webhook de
   agent bot só retenta em 429 e 500", **um timeout deixa o bot surdo em definitivo** — ele não
   tem como se recuperar consultando o histórico **[R18 §D.11.4]**. É o pior par de gaps do
   inventário de servidor.

#### 2.6.2 De saída: o chat avisa o backend

**O que temos e é bom** — e precisa ser dito antes da lista de problemas: assinatura HMAC-SHA256
com **timestamp no material assinado** (`"{ts}.{body}"`), que nos coloca no grupo mais forte junto
de Zendesk, HubSpot v3, Tidio e Crisp; payload rico (o `message_created` carrega conta, inbox,
conversa inteira com labels/prioridade/assignee/team e remetente numa tacada, o que dispensa a
segunda chamada); e `meta.hmac_verified` no payload **[R18 §D.12]**.

**As quatro travas, na ordem em que mordem:**

| # | Trava | Evidência | Comparação |
|---:|---|---|---|
| 1 | **Zero retentativa** no webhook de conta e de inbox. O `retry_on ... attempts: 5` do `WebhookJob` **nunca dispara** porque `Webhooks::Trigger#execute` engole a exceção antes | **[R18 §D.10.4]** — provado rodando o arquivo real com stubs | **Somos o único fornecedor medido sem retry no caminho principal** |
| 2 | **`X-Chatwoot-Delivery` está invertido**: existe onde não há retry, e falta no agent bot, que é onde há | **[R18 §0.4]** | tawk.to: *"The event Id will remain the same in case of retries"* |
| 3 | **Três dos quatro caminhos não são assinados** (inbox/canal API, agent bot, automação/macro/flow) | **[R18 §0.2]** | um endpoint que valida assinatura é obrigado a abrir exceção — e a exceção vira o buraco |
| 4 | **Filtro por inbox é letra morta**: a coluna e o enum existem, o controller aceita `inbox_id`, e **nada no código jamais grava `webhook_type: inbox_type`** | **[R18 §D.10.5]** | cliente com WhatsApp + widget + e-mail recebe **3× o tráfego que pediu** |

**[CÓDIGO]** Confirmei nesta task o catálogo de **12 eventos** em `app/models/webhook.rb:32-34` e a
unicidade de URL por conta (`:28`), que impede a configuração legítima "mesma URL, dois conjuntos
de eventos". **[R18 §D.10.1]** registra a divergência doc × código: a documentação oficial publica
**8** eventos e omite `contact_created`, `contact_updated`, `inbox_created`, `inbox_updated`.

**O que falta no catálogo, e é o que muda a venda [R18 §Trava 5]:** `conversation_resolved` existe
no barramento (`lib/events/types.rb:22-23`) e é entregue **só a agent bots** — não a webhooks de
conta. Junto dele faltam CSAT respondido, etiqueta aplicada, atribuição mudada, e o
`chat:transcript_created` do tawk.to (a conversa inteira num payload só, uma vez, depois que
acabou), que é o que economiza trabalho de quem integra com CRM.

**Um padrão que já temos em casa e não aplicamos ao caminho de saída [R18 §D.11.6]:** o webhook de
**entrada** do motor Flow (`POST /webhooks/flows/:token`) tem cap de payload, rate-limit por token
em Redis, dedupe por `Idempotency-Key` com janela configurável, e **404 genérico anti-enumeração**.
É um contrato de confiabilidade **melhor que o do nosso próprio webhook de saída**. Não é preciso
inventar o desenho — é preciso copiá-lo de um lado da casa para o outro.

#### 2.6.3 O padrão que falta e que o mercado brasileiro reconhece na hora

**[R18 §A.1.9, §Trava 10]** — o **enriquecimento síncrono** do JivoChat: quando o agente aceita a
conversa, o chat faz POST no CRM do cliente, e **a resposta HTTP** vira `contact_info` (preenche
nome/telefone/e-mail no painel), `custom_data` (linhas título/valor: saldo, plano, último pedido) e
`crm_link` (botão para o cadastro). Sem iframe, sem página nova, sem front do integrador.

Nosso equivalente é o **Dashboard App em iframe**, e **[R19 §B.2]** mostra que ele resolve outro
problema: **[R19]** `ConversationBox.vue:143-180` — o app vira **aba**, e a linha 159
(`v-show="!activeIndex"`) **esconde o `MessagesView` inteiro**. Confirmado independentemente pelo
print da documentação oficial do Chatwoot (`shots/chatwoot-dashboard-apps-doc-img3.png`).

**[INFERÊNCIA, R19 §B.2]** — a formulação é precisa e vale repetir: *"um app que esconde a conversa
não é contexto, é destino"*. Intercom (Canvas Kit) e Zendesk (`ticket_sidebar`) colocam o card **ao
lado** justamente porque contexto só serve enquanto se lê a mensagem. Nossa arquitetura de
Dashboard App resolve "integrar sistema externo" e **não resolve** "dar contexto ao atendente" —
dois problemas diferentes compartilhando o mesmo recurso.

---

### 2.7 Resumo: o que já existe × o que é novo

| Bloco do contrato | Já existe | Existe com defeito | Novo |
|---|---|---|---|
| **Identidade** | `identifier`, `email`, `name`, `avatar_url`, `custom_attributes` | `phone_number` (não passa sozinho), dedupe por hash incompleto, reenvio pós-boot assimétrico | `signed_up_at`, objeto `company`, `language` na identidade |
| **Contexto de conversa** | atributos livres | substitui em vez de mesclar; perde-se antes de existir conversa | `page_title`, `landing_page`, `entry_referrer` |
| **Eventos do site** | — | `pushEvent` existe interno e não exposto | `track(name, props)` |
| **Autenticação** | HMAC-SHA256 por inbox; `hmac_verified` propagado até a IA | dois furos no enforcement; sem expiração; atributos fora da assinatura | JWT com `exp`; credencial por callback; três estados de enforcement; confiança por atributo |
| **Vias de passagem** | API JS; query string anexada às chamadas | `postMessage` aberto; GTM hostil | `data-*` de configuração; fila pré-boot; parser de UTM |
| **Persistência** | 4 destinos, tipagem com 8 formatos, regex, chaves reservadas | assimetria merge/substitui; sem limite de quantidade; sem limite no contato | selo de origem/confiança; auto-provisionamento de definição |
| **Saída para o site** | 7 eventos de `window` | `on-start-conversation` é intenção; `postback` órfão; `reset` mudo | retorno de chamada; eventos de conclusão; getters |
| **Servidor → backend** | 12 eventos; HMAC com timestamp; payload rico; `hmac_verified` | sem retry; delivery-id invertido; 3 caminhos sem assinatura; filtro por inbox morto | `conversation_resolved` e CSAT no webhook de conta; log de entrega e replay; mensagem proativa em 1 chamada |
| **Backend → chat** | REST completa; canal API nos dois sentidos; jaula do agent bot | sem escopo/expiração; bot não pode ler | enriquecimento síncrono; card lateral no lugar de aba |

---

## 3. Matriz de paridade — frente de integração

Legenda: ✅ suportado com mecanismo próprio · 🟡 possível de forma indireta ou com defeito ·
❌ não existe · **[proposto]** = coluna do contrato deste documento, não implementado.

A coluna "Zendesk/HubSpot" traz o **melhor dos dois** na linha, com o nome entre parênteses; onde
divergem, registro os dois.

| # | Capacidade de integração | Intercom | Zendesk / HubSpot | Leadster | **ChatSPX hoje** | **ChatSPX proposto** |
|---:|---|:--:|:--:|:--:|:--:|:--:|
| 1 | ID interno do sistema do cliente | ✅ `user_id` | ✅ `external_id` (Z) | ❌ | ✅ `identifier` | ✅ |
| 2 | Nome / e-mail | ✅ | ✅ | ❌ | ✅ | ✅ |
| 3 | Telefone | ✅ | 🟡 (H, via CRM) | ❌ | 🟡 não passa sozinho | ✅ E.164 |
| 4 | Data de cadastro | ✅ `created_at` | ❌ | ❌ | ❌ | ✅ `signed_up_at` |
| 5 | Objeto de empresa estruturado | ✅ `company` | 🟡 (H, CRM) | ❌ | 🟡 `company_name` string | ✅ |
| 6 | Várias empresas | ✅ `companies` | ❌ | ❌ | ❌ | ❌ (fora de escopo, §2.1.2) |
| 7 | Atributos livres no contato | ✅ | ✅ | ❌ | ✅ merge | ✅ |
| 8 | Atributos livres na conversa | 🟡 | ✅ `conversationFields` (Z) | ❌ | 🟡 substitui e some antes da conversa | ✅ merge + fila |
| 9 | Merge × substituição explícitos | ❌ | ❌ | ❌ | 🟡 acidental e invertido | ✅ dois verbos |
| 10 | Tags / segmentos | 🟡 | ✅ `conversationTags` (Z) | ❌ | ✅ `setLabel` | ✅ + limite de 10 |
| 11 | Eventos tipados do site | ✅ `trackEvent` | ✅ (H, behavioral events) | ❌ | ❌ (`pushEvent` interno) | ✅ `track()` |
| 12 | Ler o estado de volta | ✅ `getVisitorId` | ✅ `status()` (H) | ❌ | ❌ | ✅ getters |
| 13 | Confirmação de recebimento (callback/Promise) | 🟡 | ✅ `updateUser(cb)` (Z) | ❌ | ❌ **em 6 de 7 métodos** | ✅ **em todos** |
| 14 | Fila de chamadas antes do boot | ✅ `i.q = []` | ✅ (H, `loadImmediately`) | ❌ | 🟡 reenvio assimétrico (D1) | ✅ |
| 15 | Declarar identidade antes da carga | ✅ | ✅ `hsConversationsSettings` (H) | ❌ | ❌ | ✅ via fila |
| 16 | Encerrar sessão / logout | ✅ `shutdown` | ✅ `logoutUser` (Z) / `clear` (H) | ❌ | ✅ `reset()` | ✅ + confirmação |
| 17 | Verificação criptográfica de identidade | ✅ JWT HS256 | ✅ JWT (Z) / token 12 h (H) | ❌ | ✅ HMAC-SHA256 | ✅ JWT + HMAC legado |
| 18 | Credencial com expiração | ✅ `exp` | ✅ `exp` honrado (Z) | — | ❌ **nenhuma** | ✅ |
| 19 | Atributos **dentro** da assinatura | ✅ (no JWT) | ✅ (Z) | — | ❌ | ✅ |
| 20 | Credencial obtida por callback (anti-CDN) | ❌ | ✅ `loginUser(cb)` (Z) | — | ❌ | ✅ |
| 21 | Enforcement com estado intermediário | ✅ 3 modos | 🟡 | — | ❌ booleano **com 2 furos** | ✅ 3 estados |
| 22 | Bloquear escrita de atributo por origem | ✅ "Require verified updates" | ❌ | — | ❌ | ✅ |
| 23 | Limites publicados (quantidade/tamanho) | ✅ 250 / 255 | ✅ (Z, 11 tipos, 2000 opções) | ❌ | 🟡 1500/chave só na conversa, **sem teto de quantidade** | ✅ 50 chaves / 1500 |
| 24 | `data-*` de configuração no script | ❌ | ❌ | ❌ | ❌ | ✅ |
| 25 | Passagem por URL (contexto não sensível) | 🟡 UTM | 🟡 | ✅ **é a única via deles** | 🟡 query anexada, não parseada | ✅ allowlist |
| 26 | Validação de origem no `postMessage` | ❔ | ❔ | ❌ (`targetOrigin: '*'`) | ❌ **nos dois lados** | ✅ |
| 27 | Eventos de `window` para o site | ✅ 4 | ❔ | ❌ **zero** | ✅ **7** | ✅ 12+ |
| 28 | Evento de conversa criada com id | ✅ | ✅ (H, `conversationStarted`) | ❌ | ❌ | ✅ |
| 29 | Evento de CSAT respondido | ✅ `conversation.rating.added` | ✅ (Z, via trigger) | ❌ | ❌ | ✅ |
| 30 | Webhook de saída assinado | ✅ SHA-1 | ✅ SHA-256+ts (Z) / v3 (H) | ❔ | ✅ **SHA-256 + timestamp** (só o de conta) | ✅ nos 4 caminhos |
| 31 | Retentativa no webhook | ✅ | ✅ | ❔ | ❌ **zero** | ✅ escada tipo Tidio |
| 32 | Chave de idempotência estável entre retries | ✅ `id` + `delivery_attempts` | ✅ `attemptNumber` (H) | ❔ | 🟡 forma certa, comportamento errado | ✅ |
| 33 | Filtro de webhook por inbox/canal | ❌ | ✅ (Z, via trigger) | ❔ | ❌ **letra morta** | ✅ |
| 34 | Log de entregas + replay | ✅ | ✅ (Z, 7 dias) | ❔ | ❌ **nada** | ✅ |
| 35 | Rotação de segredo do webhook | ❔ | ❔ | ❔ | ❌ (destruir e recriar) | ✅ |
| 36 | Mensagem proativa em 1 chamada | ✅ `POST /messages` | 🟡 (H) | ❌ | 🟡 **3 chamadas** | ✅ |
| 37 | Enriquecimento síncrono pela resposta do webhook | ❌ | ❌ | ❌ | ❌ | ✅ (padrão JivoChat) |
| 38 | Contexto ao lado da conversa (não no lugar) | ✅ Canvas Kit | ✅ `ticket_sidebar` (Z) | ❌ | ❌ **aba esconde a conversa** | ✅ card lateral |
| 39 | Payload do app de terceiro assinado | ✅ `X-Body-Signature` | ✅ ZAF (Z) | — | ❌ | ✅ |
| 40 | Atributo sem definição aparece no painel | ✅ | ✅ | — | ❌ **invisível** | ✅ órfãos em seção própria |
| 41 | Presença em Zapier / Make | ✅ 18 triggers / 16 actions | ✅ | ❔ | ❌ **404 no Zapier** | 🟡 (fora do escopo técnico) |
| 42 | `hmac_verified` exposto no payload | ❌ | ❌ | — | ✅ **só nós** | ✅ |

**Placar da frente [INFERÊNCIA], contando 🟡 como meio ponto sobre 42 linhas:**

| Coluna | ✅ | 🟡 | ❌ / ❔ | Leitura |
|---|---:|---:|---:|---|
| Intercom | 25 | 4 | 13 | referência em identidade e catálogo |
| Zendesk/HubSpot | 24 | 5 | 13 | o melhor desenho de token (Z) e de eventos de conversa (H) |
| Leadster | 2 | 1 | 39 | **não disputa esta frente** — o produto deles resolve captura, não integração |
| **ChatSPX hoje** | **13** | **11** | **18** | superfície razoável, contrato quebrado |
| **ChatSPX proposto** | **38** | **2** | **2** | à frente do Intercom em 6 linhas (18, 20, 22, 37, 40, 42) |

**Três leituras que a tabela sustenta e que valem para a decisão:**

1. **A Leadster não é o benchmark desta frente.** Com 2 ✅ em 42 linhas, comparar-se a ela aqui é
   comparar-se ao piso. **[R17 §2.11]** é categórico: na Leadster, *"um usuário logado no site do
   cliente não pode ser identificado no chat sem expor os dados dele na barra de endereço"*.
   **Ganhamos por larga margem, e o gap deles não é de UI — é de arquitetura.**
2. **Onde perdemos, perdemos para Intercom e Zendesk**, que são as referências globais. As seis
   linhas em que o contrato proposto passa à frente deles (expiração + callback + confiança por
   atributo + enriquecimento síncrono + órfãos visíveis + `hmac_verified` exposto) são todas
   **baratas em relação ao valor percebido**, e três delas já têm infraestrutura em casa.
3. **A linha 42 é a única em que já estamos sozinhos na frente**, e ninguém sabe disso — nem
   comercial, nem documentação.

---

## 4. Segurança — modelo de ameaça do handshake

Cinco ameaças, como pedido. Para cada uma: o cenário, onde ele **para** hoje (com precisão), o que
resta aberto, e a mitigação. Mantenho separado o que é **[CÓDIGO]** lido do que é **[INFERÊNCIA]**
sobre consequência. **Nada aqui foi explorado.**

---

### T1 — Spoof de identidade: personificar outro visitante

**Cenário canônico [R17 §3.3]:** a vítima conversou com o suporte de `loja.com.br` e mandou número
do pedido, endereço e print de fatura. O atacante abre o site em aba anônima, chama o método de
identificação pelo console passando **o e-mail da vítima**, e — se o servidor aceitar sem prova —
a sessão do atacante é vinculada ao registro da vítima.

**Onde isso para hoje, com precisão.** **[CÓDIGO]** `app/controllers/api/v1/widget/base_controller.rb:10-17`:
o escopo de leitura é do **`contact_inbox`** (a sessão), não do contato — **a menos que**
`hmac_verified` esteja marcado. A sessão do atacante é um `contact_inbox` novo, sem conversas.
**Então o histórico da vítima não é servido.**

**Isto é uma proteção real e é ponto forte do desenho.** Mas tem preço e limite, e é aqui que a
advertência de rigor da onda se aplica com força:

- **O preço:** é exatamente por isso que, **sem** HMAC, o mesmo cliente que troca de navegador
  **não vê a própria conversa anterior**. A continuidade entre dispositivos é o prêmio que a
  verificação libera — o motivo **comercial** do HMAC, não só o de segurança.
- **O limite, dito sem achatar:** *ler a conversa alheia* está bloqueado pelo escopo do
  `contact_inbox`; ***assumir o registro de contato alheio* não está**, quando o enforcement não
  pega. **[R17 §3.3]** — o `ContactIdentifyAction` faz merge por e-mail, então a sessão do atacante
  passa a **apontar** para o contato da vítima. **[INFERÊNCIA]** As consequências (poluir o cadastro
  com dados forjados, herdar `custom_attributes`, e a próxima mensagem do atacante chegar ao
  atendente **com o nome e o histórico de cadastro da vítima na ficha lateral**) são reais e não
  dependem de ler a conversa antiga.

**E o enforcement não pega em dois caminhos** (§2.3.2, confirmados **[CÓDIGO]** nesta task):
`PATCH /widget/contact` não tem `validate_hmac`, e o *early return* da linha 59 desliga a
verificação quando há `custom_attributes` sem `identifier`.

**Mitigação, em ordem:**
1. **Fechar os dois furos** — é correção de coerência, não feature. Prioridade máxima da frente
   inteira, e **não depende de nenhuma decisão de front**.
2. Enforcement em três estados, para poder ligar em cliente com tráfego (§2.3.4).
3. JWT com `exp`, que limita a janela de um par `(identifier, hash)` vazado — hoje ele vale **para
   sempre**, até rotacionar o `hmac_token` do widget inteiro, o que invalida **todos** os usuários
   de uma vez **[R17 §3.2, §3.6]**.

---

### T2 — Session fixation e leitura de conversa alheia pela ponte `postMessage`

**[R17 §4.3]**, confirmado **[CÓDIGO]** nesta task em `app/javascript/sdk/IFrameHelper.js:104-117`:

- O SDK escuta `window.onmessage` e o **único filtro** é o prefixo `chatwoot-widget:` — que é
  público e está no bundle. **Não há checagem de `e.origin`.**
- O handler é atribuído com `window.onmessage = ...`, o que **sobrescreve** qualquer handler
  `onmessage` que o site do cliente já tenha.
- Do lado do widget, `widget/helpers/utils.js:18-21` também não valida origem, e a saída
  (`:8-13`) usa `targetOrigin: '*'`.
- **[CÓDIGO]** `IFrameHelper.js:213-215` — entre os handlers registrados está `setAuthCookie`, que
  chama `updateAuthCookie(widgetAuthToken, ...)`.

**[INFERÊNCIA]** Qualquer script já em execução na página do cliente — tag manager, pixel de mídia,
plugin de CMS, outro widget — tem referência a `window` e ao `contentWindow` do iframe, e pode
(a) enviar `set-user` ao **iframe**, identificando o visitante com dados que o site não autorizou;
e (b) enviar `setAuthCookie` ao **parent**, fazendo o SDK **gravar o cookie `cw_conversation`** com
um valor recebido. O segundo é o formato clássico de *session fixation*. **Não testei.**

**Contexto de risco, para não inflar:** isto **não é atacável de fora** — exige código já rodando
na página do cliente. Mas "código de terceiro rodando na página do cliente" é a situação **normal**
de qualquer site comercial com GTM, e o modelo de ameaça de um widget de chat precisa contá-la.

**Mitigação:** validar `e.origin` nos dois lados e trocar o `targetOrigin: '*'` da saída do widget.
**[R17 §6, camada 3]** registra o detalhe que torna isto quase gratuito: **o SDK já sabe a origem
correta** — ele a calcula em `IFrameHelper.js:96-98` para **enviar**, e simplesmente não a usa para
**receber**. Adicionalmente: parar de usar `window.onmessage =` (usar `addEventListener`), para
não sequestrar o handler do site.

**[R14 §15.6]** reforça pelo contraexemplo: "não copiar `postMessage(…, '*')` sem checar origin
(Leadster) — vaza os dados do lead para qualquer parent frame".

---

### T3 — Injeção de atributo: escrever no cadastro sem autorização do site

**Dois vetores distintos, e não os confundo:**

**Vetor A — pela API pública, por qualquer script da página.** **[R19 §C.3.3, elos 1-5]**:
`setConversationCustomAttributes` é chamável por qualquer JS da página — **inclusive pelo console
do próprio visitante**. A autenticação é `website_token` (público, está no snippet) + o JWT do
widget no cookie do visitante. **Nenhum HMAC** para atributos de conversa. Strong params aceitam
**qualquer chave** (`custom_attributes: {}`), e a gravação é `update!` com **substituição total**.

**Vetor B — pelo furo 1 do enforcement.** `setCustomAttributes` do contato usa
`PATCH /widget/contact` **[CÓDIGO]** `widget/api/contacts.js:18-22`, que não tem `validate_hmac`.

**Limites que existem hoje:** 1500 caracteres por chave **só na conversa**; **nenhum** no contato;
**nenhum teto de quantidade de chaves** em lugar nenhum **[R19 §C.3.3, elo 6]**.

**Mitigação:**
1. **Coluna de confiança na `CustomAttributeDefinition`** (§2.3.5) + comportamento "ignora
   silenciosamente" para escrita bloqueada — é literalmente o desenho do Intercom, cuja
   documentação diz *"The data is ignored"* **[FATO, R19 §C.3.2]**.
2. Teto de quantidade de chaves vindas do widget (50) e extensão da validação de comprimento ao
   contato.
3. Semântica de merge (em vez de substituição) na conversa, o que impede que uma chamada apague o
   contexto legítimo escrito por outra.

---

### T4 — PII em log, em cache e em lugar errado

**Quatro superfícies distintas, medidas em relatórios diferentes. Não as achato:**

| Superfície | O que acontece | Evidência |
|---|---|---|
| **IP no painel** | exibimos **IP bruto** para qualquer agente, sob o rótulo `CONTACT_PANEL.IP_ADDRESS` | **[R19 §A.5]** `ConversationInfo.vue:43,78-81`. O Intercom decidiu o oposto: *"we do not provide the IP addresses of users/visitors"* **[FATO]** |
| **Segredo do webhook em texto claro** | `GET /api/v1/accounts/{id}/webhooks` devolve **todos os segredos** | **[R18 §D.10.3]** `_webhook.json.jbuilder:6`. Só administradores; a auditoria enterprise exclui o campo; **não há endpoint de rotação** |
| **Dashboard App recebe tudo** | conversa **inteira** + contato **inteiro** para o iframe de terceiro, sem seleção de campos e **sem assinatura** | **[R19 §C.3.4]** `Frame.vue:33-39` |
| **Credencial em HTML cacheado** | um par `(identifier, identifier_hash)` que vaze **vale para sempre** (sem `exp`) | **[R17 §3.6]** |
| **Retenção de visitante** | **[R19 §A.5]** não encontrou política de expurgo equivalente aos 9 meses do Intercom | **[FATO]** Intercom: *"We will automatically delete the entire record and event history of visitors who have not visited your site in 9 months"* |

**Mitigação:** mascarar IP por padrão (e restringir a exibição bruta a um perfil); rotação de
segredo de webhook; payload delimitado **e assinado** para o Dashboard App (o Intercom usa
HMAC-SHA256 em `X-Body-Signature`) e validação de `event.origin` no listener de refetch
(**[R19 §C.3.4]** `Frame.vue:62-67`); `exp` na credencial; política de expurgo de visitante.

**A lista negativa de §2.1.6 é parte da mitigação, não documentação.** **[R19 §A.5]** registra o
ponto jurídico que o time comercial esquece: a LGPD exige consentimento *"livre, informado e
inequívoco"* para *"finalidade determinada"*, e um banner de cookies genérico **não cobre** enviar
CPF e simulação de financiamento para dentro do chat **[FATO + INFERÊNCIA]**.

---

### T5 — Prompt injection pelo canal do site

**A cadeia, elo a elo [R19 §C.3.3]** — cada elo é medido lá; a conclusão de ponta a ponta é
inferência, e **não foi executada**:

1. `setConversationCustomAttributes` é chamável por qualquer JS da página (`sdk.js:157-165`);
2. vira `postMessage` para o iframe, que despacha para a store (`App.vue:304-309`);
3. autenticação é `website_token` + JWT do widget — **nenhum HMAC**;
4. strong params aceitam **qualquer chave** (`conversations_controller.rb:100`);
5. grava com **substituição total, sem allowlist** (`:68`);
6. único limite: 1500 caracteres por chave; **sem teto de quantidade**;
7. o snippet do prompt interpola **cada par** como linha `- chave: valor`, **sem delimitador, sem
   escape** (`prompts/snippets/conversation.liquid:9-13`);
8. **a conversa sempre entra no contexto** — a flag `feature_contact_attributes` gateia **só o
   contato** (`agentable.rb:19-25`);
9. isso é renderizado dentro do **system prompt** do agente (`prompts/runtime_context.liquid:4-20`).

**[INFERÊNCIA, R19]** Encadeando 1→9: texto arbitrário controlado pelo lado do site chega ao system
prompt do agente de IA sem sanitização, sem delimitação e **sem limite de volume** — porque o teto
é por chave e não há teto de chaves. É vetor de custo e de esvaziamento de contexto, não só de
injeção.

**Agravante assimétrico, que é o mais anômalo:** a flag `feature_contact_attributes` nasce
**desligada**, o que é bom para o contato — e torna ainda mais estranho que **a conversa não tenha
controle nenhum**, sendo ela justamente a que o site escreve com mais liberdade.

**Contexto externo:** prompt injection é **#1 no OWASP Top 10 for LLM Applications 2025**, e a
variante que importa aqui é a **indireta** — instruções escondidas em conteúdo que o sistema
ingere depois, com campos de CRM citados explicitamente como vetor **[FATO, R19 §C.3.1]**.

**Mitigação, em ordem de retorno [R19 §recomendação 4]:**
1. **Allowlist** — só atributos com definição cadastrada **e** marcados como aptos entram no
   prompt. Hoje vai tudo.
2. **Delimitação explícita** do bloco de atributos como *dado*, não como instrução.
3. **Simetria**: a conversa precisa de um gate equivalente ao `feature_contact_attributes`.
4. Teto de quantidade de chaves (T3).

**[INFERÊNCIA, R19]** (1) e (2) resolvem a maior parte do risco com custo baixo. Dual-LLM é a
resposta estrutural do OWASP, mas é desproporcional para o estágio atual.

---

### Resumo do modelo de ameaça

| # | Ameaça | Bloqueado hoje? | Mitigação-chave | Depende de front? |
|---:|---|---|---|:---:|
| T1 | Spoof de identidade | **Parcial** — leitura de conversa alheia bloqueada; assumir o cadastro **não** | fechar os 2 furos; 3 estados; `exp` | **não** |
| T2 | Session fixation via `postMessage` | **Não** | validar `e.origin` nos 2 lados; `targetOrigin` real; `addEventListener` | **não** |
| T3 | Injeção de atributo | **Não** | confiança por atributo; teto de chaves; merge | **não** |
| T4 | PII em log/cache/iframe | **Não** | mascarar IP; assinar payload do app; rotação; expurgo | parcial |
| T5 | Prompt injection | **Não** | allowlist + delimitação + simetria com o contato | **não** |

**[INFERÊNCIA] A leitura que mais importa para o planejamento:** quatro das cinco mitigações-chave
**não dependem de nenhuma decisão de front end**. Elas podem — e devem — andar em paralelo ao
redesenho visual do widget, e não competem pelo mesmo recurso. Um redesenho que só troque a
aparência deixa as cinco de pé.

---

## 5. Como isso se conecta com o tracking (frente C0–C9)

> A formulação que organiza esta seção: **origem e identidade são o mesmo problema visto de dois
> lados.** A frente de tracking pergunta *"de onde veio essa pessoa?"*; a frente de integração
> pergunta *"quem é essa pessoa?"*. As duas respondem com o mesmo dado, pelo mesmo cano, e
> gravam no mesmo lugar. Fazer as duas sem coordenar é construir dois canos paralelos.

### 5.1 Onde as duas frentes se encontram — quatro pontos de contato

**Ponto 1 — O coletor de origem (C2) é o mesmo componente que a fila pré-boot precisa.**

**[R10 §4.1, C2]** especifica que o coletor tem de morar no **SDK (parent)**, porque o widget roda
em iframe de outra origem e **nunca** enxerga `window.fbq` nem `window.dataLayer` do cliente. A
fila pré-boot (§2.0, P2) mora **exatamente no mesmo lugar** e resolve o mesmo problema temporal:
capturar coisas que acontecem **antes** de o widget existir. **[INFERÊNCIA]** Construir a fila sem
pensar no coletor significa reescrevê-la quando o coletor chegar; construir os dois juntos custa
quase o mesmo que construir um.

**Ponto 2 — O contrato de eventos é um só.**

**[R10 §4.1, C3]** define 12 eventos `chatspx_*`. O contrato de saída desta spec (§2.5.2) define os
eventos de `window` que faltam. **São a mesma lista vista de dois ângulos**: `chatspx_lead` precisa
de um evento de "contato passou a ter e-mail ou telefone"; `chatspx_prechat_submitted` precisa de
"pre-chat submetido"; `chatspx_conversation_started` precisa de "conversa criada com id" — e os
três estão na lista de lacunas de **[R09 §4.5]**.

**[R10 §4.1, C3]** é explícito sobre a dependência: *"hoje não existe evento de conversa criada com
`conversation_id`, nem de pre-chat submetido, nem de CSAT respondido. Sem esses eventos, não há o
que disparar"*. **Ou seja: a frente de tracking está bloqueada por um item desta frente.**

**Ponto 3 — A persistência é o mesmo jsonb, com a mesma armadilha.**

**[R10 §4.1, C2]** recomenda gravar `first_utm_*` (write-once) e `last_utm_*` em
`contact.custom_attributes` / `conversation.custom_attributes` — **os mesmos destinos de §2.4**. E
herda o mesmo gap **[R19 §D.3]**: sem `CustomAttributeDefinition` provisionada, o `first_utm_source`
gravado **não aparece no painel e não é filtrável**. Construir o coletor sem provisionar as
definições produz exatamente o sintoma que motivou esta onda inteira: *"os dados chegam, o painel
não muda, e a conclusão do cliente é 'não funcionou'"*.

**Ponto 4 — A rota de menor atrito de merge é a mesma.**

**[R09 §15.5]**, confirmado **[CÓDIGO]** nesta task: `app/controllers/api/v1/widget/base_controller.rb:31-46`
já monta `custom_attributes: permitted_params[:custom_attributes].presence || {}` (linha 44) na
criação da conversa, e `conversations_controller.rb:97-100` já os aceita no `permit`. **O canal para levar dado
novo do widget ao servidor na criação da conversa já existe e não conflita com o upstream.** Serve
igualmente para atributo de negócio (esta frente) e para UTM (a frente de tracking).

### 5.2 O que NÃO pode ser feito duas vezes

Esta é a parte operacional da seção. Seis itens, cada um com o dono proposto:

| # | Item | Dono | Por quê não duplicar |
|---:|---|---|---|
| 1 | **Fila pré-boot / coletor no SDK** | **Integração** (C2 consome) | Mesmo componente, mesmo arquivo, mesmo problema temporal. Duas filas = duas ordens de drenagem = bug de corrida |
| 2 | **Contrato de eventos** | **Tracking (C3)** define nomes; **Integração** expõe no `window` | Nome de evento é contrato público. Dois vocabulários (`chatwoot:on-*` e `chatspx_*`) para o mesmo fato é dívida permanente de documentação |
| 3 | **Método `track()`** | **Integração** define a API; **Tracking** consome | O `track()` do site (§2.1.4) e o evento de negócio do pixel são a mesma chamada. Dois métodos = o cliente chama o errado |
| 4 | **Provisionamento de `CustomAttributeDefinition`** | **Integração** | Se cada frente provisionar as suas, o painel do cliente vira lixo. Um mecanismo, com namespace por origem |
| 5 | **Parser de UTM** | **Tracking (C0)** | C0 parseia o `referer` **já gravado**, retroativamente. Não faz sentido a frente de integração parsear de novo no coletor |
| 6 | **Modelo de consentimento** | **Tracking (C7)** | O `setConsent` do C7 governa disparo de tag. A frente de integração **não deve** ter um segundo modelo de consentimento — deve consultar o mesmo estado |

**Uma ordem que decorre disso, e é a única imposição de sequência entre as frentes
[INFERÊNCIA]:** **C0 é independente e vem primeiro.** **[R10 §4.1]** é categórico: *"é o único item
que entrega valor sem depender de credencial de terceiro, sem tocar no widget e sem risco de
merge"*, e entrega "de onde veio esse lead" para **100% da base, retroativamente**. Ele não colide
com nada desta spec. **Tudo o mais da frente de tracking que toca o navegador (C2, C3, C4) deve
esperar a Fase 1 desta frente**, porque herda os quatro defeitos de contrato se não esperar.

### 5.3 Uma correção de premissa que a junção das duas frentes revela

**[R09 §6.5]** e **[R10 §4.0]** já registram, mas vale destacar porque é o tipo de coisa que vira
conclusão errada num resumo: **`referer` no nosso schema NÃO é o `document.referrer` do navegador.**
É a URL da página onde o visitante estava **no momento em que enviou a primeira mensagem**.

**[R19 §B.3]** fecha o raciocínio com a consequência exata: se o visitante entrou por um anúncio,
navegou cinco páginas e só então abriu o chat, **a origem real da campanha se perdeu**. E a ironia
medida: o widget **já detecta toda navegação**, inclusive em SPA, via `MutationObserver`
(`DOMHelpers.js:49-74`) — e o resultado só dispara campanha e **sobrescreve uma variável global**.
Não existe tabela de páginas visitadas no schema.

**[INFERÊNCIA]** A instrumentação existe e funciona; falta persistir. E o modelo barato já foi
identificado: o **agregado** do Intercom (primeira vez, última vez, contagem) em vez de log
completo, guardando as últimas ~20 páginas e, separadamente, a **landing page real com os UTMs**
**[R19 §recomendação 5]**. Isso conserta simultaneamente o gap de atribuição da frente de tracking
e o campo `landing_page`/`entry_referrer` desta spec (§2.1.3).

---

## 6. Faseamento

Três fases. Esforço **relativo** (P/M/G), nunca em horas. "Critério de pronto" é o que precisa ser
**verificável** para a fase estar encerrada — e verificável significa que alguém consegue conferir
sem acreditar em ninguém.

**Convenção de risco de merge com o upstream**, ancorada em **[R09 §15]**:
**Nenhum** = código novo isolado · **Baixo** = usa ponto de extensão declarado (`additional_attributes`,
`sdkEvents.js`, `custom_attributes` já permitidos) · **Médio** = toca arquivo que conflita
(`App.vue:258-345`, `sdk.js`, `base_controller.rb permitted_params`) · **Alto** = toca estrutura
compartilhada.

---

### Fase 1 — Fechar a porta e dar voz ao contrato

> Nada aqui é feature. É tudo coerência: o que o produto já promete e não cumpre. **Nenhum item
> desta fase depende de decisão de design do widget** — pode andar em paralelo ao redesenho visual.

| # | Item | Esforço | Depende de | Risco de merge |
|---:|---|:---:|---|---|
| 1.1 | Fechar o furo do `PATCH /widget/contact` (sem `validate_hmac`) | **P** | — | **Baixo** — 1 `before_action` + revisão de `permitted_params` |
| 1.2 | Corrigir o *early return* da linha 59 (`custom_attributes` sem `identifier`) | **P** | — | **Baixo** |
| 1.3 | Validar `e.origin` nos dois lados do `postMessage`; trocar `targetOrigin: '*'`; parar de usar `window.onmessage =` | **P** | — | **Médio** (`IFrameHelper.js`, `widget/helpers/utils.js`) — **[R10 §7, Q8]** recomenda oferecer este patch ao upstream: se aceito, some do nosso diff de graça |
| 1.4 | Retorno (`Promise`) em todos os métodos de dados + `chatwoot:error` com motivo | **M** | — | **Médio** (`sdk.js` + a cadeia de `else if` em `App.vue`) |
| 1.5 | Fila pré-boot, drenada com o **mesmo formato** da chamada tardia (resolve D1) | **M** | 1.4 | **Médio** — **[R09 §15.4]**: refatorar a cadeia de `else if` para mapa **antes** de estender |
| 1.6 | `setConversationCustomAttributes` antes de existir conversa: enfileirar e aplicar na criação, em vez de 404 mudo | **M** | 1.5 | **Baixo** — o `custom_attributes` do `POST /widget/conversations` **já é aceito** **[CÓDIGO]** |
| 1.7 | Nenhuma exceção não capturada (compatibilidade com GTM) | **P** | 1.4 | **Médio** |
| 1.8 | Teto de quantidade de chaves (50) + validação de comprimento no contato | **P** | — | **Baixo** |
| 1.9 | Retry no webhook de saída + `X-Chatwoot-Delivery` estável entre retentativas | **M** | — | **Baixo** — o `retry_on` já está declarado; o que falta é deixar a exceção subir |
| 1.10 | **Teste dirigido de D1**: `setUser` chamado antes do `loaded` | **P** | — | **Nenhum** (teste) |

**Critério de pronto, verificável:**

- Com `hmac_mandatory` (ou o estado `obrigatório`) ligado, uma requisição a `PATCH /widget/contact`
  com `{email: "<alvo>"}` e uma a `set_user` com `{email, custom_attributes}` sem `identifier`
  **não alteram** o contato — comprovado por teste automatizado em ambiente isolado, não por
  inspeção de código.
- Uma mensagem `chatwoot-widget:{"event":"setAuthCookie",...}` postada de outra origem **não**
  grava cookie.
- Chamar cada um dos 7 métodos de dados com o widget ainda não carregado e conferir que **todos**
  são aplicados depois, com o mesmo efeito da chamada tardia.
- Cada método devolve `Promise` que resolve com resultado tipado, e o cenário de erro dispara
  `chatwoot:error` com motivo legível.
- Colar as chamadas numa tag de HTML customizado do GTM e confirmar que uma chamada malformada
  **não derruba** as tags seguintes do contêiner.
- Um webhook apontado para endpoint que devolve 500 registra **N tentativas** com o **mesmo**
  `X-Chatwoot-Delivery`.
- O teste de D1 produz um veredito escrito: funciona, falha ruidosamente, ou falha em silêncio.

---

### Fase 2 — Tornar o dado visível, tipado e confiável

> Aqui o cliente começa a **ver** o resultado. É a fase de maior retorno percebido, e a maior parte
> dela é **painel do agente**, não widget.

| # | Item | Esforço | Depende de | Risco de merge |
|---:|---|:---:|---|---|
| 2.1 | Auto-provisionar `CustomAttributeDefinition` para chave nova vinda do widget (tipo `text`, marcada não confiável) | **M** | 1.4 | **Baixo** — model + service novos |
| 2.2 | Seção "Dados recebidos do site (N)" no painel, separada dos atributos curados | **M** | 2.1 | **Médio** (`CustomAttributes.vue`) |
| 2.3 | Coluna de **origem/confiança** na `CustomAttributeDefinition` + selo no painel | **M** | 2.1 | **Baixo** (migration + coluna nova) |
| 2.4 | Enforcement por atributo ("exige origem verificada" → escrita ignorada) | **M** | 2.3 | **Baixo** |
| 2.5 | Allowlist + delimitação do bloco de atributos no prompt da IA; gate para a conversa (simetria com `feature_contact_attributes`) | **M** | 2.3 | **Baixo** (`enterprise/`, arquivos nossos) |
| 2.6 | Três estados de enforcement (`desativado`/`observado`/`obrigatório`) | **M** | 1.1, 1.2 | **Baixo** |
| 2.7 | JWT como formato adicional (`sub`, `exp`, atributos no payload), HMAC mantido como legado | **M** | 2.6 | **Baixo** — `Widget::TokenService` já existe **[CÓDIGO]** |
| 2.8 | Reordenar o painel: contexto de negócio antes de navegador/SO/IP; bloco do site aberto por padrão; não misturar as 6 linhas técnicas na mesma cota de 5 itens | **M** | 2.2 | **Médio** (`useUISettings.js`, `ContactPanel.vue`) |
| 2.9 | Mascarar IP por padrão | **P** | — | **Baixo** |
| 2.10 | `conversation_resolved` + CSAT respondido + etiqueta aplicada no webhook de conta | **M** | — | **Baixo** — `conversation_resolved` **já existe no barramento** |
| 2.11 | Log de entregas de webhook + replay (retenção 7 dias, padrão do mercado) | **M** | 1.9 | **Nenhum** |

**Critério de pronto, verificável:**

- `setCustomAttributes({carrinho_valor: 4200})` sem cadastro prévio: o valor aparece no painel do
  agente **na mesma sessão**, dentro da seção de dados do site, com selo de origem — validado em
  navegador real, **light e dark** (o Playwright com DOM walker é a técnica de casa para isto).
- Um atributo marcado "exige origem verificada" e escrito pelo widget sem credencial válida **não**
  altera o valor, e o painel mostra que a tentativa foi ignorada.
- Uma conversa cujo `custom_attributes` contém texto com instruções não altera o comportamento do
  agente de IA — verificado com **dry run**, nunca contra IA de cliente em produção.
- Ligar o estado `observado` numa inbox com tráfego real e obter a lista de identificações não
  verificadas **sem quebrar nenhuma sessão**.
- Um webhook de conta recebe `conversation_resolved` e o evento de CSAT; a tela de log mostra a
  entrega e permite reenviar.

---

### Fase 3 — Ampliar a superfície

> Só agora entram métodos e campos novos. Antes disso, cada método novo herdaria os defeitos que a
> Fase 1 corrigiu.

| # | Item | Esforço | Depende de | Risco de merge |
|---:|---|:---:|---|---|
| 3.1 | `track(name, props)` — evento tipado do site | **M** | 1.4, 1.5 | **Baixo** — `pushEvent` já existe interno; `sdkEvents.js` tem 7 linhas |
| 3.2 | Objeto `company` + `signed_up_at` | **M** | 2.1 | **Médio** (`contacts.js` do widget + `ContactIdentifyAction`) |
| 3.3 | Getters (`get('state')`, `get('unread_count')`, `get('contact')`) | **P** | 1.4 | **Baixo** |
| 3.4 | Eventos de conclusão: conversa criada com id, pre-chat submetido, mensagem do visitante, reset concluído | **P/M** | 1.4 | **Baixo** — **[R09 §15.1]**, ponto de extensão mais barato do sistema |
| 3.5 | `data-*` de **configuração** no script de embed (nunca identidade) | **M** | — | **Baixo** — `inbox.additional_attributes` **[R09 §15.3]** |
| 3.6 | Credencial por **callback** (modelo Zendesk), resolvendo o problema de CDN | **M** | 2.7 | **Médio** |
| 3.7 | Mensagem proativa em **1 chamada** (`POST .../proactive_messages`) | **M** | — | **Nenhum** — açúcar sobre o que já existe |
| 3.8 | Assinar os outros três caminhos de webhook + filtro por inbox de verdade | **M** | 1.9 | **Baixo** — a coluna e o enum já existem |
| 3.9 | Card de contexto **ao lado** da conversa (não aba), com payload delimitado e assinado | **G** | 2.3 | **Médio-alto** (`ConversationBox.vue`, `Frame.vue`) |
| 3.10 | Enriquecimento síncrono no aceite da conversa (padrão JivoChat) | **G** | 3.9 | **Nenhum** (caminho novo) |
| 3.11 | Agent bot pode **ler** a própria conversa + evento de handoff observável | **M** | — | **Baixo** |

**Critério de pronto, verificável:**

- Um site dispara `track('adicionou_ao_carrinho', {valor: 250})` e o evento aparece na linha do
  tempo da conversa **e** está disponível como condição de automação.
- Um site passa `company: {id, name, plan}` e o painel mostra a empresa como objeto, não como
  string solta.
- O snippet com `data-position="left"` posiciona o widget à esquerda **sem** uma linha de
  JavaScript no site.
- Um backend cliente envia **uma** requisição e o visitante identificado recebe a mensagem no
  widget aberto, em tempo real.
- O agente vê o contexto do CRM **sem perder a conversa de vista** — verificado em navegador real,
  light e dark.

---

### Quadro de conjunto

| | Fase 1 | Fase 2 | Fase 3 |
|---|---|---|---|
| **Tema** | coerência e segurança | visibilidade e confiança | superfície nova |
| **Esforço agregado** | **M** | **G** | **G** |
| **Depende de decisão de design?** | **não** | parcial (painel) | parcial |
| **Risco de merge predominante** | baixo/médio | baixo | baixo/médio |
| **Destrava** | tudo o mais desta frente; C2/C3/C4 do tracking | percepção de valor pelo cliente | paridade com Intercom/Zendesk |
| **Se parar aqui** | produto honesto: promete o que cumpre | integração que o cliente **vê** funcionando | frente completa |

---

## 7. Perguntas para o Walisson

Seis, cada uma com as opções reais, o que muda, e minha recomendação. Deixei de fora tudo que já
foi perguntado em **[R10 §7]** (Q1 comprador-alvo, Q2 arquitetura iframe/Shadow DOM, Q6 enforcement
por padrão, Q8 contribuir upstream) para não pedir a mesma decisão duas vezes com nomes diferentes.

---

### P1 — Os dois furos do enforcement de HMAC entram no fluxo normal de fase, ou saem antes de tudo?

| Opção | O que significa |
|---|---|
| **(a) Correção fora de fase, imediata** | Trata-se como incidente de coerência de segurança, com teste dirigido em ambiente isolado, antes de qualquer trabalho de redesenho |
| (b) Item 1.1/1.2 da Fase 1, na ordem normal | Sai junto com o resto da fase |
| (c) Esperar a Fase 2 e resolver junto com o JWT | Um único mexe no controller |

**Recomendação: (a).** São duas correções pequenas (`before_action` e uma condição), e o que está
em jogo não é o tamanho: é que **um toggle de segurança que não trava é pior que a ausência do
toggle** — quem liga acredita ter fechado a porta. Enquanto isso estiver de pé, não temos como
oferecer "identidade verificada" a cliente de banco, saúde ou jurídico sem uma ressalva que ninguém
vai querer escrever no contrato. **(c) é a pior opção** e está registrada porque é a tentação
natural: o JWT **não** conserta os furos (divergência D5).

---

### P2 — Qual formato de credencial vamos sustentar daqui para frente?

| Opção | Trade-off |
|---|---|
| **(a) JWT como formato adicional, HMAC aceito como legado** | É o caminho do Intercom, documentado e testado por eles. Destrava `exp` e atributo autenticado. Custo: dois caminhos de validação convivendo |
| (b) Só HMAC, com `exp` embutido de forma proprietária | Menor custo imediato; inventa formato que ninguém mais fala; não resolve atributo dentro da assinatura |
| (c) JWT substituindo o HMAC, com prazo de migração | Mais limpo; **quebra todo cliente que já integrou**, e não sabemos quantos são |

**Recomendação: (a).** Além de ser o padrão, a infraestrutura já está em casa: **[CÓDIGO]**
`app/services/widget/token_service.rb` já faz `JWT.encode` com `exp`/`iat` e expiração
configurável. **A pergunta real embutida aqui, e que precisa da sua resposta:** aceitamos o custo
de manter **dois** caminhos de verificação por tempo indeterminado? Minha leitura é que sim, porque
o custo de quebrar integração existente em silêncio é maior — e é exatamente o pecado que esta spec
combate.

---

### P3 — Quando o site manda um atributo que não existe, o que o produto faz?

| Opção | Trade-off |
|---|---|
| **(a) Auto-provisiona a definição (tipo `text`, marcada "não confiável") E mostra numa seção separada "Dados recebidos do site (N)"** | A integração "funciona de primeira". Custo: o cadastro do cliente ganha definições que ele não criou, e alguém precisa refinar tipo e rótulo depois |
| (b) Só mostra numa seção separada, sem provisionar | Nada é criado sem o admin pedir; mas o dado continua sem tipo, sem filtro e fora do relatório |
| (c) Só avisa: "3 atributos recebidos não estão configurados — configurar" | Mais conservador; é remendo, e transfere trabalho para quem tem menos contexto |

**Recomendação: (a).** É a mesma conclusão de **[R19 §recomendação 1]**, e o argumento decisivo é o
custo de suporte: hoje o cliente integra, o dado chega, o painel não muda, e a conclusão dele é
"não funcionou" — com o site jurando que mandou e o atendente jurando que não vê, **os dois
certos**. **Ressalva honesta de (a):** poluir o cadastro é um risco real, e a mitigação é o
namespace por origem + a seção separada, que impede o auto-provisionado de se misturar ao curado.

---

### P4 — Quem é o dono do `track()` — a frente de integração ou a de tracking?

| Opção | Trade-off |
|---|---|
| **(a) Um `track()` só, definido na frente de integração, consumido pela de tracking** | Um vocabulário, uma documentação, um método na API pública. Exige coordenar as duas frentes antes de qualquer uma codar |
| (b) Dois caminhos: `track()` de negócio e um disparo interno de eventos de conversão | Cada frente anda sozinha; o cliente descobre dois métodos parecidos e chama o errado |
| (c) Adiar o `track()` até a frente de tracking existir | Zero risco de retrabalho; atrasa um dos itens mais pedidos da API |

**Recomendação: (a).** É o item 3 da tabela de §5.2. **[R10 §4.1, C3]** já registra que a frente de
tracking está **bloqueada** por eventos que pertencem a esta frente — a coordenação não é opcional,
é uma dependência que já existe. **A decisão que preciso de você:** as duas frentes vão ser
planejadas juntas, ou uma delas anda primeiro? Se andarem separadas, (b) acontece por inércia.

---

### P5 — O contexto do sistema externo vai ficar ao lado da conversa ou continua sendo aba?

| Opção | Trade-off |
|---|---|
| **(a) Card lateral (novo formato) + manter a aba para o caso "tela cheia"** | Resolve "dar contexto" sem perder "abrir sistema externo". É o desenho de Intercom (Canvas Kit) e Zendesk (`ticket_sidebar`). Custo: **G**, e mexe em `ConversationBox.vue` |
| (b) Manter só a aba | Zero custo; o agente continua lendo o pedido, voltando para as mensagens e tendo que **lembrar** o que leu |
| (c) Enriquecimento síncrono (padrão JivoChat) no lugar do card | O CRM responde ao webhook e nós renderizamos nativamente — **sem o cliente construir página nenhuma**. É o de maior valor percebido para PME, e o de maior esforço nosso |

**Recomendação: (a) primeiro, (c) depois.** **[R19 §B.2]** é a frase que fecha o argumento: *"um
app que esconde a conversa não é contexto, é destino"* — e **[R19]** confirmou isso por código
(`ConversationBox.vue:159`) **e** por print da documentação oficial do Chatwoot. (c) é o
diferencial competitivo real contra Jivo/RD/Leadster no mercado brasileiro **[R18 §Trava 10]**, mas
depende de (a) existir para ter onde renderizar. **Esta é a única pergunta desta lista que
realmente depende do redesenho de front** — as outras cinco não.

---

### P6 — Vamos publicar um contrato de integração público?

| Opção | Trade-off |
|---|---|
| **(a) Sim — página pública com campos, tipos, limites, eventos, erros e exemplos** | **[R10 §4.1, C8]** identificou que *"o ponto fraco documentado da Leadster é a documentação"* — o artigo oficial deles sobre eventos é essencialmente um vídeo, sem especificação escrita. Agências e times de dados escolhem por isso |
| (b) Documentação interna, entregue no onboarding | Menor exposição; perde o efeito de autoridade e não ajuda quem avalia antes de comprar |
| (c) Nada por enquanto | Cada integração vira ticket de suporte |

**Recomendação: (a), e escrita junto com a Fase 1, não depois.** Duas razões. Primeira: uma spec
pública é o que **força** o contrato a ser coerente — é difícil publicar "este método não devolve
nada e falha em silêncio". Segunda: **[R19 §recomendação 8]** aponta que o que trava a adoção não é
a API, é o cliente **não saber o que mandar** — e as tabelas por vertical de **[R19 §A]** já são o
rascunho desse material. **Ressalva:** publicar contrato cria compromisso de estabilidade. Vale
declarar explicitamente o que é estável e o que é experimental, como o Sunshine faz carregando
`webhook.version` no próprio payload **[R18 §A.1.2]**.

---

## 8. O que isso significa para o redesenho do ChatSPX

> Bloco de fechamento exigido pela onda. Recomendação, sem código de implementação.

**1. A maior parte desta frente não é trabalho de front, e isso é uma boa notícia.** Das cinco
mitigações de segurança (§4), **quatro** não dependem de nenhuma decisão de design. Dos onze itens
da Fase 1, **nove** são backend ou SDK. Isso significa que a frente de integração e o redesenho
visual do widget **não competem pelo mesmo recurso** e podem andar em paralelo — o que muda o
planejamento, porque a leitura intuitiva ("primeiro o visual, depois a integração") é justamente a
que desperdiça a paralelização disponível.

**2. Refatore antes de estender — é a diferença entre conflito de merge por linha e por arquivo.**
**[R09 §15.4, §15.8]** é explícito: a cadeia de `else if` em `App.vue:258-345` é *"exatamente o
tipo de código que conflita"*, e a recomendação é substituí-la por um mapa `{evento: handler}`
**antes** de adicionar métodos. Como esta frente adiciona vários eventos e o redesenho toca os
mesmos arquivos, a refatoração paga duas vezes. Vale a mesma regra para o `v-if` composto de
`AgentMessageBubble.vue`.

**3. O redesenho do widget não deve encostar em nada que esta spec vá mudar por baixo.** Três
superfícies em transformação: os métodos de dados (ganham `Promise`), a fila pré-boot (muda o
momento em que o dado chega ao widget) e o pre-chat. Sobre o pre-chat, um ponto que o redesenho
**vai** tocar e precisa decidir com informação: **[R17 §5.2]** — hoje nós **escondemos** o campo
que o site já preencheu, não o pré-preenchemos (`PreChat/Form.vue:83-105`), e a regra do nome faz
`fullName` sumir se **qualquer** um entre identifier, e-mail ou telefone estiver presente, mesmo
que o nome não tenha sido informado. **[R17]** também registra que **não localizou** fornecedor que
exiba o campo preenchido e editável. Esta é uma decisão de design com consequência de dado: campo
escondido preserva a verificação de identidade (o visitante não pode "corrigir" para o e-mail de
outro); campo preenchido e editável dá ao visitante a chance de perceber que o site errou.

**4. Não desmonte o que já é diferencial.** **[R17 §6]** lista explicitamente, e vale repetir aqui
porque num redesenho é fácil derrubar coisa que funciona: o escopo de histórico por `contact_inbox`
sem HMAC (é o que faz o ataque de §4/T1 parar); o `hmac_verified` propagado até o Captain e até o
header de webhook das tools; os 7 eventos de `window` (a Leadster tem zero); o suporte a
Turbo/Turbolinks/Astro com restauração de nós; o `targetOrigin` correto na direção site → widget;
e o loader de **28.834 bytes** contra os **456.101** da Leadster — 16× menor, porque o peso vive
dentro do iframe.

**5. A integração precisa aparecer na tela do agente, e essa tela não é o widget.** O item de maior
retorno percebido da frente inteira (§2.4.3) é o painel lateral do dashboard: hoje o atributo
enviado pelo site grava, alimenta a IA e **some**. Enquanto isso não mudar, todo o resto deste
documento chega ao cliente como "não funcionou". Se houver um único item desta spec para levar ao
roadmap antes do redesenho, é este.

**6. O contrato público é parte do produto, não do marketing.** Publicar campos, tipos, limites,
eventos e erros é o que separa "tem API" de "dá para integrar". É também o que impede que o
contrato volte a se degradar em silêncio — é difícil publicar um método que não devolve nada.

---

## Anexo A — Lacunas desta síntese

Registro o que **não** foi verificado, para que ausência de dado não seja lida como ausência de
problema:

1. **Não executei nada nesta task.** As verificações **[CÓDIGO]** são leitura de arquivo. Os furos
   de §2.3.2 e as ameaças de §4 **não foram explorados** — confirmação exige ambiente isolado.
2. **D1 continua sem veredito de execução.** Sei o que o código faz linha a linha; não sei o que
   acontece em runtime. É o item 1.10 da Fase 1 e o teste mais barato de toda a frente.
3. **Não medi nada de mobile.** Tudo nesta síntese e nos três relatórios de entrada é desktop.
   **[R17 §7, lacuna 6]** registra que o `toggleCloseButton` usa `matchMedia('(max-width: 668px)')`,
   mas nenhum comportamento de handshake foi testado em viewport móvel. **Não afirmo nada sobre
   mobile.**
4. **Não sei quantos clientes da frota já usam `setUser` com HMAC.** Isso dimensiona o custo real
   de qualquer mudança de compatibilidade (P2) e não foi levantado por nenhum relatório da onda.
5. **Não auditei a renderização da ficha lateral em navegador real.** **[R19 §D]** é explícito
   sobre o mesmo limite: *"onde eu digo 'o agente vê', leia como 'o código renderiza'"*. A
   validação em navegador real, light e dark, com conta de teste, continua pendente para as duas
   tasks.
6. **Não verifiquei limites de tamanho/quantidade** de JivoChat, Tidio, Crisp, LiveChat e Freshchat
   — a documentação deles não publica **[R17 §7, lacuna 7]**.
7. **Não arbitrei a contradição Fin × custom attributes** de **[R19 §C.2]** — lá as duas versões
   ficaram registradas, com a fonte primária prevalecendo, e eu mantive essa escolha sem testar.
8. **Não avaliei impacto de peso no `sdk.js`.** A fila pré-boot, o coletor de origem e a ponte de
   tags moram todos no SDK, que hoje tem **28.834 bytes** com orçamento declarado de 40 KB
   **[R10 §4.1, C4]**. Somar três componentes ao mesmo arquivo sem medir é como o orçamento estoura.

---

## Anexo B — Rastreabilidade

De onde veio cada seção deste documento:

| Seção | Entradas principais | Verificação própria **[CÓDIGO]** nesta task |
|---|---|---|
| §0.3 divergências | R17 §4.1, R09 §4.3, R14 §15.4, R10 §2 | `cookieHelpers.js:4-19`, `sdk.js:112-175`, `IFrameHelper.js:94-103, 185-187`, `contacts.js:45-59` |
| §1 resumo | R17 §0, R18 §Sumário, R19 §0, R10 §1 | — |
| §2.1 campos | R17 §2.1–§2.12, §4.6; R19 §A | `cookieHelpers.js:23-24`, `contacts.js:60-74` |
| §2.2 vias | R17 §5.1; R14 §11.3 | `widget/api/contacts.js:3` |
| §2.3 autenticação | R17 §3; R19 §C.3.2; R10 §7 Q6 | `contacts_controller.rb:4-75`, `base_controller.rb:10-17`, `widget/token_service.rb`, `widget/api/contacts.js:18-22` |
| §2.4 persistência | R17 §4.5; R19 §D.1–D.3 | `conversations_controller.rb:3, 67-69, 93-95, 97-100`, `base_controller.rb:31-46` |
| §2.5 saída | R09 §4.5; R17 §4.1; R14 §11 | `widget/constants/sdkEvents.js` (7 linhas, íntegro) |
| §2.6 servidor | R18 §A, §B, §D | `app/models/webhook.rb:20-34` |
| §3 matriz | R17 §2.12; R18 §A.2, §A.3, §B.4; R19 §B.1 | — |
| §4 segurança | R17 §3.3, §3.5, §4.3; R19 §C.3; R18 §D.10.3 | `contacts_controller.rb:49-75`, `IFrameHelper.js:104-117, 213-215` |
| §5 tracking | R10 §4 (C0–C9); R07 §6, §7; R09 §11, §15.5; R19 §B.3 | `base_controller.rb:31-46` |
| §6 faseamento | todas | — |
| §7 perguntas | R10 §7 (para não duplicar); R19 §recomendações | — |
| §8 redesenho | R09 §15; R17 §5.2, §6; R14 §15.6 | — |

---

*Fim do relatório 20. Este documento é o único arquivo escrito por esta task. Nenhum arquivo de
código do repositório foi alterado.*
