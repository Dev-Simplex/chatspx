# 25 — Plano de execução: tracking e integração site ↔ chat

> **Fase:** planejamento executável. **Nenhum arquivo de código do repositório foi alterado por
> esta task.** O único artefato escrito é este markdown.
> **Data:** 12/08/2026 · **Repositório:** `/home/chatwoot/chatwoot`, branch `homologacao`,
> HEAD `ee87f5e799` (o mesmo HEAD das três ondas do estudo).
> **Base documental:** `plano/estudo-chat-web/` — relatórios 07 (tracking), 10 §4 (camadas C0–C9),
> 17 (handshake), 18 (webhooks/APIs), 19 (contexto), 20 (spec de integração), 15 §B12 (risco de
> merge) e `DECISOES.md`.

---

## ⚠ DECISÕES DO PRODUTO — 13/08/2026: leia antes de executar qualquer tarefa deste plano

**O `PLANO-MESTRE.md` é a fonte única da ordem e do escopo; este plano continua sendo a fonte do
detalhe** — mas em seis pontos o detalhe daqui foi superado. Onde este arquivo e o mestre
divergirem, **o mestre manda**.

| Decisão | O que muda **neste** plano | Onde está o novo detalhe |
|---|---|---|
| **D6** — sem backfill de histórico | **T-C0.4 está CORTADA**, e com ela a **verificação 3** da §Parte D e a linha que a chamava de portão da onda α. O parser é **só prospectivo, por decisão** — deixou de ser limitação constrangida. **T-C0.1/2/3/5/6/7 continuam.** E a frase da onda α — *"responde de onde veio o lead para a base inteira"* — **não se sustenta e sai**: o que se sustenta é *"a partir da entrada em produção, toda conversa nasce sabendo de onde veio"* | Mestre bloco **1.20**, arbitragem **A16** |
| **D1** — três níveis instrumentados | Um bloco novo de tracking: exibição, dispensa, abertura e conversão do teaser carregam **o nível** (`discreet`/`bold`/`aggressive`) **e o nível configurado**, para separar o efeito da degradação do efeito do nível. Vai pelo caminho de T-C3.1/T-C3.2, **sem vocabulário novo** (arbitragem **A9**) | Mestre bloco **4.21** |
| **D8** — instalação em WordPress, Wix e GTM | **Entra**, junto de T-C8.6/T-C8.7 (o contrato público): um caminho por plataforma, com a armadilha de cada uma escrita — inclusive **por que o snippet do GTM vai em tag de HTML customizado e não em template**, e o que acontece com o `dataLayer` do cliente (é a regra **R9**, verificada na porta de entrada) | Mestre bloco **5.22** |
| **D9** — contexto do sistema externo (**I5** do `DECISOES.md`) | **Entra na versão simples**: painel lateral com o que o site mandou. *Nota de nomenclatura que este plano criou e que custou caro:* o **"I5" deste documento é a frente de webhooks**; o "I5" do `DECISOES.md` é esta decisão. Foi atrás desse homônimo que ela sumiu na consolidação | Mestre bloco **5.23**; mestre §0.1, o aviso de colisão de identificadores |
| **D2** — a frente de IA entra | Três blocos novos (guardrail de pré-envio, eval como produto, citação de fonte). Nenhum é tracking, mas dois consomem o mesmo caminho de evento — e o **A/B de fluxo** (D4) lê o resultado pelo registro server-side de T-C3.9 | Mestre blocos **6.01–6.03**, **6.05** |
| **D7** — reordenação das ondas | As ondas α/β/γ deste plano **não são mais a ordem de execução**. A atribuição passou a ser a **5ª** onda do mestre, **antes** do acabamento visual do widget — e o marco comercial cai de **76,8% para 38,7%** do esforço. Os ids `T-C*` e `T-I*` continuam válidos | Mestre §2.1, §2.2 e **§2.6** |
| **D14 · D11–D13 · D15** | Fixture anti-erro em todo E2E; **sem** Zod nas bordas (estoura o teto de **15 KB gzip** do `sdk.js` sozinho — arbitragem **A13**); worktree por frente; autonomia até **commit local**; falha = 2 tentativas → revert → escalação | Mestre **§10** e **§11** |

---

## 0. Como ler este documento

### 0.1 O que este documento é, e o que não é

**É** o plano de execução das duas frentes que o Walisson levantou pessoalmente — *"ter o pixel da
Meta e o rastreio do Google"* e *"o site se vincula ao chat e passa parâmetros"* — quebradas em
tarefas com dependência, esforço, risco de merge e critério de aceite verificável.

**Não é** especificação de implementação: não há código de produção aqui, não há assinatura de
método inventada, não há nome de coluna que eu não tenha lido. Onde a spec precisa existir antes de
alguém codar, o plano diz **em qual tarefa ela é escrita** e **o que ela precisa conter**.

**Não reabre** as decisões já tomadas (perfil por inbox, geometria mantida, escopo das duas
superfícies, planejamento de todas as ondas) nem as 24 decisões consolidadas em
`plano/estudo-chat-web/DECISOES.md`. Onde uma decisão dali governa uma tarefa, ela é citada pelo
código (N4, I4, Q5…), não rediscutida.

### 0.2 Marcação de procedência

| Marca | Significado |
|---|---|
| **[FATO]** | Verificado por leitura de fonte primária **nesta task** — código do repositório com `arquivo:linha`, ou documentação oficial com URL. |
| **[MEDIDO]** | Medido por mim **nesta task**, com o comando reproduzido no texto (consulta SQL, `curl`, `grep`). |
| **[R07]**, **[R10]**, **[R15]**, **[R17]**, **[R18]**, **[R19]**, **[R20]** | Vem de um relatório do estudo, com a seção. Herda a marcação de lá. |
| **[INFERÊNCIA]** | Conclusão minha, com a base explícita ao lado. |
| **[NÃO VERIFICADO]** | Buraco declarado. Ausência de dado nunca é apresentada como ausência de problema. |
| **DIVERGÊNCIA** | Onde eu discordo do estudo com base em medição nova. Sempre com a medição junto. |

### 0.3 O que eu verifiquei por conta própria nesta task

Sete verificações de primeira mão, todas somente leitura. Elas mudam três coisas no plano e
respondem parcialmente duas das quatro pendências da §Parte D:

| # | O que verifiquei | Comando | Resultado |
|---:|---|---|---|
| V1 | O `referral` do WhatsApp Cloud **já é persistido** | leitura de `app/services/whatsapp/incoming_message_base_service.rb:194` | `attrs[:referral] = message[:referral].to_h if message[:referral].present?` — **o objeto inteiro** é copiado para `messages.content_attributes` |
| V2 | O `referral` **já é consumido** pela IA e pelo painel | `enterprise/app/services/captain/open_ai_message_builder_service.rb:100-117`; `app/javascript/dashboard/components-next/message/ReferralCard.vue`; `Message.vue:971-972` | há `referral_note` para CTWA no prompt e um card de anúncio no painel |
| V3 | A WAHA **não passa** por esse caminho | `app/controllers/public/api/v1/inboxes/messages_controller.rb:23,34,38,108-151`; `app/jobs/webhooks/waha_events_job.rb:9-16` | WAHA entra pelo **canal API público**; o job de webhook WAHA só trata `poll.vote` |
| V4 | Cache do `sdk.js` | `curl -sSI https://hmlchat.simplexsolucoes.com.br/packs/js/sdk.js` | `cache-control: public, max-age=31556952` (365 dias), sem `ETag`, sem fingerprint no path |
| V5 | **Quem** define esse header | `config/environments/production.rb:23-26` e `grep` em `/etc/nginx/sites-enabled/` | é o **Rails** (`public_file_server.headers`), **não o nginx** — o nginx só faz `proxy_pass` |
| V6 | Presença de UTM/`gclid`/`fbclid` no `referer` | consulta SQL (Ap.A1) contra o banco desta VM de homologação | 3.140 conversas · 4 com `referer` · **0** com query string · **0** com `utm_`/`gclid`/`fbclid` |
| V7 | Presença de `referral` gravado | consulta SQL (Ap.A2) | **0** mensagens com `content_attributes ? 'referral'` nesta VM |

**V6 e V7 não respondem nada sobre a frota** — dizem apenas que **homologação não serve de
amostra** (1 inbox `Channel::WebWidget`, sem tráfego de site real). O valor delas é outro: as
consultas do apêndice A estão **testadas contra o schema real** e podem ser rodadas em produção sem
ajuste.

### 0.4 Convenções

**Esforço** — sempre relativo, nunca em horas:

| Marca | Leitura |
|:---:|---|
| **P** | mudança pontual, um ou dois arquivos, sem modelagem nova |
| **M** | uma vertical completa (modelo + serviço + tela, ou SDK + backend), com testes |
| **G** | vertical com dependência externa (credencial de terceiro, fila, migração de dado) ou que muda contrato público |

**Risco de merge com o upstream** — a escala é a do **[R15 §B12]**, que mediu o fork:

| Marca | Leitura |
|:---:|---|
| **Nenhum** | arquivo novo em pasta nova. Conflito zero por definição |
| **Baixo** | usa ponto de extensão declarado (`custom_attributes` já aceito, `sdkEvents.js`, `inbox.additional_attributes`) |
| **Médio** | toca arquivo que o upstream mexe (`IFrameHelper.js` — 10 commits em 36 meses; `App.vue`; `base_controller.rb#permitted_params`) |
| **Alto** | toca campo minado do **[R15 §B12.3]**: `ChatInputWrap.vue`, `PreChat/Form.vue`, `ChatFooter.vue`, `store/modules/conversation/*`, `api/endPoints.js`, `woot.scss` |

**Identificador de tarefa** — `T-C4.2` = frente de tracking, camada C4, tarefa 2. `T-I1.3` =
frente de integração, bloco I1, tarefa 3. Os identificadores são estáveis e servem para referência
cruzada entre as duas frentes (§Parte C).

### 0.5 Sumário

| Parte | Conteúdo |
|---|---|
| **§1** | A tese, e os três achados desta task que mudam o plano |
| **§A** | **Tracking** — linha de base, 10 regras de conduta, C0 a C9 tarefa a tarefa, tabela mestre de eventos, sGTM, consolidado |
| **§B** | **Integração** — os sete defeitos, I1 (estabilização), I2 (visibilidade), dicionário de campos, cinco vias, webhooks, superfície nova, contrato de saída, mensagem proativa |
| **§C** | **A fronteira** — mapa, as sete peças de dono único, ordem conjunta, cinco regras de coordenação |
| **§D** | **As quatro verificações** — o que já foi respondido, como verificar o resto, o que muda por resposta |
| **§E** | Sequenciamento em cinco ondas, critério de pronto verificável, métricas de sucesso |
| **§F** | Riscos: merge com upstream, produto/dado/conformidade |
| **Apêndices** | A: consultas e comandos · B: checklist de QA · C: rastreabilidade · D: lacunas |

---

## 1. A tese: uma frente com dois nomes

> **Origem e identidade são o mesmo problema visto de dois lados.** A frente de tracking pergunta
> *"de onde veio essa pessoa?"*; a frente de integração pergunta *"quem é essa pessoa?"*. As duas
> respondem com o mesmo dado, pelo mesmo cano, e gravam no mesmo jsonb. Fazer as duas sem coordenar
> é construir dois canos paralelos — e é o desfecho *default* se ninguém decidir o contrário
> **[R20 §5]**.

Três consequências organizam o documento inteiro:

**1. C0 primeiro, e sozinho.** O parser retroativo do `referer` é o único item das duas frentes que
entrega valor **sem credencial de terceiro, sem tocar no widget e sem risco de merge**
**[R10 §4.2]**. Ele também é o único que produz o número que dimensiona o resto do investimento
(§Parte D, verificação 3). Fazer C4 (a vitrine: pixel no site do cliente) antes de C0 é montar a
vitrine antes de saber se há estoque.

**2. Estabilizar antes de somar.** Os sete métodos de dados do `$chatwoot` falham em silêncio hoje;
`setConversationCustomAttributes` antes de existir conversa devolve 404 e o store engole
**[R20 §1.2, §2.4.1]**. Todo método novo — inclusive o `track()` de que a frente de tracking
depende — **herda** esses defeitos. Estabilização não é fase paralela: é pré-requisito.

**3. Um dono por peça.** A decisão **I4** já está tomada: o `track()` é da frente de tracking
(`DECISOES.md`, Parte 1). O que falta, e é o que a §Parte C entrega, é a fronteira completa — seis
peças com dono único e o sintoma de cada duplicação.

### 1.1 Os três achados desta task que mudam o plano

**Achado 1 — o CTWA já está meio construído, e ninguém sabe.**
**[FATO]** `app/services/whatsapp/incoming_message_base_service.rb:194` copia o objeto `referral`
**inteiro** do webhook do WhatsApp Cloud para `messages.content_attributes['referral']`. Ele é
lido pela IA (`open_ai_message_builder_service.rb:104-117`, que injeta título/corpo do anúncio no
prompt) e renderizado no painel (`ReferralCard.vue`, acionado por `Message.vue:971-972`).
**[INFERÊNCIA]** Como a cópia é `.to_h` do objeto sem allowlist, **se a Meta enviar `ctwa_clid`, ele
já está no nosso banco hoje**. A verificação pendente nº 1 deixa de ser "precisa mudar código de
ingestão?" e vira "roda esta consulta e olha" (§Parte D). Isso rebaixa o custo de C9/CTWA de forma
material.

**Achado 2 — o `sdk.js` está cacheado por um ano, e a culpa é nossa, não do nginx.**
**[MEDIDO]** `curl -sSI https://hmlchat.simplexsolucoes.com.br/packs/js/sdk.js` →
`cache-control: public, max-age=31556952`, `last-modified: Thu, 23 Jul 2026`, **sem `ETag`**.
**[FATO]** O header vem de `config/environments/production.rb:23-26`
(`config.public_file_server.headers = { 'Cache-Control' => "public, max-age=#{1.year.to_i}" }`); o
`nginx_chatwoot.conf` desta VM só faz `proxy_pass` e não define `expires` nem `add_header` de cache.
**[FATO]** O snippet de instalação (`app/models/channel/web_widget.rb:64-82`) aponta para
`BASE_URL + "/packs/js/sdk.js"`, sem query de versão.

> **DIVERGÊNCIA com o enunciado da verificação nº 4 do estudo** (`DECISOES.md`: *"quais headers de
> cache o nginx devolve para `/packs/`"*): **não é o nginx**. É o Rails. A consequência é boa — a
> correção é uma linha de configuração no nosso código, propagada pelo deploy normal, sem precisar
> de acesso de infra a cada VM da frota.

E a consequência é grande para o planejamento: **C2, C4 e C7 vivem no `sdk.js`**. Sem resolver a
propagação, uma versão nova do SDK pode levar até um ano para chegar ao navegador de um visitante
recorrente. Isso vira uma tarefa de pré-requisito explícita (**T-C2.0**), e não uma nota de rodapé.

**Achado 3 — a WAHA está fora do caminho que grava `referral`.**
**[FATO]** A WAHA entra pelo **canal API público** (`app/controllers/public/api/v1/inboxes/messages_controller.rb`
tem tratamento dedicado a WAHA nas linhas 23, 34, 38, 108-151), e o nosso job de webhook WAHA
(`app/jobs/webhooks/waha_events_job.rb:9-16`) só trata `poll.vote`/`poll.vote.failed`. O
`Whatsapp::IncomingMessageBaseService` — onde mora a linha 194 — atende `Channel::Whatsapp` (Cloud
API e 360dialog), não `Channel::Api`. **[INFERÊNCIA]** Portanto, para inbox WAHA, qualquer contexto
de anúncio só existiria se a aplicação externa o enviasse dentro de `content_attributes` — e nada
no nosso código lê isso. **O plano de CTWA cobre WhatsApp Cloud; WAHA fica marcado como
[NÃO VERIFICADO] e sai do escopo até haver evidência.**

---

# Parte A — TRACKING: as dez camadas viram tarefas

## A.0 Linha de base verificada

Tudo nesta tabela é **[FATO]**, lido nesta task no HEAD `ee87f5e799`.

| O que existe hoje | Onde | Por que importa para o plano |
|---|---|---|
| A URL completa da página (com query string) chega ao backend | `app/javascript/sdk/DOMHelpers.js:42-64` → `widget/api/endPoints.js:18,35,53` (`message[referer_url]`) → `app/controllers/api/v1/widget/base_controller.rb:38-44` | **os UTMs, o `gclid` e o `fbclid` já estão no banco**, crus, em `conversations.additional_attributes.referer` |
| Validação que **anula** o campo | `app/models/conversation.rb:83, 536-539` (`validate_referer_url`) | URL inválida vira `nil`: o parser de C0 precisa contar isso |
| `referer` já é atributo condicional de automação | `app/models/automation_rule.rb:38` | dá para criar regra "referer contém `utm_source=google` → aplica etiqueta" **hoje, sem uma linha de código** |
| Canal genérico de eventos widget → backend | `app/controllers/api/v1/widget/events_controller.rb:4-8`; rota em `config/routes.rb:598` | subutilizado: o único emissor é `webwidget.triggered` (`IFrameHelper.js:253`) |
| Ponte iframe → `window` do site | `app/javascript/sdk/IFrameHelper.js:206-207` (`onEvent` → `dispatchWindowEvent`) | ponto de extensão mais barato do sistema: evento novo **não exige tocar no SDK** |
| Sete eventos públicos | `app/javascript/widget/constants/sdkEvents.js` (7 linhas, íntegro) | é onde os eventos de C3 são declarados |
| `custom_attributes` aceitos na criação da conversa | `base_controller.rb:44`; `conversations_controller.rb` (`permit`) | rota de **menor atrito de merge** para levar origem ao servidor |
| `referral` do WhatsApp Cloud persistido inteiro | `app/services/whatsapp/incoming_message_base_service.rb:194` | ver Achado 1 |
| Nenhuma ocorrência de `fbq`, `gtag`, `dataLayer`, `googletagmanager` em `app/` | **[R07 §6.2]**, reconfirmado por `grep` nesta task | a frente parte do zero no navegador |
| Telemetria do **dashboard** com Amplitude e LogRocket | `app/javascript/dashboard/helper/AnalyticsHelper/`; `config/installation_config.yml` | **não confundir**: é telemetria do agente, não do visitante |

E o que **não** existe, além do óbvio: nenhum campo de origem de primeira classe no contato,
nenhuma camada de consentimento, nenhuma fila de envio server-side, nenhuma configuração de
tracking por caixa de entrada **[R07 §6.2]**.

## A.1 As dez regras de conduta da frente

Regras que decidem todo caso omisso. Cada uma tem origem e um sintoma concreto se for violada.

| # | Regra | Origem | Sintoma se violar |
|---:|---|---|---|
| **RC1** | **Nunca instalar um GA4 nosso no site do cliente.** A Leadster injeta `G-43W2WYML5H` por padrão, desligável só por uma flag global não documentada | **[R07 §4.1.2]**; decisão **N5** | tratamento de dado do visitante do cliente para finalidade própria nossa — indefensável sob LGPD |
| **RC2** | **Código aditivo, nunca destrutivo.** `window.gtag = window.gtag \|\| …`, jamais reatribuir | **[R07 §3.1]** | quebrar a medição do site inteiro do cliente. Perda de confiança irreversível |
| **RC3** | **`trackSingle` no Meta, `send_to` no Google.** Nunca `fbq('track', …)` puro | **[R07 §2.1, §2.4]** — a própria Meta avisa que `track` com múltiplos pixels *"could produce over-firing"* | evento vaza para o pixel da agência e do parceiro na mesma página |
| **RC4** | **`dataLayer.push` sempre**, mesmo quando há `fbq`/`gtag` | **[R07 §3.5]** | quem usa GTM fica refém do resto da implementação |
| **RC5** | **Nenhuma PII crua fora do servidor.** Nem no `dataLayer`, nem nos params do `fbq`/`gtag` | **[R07 §7.6]** | o `dataLayer` é legível por qualquer script da página: incidente de LGPD |
| **RC6** | **Hash no servidor**, não no navegador | decisão **N4**; **[R07 §7.5 decisão 1]** | hash de telefone mal formatado perde o match **em silêncio**, e o servidor não pode corrigir |
| **RC7** | **`event_id` nasce no backend** e é propagado aos dois caminhos | **[R07 §7.5 decisão 2]** | aba fechada antes do POST = evento sem par = dedup quebrada |
| **RC8** | **Um caminho por evento lógico no GA4.** Ou navegador, ou Measurement Protocol — nunca os dois | **[R07 §3.4]** — o GA4 **não tem** dedup nativa | conversão contada em dobro no relatório do cliente |
| **RC9** | **Allowlist de cookies.** Nunca `document.cookie` inteiro | **[R07 §4.1.5]** — a Leadster copia tudo | coleta indiscriminada, difícil de justificar sob LGPD |
| **RC10** | **IP e user-agent do visitante, nunca do servidor.** E segredo nunca sai do backend | **[R07 §7.4 C4, §7.6]** | IP do servidor destrói o EMQ; `access_token`/`api_secret` no navegador é vazamento |

## A.2 C0 — Parser retroativo do `referer` já gravado

**O que entrega.** "De onde veio esse lead?" respondido para **100% da base, retroativamente**, sem
tocar no widget e sem credencial de terceiro. Risco de merge **Baixo**: a única edição em arquivo do
upstream é a linha de chamada do saneamento em `conversation.rb` (**A6**, ver abaixo). É a fase que
compra credibilidade para pedir orçamento das outras **[R10 §4.1]**.

**Tarefas.**

| ID | Tarefa | Esforço | Depende de | Risco de merge |
|---|---|:---:|---|---|
| **T-C0.1** | Serviço de parsing: recebe uma URL, devolve `{utm_source, utm_medium, utm_campaign, utm_term, utm_content, utm_id, gclid, gbraid, wbraid, fbclid, msclkid, ttclid}` normalizados (minúsculas nas chaves, valor preservado, truncado em limite declarado) | **P** | — | **Nenhum** (arquivo novo) |
| **T-C0.2** | Escrita dos campos parseados em `conversation.custom_attributes` no **momento da criação da conversa**, a partir do `referer` que já chega | **P** | T-C0.1 | **Baixo** — `base_controller.rb:38-44` já monta o hash; preferir o caminho de `custom_attributes` (linha 44) ao de `additional_attributes` **[R15 §B12.3]** |
| **T-C0.3** | Provisionamento das `CustomAttributeDefinition` correspondentes (namespace de origem), para que os campos **apareçam no painel e sejam filtráveis** | **P** | T-C0.2 | **Baixo** — seed/model, sem migration |
| ~~**T-C0.4**~~ | ~~Backfill: job idempotente que varre `conversations.additional_attributes->>'referer'` histórico~~ — **CORTADA em 13/08/2026 (decisão D6).** O backfill lê o que está no banco, e o que a validação anulou **não está lá**: **0 conversas com `referer` preenchido em 3.180** [mestre M12], porque `conversation.rb:536-539` anula na escrita. Cortada, não adiada — ver `PLANO-MESTRE` **A16**. **O esforço vai para BK-12/1.20** (parar de destruir o dado), que é o que faz o dado passar a existir | — | — | — |
| **T-C0.5** | Exibição no painel do agente (bloco "Origem") e **filtro** na lista de conversas usando o mecanismo de atributo customizado que já existe | **M** | T-C0.3 | **Médio** — toca `CustomAttributes.vue`/painel lateral; coordenar com **T-I2.2** para não escrever a mesma seção duas vezes |
| **T-C0.6** | Relatório mínimo: conversas por `utm_source`/`utm_medium`/`utm_campaign` no período | **M** | T-C0.4 | **Nenhum** |
| **T-C0.7** | Regra de propagação para o **contato**: `first_*` write-once, `last_*` sobrescrito só quando a nova conversa traz parâmetro de campanha ou referrer externo | **P** | T-C0.2 | **Baixo** |

**Arquivos.**

- **Novos:** serviço de parsing (sugestão de lar: `app/services/tracking/` — o **job de backfill saiu com T-C0.4**, D6) —
  pasta nova, risco de merge zero); seed/serviço de provisionamento de definições.
- **Tocados:** `app/controllers/api/v1/widget/base_controller.rb` (só para ler o `referer` que a
  linha 42 já grava — **sem** acrescentar parâmetro ao `permitted_params`); painel lateral do
  dashboard (`CustomAttributes.vue` e vizinhança) para T-C0.5.
- **Tocar, com uma linha só:** `app/models/conversation.rb` (a chamada do saneamento) —
  ver a arbitragem abaixo.

> **ARBITRADO — PLANO-MESTRE §5 A6: sanear o `referer` antes de anular, com a lógica em
> `lib/url_helper.rb:3-10` e apenas a **linha de chamada** em `app/models/conversation.rb:536-540`.**
> A instrução original desta seção — *"não tocar `conversation.rb`, o parser lida com o `nil`"* —
> **não vale mais**. Medição do mestre [M2]: `conversation.rb` teve +79/−8 do upstream em 4 commits,
> **mas o método `validate_referer_url` é byte-idêntico** entre v4.12.1 e v4.16.2 (só desceu de
> `:334` para `:405`), e `lib/url_helper.rb` teve **0/0**. O risco real é o **deslocamento** do
> arquivo, que o merge resolve — não conflito no método. Com a lógica no helper (0/0), o risco de
> BK-12 cai de **Médio** para **Baixo**.
>
> **Por que não deixar como está:** hoje uma URL com espaço não escapado ou colchete cru faz o campo
> virar `nil` **e a conversa salvar normalmente** — o dado de origem some antes de o parser existir.
> Uma frente cujo primeiro entregável é "de onde veio esse lead" não pode conviver com uma validação
> que apaga a resposta em silêncio. O parser continua tendo de lidar com `nil` (as conversas
> antigas), mas para de **produzir** `nil` daqui para frente. A alternativa de sanear em
> `base_controller.rb#permitted_params` continua **rejeitada** — é a área de maior atrito de merge.

**Antes de começar, verificar.**

1. ~~O volume real na frota (verificação 3 da §Parte D).~~ **ENCERRADA em 13/08/2026 (D6).** Ela
   existia para decidir se o backfill valia a pena; **o backfill foi cortado**, e com ele foi a
   pergunta. **T-C0.1/2/3/5/6/7 continuam** — eles sempre valeram para o fluxo novo, e agora esse é
   o escopo declarado, não uma consolação.
2. ~~Quantas conversas têm `referer` nulo por invalidação~~ — **também encerrada, e por um motivo que
   vale registrar:** o banco **não distingue** "o SDK nunca mandou" de "a validação anulou" (os dois
   gravam o mesmo `null`), então essa consulta media a soma dos dois. A separação só passaria a
   existir **depois** de BK-12/1.20, quando o que não valida vai para `referer_raw` — ou seja, a
   verificação teria de ser refeita para significar alguma coisa. Ver `PLANO-MESTRE` **A16**.
3. Se alguma conta da frota já usa `referer` em regra de automação (`automation_rule.rb:38`) — para
   não conflitar com convenção já criada por cliente.

**Critério de aceite verificável.**

- Uma conversa **antiga**, escolhida ao acaso entre as que têm `utm_` no `referer`, mostra
  `utm_source`, `utm_medium` e `utm_campaign` no painel do agente, e é encontrável por filtro.
- ~~Rodar o backfill duas vezes não altera nenhum valor na segunda passagem.~~ **Sai com T-C0.4
  (D6).**
- Uma conversa cujo `referer` foi anulado pela validação aparece como "origem não disponível", não
  como "origem direta" — a diferença entre "não sei" e "sei que é direto" precisa sobreviver. **E o
  período anterior à entrada em produção aparece rotulado como "antes da medição"**, nunca vazio nem
  zerado: vazio é lido como "não veio ninguém", que é mentira (D6, mestre bloco **1.22**).
- Nenhum campo novo aparece no painel **sem definição** (isto é: T-C0.3 tem de estar pronto antes
  de T-C0.2 chegar a produção, senão o dado grava e some — **[R19 §D.3]**).

**Riscos e armadilhas.**

- **A armadilha do nome.** `referer` no nosso schema **não é** `document.referrer`: é a URL onde o
  visitante estava quando enviou a primeira mensagem **[R07 §6.1; R10 §4.0]**. O parser não pode
  chamar isso de "origem" na tela sem qualificar, senão cria mito interno. O `document.referrer` de
  verdade só chega com **T-C2.2**.
- Um visitante que entrou por anúncio, navegou cinco páginas e só então abriu o chat **perde a
  campanha** no C0 — a landing page real só existe a partir de C2 **[R19 §B.3]**. Dizer isso na
  tela ("origem observada na página de abertura do chat") é mais barato que explicar depois.

---

## A.3 C1 — Configuração de tracking por caixa de entrada

**O que entrega.** O lugar onde o cliente cola os IDs, e a chave de tudo o mais: sem C1, nenhuma
camada client-side ou server-side sabe para onde mandar. **Escopo por inbox, não por conta** —
agência e cliente multi-site precisam de pixels diferentes por site (decisão **[R07 §7.5, 10]**).

Esta é **uma das quatro telas de configuração** do escopo aprovado pelo Walisson (aparência,
gatilhos, pré-chat, **tracking**) e é a única das quatro que pertence a esta frente.

**Tarefas.**

| ID | Tarefa | Esforço | Depende de | Risco de merge |
|---|---|:---:|---|---|
| **T-C1.1** | Modelo de configuração em `inbox.additional_attributes['widget_tracking']`, sem migration e sem tocar em `EDITABLE_ATTRS` **[R10 §4.1 C1]**; `app/models/inbox.rb:50` já usa `store_accessor` sobre esse jsonb — seguir o mesmo padrão. **Correção de premissa (ARBITRADO §5 A1): o jsonb NÃO é "livre".** Strong params rejeita chave não declarada — `inboxes_controller.rb:217` é lista fechada. A chave `widget_tracking: {}` já entra ali na **edição única** do bloco 3.01, junto de `widget_profile` e `widget_triggers`; **esta tarefa não reabre o controller** | **P** | **3.01** (a edição única do `permit`) | **Baixo** |
| **T-C1.2** | Armazenamento de **segredo** (Meta access token, GA4 api_secret) fora do jsonb público: coluna/registro cifrado, nunca exposto em endpoint de widget nem no `index` da API | **M** | T-C1.1 | **Baixo** — código novo. Ver o antipadrão em `webhooks/_webhook.json.jbuilder:6`, que devolve segredo em texto claro **[R18 §D.10.3]** |
| **T-C1.3** | Tela de configuração "Rastreio e conversões" na inbox, com os campos da tabela abaixo, ajuda inline e estado de validação por campo | **M** | T-C1.1 | **Médio** — telas do dashboard de settings de inbox |
| **T-C1.4** | Publicar a configuração **client-side** (só o que é público: Pixel ID, Measurement ID, `send_to`, mapa de eventos, modo de consentimento) nos **dois lugares**: `app/views/widgets/show.html.erb` **e** `app/views/api/v1/widget/configs/create.json.jbuilder` | **P** | T-C1.1 | **Médio** — esquecer um dos dois faz web e mobile divergirem em silêncio **[R10 §6.1]** |
| **T-C1.5** | Mapa de eventos: tabela editável "evento ChatSPX → nome no destino / ligado-desligado", com os defaults da §A.6 já preenchidos | **M** | T-C1.3, C3 | **Nenhum** |
| **T-C1.6** | Valor do lead: fixo, por regra (etiqueta, resposta de pré-chat, funil) ou desligado — é o que destrava campanha por ROAS **[R07 §7.5, 8]** | **M** | T-C1.3 | **Nenhum** |
| **T-C1.7** | OAuth de um clique para Meta (Facebook Login for Business) e Google — **é requisito de produto, não detalhe técnico**: Pixel ID e Measurement ID são triviais de colar, `access_token`, `api_secret` e OAuth do Ads não são **[R07 §5.3, §7.3]** | **G** | T-C1.2 | **Nenhum** |
| **T-C1.8** | Modo teste por inbox (`test_event_code` da Meta, DebugView do GA4), com aviso visível de que está ligado e desligamento automático após N dias | **P** | T-C1.3 | **Nenhum** |

**Campos da tela** (todos opcionais exceto onde marcado):

| Campo | Tipo | Público? | Observação |
|---|---|:---:|---|
| Meta Pixel ID | string | **sim** | vazio ⇒ só `dataLayer` |
| Meta Access Token | segredo | não | preferir OAuth (T-C1.7) |
| Meta `test_event_code` | string | não | só modo teste; a doc da Meta é explícita: *"You need to remove it when sending your production payload"* **[R07 §2.5]** |
| GA4 Measurement ID | string | **sim** | autodetectável varrendo o `dataLayer` por `['config', ID]` **[R07 §3.3]** |
| GA4 API Secret | segredo | não | só Measurement Protocol |
| Google Ads `send_to` | string | **sim** | formato `AW-XXXX/label` |
| Google Ads OAuth | conexão | não | necessário só para C9 (offline) |
| Mapa de eventos | tabela | **sim** (nomes) | **obrigatório** ter default |
| Valor do lead | número/regra | **sim** (valor calculado) | |
| Modo de consentimento | enum | **sim** | `sem CMP` / `aguardar consentimento` / `sempre negado` — **obrigatório** |
| Instalar tag faltante | booleano | **sim** | default **desligado** (decisão **Q5**: opt-in explícito, nunca por padrão) |

**Arquivos.**

- **Novos:** serviço de leitura/escrita da configuração; armazenamento cifrado de segredo; telas de
  settings da inbox (componentes novos, em pasta nova).
- **Tocados:** `app/views/widgets/show.html.erb` **e**
  `app/views/api/v1/widget/configs/create.json.jbuilder` — **os dois, sempre juntos**;
  `app/models/inbox.rb` (`store_accessor` sobre `additional_attributes`, seguindo o padrão da
  linha 50).
- **Não tocar nesta frente:** `channel_web_widgets.feature_flags` (bitmask esgotada) e
  `EDITABLE_ATTRS`. *(A restrição é da frente de tracking, não global: `EDITABLE_ATTRS` **é**
  ampliada pelo pré-chat — bloco 3.12 do mestre, T2.1 do plano 23, BE-6 do plano 24. E a
  configuração de tracking mora em `inbox.additional_attributes['widget_tracking']`, declarada na
  edição única do strong params em 3.01 — **A1**.)*

**Antes de começar, verificar.**

1. **[R10 §6.1]** Bits livres em `channel_web_widgets.feature_flags` só a partir do 6 — e a memória
   do projeto registra que a bitmask **já estourou**. Configuração estruturada vai em
   `additional_attributes`, **nunca** em bitmask. Confirmar antes de escolher o local.
2. Se a conta é enterprise ou community — decidir se a tela nasce em `enterprise/` (menor risco de
   merge, mas indisponível em conta community) ou em `app/`.
3. Verificação 2 da §Parte D (DPA): sem ela, T-C1.2/T-C1.7 podem ser construídos, mas **C5 não pode
   ser ligado** para cliente nenhum.

**Critério de aceite verificável.**

- Configurar Pixel ID em uma inbox e **não** em outra: o `window.chatwootWebChannel` da primeira
  traz o ID e o da segunda não — conferido no HTML servido, não no código.
- Nenhum segredo aparece em: HTML do widget, `GET` de config do widget, resposta de API pública, ou
  log. Verificado por busca no corpo das respostas.
- Um `curl` no endpoint de config do widget e o `show.html.erb` devolvem **o mesmo conjunto** de
  chaves de tracking (o teste que impede a divergência web × mobile).
- Modo teste ligado aparece com aviso no painel e desliga sozinho no prazo.

---

## A.4 C2 — Coletor de origem no SDK

**O que entrega.** A origem **real** da sessão (não a página onde o chat foi aberto), sobrevivendo
ao ITP porque é persistida no servidor. É o insumo de C4 (tags), C5 (server-side) e C9 (offline).

**Restrição estrutural, não negociável** **[R07 §6.3]**: o widget roda em iframe de outra origem e
**nunca** enxerga `window.fbq`, `window.dataLayer` nem `document.cookie` do site do cliente. Todo
coletor mora no **SDK (parent)**.

**Tarefas.**

| ID | Tarefa | Esforço | Depende de | Risco de merge |
|---|---|:---:|---|---|
| **T-C2.0** | **Pré-requisito de propagação** (Achado 2): resolver a entrega de versões novas do `sdk.js`. Três opções na §A.4.1 | **P/M** | — | **Baixo** (config do Rails) a **Médio** (se mexer no snippet de `web_widget.rb:64-82`) |
| **T-C2.1** | Módulo novo `app/javascript/sdk/tracking/` (pasta nova ⇒ risco zero) com o coletor: lê `location.search` (`utm_*`, `utm_id`, `gclid`, `gbraid`, `wbraid`, `fbclid`, `msclkid`, `ttclid`), `document.referrer` e a landing page da sessão | **M** | T-C2.0 | **Nenhum** (arquivo novo) + **Médio** (uma linha de registro em `IFrameHelper.js`) |
| **T-C2.2** | Persistência local: `first_*` **write-once**, `last_*` sobrescrito **apenas** quando a nova sessão tiver parâmetro de campanha ou referrer externo — navegação interna **não zera** a origem (erro clássico) **[R07 §5.2]** | **P** | T-C2.1 | **Nenhum** |
| **T-C2.3** | Derivar `_fbc` de `fbclid` no formato oficial `fb.{subdomainIndex}.{timestamp}.{fbclid}` e `_gcl_aw` de `gclid` no formato `GCL.{unix}.{gclid}`, TTL 90 dias. **Nunca fabricar `fbc` sem `fbclid` real** **[R07 §2.7, §3.7]** | **P** | T-C2.1 | **Nenhum** |
| **T-C2.4** | Ler `_fbp`, `_ga`, `_ga_<ID>`, `_gcl_aw` **por allowlist** (RC9) | **P** | T-C2.1 | **Nenhum** |
| **T-C2.5** | `gtag('get', ID, 'client_id')` e `'session_id'` **com timeout de 1 s** e fallback para leitura direta dos cookies `_ga` / `_ga_<ID sem o "G-">` — o padrão da Leadster é a implementação de referência **[R07 §3.3]** | **M** | T-C2.1 | **Nenhum** |
| **T-C2.6** | Envio ao backend pelo caminho de menor atrito: preencher `custom_attributes` no `POST /api/v1/widget/conversations`, que o front **já envia** e o controller **já aceita** (`base_controller.rb:44`) **[R15 §B12.3]** | **P** | T-C2.1 | **Baixo** |
| **T-C2.7** | Persistência no servidor com a mesma regra `first_`/`last_` do C0 (**T-C0.7**), reusando **o mesmo** provisionamento de definições (**T-C0.3**) | **P** | T-C0.7, T-C2.6 | **Baixo** |
| **T-C2.8** | Orçamento de bytes: o `sdk.js` tem **28.834 bytes** medidos **[R17 §1.2]** e orçamento declarado de 40 KB. O coletor entra **sob demanda**, só quando a inbox tem configuração ativa | **M** | T-C1.4 | **Nenhum** |

### A.4.1 T-C2.0 — as três opções de propagação do SDK

**[MEDIDO]** O estado hoje: `cache-control: public, max-age=31556952`, sem `ETag`, path sem
fingerprint, snippet sem cache-buster.

| Opção | Como | Custo | Efeito colateral |
|---|---|:---:|---|
| **(a) Baixar o `max-age` só de `/packs/js/sdk.js`** e adicionar `ETag`/revalidação | exceção em `config/environments/production.rb` (ou uma `location` no nginx da frota) | **P** | uma requisição condicional a mais por visitante por janela; propagação passa a ser de horas, não de meses |
| **(b) Versionar o path** (`/packs/js/sdk.v3.js`) e trocar o snippet | muda `web_widget.rb:64-82` — mas **todo cliente já instalado continua no path antigo** | **M** | só resolve para instalações novas; exige manter o path antigo vivo para sempre |
| **(c) SDK como carregador fino**: o `sdk.js` cacheado busca o módulo de tracking em runtime, com a URL versionada vinda da config do widget (T-C1.4), que **não é cacheada** | módulo novo + uma linha no boot | **M** | **recomendado** — o rollout de tracking passa a ser server-driven, e o arquivo eterno some do caminho crítico |

**[INFERÊNCIA] Recomendação: (a) + (c).** (a) é barato e conserta o problema de fundo para qualquer
mudança futura do SDK, inclusive as do redesenho visual; (c) faz com que esta frente não dependa de
(a) ter chegado a todos os visitantes. (b) sozinha não resolve o estoque instalado e não vale o
custo permanente.

**Antes de começar, verificar.**

1. Rodar o mesmo `curl -sSI .../packs/js/sdk.js` em **cada VM da frota** — o header é do Rails, mas
   um proxy intermediário (Cloudflare, CDN do cliente) pode reescrever. É leitura, e as VMs de
   produção respondem publicamente. (ver Ap.A4)
2. Conferir se algum cliente serve o `sdk.js` a partir de cópia própria (auto-hospedagem do
   snippet) — nesse caso nenhuma opção acima o alcança, e a comunicação precisa dizer isso.

**Critério de aceite verificável.**

- Com bloqueador de anúncio **ligado**, a coleta de origem continua funcionando (é `location.search`
  e `document.referrer`, não requer rede de terceiro).
- Um visitante que chega por `?utm_source=google&gclid=X`, navega 5 páginas internas e **só então**
  abre o chat: a conversa nasce com `first_utm_source=google` e o `gclid` correto.
- O mesmo visitante volta uma semana depois por link direto: `first_*` **não muda**, `last_*`
  **não é zerado** por navegação interna.
- No Safari, depois de 7+ dias sem visita, a origem **continua** disponível — porque está no
  servidor, não no `localStorage` **[R07 §5.5]**.
- O peso do `sdk.js` medido depois da mudança continua dentro do orçamento declarado, e o CI falha
  se estourar.

---

## A.5 C3 — Contrato de eventos

**O que entrega.** Os nomes estáveis e o momento exato de cada disparo. É a peça que a frente de
integração e a de tracking **compartilham** — e o item 2 da tabela de fronteira (§Parte C).

**Gap de infraestrutura que bloqueia tudo** **[R09 §4.5, via R10 §4.1 C3]**: hoje **não existe**
evento de conversa criada com `conversation_id`, nem de pré-chat submetido, nem de CSAT respondido.
O `chatwoot:on-start-conversation` é **intenção** (dispara no clique), não conclusão. **Sem esses
eventos, não há o que disparar.** A boa notícia: o padrão `IFrameHelper.events.onEvent`
(`IFrameHelper.js:206-207`) permite adicionar evento novo **sem tocar no SDK** — basta declarar a
constante em `sdkEvents.js` (7 linhas) e emitir do widget.

**Tarefas.**

| ID | Tarefa | Esforço | Depende de | Risco de merge |
|---|---|:---:|---|---|
| **T-C3.1** | Escrever o contrato: nome, quando dispara, parâmetros, tipo, destino, exemplo — a tabela da §A.6 vira documento versionado | **P** | — | **Nenhum** |
| **T-C3.2** | Emitir `conversation_created` **com `conversation_id`** (conclusão, não intenção) | **P** | — | **Baixo** — `sdkEvents.js` + emissão |
| **T-C3.3** | Emitir `prechat_submitted` | **P** | — | **Alto** se editar `PreChat/Form.vue` por dentro (16 commits upstream, +39 −33 desde a base **[R15 §B12.3]**) → emitir a partir do store/ação, não do componente |
| **T-C3.4** | Emitir `message_sent_by_visitor` | **P** | — | **Médio** |
| **T-C3.5** | Emitir `csat_submitted` | **P** | — | **Baixo** |
| **T-C3.6** | Emitir `campaign_shown` (teaser/campanha exibida) | **P** | — | **Baixo** |
| **T-C3.7** | Emitir `lead_identified` — o momento em que o contato passa a ter e-mail **ou** telefone. É server-side por natureza (o backend é quem sabe) | **M** | — | **Nenhum** (listener novo) |
| **T-C3.8** | **Refatorar antes de estender**: a cadeia de `else if` em `App.vue:258-345` vira mapa `{evento: handler}` **[R09 §15.4; R10 §6.1]** | **M** | — | **Médio** — mas **reduz** o risco futuro. Fazer **antes** de T-C3.2..6 |
| **T-C3.9** | Registro server-side do evento (tabela própria, com `event_id`, inbox, conversa, contato, payload de parâmetros e status por destino) — é o que C5, C6 e C8 consomem | **M** | — | **Nenhum** |

**Arquivos.**

- **Novos:** listener/serviço de `lead_identified`; modelo e migration do registro de evento
  (T-C3.9); documento de contrato (T-C3.1).
- **Tocados:** `app/javascript/widget/constants/sdkEvents.js` (7 linhas, muda pouco upstream);
  `App.vue:258-345` **uma vez só**, na refatoração de T-C3.8; as ações do store que já sabem quando
  cada fato aconteceu.
- **Não tocar por dentro:** `PreChat/Form.vue`, `ChatFooter.vue`, `ChatInputWrap.vue` — campo minado
  **[R15 §B12.3]**; emitir do store (regra **RG3**).

**Antes de começar, verificar.**

1. Se o `track()` da frente de integração (**T-I3.1**) vai reusar o mesmo registro de **T-C3.9** —
   e a resposta precisa ser sim (§Parte C, item 3). Decidir **antes** de modelar a tabela.
2. Se o evento `webwidget.triggered` existente (`lib/events/types.rb:14`) deve virar
   `widget_opened` do contrato novo ou conviver — recomendo conviver e mapear, porque ele já é
   consumido por `webhook_listener.rb:65` e `agent_bot_listener.rb:36`.

**Critério de aceite verificável.**

- Uma conversa iniciada produz, na ordem: `widget_opened` → `conversation_created` (com id) →
  `prechat_submitted` (se houver pré-chat) → `lead_identified` (se houver e-mail/telefone).
- Cada evento chega ao `window` do site como `CustomEvent` e é observável por
  `window.addEventListener` — verificado em navegador real.
- Renomear um evento **quebra o CI** (teste de contrato), porque nome de evento é contrato público
  e um rename derruba o GTM de todos os clientes **[R07 §3.5]**.
- Todo nome respeita: prefixo fixo, `snake_case`, ≤ 40 caracteres (limite do GA4 **[R07 §3.2]**).

---

## A.6 A tabela mestre de eventos

Contrato proposto. Nomes com prefixo fixo `chatspx_`, `snake_case`, ≤ 40 caracteres. Base:
**[R07 §7.2]** e **[R10 §4.1 C3]**, com as colunas de parâmetro e PII acrescentadas aqui.

| # | Evento ChatSPX | Quando dispara | Parâmetros | Meta Pixel | GA4 | Google Ads | Server-side | `event_id`? | PII? |
|---:|---|---|---|---|---|---|:---:|:---:|:---:|
| 1 | `chatspx_widget_loaded` | SDK pronto (`chatwoot:ready`) | `inbox_id` | — | — | — | não | não | não |
| 2 | `chatspx_widget_opened` | bolha aberta | `inbox_id`, `page_url` | `ChatOpened` (custom) | `chatspx_widget_opened` | — | opcional | não | não |
| 3 | `chatspx_conversation_started` | 1ª mensagem do visitante / conversa criada | `conversation_id`, `inbox_id`, `first_utm_*` | **`Contact`** (padrão) | `chatspx_conversation_started` | — | **sim** | **sim** | não |
| 4 | `chatspx_prechat_submitted` | pré-chat concluído | **nomes** dos campos preenchidos, nunca os valores | **`CompleteRegistration`** | `chatspx_prechat_submitted` | — | **sim** | **sim** | só server |
| 5 | `chatspx_lead` | contato passa a ter e-mail **ou** telefone | `value`, `currency`, `lead_source`, `conversation_id` | **`Lead`** | **`generate_lead`** | `conversion` (`send_to`) | **sim** | **sim** | **só server, hasheada** |
| 6 | `chatspx_lead_qualified` | regra / agente / IA marca como qualificado | `value`, `currency`, `qualification_reason` | `QualifiedLead` (custom) | **`qualify_lead`** | conversão secundária | **sim** | **sim** | só server |
| 7 | `chatspx_lead_disqualified` | descartado | `disqualified_lead_reason` | — | **`disqualify_lead`** | — | opcional | não | não |
| 8 | `chatspx_agent_engaged` | agente humano assume | `lead_status`, `agent_id` | — | **`working_lead`** | — | opcional | não | não |
| 9 | `chatspx_meeting_scheduled` | agendamento confirmado | `scheduled_at` | **`Schedule`** | `chatspx_meeting_scheduled` | conversão | **sim** | **sim** | só server |
| 10 | `chatspx_conversation_resolved` | conversa resolvida | `resolution`, `duration_s` | — | `chatspx_conversation_resolved` | — | opcional | não | não |
| 11 | `chatspx_deal_won` | negócio ganho (funil/CRM) | `value`, `currency`, `gclid`, `deal_id` | **`Purchase`** (offline) | **`close_convert_lead`** | **Offline Import** | **só server** | **sim** | só server |
| 12 | `chatspx_deal_lost` | negócio perdido | `unconvert_lead_reason` | — | **`close_unconvert_lead`** | — | opcional | não | não |

> **ARBITRADO — PLANO-MESTRE §5 A9: dois nomes, uma emissão, mapa publicado.** Esta tabela é o
> vocabulário de **tracking** (GA4, Meta, `dataLayer`) e continua como está. O vocabulário de
> **`window`** — o que o site do cliente escuta — mantém o namespace `chatwoot:` e está em
> `24-plano-backend-dados.md` §17.1. Não é duplicação: são dois contratos com públicos distintos,
> **com uma emissão só** (RG4). O mapa 1:1 é publicado no bloco 5.15:
>
> | Fato | Evento de `window` | Evento de tracking (esta tabela) |
> |---|---|---|
> | conversa criada no servidor | `chatwoot:conversation-created` | `chatspx_conversation_started` (#3) |
> | pré-chat concluído | `chatwoot:prechat-submitted` | `chatspx_prechat_submitted` (#4) |
> | visitante enviou mensagem | `chatwoot:message-sent` | — (sinal interno) |
> | CSAT respondido | `chatwoot:csat-submitted` | `chatspx_csat_submitted` ⚠ |
> | teaser/campanha exibida | `chatwoot:campaign-shown` | — |
> | contato passou a ter e-mail ou telefone | — (server-side) | `chatspx_lead` (#5) |
>
> ⚠ `chatspx_csat_submitted` **não consta dos 12 eventos desta tabela** — o mapa do mestre o prevê,
> a tabela não o define. Ponto a fechar em 5.15: ou ele entra como evento #13 (com parâmetros,
> canais e política de PII declarados como os outros), ou o CSAT vai só ao `window` e o mapa perde
> essa linha. **Não implementar antes de decidir**, para não nascer evento sem contrato.

**Regras do contrato:**

1. Eventos 3, 4, 5, 6, 9 e 11 nascem com **`event_id` gerado no backend** (RC7) e vão pelos dois
   caminhos com o mesmo id.
2. Eventos 11 e 12 são **exclusivamente server-side** — o navegador já não existe.
3. Todos são empurrados ao `dataLayer` **sempre** (RC4), independentemente de haver `fbq`/`gtag`.
4. Nenhum evento leva PII crua ao `dataLayer` nem aos params do `fbq`/`gtag` (RC5).
5. **A família GA4 completa** (`generate_lead` → `qualify_lead` → `working_lead` →
   `disqualify_lead` → `close_convert_lead` / `close_unconvert_lead`) é exatamente o modelo mental
   de um chat de qualificação, e **nenhum fornecedor de chat estudado a usa inteira**
   **[R07 §3.2]**. Usar os nomes recomendados (decisão **[R07 §7.5, 6]**) habilita relatório pronto
   no GA4 do cliente e é diferencial verificável.

---

## A.7 C4 — Ponte de tags client-side (Meta Pixel, GA4, Google Ads, dataLayer)

**O que entrega.** O cliente cola dois IDs e vê a conversão do chat aparecer no Gerenciador de
Anúncios e no GA4 dele. É a camada que o comprador percebe primeiro — e a que mais pode quebrar o
site do cliente se for feita errado.

**Precedência em runtime**, decidida em **[R07 §2.4]** e reafirmada aqui:

1. Pixel ID configurado **e** existe `window.fbq` → **`trackSingle`** naquele ID, com `eventID`.
2. Pixel ID configurado e **não** existe `fbq` → instalar com **`skipPageView = true`** e disparar
   `trackSingle` — **só se** o cliente tiver marcado "instalar tag faltante" (decisão **Q5**:
   opt-in explícito, nunca padrão).
3. **Sempre, em paralelo e independentemente de 1 e 2** → `dataLayer.push` com nome prefixado.

**Tarefas.**

| ID | Tarefa | Esforço | Depende de | Risco de merge |
|---|---|:---:|---|---|
| **T-C4.1** | Módulo `sdk/tracking/tags.js` (pasta nova): recebe o evento vindo do iframe e decide o disparo | **M** | T-C2.1, T-C1.4, C3 | **Nenhum** (arquivo novo) |
| **T-C4.2** | Detecção do que já existe na página: `window.fbq.getState().pixels` para Meta e varredura do `dataLayer` por `['config', ID]` para GA4 — o padrão da Leadster, que vale copiar **[R07 §4.1.6]** | **P** | T-C4.1 | **Nenhum** |
| **T-C4.3** | Instalação condicional da tag faltante com `skipPageView`, atrás do toggle de opt-in | **P** | T-C4.2, T-C1.3 | **Nenhum** |
| **T-C4.4** | Disparo Meta: `fbq('trackSingle', <pixel>, <evento>, <params>, { eventID })` (RC3 + RC7) | **P** | T-C4.1 | **Nenhum** |
| **T-C4.5** | Disparo GA4: `gtag('event', <nome>, { …params, send_to: <measurementId> })` (RC3) | **P** | T-C4.1 | **Nenhum** |
| **T-C4.6** | Disparo Google Ads: `gtag('event', 'conversion', { send_to: 'AW-XXXX/label', value, currency, transaction_id })` | **P** | T-C4.1 | **Nenhum** |
| **T-C4.7** | `dataLayer.push` sempre, com `event: 'chatspx_*'` e parâmetros sem PII (RC4 + RC5) | **P** | T-C4.1 | **Nenhum** |
| **T-C4.8** | Guarda de exceção: **nada** dentro da ponte pode lançar exceção não capturada. Uma exceção dentro de uma tag do GTM **quebra as tags seguintes do contêiner** **[R20 §2.2]** | **P** | T-C4.1 | **Nenhum** |
| **T-C4.9** | Carregamento sob demanda: a ponte só é buscada quando a inbox tem configuração ativa (orçamento de bytes — **T-C2.8**) | **P** | T-C2.8 | **Nenhum** |
| **T-C4.10** | Modo "somente `dataLayer`" como **padrão seguro** de fábrica: quem não configurar nada não tem tag nossa disparando no site dele | **P** | T-C4.1 | **Nenhum** |

**Diferenças deliberadas em relação à referência de mercado** (a Leadster), que valem como
argumento técnico verificável **[R07 §7.3 C3]**:

| # | Nós | Leadster |
|---:|---|---|
| 1 | `trackSingle` | `track` — vaza para todos os pixels da página |
| 2 | `eventID` presente ⇒ dedup com o server-side | sem `eventID` ⇒ **sem dedup** |
| 3 | `send_to` explícito no GA4 | dispara em todas as propriedades configuradas |
| 4 | `dataLayer.push` sempre | só em alguns caminhos |
| 5 | **nunca** um GA4 nosso no site do cliente (RC1) | instala `G-43W2WYML5H` por padrão |

**Arquivos.**

- **Novos:** `app/javascript/sdk/tracking/tags.js` e vizinhos (pasta nova ⇒ conflito zero).
- **Tocados:** `IFrameHelper.js` — **uma linha** de registro do handler, nada mais (o arquivo tem 10
  commits upstream em 36 meses **[R15 §B12.2]**).
- **Não tocar:** nada dentro do iframe. A ponte de tags é código de `window` do cliente, por
  definição arquitetural **[R07 §6.3]**.

**Antes de começar, verificar.**

1. Se o site do cliente usa **Consent Mode** — a ponte precisa consultar o estado de C7 **antes**
   de qualquer disparo. Construir C4 sem o gancho de consentimento significa reabrir o arquivo
   depois.
2. Se há sites da frota com **múltiplos pixels** (agência) — é o cenário que justifica o
   `trackSingle` e o melhor caso de teste.
3. O peso do `sdk.js` **antes** de começar, para comparar depois (o orçamento é medido, não sentido).

**Critério de aceite verificável** (é a lista de QA de **[R07 §8.2]**, aplicada):

- Página **sem** pixel: o widget instala (se opt-in) e **não** dispara `PageView` duplicado.
- Página **com** o mesmo pixel: **não** há duplicidade.
- Página com **três pixels diferentes**: o evento **não** vaza para os outros dois.
- `window.gtag` e `window.dataLayer` do cliente continuam funcionais depois do widget carregar.
- Console do navegador **limpo** no site do cliente.
- Uma chamada malformada colada numa tag de HTML customizado do GTM **não derruba** as tags
  seguintes do contêiner.
- Com CMP negando consentimento: **nenhum** evento client-side dispara.
- O `dataLayer` **não contém** e-mail, telefone ou nome em claro — verificado por inspeção do objeto
  em navegador real.

---

## A.8 C5 — Fila server-side: Meta CAPI, GA4 Measurement Protocol, Enhanced Conversions

**O que entrega.** Recupera os **20–40%** de eventos perdidos por bloqueador e ITP **[R07 §2.5]**, e
entrega ao cliente o benefício do server-side **sem ele operar servidor nenhum** — que é o
posicionamento mais forte de toda a pesquisa **[R07 §3.6]**. É a camada que exige credencial e a que
o jurídico precisa liberar (verificação 2 da §Parte D).

**Por que o chat é o candidato perfeito** — vale registrar no plano porque é argumento de venda, não
só arquitetura **[R07 §2.5]**: o chat é a única superfície do site que coleta **e-mail e telefone
validados** como parte do produto (os dois campos de maior peso em EMQ), tem IP e user-agent do
visitante no servidor, sobrevive ao bloqueador, conhece o desfecho comercial e tem identidade
persistente (`contact_id` como `external_id`).

**Tarefas.**

| ID | Tarefa | Esforço | Depende de | Risco de merge |
|---|---|:---:|---|---|
| **T-C5.1** | Fila e job por evento, idempotente pelo `event_id`, com backoff exponencial, **5 tentativas** e dead-letter queue visível no painel (a Leadster usa 3 **[R07 §4.1.5]**) | **M** | T-C3.9 | **Nenhum** |
| **T-C5.2** | Normalização **antes** do hash, por destino: Meta = só dígitos com DDI; Google = **E.164**. Telefone sem código de país simplesmente não casa **[R07 §2.5, §3.7]** | **M** | T-C5.1 | **Nenhum** |
| **T-C5.3** | Hash SHA-256 no servidor (RC6) de `em`, `ph`, `fn`, `ln`, `ct`, `st`, `country`, `external_id`. **Nunca** hashear `fbp`, `fbc`, `client_ip_address`, `client_user_agent` **[R07 §2.5, §2.7]** | **P** | T-C5.2 | **Nenhum** |
| **T-C5.4** | Cliente da **Meta CAPI**: `POST /v{n}/{PIXEL_ID}/events`, `action_source: website`, `event_source_url`, `user_data` completo, `custom_data` com `value`/`currency`. Respeitar: até 1.000 eventos por request, `event_time` até 7 dias, offline até 62 dias **[R07 §2.5]** | **M** | T-C5.3, T-C1.2 | **Nenhum** |
| **T-C5.5** | Cliente do **GA4 Measurement Protocol**: `POST /mp/collect?measurement_id&api_secret`, com `client_id`, `session_id`, `engagement_time_msec`, bloco `consent`. Limites: 25 eventos/request, 25 params/evento, corpo < 130 kB, backdating 72 h (48 h para atribuição correta) **[R07 §3.4]** | **M** | T-C5.3, T-C2.5 | **Nenhum** |
| **T-C5.6** | **Enhanced Conversions for Leads** (Google Ads): `sha256_email_address`, `sha256_phone_number` (E.164), `sha256_first_name`, `sha256_last_name`, e `city`/`region`/`postal_code`/`country` **sem hash** **[R07 §3.7]** | **M** | T-C5.3, T-C1.7 | **Nenhum** |
| **T-C5.7** | Roteador de decisão GA4 (RC8): se há `gtag` na página → o evento vai **pelo navegador**; se não há, ou o evento é tardio → **Measurement Protocol** com `client_id`/`session_id` guardados. **Nunca os dois** | **P** | T-C5.5 | **Nenhum** |
| **T-C5.8** | IP e user-agent **do visitante** (RC10) — o backend já parseia user-agent em `base_controller.rb:62` (`browser_params`) | **P** | T-C5.4 | **Baixo** |
| **T-C5.9** | Modo "sem PII": envia só `fbp`/`fbc`/`gclid`/`external_id` e nenhum campo hasheado de pessoa. É o modo em que a feature pode operar **enquanto o DPA não existir** (verificação 2) | **P** | T-C5.4 | **Nenhum** |
| **T-C5.10** | Batch e throttling por conta, com métrica de custo — a CAPI aceita até 1.000 eventos por request **[R07 §7.6]** | **M** | T-C5.4 | **Nenhum** |

**Arquivos.**

- **Novos, todos:** clientes HTTP dos três destinos, normalizadores, hasher, jobs e DLQ — em
  `app/services/tracking/` ou `enterprise/app/services/…`. **Risco de merge: nenhum.**
- **Tocados:** nada do widget. C5 não encosta em front.
- Reusar `browser_params` (`base_controller.rb:62`) para o `client_user_agent`, em vez de reparsear.

**Antes de começar, verificar.**

1. **Verificação 2 (DPA) — bloqueante para o modo com PII.** Sem ela, só **T-C5.9** pode ir ao ar.
2. A versão corrente da Graph API a usar no endpoint da CAPI (a doc do estudo cita `v25.0` como
   exemplo em 08/2026 **[R07 §2.5]**; confirmar a versão vigente no momento da implementação e
   fixá-la em configuração, não no código).
3. Se a Meta exige revisão de app / permissão específica para o System User Token na conta do
   cliente — **[NÃO VERIFICADO]** por qualquer relatório do estudo.

**Critério de aceite verificável.**

- No Events Manager do cliente, o evento `Lead` aparece com origem **Browser e Server**, e o total
  **não dobra**.
- EMQ ≥ 6,0 (alvo 8,0 para eventos com PII) **[R07 §2.8]**.
- Bloqueador de anúncio ligado: o client-side falha e o **server-side entrega** — comprovado no
  mesmo evento.
- Um destino que devolve 5xx: a retentativa acontece e, depois da última, o evento aparece na DLQ
  visível — não some.
- Nenhum segredo aparece em log, em resposta de API pública ou no navegador.
- No modo "sem PII", nenhum campo `em`/`ph`/`fn`/`ln` sai — verificado no log de auditoria de C8,
  que registra **nomes** de campos enviados.

---

## A.9 C6 — Deduplicação

**O que entrega.** O item de melhor relação "impacto de credibilidade ÷ esforço" da frente inteira:
**nem a Leadster faz** — o bundle dela não passa `eventID` ao `fbq` **[R07 §4.1.3]** — e o cliente
verifica em 30 segundos no Events Manager dele.

**A regra, literal da Meta** **[R07 §2.6]**: a chave é o par **(`event_id`, `event_name`)**, e
*"events are only deduplicated if they are received within 48 hours of when we receive the first
event with a given `event_id`"*. Sem `event_id`, a Meta tenta por `event_name` + `fbp`, mas só
funciona na ordem navegador→servidor. Dedup **não** olha `em`/`ph` — esses servem para *matching*.

**Tarefas.**

| ID | Tarefa | Esforço | Depende de | Risco de merge |
|---|---|:---:|---|---|
| **T-C6.1** | `event_id` (UUID v4 ou ULID) gerado no backend **uma vez por ação do usuário**, persistido no registro de evento (T-C3.9) e devolvido ao widget (RC7) | **P** | T-C3.9 | **Nenhum** |
| **T-C6.2** | Propagação ao `fbq` como `{ eventID }` e ao payload CAPI como `event_id` | **P** | T-C6.1, T-C4.4, T-C5.4 | **Nenhum** |
| **T-C6.3** | Guarda de janela: se o envio server-side for atrasar além das 48 h (fila entupida, retry longo), **não** mandar como par — mandar como evento server-only e registrar o motivo | **P** | T-C5.1 | **Nenhum** |
| **T-C6.4** | Teste de QA automatizado que compara contagens client × server em ambiente de teste com `test_event_code` | **M** | T-C1.8 | **Nenhum** |

**Arquivos.** Nenhum arquivo novo além do gerador de id (serviço pequeno) — C6 é, na prática, uma
disciplina aplicada a C4 e C5, não uma camada com superfície própria. **Risco de merge: nenhum.**

**Critério de aceite verificável.** No Test Events da Meta, os dois eventos aparecem com **o mesmo
`event_id`** e o painel mostra a deduplicação reconhecida. Uma amostragem de 20 pares no Events
Manager em produção fecha 100%.

---

## A.10 C7 — Consentimento (Consent Mode v2 e LGPD)

**O que entrega.** A camada que permite ligar a feature na Europa sem perder sinal e no Brasil sem
expor o cliente ao Guia Orientativo de Cookies da ANPD **[R07 §3.8, §3.9]**.

**O que a Google exige, literal** **[R07 §3.8]**: os quatro sinais (`ad_storage`,
`analytics_storage`, `ad_user_data`, `ad_personalization`), com `default` **antes** de qualquer
comando de medição e `update` depois do aceite — *"The order of the code here is vital. If your
consent code is called out of order, consent defaults won't work."*

**Tarefas.**

| ID | Tarefa | Esforço | Depende de | Risco de merge |
|---|---|:---:|---|---|
| **T-C7.1** | Método público no SDK para o CMP do cliente chamar, com os quatro sinais | **M** | I1 (retorno e fila) | **Médio** — entra na API pública; **precisa herdar o contrato estabilizado de T-I1.x**, senão nasce mudo como os outros sete |
| **T-C7.2** | Estado de consentimento por conta/inbox: `sem CMP` / `aguardar consentimento` / `sempre negado`, com o **padrão negado** para quem declarar operar sob CMP (decisão **[R07 §7.5, 9]**) | **P** | T-C1.1 | **Baixo** |
| **T-C7.3** | Gate no client-side: nenhum disparo de C4 sem estado permitido | **P** | T-C4.1, T-C7.2 | **Nenhum** |
| **T-C7.4** | Campo `consent` no payload do Measurement Protocol e respeito ao estado nos envios da CAPI | **P** | T-C5.5 | **Nenhum** |
| **T-C7.5** | Ordem de execução correta: `default` antes de qualquer medição nossa; nunca emitir `default` se o site do cliente já emitiu o dele (RC2 — aditivo, não destrutivo) | **P** | T-C7.3 | **Nenhum** |
| **T-C7.6** | Persistência do estado de consentimento junto ao contato/conversa, para auditoria posterior | **P** | T-C7.2 | **Baixo** |

**Arquivos.**

- **Novos:** módulo de consentimento em `sdk/tracking/`; serviço de estado no backend.
- **Tocados:** `app/javascript/entrypoints/sdk.js` (o método público novo) — **depois** de T-I1.4,
  para nascer com retorno e sem exceção não capturada; `App.vue` pelo mapa de handlers (T-I1.5).

**Antes de começar, verificar.**

1. Verificação 2 (DPA) — C7 é a camada que **implementa** a resposta jurídica; sem a resposta, ela
   é construída mas não define a política.
2. Se alguma conta da frota já opera com CMP (banner de cookies) — para escolher o default por conta
   com base em fato, não em suposição.

**Critério de aceite verificável.** Com CMP negando: nenhum evento client-side dispara e o payload
server-side carrega `consent` negado. Com CMP aceitando depois: o `update` chega e os eventos
subsequentes disparam. Revogação posterior volta ao estado negado **na mesma sessão**.

---

## A.11 C8 — Auditoria, diagnóstico e documentação pública

**O que entrega.** A diferença entre uma feature que dá certo e uma que gera chamado eterno
("não apareceu no Gerenciador"). E, junto, o ativo comercial mais barato da frente: **a documentação
que a Leadster não tem** — o artigo oficial deles sobre eventos é essencialmente um vídeo, sem
especificação escrita de nomes, parâmetros ou payloads **[R07 §4.1.7]**.

**Tarefas.**

| ID | Tarefa | Esforço | Depende de | Risco de merge |
|---|---|:---:|---|---|
| **T-C8.1** | Log de auditoria por evento: `event_id`, destino, `event_name`, **lista de nomes** dos campos enviados (nunca os valores), timestamp, status HTTP, mensagem de erro, EMQ quando disponível | **M** | T-C5.1 | **Nenhum** |
| **T-C8.2** | Retenção configurável do log (sugestão 90 dias) e expurgo automático | **P** | T-C8.1 | **Nenhum** |
| **T-C8.3** | Painel de diagnóstico por inbox: últimos N eventos, taxa de entrega, erros agrupados, botão de reenvio | **M** | T-C8.1 | **Nenhum** |
| **T-C8.4** | Kill switch por conta **e** por inbox | **P** | T-C1.1 | **Baixo** |
| **T-C8.5** | Exibir o **EMQ estimado** como métrica de saúde da integração — um chat bem instrumentado junta nove sinais (`em`, `ph`, `fn`, `ln`, `external_id`, IP, UA, `fbp`, `fbc`), o que deveria colocar o cliente na faixa 8+ sem esforço dele **[R07 §2.8]** | **M** | T-C8.1 | **Nenhum** |
| **T-C8.6** | **Página pública de contrato**: cada evento com nome, quando dispara, parâmetros, tipo, exemplo de payload, e a tabela de limites. Escrita **junto** com C3, não depois (decisão **I6**) | **M** | T-C3.1 | **Nenhum** |
| **T-C8.7** | Guia de verificação para o cliente: como conferir no Events Manager, no GA4 DebugView e no Tag Assistant | **P** | T-C8.6 | **Nenhum** |

**Arquivos.** Modelo de log e telas — todos novos. **Risco de merge: nenhum.** A página pública
(T-C8.6) sai do repositório de documentação, não do produto.

**Critério de aceite verificável.** Um agente de suporte consegue responder "o evento saiu?" sem
abrir o console de ninguém, olhando só o painel de C8. E o log **não contém** nenhum valor de PII —
verificado por inspeção direta do registro.

---

## A.12 C9 — Ciclo fechado: conversão offline e `ctwa_clid`

**O que entrega.** O espaço em branco do mercado: **nenhum** fornecedor de chat brasileiro devolve
a venda fechada para o Ads/Meta com valor real **[R07 §4.10]**. E o `ctwa_clid`, que pode valer
comercialmente **mais que o pixel do site**, porque resolve um problema que o cliente **não
consegue** resolver sozinho **[R07 §2.10]**.

### A.12.1 Conversão offline (Google Ads e Meta)

| ID | Tarefa | Esforço | Depende de | Risco de merge |
|---|---|:---:|---|---|
| **T-C9.1** | Guardar `gclid` no **contato** com timestamp, e mantê-lo acessível pela janela de 90 dias (o Google retém o `gclid` por 90 dias **[R07 §3.7]**) | **P** | T-C2.7 | **Baixo** |
| **T-C9.2** | Gatilho de "negócio ganho": a partir do funil/Kanban ou de etiqueta configurável, produzindo o evento 11 da §A.6 | **M** | T-C3.9 | **Nenhum** |
| **T-C9.3** | Upload de `ClickConversion` para a Google Ads API (`gclid` **e** `user_identifiers` juntos, como a doc recomenda), com frequência **ao menos diária** para o Smart Bidding responder **[R07 §3.7]** | **G** | T-C1.7, T-C9.1 | **Nenhum** |
| **T-C9.4** | `Purchase` para a Meta via CAPI com `action_source` adequado e janela offline de 62 dias | **M** | T-C5.4 | **Nenhum** |
| **T-C9.5** | `close_convert_lead` / `close_unconvert_lead` para o GA4 via Measurement Protocol | **P** | T-C5.5 | **Nenhum** |
| **T-C9.6** | Alerta de janela: avisar quando um negócio ganho tem `gclid` **fora** da janela de 90 dias (ou 63 dias no caminho com PII) — o cliente precisa saber que aquela venda não vai voltar para a campanha | **P** | T-C9.3 | **Nenhum** |

### A.12.2 `ctwa_clid` — Click-to-WhatsApp

**Estado real, verificado nesta task** (Achado 1) — isto muda a estimativa do estudo:

| Peça | Estado |
|---|---|
| Ingestão do objeto `referral` do WhatsApp Cloud | **já existe** — `incoming_message_base_service.rb:194`, cópia integral do objeto |
| Consumo pela IA | **já existe** — `open_ai_message_builder_service.rb:104-117` |
| Exibição no painel | **já existe** — `ReferralCard.vue` via `Message.vue:971-972` |
| `ctwa_clid` presente no objeto recebido | **[NÃO VERIFICADO]** — depende do que a Meta envia; resolvido por consulta (Ap.A2) |
| Uso do `ctwa_clid` para CAPI | **não existe** |
| Cobertura WAHA | **fora de escopo** até haver evidência (Achado 3) |

| ID | Tarefa | Esforço | Depende de | Risco de merge |
|---|---|:---:|---|---|
| **T-C9.7** | Consulta de verificação: existe `ctwa_clid` dentro de `content_attributes->'referral'` na frota? (Ap.A2) | **P** | acesso de leitura à produção | — |
| **T-C9.8** | Promover `referral` a atributo de **conversa** (hoje vive só na mensagem), com `source_id`, `source_type`, `ctwa_clid` e `source_url` legíveis e filtráveis | **P** | T-C9.7 | **Baixo** |
| **T-C9.9** | Evento CAPI com `action_source: "business_messaging"`, `messaging_channel: "whatsapp"` e `ctwa_clid` — sem os três, o evento é aceito mas **não é atribuído ao anúncio**, o algoritmo não aprende e o CPL sobe **[R07 §2.10]** | **M** | T-C5.4, T-C9.8 | **Nenhum** |
| **T-C9.10** | Configuração de tracking também na inbox de **WhatsApp** (a tela de C1 hoje é pensada para Website) | **M** | T-C1.3 | **Baixo** |

**Arquivos.**

- **Novos:** cliente da Google Ads API, job de upload, serviço de promoção do `referral`.
- **Tocados:** nada do widget. Eventualmente `app/services/whatsapp/incoming_message_base_service.rb`
  — mas **só se** for preciso promover o `referral` para a conversa no momento da ingestão; a
  alternativa sem tocar nele é um listener que lê `content_attributes` depois. **Preferir o
  listener**: esse arquivo é caminho quente de mensagens de WhatsApp.

**Critério de aceite verificável.** Uma conversa iniciada por anúncio Click-to-WhatsApp aparece no
painel com a campanha identificada, e o evento correspondente é atribuído ao anúncio no Gerenciador
— não apenas aceito.

---

## A.13 GTM server-side: o que fazemos e o que não fazemos

Registro explícito porque é a pergunta que toda agência faz.

**Não construímos sGTM.** **[R07 §3.6]** O custo de mercado (Stape a partir de US$ 17–20/mês, com a
armadilha de contagem de requests que inclui carregamentos de script; Cloud Run com custo de infra)
e a operação exigida colocam isso fora do perfil da base típica do ChatSPX. E o argumento decisivo:
**o ChatSPX já é o servidor** que tem o dado — entregamos o benefício do server-side sem o cliente
operar container nenhum.

**Somos uma fonte limpa para quem já tem.** Três compromissos:

1. `dataLayer` documentado e estável — o cliente com sGTM pluga o container dele no nosso evento.
2. Webhook com os mesmos eventos, para quem prefere consumir server-to-server (§B.5).
3. Nenhuma tentativa de substituir CDP (Segment/RudderStack) de quem já tem **[R07 §5.4]**.

**Regra de segmentação comercial** **[R07 §5.4]**: cliente com menos de ~R$ 5 mil/mês em mídia e sem
agência → client-side + CAPI feito por nós, e **não** vender sGTM. Acima de ~R$ 50 mil/mês com time
de dados → ser fonte, não competir.

---

## A.14 Consolidado da frente de tracking

| Camada | Entrega | Esforço | Depende de | Risco de merge | Bloqueada por verificação? |
|---|---|:---:|---|---|---|
| **C0** parser **prospectivo** (D6: deixou de ser retroativo) | origem para toda conversa **nascida a partir da entrada em produção** — nunca "100% da base", que era premissa falsa nesta base [mestre M12] | **P** | nada | **Nenhum** | **não** — a verificação nº 3 foi encerrada com o backfill |
| **C1** config por inbox | onde o cliente cola os IDs | **M** | — | **Baixo/Médio** | não |
| **C2** coletor no SDK | first/last touch, `_fbc`/`_gcl_aw`, `client_id` | **M** | C1, **T-C2.0** | **Nenhum/Médio** | nº 4 (propagação) |
| **C3** contrato de eventos | o que disparar e quando | **P/M** | I1 (estabilização) | **Baixo/Médio** | não |
| **C4** ponte de tags | pixel/GA4/Ads no site do cliente | **M** | C1, C2, C3, C7 | **Nenhum/Médio** | nº 4 |
| **C5** fila server-side | recupera 20–40% perdidos | **G** | C1, C3 | **Nenhum** | **nº 2 (DPA)** para o modo com PII |
| **C6** dedup | credibilidade verificável | **P** | C4, C5 | **Nenhum** | não |
| **C7** consentimento | conformidade LGPD/GDPR | **M** | C4, C5, I1 | **Baixo/Médio** | nº 2 |
| **C8** auditoria e doc | suporte e prova de valor | **M** | C5 | **Nenhum** | não |
| **C9** offline + CTWA | ciclo fechado | **G** (offline) / **M** (CTWA) | C5 + funil | **Nenhum/Baixo** | **nº 1** para CTWA |

**Ordem inegociável:** **C0 antes de tudo** **[R10 §4.2]**. Depois, a sequência que respeita as
dependências reais é **C3 → C1 → C2 → C7 → C4 → C5 → C6 → C8 → C9** — note que C7 (consentimento)
vem **antes** de C4, e não depois: construir a ponte de tags sem o gate de consentimento significa
reabrir o mesmo arquivo, e é o tipo de retrabalho que este plano existe para evitar.

---

# Parte B — INTEGRAÇÃO: o contrato site ↔ chat

## B.0 Linha de base: não perdemos em superfície, perdemos em contrato

A leitura honesta do estudo, que contraria a expectativa comum dentro de casa **[R20 §1.2]**:
temos 13 métodos em `window.$chatwoot`, 7 eventos de `window`, HMAC-SHA256 por inbox com toggle,
webhook de conta assinado com timestamp no material assinado (grupo mais forte do mercado) e
`meta.hmac_verified` no payload — coisa que **nenhum concorrente medido faz**. Isso é **mais** do
que Leadster, Tidio, JivoChat e tawk.to entregam.

> **Nota de precisão.** O estudo cita ora 13, ora 14 métodos (**[R10 §2, linha 5]** diz 14;
> **[R17 §0.1]** e **[R20 §1.2]** dizem 13). **[MEDIDO]** nesta task, `app/javascript/entrypoints/sdk.js`
> expõe **13 funções** em `window.$chatwoot`: `toggle`, `toggleBubbleVisibility`,
> `popoutChatWindow`, `setUser`, `setCustomAttributes`, `deleteCustomAttribute`,
> `setConversationCustomAttributes`, `deleteConversationCustomAttribute`, `setLabel`, `removeLabel`,
> `setLocale`, `setColorScheme`, `reset` — mais propriedades de estado (`isOpen`,
> `hideMessageBubble`), que não são métodos. **Use 13.**

**O que está quebrado é o contrato.** Os sete defeitos, com a evidência de origem:

| # | Defeito | Evidência |
|---:|---|---|
| 1 | Seis dos sete métodos de dados **não confirmam nada** — nem sucesso, nem erro | **[R20 §1.2]**; `// IgnoreError` em `widget/store/modules/contacts.js:88-103` e `conversation/actions.js:183-197` |
| 2 | `setConversationCustomAttributes` **antes de existir conversa** devolve 404 e o widget engole | **[R20 §2.4.1]**; `conversations_controller.rb:3, 93-95` |
| 3 | Métodos irmãos com semânticas **opostas**: contato faz merge, conversa **substitui** | **[R20 §2.4.1]**; `contact_identify_action.rb:128-132` × `conversations_controller.rb:67-69` |
| 4 | `hmac_mandatory` **não cobre** dois caminhos de escrita de identidade | **[R20 §2.3.2]**; `contacts_controller.rb:4, 59, 72-75` |
| 5 | **Nenhum dos dois lados** do `postMessage` valida `e.origin` | **[R20 §4/T2]**; `IFrameHelper.js:104-117` (confirmado nesta task: `window.onmessage =` na linha 105), `widget/helpers/utils.js:8-21` |
| 6 | Atributo sem definição prévia: **grava, entra no prompt da IA, e some do painel** | **[R19 §D.3]**; `CustomAttributes.vue:76-89` |
| 7 | Webhook de conta e de inbox: **zero retentativa**, em qualquer falha | **[R18 §D.10.4]**, provado com o arquivo real e stubs |

**[INFERÊNCIA]** Estes sete não são "features que faltam": são **promessas que o produto faz e não
cumpre**. Um método que existe e falha em silêncio é pior que um método ausente — o ausente o
integrador contorna, o mudo ele confia.

---

## B.1 I1 — Estabilizar o contrato (pré-requisito, não fase paralela)

**Por que é pré-requisito.** O `track()` que a frente de tracking precisa (**T-I3.1**), o
`setConsent` de C7 (**T-C7.1**) e todo evento novo de C3 **nascem dentro deste contrato**. Se ele
não for consertado antes, cada peça nova herda os quatro defeitos: sem retorno, sem fila, sem erro,
com exceção não capturada **[R20 §1.3]**.

**Nenhum item deste bloco depende de decisão de design do widget** — pode andar em paralelo ao
redesenho visual, e é a paralelização que a leitura intuitiva ("primeiro o visual, depois a
integração") desperdiça **[R20 §8]**.

| ID | Tarefa | Esforço | Depende de | Risco de merge |
|---|---|:---:|---|---|
| **T-I1.1** | Fechar o furo do `PATCH /widget/contact` (sem `validate_hmac`) — e é por essa rota que o `setCustomAttributes` passa, `widget/api/contacts.js:18-22` | **P** | — | **Baixo** — 1 `before_action` + revisão de `permitted_params` |
| **T-I1.2** | Corrigir o *early return* de `contacts_controller.rb:59` (`custom_attributes` sem `identifier` desliga a checagem, **inclusive com o modo obrigatório ligado**) | **P** | — | **Baixo** |
| **T-I1.3** | Validar `e.origin` nos dois lados do `postMessage`; trocar `targetOrigin: '*'` do widget; trocar `window.onmessage =` (`IFrameHelper.js:105`) por `addEventListener` para não sequestrar o handler do site | **P** | — | **Médio** — `IFrameHelper.js` tem 10 commits upstream em 36 meses **[R15 §B12.2]**. **[R10 §7 Q8]** recomenda oferecer este patch ao upstream: se aceito, some do nosso diff de graça |
| **T-I1.4** | Retorno (`Promise`) em **todos** os métodos de dados + `chatwoot:error` com motivo legível | **M** | — | **Médio** — `sdk.js` + a cadeia de `else if` de `App.vue` |
| **T-I1.5** | **Refatorar a cadeia de `else if` de `App.vue:258-345` para mapa `{evento: handler}` antes de estender** — é o mesmo **T-C3.8** da outra frente: **uma tarefa, não duas** | **M** | — | **Médio**, mas **reduz** conflito futuro **[R09 §15.4]** |
| **T-I1.6** | Fila pré-boot, drenada com o **mesmo formato** da chamada tardia — resolve a divergência D1 do **[R20 §0.3]** (existe rede de segurança em `IFrameHelper.js:185-187`, mas ela entrega payload em formato diferente e a desestruturação recebe `undefined`) | **M** | T-I1.4 | **Médio** |
| **T-I1.7** | `setConversationCustomAttributes` antes de existir conversa: **enfileirar e aplicar na criação**, em vez de 404 mudo | **M** | T-I1.6 | **Baixo** — o `custom_attributes` do `POST /widget/conversations` **já é aceito** (`base_controller.rb:44`) |
| **T-I1.8** | Nenhuma exceção não capturada (compatibilidade com GTM): `sdk.js:113-121` e `:139-175` lançam `Error` hoje | **P** | T-I1.4 | **Médio** |
| **T-I1.9** | Teto de quantidade de chaves vindas do widget (**50**, âncora do tawk.to) e extensão da validação de comprimento ao **contato** (hoje só a conversa tem limite) | **P** | — | **Baixo** |
| **T-I1.10** | Retry no webhook de saída + `X-Chatwoot-Delivery` estável entre retentativas (detalhado em §B.5) | **M** | **0.2 — o merge da v4.16.2** (**A7**: a v4.16.2 reescreveu `Webhooks::Trigger`) | **Baixo** |
| **T-I1.11** | **Teste dirigido de D1**: `setUser` chamado antes do `loaded` — produzir veredito escrito (funciona / falha ruidosamente / falha em silêncio) | **P** | — | **Nenhum** (teste) |

**Critério de aceite verificável** (é o do **[R20 §6 Fase 1]**, mantido porque é bom e é
verificável):

- Com o enforcement em `obrigatório`, uma requisição a `PATCH /widget/contact` com `{email: alvo}` e
  outra a `set_user` com `{email, custom_attributes}` sem `identifier` **não alteram** o contato —
  comprovado por teste automatizado em ambiente isolado, não por inspeção de código.
- Uma mensagem `chatwoot-widget:{"event":"setAuthCookie",…}` postada de **outra origem** não grava
  cookie.
- Chamar cada um dos sete métodos de dados com o widget ainda não carregado: **todos** são aplicados
  depois, com o mesmo efeito da chamada tardia.
- Colar as chamadas numa tag de HTML customizado do GTM: uma chamada malformada **não derruba** as
  tags seguintes do contêiner.
- Um webhook apontado para endpoint que devolve 500 registra **N tentativas** com o **mesmo**
  `X-Chatwoot-Delivery`.

---

## B.2 I2 — Tornar o dado visível, tipado e confiável

> É a fase de maior retorno percebido, e a maior parte dela é **painel do agente**, não widget
> **[R20 §6 Fase 2]**. Enquanto o gap 6 existir, **toda** melhoria de transporte descrita neste
> documento chega ao cliente como "não funcionou".

| ID | Tarefa | Esforço | Depende de | Risco de merge |
|---|---|:---:|---|---|
| **T-I2.1** | Auto-provisionar `CustomAttributeDefinition` para chave nova vinda do widget (tipo `text`, marcada "não confiável"), com **namespace por origem** (decisão **I3**) | **M** | T-I1.4 | **Baixo** |
| **T-I2.2** | Seção "Dados recebidos do site (N)" no painel, separada dos atributos curados — **é a mesma superfície de T-C0.5**: coordenar, não duplicar | **M** | T-I2.1 | **Médio** (`CustomAttributes.vue`) |
| **T-I2.3** | Coluna de **origem/confiança** na `CustomAttributeDefinition` + selo no painel (hoje as colunas existentes não expressam nada disso **[R20 §2.3.5]**) | **M** | T-I2.1 | **Baixo** (migration + coluna) |
| **T-I2.4** | Enforcement por atributo ("exige origem verificada" → escrita ignorada), o desenho do "Require verified updates" do Intercom | **M** | T-I2.3 | **Baixo** |
| **T-I2.5** | Allowlist + delimitação do bloco de atributos no prompt da IA, e gate para a conversa (hoje `feature_contact_attributes` gateia **só o contato**; a conversa — que o site escreve com mais liberdade — não tem controle nenhum **[R20 §4/T5]**) | **M** | T-I2.3 | **Baixo** (`enterprise/`, arquivos nossos) |
| **T-I2.6** | Três estados de enforcement (`desativado` / `observado` / `obrigatório`), copiando o Drift. O estado do meio é o que viabiliza migrar cliente com tráfego | **M** | T-I1.1, T-I1.2 | **Baixo** |
| **T-I2.7** | JWT como formato **adicional** (`sub`, `exp`, atributos no payload), HMAC mantido como legado (decisão **I2**) — `app/services/widget/token_service.rb` já faz `JWT.encode` com `exp`/`iat` | **M** | T-I2.6 | **Baixo** |
| **T-I2.8** | Mascarar IP por padrão no painel | **P** | — | **Baixo** |

**Critério de aceite verificável.** `setCustomAttributes({carrinho_valor: 4200})` sem cadastro
prévio: o valor aparece no painel **na mesma sessão**, dentro da seção de dados do site, com selo de
origem — validado em navegador real, **light e dark**. Um atributo marcado "exige origem verificada"
escrito sem credencial válida **não** altera o valor, e o painel mostra que a tentativa foi
ignorada. Uma conversa cujo `custom_attributes` contém texto com instruções **não** altera o
comportamento do agente de IA — verificado com **dry run**, nunca contra IA de cliente em produção.

---

## B.3 O dicionário de campos

Legenda: **HOJE** = existe e funciona · **HOJE⚠** = existe com defeito documentado · **NOVO**.

### B.3.1 Identidade — mora no **contato**

| Campo | Tipo | Limite proposto | Estado | Observação |
|---|---|---|:---:|---|
| `identifier` | string | 255 | **HOJE** | é o que o HMAC assina |
| `email` | string | 255 | **HOJE** | dispara merge por e-mail no `ContactIdentifyAction` |
| `name` | string | 255 | **HOJE** | |
| `phone_number` | string **E.164** | 20 | **HOJE⚠** | `cookieHelpers.js:23-24` — telefone **sozinho não passa** na validação do `setUser`, que exige uma de `avatar_url`/`email`/`name`. Quem só tem telefone não consegue identificar **[R20 §2.1.1]** |
| `avatar_url` | string https | 512 | **HOJE** | |
| `language` | BCP-47 / `pt_BR` | 10 | **HOJE⚠** | hoje só via `setLocale`, separado da identidade |
| `signed_up_at` | inteiro unix (s) | — | **NOVO** | é o `created_at` do Intercom; habilita segmentação por antiguidade, hoje impossível |
| `company` | objeto (B.3.2) | — | **NOVO** | hoje só `company_name` string |
| `custom_attributes` | objeto plano | ver B.3.5 | **HOJE** | merge profundo |

**Armadilha não documentada em lugar nenhum** **[R20 §2.1.1]**: `company_name`, `city`,
`description`, `country_code` e `social_profiles` são campos de topo no `setUser` que viram
`additional_attributes` sem aviso (`widget/store/modules/contacts.js:60-74`). É preciso ler o store
para descobrir. **Manter a compatibilidade e documentar o remapeamento** é tarefa de **T-C8.6**
(contrato público) e de **T-I3.2** (quando o objeto `company` entrar e tornar `company_name`
redundante).

**Dedupe do `setUser` — o defeito que engole dado** **[R20 §0.3, D2]**: o hash de deduplicação usa
4 chaves (`avatar_url`, `email`, `name`, `identifier_hash`) mais o `identifier`. **`phone_number`,
`company_name`, `city`, `country_code`, `description`, `social_profiles` e `custom_attributes` ficam
FORA.** Mudar só o telefone e rechamar `setUser` com o mesmo nome/e-mail é descartado pelo *early
return* e **o dado novo nunca sai do navegador**. Corrigir isso é **T-I3.4**.

### B.3.2 Empresa / conta — **NOVO**

O Intercom aceita `company` com `company_id`, `name`, `created_at`, `plan`, `monthly_spend`,
`user_count`, `size`, `website`, `industry` e um array `companies`. Nós aceitamos **uma string**.
Existe `contacts.company_id` no schema, mas **não há caminho do widget até ele** **[R20 §2.1.2]**.

| Campo | Tipo | Obrigatório |
|---|---|:---:|
| `company.id` | string | sim, se `company` presente |
| `company.name` | string | não |
| `company.plan` | string | não |
| `company.size` | inteiro | não |
| `company.industry` | string | não |
| `company.website` | string | não |
| `company.signed_up_at` | inteiro unix | não |

**Escopo:** **um** objeto `company`, **não** o array `companies` do Intercom — B2B multi-conta é raro
no ICP e o custo de modelagem é desproporcional **[R20 §2.1.2]**.

### B.3.3 Contexto de sessão / intenção — mora na **conversa**

A distinção que decide onde o dado mora **[R19 §A.0]**:

| Tipo | O que é | Onde mora | Quem escreve |
|---|---|---|---|
| **Identidade** | quem a pessoa é; atravessa conversas | contato | backend autenticado |
| **Estado** | como a conta/pedido está **agora**; muda sozinho | **não se copia — busca-se na hora** | sistema de origem |
| **Intenção** | o que a pessoa faz nesta visita; morre com a conversa | conversa | front do site |

> **A regra mais importante do dicionário inteiro:** contexto de **estado** (saldo, status de
> entrega, fatura vencida) é o que mais tenta as pessoas a copiar para dentro do chat, e é
> justamente o que **nunca** deve ser copiado. *"Saldo copiado às 14h e lido pelo agente às 16h é
> pior que saldo ausente: parece verdade e não é"* **[R19 §A.0]**. Não é teoria: o Gorgias
> **removeu** a visão de carrinho ao vivo do sidebar do agente por custo e fragilidade.

| Campo | Tipo | Estado | Observação |
|---|---|:---:|---|
| `page_url` | string | **HOJE⚠** | hoje só a URL do momento do envio da 1ª mensagem, em `additional_attributes.referer` |
| `page_title` | string | **NOVO** | |
| `landing_page` | string | **NOVO** | a primeira página da sessão — é o que conserta a atribuição (e é **T-C2.1**) |
| `entry_referrer` | string | **NOVO** | o `document.referrer` de verdade, que hoje **não capturamos** |
| atributos livres de conversa | objeto plano | **HOJE⚠** | hoje **substitui** o objeto inteiro e se perde antes de existir conversa |

**Critério de admissão de qualquer campo novo** — o filtro de quatro perguntas **[R19 §A.0]**:
(1) muda a primeira frase do atendente? se não, é ruído; (2) é estado ou é foto? se muda sozinho,
não copia — busca; (3) o que quebra se estiver errado? se direciona ação, exige origem autenticada;
(4) precisa do valor, ou o derivado basta? (`faixa_etaria` em vez de `nascimento`).

### B.3.4 Eventos de negócio — **NOVO**

Intercom `trackEvent`, Drift `track`, Crisp `session:event`, tawk.to `addEvent`, Tidio `track`.
Nós não temos: o `pushEvent` existe (`IFrameHelper.js:298`) mas **não está exposto** no `$chatwoot`
— é interno, usado só para `webwidget.triggered` (`IFrameHelper.js:253`) **[FATO]**, confirmado
nesta task.

| Campo | Tipo | Limite proposto |
|---|---|---|
| `name` | string `snake_case` | **40 caracteres** (limite do GA4 — o mesmo da §A.6, de propósito) |
| `properties` | objeto **plano** (sem aninhamento, sem array) | 20 chaves; valores string / número / booleano |
| `value` / `currency` | número / ISO-4217 | opcional; é o que destrava campanha por ROAS |

Copiar duas regras do Drift evita uma classe inteira de bug: objeto *flat* obrigatório e atributos
**case-sensitive** **[R20 §2.1.4]**.

> **Este é o campo de maior alavancagem cruzada do contrato inteiro**, porque é o mesmo objeto que a
> frente de tracking precisa. Um `track()` bem definido serve simultaneamente à integração com o CRM
> do cliente **e** ao pixel — e precisa ser desenhado **uma vez só** (§Parte C, item 3).

### B.3.5 Limites, tipos e a lista negativa

**O que existe hoje é o desenho mais frouxo do levantamento** **[R20 §2.1.6]**:
`conversations.custom_attributes` tem 1500 caracteres por chave e **nenhum** limite de quantidade;
`contacts.custom_attributes` **não tem limite nenhum**; o formato de chave é validado **só na
definição**, não no valor gravado.

**Limites propostos**, ancorados no mercado:

| Regra | Valor | Âncora |
|---|---|---|
| Nº de chaves vindas do widget, por modelo | **50** | tawk.to publica exatamente 50 |
| Tamanho do valor (string) | **1500** (manter o nosso) | mais generoso que os 255 de tawk.to/Intercom; não há motivo para apertar |
| Formato da chave | `/\A[\p{L}\p{N}_.\-]+\z/`, minúsculas | já é o formato da `CustomAttributeDefinition` |
| Tags/labels por conversa | **10** | tawk.to |
| Aninhamento | **proibido** — objeto plano | Drift |

**A lista negativa — o que NUNCA deve ser aceito como atributo** **[R19 §A.5]**:

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

**Isto é operacional, não retórico** **[R19 §A.3]**: no **automotivo** o padrão do setor é coletar
CPF e RENAVAM no chat para simulação de financiamento; na **educação**, `ja_e_aluno = true` pode
significar **menor de idade**. O produto precisa **dificultar a coisa errada** — e o caminho do
Zendesk é o melhor: em vez de proibir, oferecer um tipo nativo que mascara e trata adequadamente.

**Interseção com a frente de tracking:** a lista negativa vale **integralmente** para o que vai ao
`dataLayer` (RC5). Um CPF que o site manda como atributo **não pode** virar parâmetro de evento
client-side — nem hasheado, porque hash de CPF é reversível por força bruta (o espaço é pequeno).

### B.3.6 Origem e atribuição — a fronteira do dicionário

**O site não deveria precisar passar isto à mão.** A camada C2 coleta no SDK, e o que o site passa é
só o que ele sabe e o navegador não.

| Campo | Quem produz | Onde mora | Estado |
|---|---|---|:---:|
| `first_utm_*`, `first_referrer`, `first_landing_page`, `first_seen_at` | **C2** (write-once) | contato | **NOVO** |
| `last_utm_*`, `last_referrer`, `last_landing_page` | **C2** | conversa | **NOVO** |
| `gclid`, `gbraid`, `wbraid`, `fbclid`, `msclkid`, `ttclid` | **C2**; e **C0** retroativamente a partir do `referer` | contato (mais recente não vazio, com timestamp) | **NOVO** |
| `fbp`, `fbc`, `ga_client_id`, `ga_session_id` | **C2** (allowlist de cookie + `gtag('get')`) | conversa | **NOVO** |
| `ctwa_clid`, `source_id`, `source_type` do anúncio | ingestão do WhatsApp Cloud (**já existe**) | mensagem hoje; conversa depois de **T-C9.8** | **HOJE⚠** |
| ID de campanha **interno do CRM do cliente** | **o site** — é o único que ele sabe e nós não | conversa | **NOVO**, via `track()`/atributo de conversa |

**Regra de fronteira:** tudo que o navegador consegue observar é responsabilidade da **frente de
tracking** (C0/C2). O site só passa o que é dele — identificador de campanha interno, código de
vendedor, id de sessão do e-commerce dele. Se o site passar `utm_source` à mão e o coletor também
capturar, **vence o do coletor** e o do site vira atributo de conversa com nome distinto — nunca
sobrescrita silenciosa.

---

## B.4 As cinco vias de passagem, e quando cada uma se aplica

| Via | Pode carregar | Quando usar | Estado hoje |
|---|---|---|:---:|
| **1. API JS** (`window.$chatwoot`) | **tudo**, inclusive identidade e credencial | caso geral | **HOJE⚠** — 13 métodos, sem fila, sem retorno |
| **2. `data-*` na tag do script** | **só configuração** (posição, locale, esconder bolha, cor) | CMS travado; marketing sem dev | **NOVO** — temos **zero** `data-*` |
| **3. Parâmetros na URL** | **só contexto não sensível** e UTMs | landing pages; CMS travado | **HOJE⚠** — `buildUrl` já anexa `window.location.search` a toda chamada de API do widget (`widget/api/contacts.js:3`), mas **nada é parseado** |
| **4. GTM / `dataLayer`** | o que a API JS aceitar, via tag de HTML customizado que **chama a API** | cliente com GTM e sem dev | **HOJE⚠** — funciona, mas é hostil |
| **5. `postMessage` direto ao iframe** | — | **nunca** | **HOJE** — funciona e **não deveria**; é a via a **fechar** (T-I1.3) |

**Sobre a via 4, o achado que muda o pedido** **[R20 §2.2]**: **não existe nenhum fornecedor que
consuma `dataLayer` nativamente**. O padrão real é o inverso — uma tag de HTML customizado no GTM
chama a API JS do widget. Isso muda a natureza do requisito: *"receber parâmetros via GTM"* **não
exige** que o chat leia o `dataLayer`; exige que a API JS seja **chamável de dentro de uma tag do
GTM**, o que impõe três coisas concretas — (a) tolerar chamada antes do boot (T-I1.6), (b) ser
idempotente, (c) **nunca** lançar exceção não capturada (T-I1.8). Hoje falhamos em (a) e (c).

> **A fronteira dura que resolve todo caso omisso:**
> **configuração pode viajar por qualquer via; identidade e credencial, só pela via 1.**
> `data-*` vive no HTML servido e HTML é cacheado; URL vaza no histórico, no `Referer` de terceiros
> e no log de CDN. Um par `(identifier, identifier_hash)` que vaze **vale para sempre**, porque o
> nosso hash não tem expiração **[R20 §2.2, P4]**.

**Nota de interseção com o Achado 2:** a via 2 (`data-*`) e o problema de cache do `sdk.js` se
encontram. Configuração colocada no `data-*` do snippet muda com o HTML do cliente (cache dele);
configuração vinda do endpoint de config (T-C1.4) muda quando **nós** mudamos. Para tudo que
precise ser alterável pelo painel, **a fonte é o endpoint de config, não o `data-*`**.

---

## B.5 I5 — Webhooks: consertar, assinar, filtrar e ampliar

**O que temos e é bom, e precisa ser dito antes da lista de problemas** **[R18 §D.12]**: assinatura
HMAC-SHA256 com **timestamp no material assinado** (`"{ts}.{body}"`), que nos coloca no grupo mais
forte ao lado de Zendesk, HubSpot v3, Tidio e Crisp; payload rico (o `message_created` carrega
conta, inbox, conversa inteira e remetente numa tacada, dispensando a segunda chamada); e
`meta.hmac_verified` no payload.

### B.5.1 As quatro travas

| ID | Tarefa | Esforço | Depende de | Risco de merge |
|---|---|:---:|---|---|
| **T-I5.1** | **Retry de verdade**: deixar a exceção subir para o ActiveJob nos caminhos de conta e de inbox. O `retry_on … attempts: 5` já está declarado em `app/jobs/webhook_job.rb:3`; o que o anula é `Webhooks::Trigger#execute` engolir a exceção (`lib/webhooks/trigger.rb:16-29`) **[R18 §D.10.4]**. Tratar como não-recuperáveis os códigos que a Sunshine enumera (`400`, `401`, `403`, `404`, `406`) | **M** | — | **Baixo** |
| **T-I5.2** | `X-Chatwoot-Delivery` **gerado uma vez por evento e repetido em todas as retentativas** — hoje é gerado no listener a cada `perform_later` e não sobrevive a nada, porque não há retentativa para sobreviver. E **precisa existir no caminho de agent bot**, que é justamente onde HÁ retry hoje e onde ele está ausente **[R18 §0.4, Trava 2]** | **P** | T-I5.1 | **Baixo** |
| **T-I5.3** | **Assinar os outros três caminhos**: webhook de inbox (canal API), de agent bot e de automação/macro/flow saem **sem assinatura** hoje. Um endpoint que valida assinatura é obrigado a abrir exceção — e a exceção vira o buraco **[R18 §D.10.7, Trava 3]** | **M** | T-I5.1 | **Baixo** |
| **T-I5.4** | **Filtro por inbox de verdade**: a coluna `inbox_id`, o `enum webhook_type: {account_type: 0, inbox_type: 1}` (`app/models/webhook.rb:30`) e o `permit` do controller existem — e **nada no código jamais grava `inbox_type`**; a entrega itera `account.webhooks.account_type` e filtra só por evento **[R18 §D.10.5]**. Falta gravar, filtrar e expor o seletor no formulário | **M** | — | **Baixo** |
| **T-I5.5** | Revisar `validates :url, uniqueness: { scope: [:account_id] }` (`app/models/webhook.rb:28`), que impede a configuração legítima "mesma URL, dois conjuntos de eventos, duas inboxes" | **P** | T-I5.4 | **Baixo** |
| **T-I5.6** | Log de entregas + replay (retenção 7 dias, padrão do mercado) — hoje não há tela, endpoint, job nem estatística **[R18 §D.10.8]** | **M** | T-I5.1 | **Nenhum** |
| **T-I5.7** | Rotação de segredo (hoje o único jeito de trocar é destruir e recriar o webhook) e **parar de devolver o segredo em texto claro** no `index` (`_webhook.json.jbuilder:6`) | **P** | — | **Baixo** |
| **T-I5.8** | Ping/validação de endpoint no cadastro, como o Intercom faz | **P** | — | **Baixo** |

> **ARBITRADO — PLANO-MESTRE §5 A7: T-I5.1 e T-I5.2 (= BK-02, = bloco 1.13) dependem do merge da
> v4.16.2 (0.2), não de "—".** A v4.16.2 **reescreveu `Webhooks::Trigger`** (+30/−10): construtor com
> `secret:` e `delivery_id:`, transporte por `SafeFetch` no lugar de `RestClient`, e uma classe
> `RetryableError` nova. Corrigir antes do merge é escrever contra uma classe que vai ser
> substituída — e o `spec/lib/webhooks/trigger_spec.rb`, que hoje stuba `RestClient::Request`,
> também muda. **O defeito sobrevive ao merge** (o `raise` continua valendo só para
> `agent_bot_webhook`), então a tarefa continua necessária — e **T-I5.2 fica mais barata**, porque o
> upstream já passa `delivery_id:` pelo construtor. Vale o mesmo para **T-I1.10**, que é a mesma
> tarefa vista da frente de estabilização. Reconferir os intervalos de linha depois do merge.

**Referência de janela de retry para T-I5.1** **[R18 §A.2]**: Tidio faz 9 tentativas até ~4h45;
HubSpot 10 em 24 h; tawk.to retenta por até 12 h. **Uma escada tipo Tidio é a mais adequada ao
nosso perfil de cliente.**

### B.5.2 A expansão do catálogo — priorizada para venda

Temos **12 eventos** (`app/models/webhook.rb:32-34`, confirmado nesta task). Crisp tem ~60 e o
Intercom 90+. Mas o critério não é quantidade: é **quais mudam a venda**.

| Prioridade | Evento a acrescentar | Por que vale | Custo |
|:---:|---|---|:---:|
| **1** | `conversation_resolved` | **Já existe no barramento** (`lib/events/types.rb:23`, confirmado nesta task) e é entregue **só a agent bots** (`agent_bot_listener.rb`). É o evento mais pedido por integração de CRM, NPS e pós-venda **[R18 Trava 5]** | **P** |
| **2** | CSAT respondido | Fecha o par "atendeu → o cliente gostou?", que é o que alimenta relatório de qualidade no CRM | **P** |
| **3** | `chatspx_lead` / lead identificado | **É o mesmo evento 5 da §A.6.** Quem não quer pixel quer o lead no CRM dele — é a mesma informação, outro cano | **P** |
| **4** | Etiqueta aplicada/removida | Etiqueta é como PME brasileira modela funil. Sem o evento, o CRM não vê a mudança de estágio | **P** |
| **5** | Atribuição mudada | Permite espelhar dono do lead no CRM | **P** |
| **6** | Transcript completo da conversa (uma vez, no fim) | O `chat:transcript_created` do tawk.to — **é o que economiza trabalho de quem integra** | **M** |
| 7 | Resposta a menu interativo / postback | Crisp, LiveChat e Sunshine têm; casa com o motor Flow | **M** |
| 8 | Mensagem entregue / falha de entrega | Sunshine tem; é operacional, não comercial | **M** |

**[INFERÊNCIA] Os três primeiros são os que mudam a conversa de venda**, e os três são **P** —
porque o evento já existe no barramento ou é derivado de um que existe. Isso é raro o suficiente
para merecer destaque no roadmap.

### B.5.3 O padrão que já temos em casa e não aplicamos ao caminho de saída

**[R18 §D.11.6]** O webhook de **entrada** do motor Flow (`POST /webhooks/flows/:token`) tem cap de
payload, rate-limit por token em Redis, dedupe por `Idempotency-Key` com janela configurável e
**404 genérico anti-enumeração**. É um contrato de confiabilidade **melhor que o do nosso próprio
webhook de saída**. Não é preciso inventar o desenho — é preciso copiá-lo de um lado da casa para o
outro (**T-I5.1**, **T-I5.2**, **T-I5.6**).

---

## B.6 I3 — Ampliar a superfície (só depois de I1)

> Antes disso, cada método novo herdaria os defeitos que I1 corrigiu.

| ID | Tarefa | Esforço | Depende de | Risco de merge |
|---|---|:---:|---|---|
| **T-I3.1** | **`track(name, properties)`** — evento tipado do site. **Dono: frente de tracking** (decisão **I4**); a frente de integração define a **assinatura**, a de tracking define o **vocabulário** e consome (§Parte C) | **M** | T-I1.4, T-I1.6, T-C3.9 | **Baixo** — `pushEvent` já existe interno; `sdkEvents.js` tem 7 linhas |
| **T-I3.2** | Objeto `company` + `signed_up_at` | **M** | T-I2.1 | **Médio** (`widget/store/modules/contacts.js` + `ContactIdentifyAction`) |
| **T-I3.3** | Getters: estado do widget, contagem de não lidas, contato atual — LiveChat, Intercom, HubSpot, Crisp e tawk.to têm; nós não temos nenhum | **P** | T-I1.4 | **Baixo** |
| **T-I3.4** | Corrigir o dedupe do `setUser` para incluir os campos que hoje ficam de fora (telefone, empresa, cidade, país, `custom_attributes`) — hoje mudar só o telefone **não sai do navegador** | **P** | T-I1.4 | **Médio** (`sdk/cookieHelpers.js`) |
| **T-I3.5** | `phone_number` sozinho passa a identificar (hoje não passa na validação) — relevante no Brasil, onde telefone é a identidade prática | **P** | T-I3.4 | **Médio** |
| **T-I3.6** | `data-*` de **configuração** no script de embed (nunca identidade) | **M** | — | **Baixo** — cabe em `inbox.additional_attributes` |
| **T-I3.7** | Credencial por **callback** (modelo Zendesk: recebe uma função que resolve o token, chamada de novo a cada 401) — resolve na raiz o token em página cacheada por CDN | **M** | T-I2.7 | **Médio** |
| **T-I3.8** | Regra de verbo explícita: `update…` mescla, `set…` substitui. Manter `setConversationCustomAttributes` com a semântica de hoje e marcá-lo legado — trocar a semântica de um método existente quebraria integração em produção **em silêncio**, que é o pecado que esta spec combate | **P** | T-I1.4 | **Baixo** |

---

## B.7 I4 — O contrato de saída: o que o widget emite para o site

**Hoje:** 7 eventos (`sdkEvents.js`, íntegro, confirmado nesta task). Isso é diferencial — a
Leadster tem **zero** eventos de `window`, o Intercom tem 4 **[R20 §2.5.1]**.

**Defeitos conhecidos:** `chatwoot:on-start-conversation` é **intenção**, não conclusão; não existe
evento de conversa criada com id; não existe pré-chat submetido, mensagem do visitante, CSAT
respondido nem campanha exibida; `chatwoot:postback` é handler órfão; `chatwoot:error` só é usado
para `SET_USER_ERROR`; `reset()` não confirma conclusão.

| ID | Tarefa | Esforço | Depende de | Risco de merge |
|---|---|:---:|---|---|
| **T-I4.1** | Camada A — **retorno das chamadas**: `Promise` com resultado tipado (aceito / rejeitado por confiança / rejeitado por limite / enfileirado / **chaves sem definição correspondente**). O último caso é o que torna o gap 6 **visível para quem integra** | **M** | T-I1.4 | **Médio** |
| **T-I4.2** | Camada B — **eventos novos**: são exatamente os de **T-C3.2..T-C3.6**. **Uma implementação, dois consumidores** | **P/M** | T-C3.x | **Baixo** |
| **T-I4.3** | Camada C — **getters** (é o **T-I3.3**) | **P** | T-I1.4 | **Baixo** |
| **T-I4.4** | Corrigir `on-start-conversation` (intenção → conclusão) mantendo o evento antigo por compatibilidade | **P** | T-C3.2 | **Baixo** |
| **T-I4.5** | `reset()` confirma conclusão (hoje `IFrameHelper.js:195-197` suprime o `chatwoot:ready` seguinte) | **P** | T-I4.1 | **Médio** |

**O que NÃO recomendo copiar** **[R20 §2.5.2]**: injetar mensagem na conversa pelo site (Intercom
`showNewMessage`, Tidio `messageFromVisitor`/`messageFromOperator`). É poder de escrita no conteúdo
da conversa concedido a **qualquer** script da página — inclusive um de terceiro. Com o
`postMessage` sem validação de origem, isso vira injeção de mensagem falsa atribuída ao operador.
Se um dia entrar, entra **depois** de T-I1.3 e **atrás** do nível de confiança verificada.

---

## B.8 I6 — Mensagem proativa do backend do cliente: vale um endpoint de conveniência?

**Resposta curta: sim, e é açúcar barato.**

**O estado medido** **[R18 §D.13]**: dá para fazer hoje, sem gambiarra, em **3 chamadas** — achar o
contato (`GET .../contacts/search`), achar/criar a conversa (`POST .../conversations` com
`source_id`, `inbox_id`, `contact_id`), mandar a mensagem (`POST .../conversations/{display_id}/messages`).
O Intercom faz em **1** (`POST /messages`, endereçando por identificador externo).

**O que existe e não resolve:** as **Campanhas**. O tipo é forçado pelo canal — `Website` cai em
`ongoing` com `scheduled_at = nil`, e `execute_campaign` só tem ramo para Twilio SMS, SMS e
WhatsApp. **Campanha de widget é, por construção, disparada por comportamento do visitante no site,
nunca por decisão do backend do cliente** **[R18 §D.13]**.

| ID | Tarefa | Esforço | Depende de | Risco de merge |
|---|---|:---:|---|---|
| **T-I6.1** | Endpoint de conveniência: **uma** chamada que aceita destinatário por `identifier`/`email`/`phone_number` + `inbox_id` + conteúdo, e resolve contato → contact_inbox → conversa internamente | **M** | — | **Nenhum** (rota nova) |
| **T-I6.2** | Opção "não abrir conversa na caixa se o contato não responder" (o `create_conversation_without_contact_reply` do Intercom) — evita inflar a fila do atendimento com disparo automático | **P** | T-I6.1 | **Nenhum** |
| **T-I6.3** | Exigir contato **verificado** (`hmac_verified`) para o disparo proativo, ou marcar explicitamente o não verificado — é a diferença entre "mandar mensagem para o meu cliente" e "mandar mensagem para quem digitou o e-mail dele" | **P** | T-I2.6 | **Baixo** |
| **T-I6.4** | Agent bot pode **ler** a própria conversa (`messages#index` não está em `BOT_ACCESSIBLE_ENDPOINTS`) — hoje um bot que perde um webhook fica **surdo em definitivo**, porque não pode consultar o histórico **[R18 §D.11.4]** | **M** | — | **Baixo** |

**Critério de aceite verificável.** Um backend cliente envia **uma** requisição e o visitante
identificado recebe a mensagem no widget aberto, em tempo real; com o widget fechado, ela aparece
como não lida quando ele voltar, e segue por e-mail se `continuity_via_email` estiver ligado.

---

## B.9 Consolidado da frente de integração

| Bloco | Tema | Esforço agregado | Depende de decisão de design? | Destrava |
|---|---|:---:|:---:|---|
| **I1** | coerência e segurança | **M** | **não** | tudo o mais das duas frentes; C2/C3/C4/C7 do tracking |
| **I2** | visibilidade e confiança | **G** | parcial (painel) | percepção de valor pelo cliente |
| **I5** | webhooks | **M** | **não** | integração com CRM/ERP; o lead no cano de quem não quer pixel |
| **I3** | superfície nova | **G** | parcial | paridade com Intercom/Zendesk; `track()` |
| **I4** | contrato de saída | **M** | **não** | é o insumo direto de C3/C4 |
| **I6** | backend age no chat | **M** | não | venda para quem tem sistema próprio |

---

# Parte C — Onde as duas frentes se encontram

## C.1 O mapa da fronteira

```
              SITE DO CLIENTE (window)                      IFRAME (widget)            BACKEND
   ┌───────────────────────────────────────────┐      ┌────────────────────┐   ┌────────────────────┐
   │  ┌─────────────────────────────────────┐  │      │                    │   │                    │
   │  │  API JS  window.$chatwoot           │◄─┼──────┼─ postMessage ──────┼──►│  widget controllers│
   │  │  ── dono: INTEGRAÇÃO ────────────── │  │      │                    │   │                    │
   │  │  setUser / update* / get*           │  │      │                    │   │                    │
   │  │  track(name, props) ────────────────┼──┼──────┼────────────────────┼──►│  registro de       │
   │  │        assinatura: INTEGRAÇÃO       │  │      │                    │   │  evento (T-C3.9)   │
   │  │        vocabulário: TRACKING (I4)   │  │      │                    │   │  ── dono: TRACKING │
   │  └─────────────────────────────────────┘  │      │                    │   │                    │
   │  ┌─────────────────────────────────────┐  │      │  emite eventos     │   │                    │
   │  │  FILA PRÉ-BOOT + COLETOR DE ORIGEM  │  │      │  de negócio  ──────┼──►│  parser C0/C2      │
   │  │  ── dono: INTEGRAÇÃO (T-I1.6)       │  │      │                    │   │  ── dono: TRACKING │
   │  │     consumido por C2               │  │      │                    │   │                    │
   │  └─────────────────────────────────────┘  │      └────────────────────┘   │                    │
   │  ┌─────────────────────────────────────┐  │                               │  fila server-side  │
   │  │  PONTE DE TAGS (fbq/gtag/dataLayer) │  │                               │  CAPI / MP / Ads   │
   │  │  ── dono: TRACKING (C4)             │  │                               │  ── dono: TRACKING │
   │  │     gate de consentimento (C7)      │  │                               │                    │
   │  └─────────────────────────────────────┘  │                               │  webhooks de saída │
   └───────────────────────────────────────────┘                               │  ── dono: INTEGRAÇÃO│
                                                                               └────────────────────┘
                    ┌──────────────────────────────────────────────────────┐
                    │  PROVISIONAMENTO DE CustomAttributeDefinition        │
                    │  ── dono: INTEGRAÇÃO (T-I2.1) — namespace por origem │
                    │     usado por C0 (T-C0.3) e C2 (T-C2.7)              │
                    └──────────────────────────────────────────────────────┘
```

## C.2 O que NÃO pode ser construído duas vezes

Sete peças. Para cada uma: o dono, o motivo, e **o sintoma concreto se for duplicada** — porque
"não duplicar" sem sintoma é conselho, e com sintoma é critério.

| # | Peça | Dono | Por que | Sintoma se duplicar |
|---:|---|---|---|---|
| 1 | **Fila pré-boot + coletor no SDK** | **INTEGRAÇÃO** (T-I1.6); C2 consome | Mesmo arquivo, mesmo problema temporal: capturar o que acontece **antes** do widget existir | Duas filas ⇒ duas ordens de drenagem ⇒ bug de corrida em que a identidade chega depois do evento que dependia dela |
| 2 | **Contrato de eventos** | **TRACKING (C3)** define nomes; **INTEGRAÇÃO** expõe no `window` | Nome de evento é contrato público | **ARBITRADO §5 A9 — dois nomes, uma emissão, mapa publicado.** O risco real não é ter dois vocabulários: é ter **duas emissões**. `chatwoot:*` é o contrato com o site do cliente (renomear quebra integração em produção, em silêncio); `chatspx_*` é o contrato com GA4/Meta (`snake_case`, ≤ 40 caracteres, aparece no relatório do cliente). A emissão é **uma só** (RG4) e o mapa 1:1 é publicado em **5.15** — ver §A.6 |
| 3 | **Método `track()`** | **TRACKING** (decisão **I4**); **INTEGRAÇÃO** define a assinatura e o retorno | O `track()` do site e o evento de negócio do pixel são **a mesma chamada** | Dois métodos parecidos ⇒ o cliente chama o errado ⇒ o evento não chega no destino que ele esperava |
| 4 | **Provisionamento de `CustomAttributeDefinition`** | **INTEGRAÇÃO** (T-I2.1), com namespace por origem | Se cada frente provisionar as suas, o cadastro do cliente vira lixo | Painel com `utm_source` aparecendo duas vezes, uma "não confiável" e outra não |
| 5 | **Parser de UTM** | **TRACKING (C0)** | C0 parseia o `referer` **já gravado**, retroativamente; não faz sentido a integração parsear de novo no coletor | Duas implementações divergindo na normalização ⇒ `utm_source=Google` e `utm_source=google` no mesmo relatório |
| 6 | **Modelo de consentimento** | **TRACKING (C7)** | O estado governa disparo de tag; a integração **consulta**, não mantém um segundo | Dois estados divergentes ⇒ evento disparando com consentimento negado ⇒ incidente |
| 7 | **Seção do painel "dados recebidos do site"** | **INTEGRAÇÃO** (T-I2.2); C0/C2 usam | É a mesma superfície visual (T-C0.5 e T-I2.2 são a mesma tela) | Dois blocos concorrentes no painel lateral, um com origem e outro com atributos, sem relação visível |

## C.3 A ordem conjunta

**A única imposição de sequência entre as frentes** **[R20 §5.2]**:

> **C0 é independente e vem primeiro.** Tudo o mais da frente de tracking que toca o navegador
> (C2, C3, C4) deve esperar **I1**, porque herda os quatro defeitos de contrato se não esperar.

```
   ┌─ ONDA α ────────────────────────────────────────────────────────────────┐
   │  C0 (parser retroativo)          ‖  I1 (estabilização + segurança)      │
   │  ── independente, começa já      ‖  ── independente do design do widget │
   │                                  ‖  T-I1.5 = T-C3.8 (a refatoração)     │
   └─────────────────────────────┬────╨──────────────┬───────────────────────┘
                                 │                   │
   ┌─ ONDA β ────────────────────▼───────────────────▼───────────────────────┐
   │  C3 (contrato + eventos)  ←── consome T-I1.4/T-I1.6                     │
   │  I2 (visibilidade)        ←── T-I2.1 é pré-requisito de T-C0.3/T-C2.7   │
   │  C1 (config por inbox)                                                  │
   │  I5 (webhooks: retry, delivery, assinatura, filtro)                     │
   └─────────────────────────────┬───────────────────────────────────────────┘
                                 │
   ┌─ ONDA γ ────────────────────▼───────────────────────────────────────────┐
   │  T-C2.0 (propagação do SDK) → C2 (coletor) → C7 (consentimento) → C4    │
   │  I3 (track, company, getters)  ←── T-I3.1 depende de T-C3.9             │
   │  I4 (contrato de saída)        ←── mesma implementação de T-C3.2..6     │
   └─────────────────────────────┬───────────────────────────────────────────┘
                                 │
   ┌─ ONDA δ ────────────────────▼───────────────────────────────────────────┐
   │  C5 (fila server-side) → C6 (dedup) → C8 (auditoria e doc pública)      │
   │  I6 (mensagem proativa em 1 chamada)                                    │
   └─────────────────────────────┬───────────────────────────────────────────┘
                                 │
   ┌─ ONDA ε ────────────────────▼───────────────────────────────────────────┐
   │  C9 (offline import + ctwa_clid)                                        │
   └─────────────────────────────────────────────────────────────────────────┘
```

## C.4 Cinco regras de coordenação

**RG1 — A refatoração do `App.vue` acontece uma vez, e antes de qualquer extensão.** T-I1.5 e
T-C3.8 são a mesma tarefa com dois nomes. Quem chegar primeiro faz; a outra frente referencia. A
cadeia de `else if` de `App.vue:258-345` é *"exatamente o tipo de código que conflita"* **[R09 §15.4]**
e as duas frentes vão adicionar handlers nela.

**RG2 — Todo código novo em pasta nova.** `sdk/tracking/`, `widget/bridge/`, `app/services/tracking/`
não existem no upstream ⇒ conflito zero, para sempre **[R15 §B12.4]**. Quanto mais das duas frentes
morar em arquivo novo, menor o custo permanente de merge.

**RG3 — Nos arquivos do campo minado, delegar em vez de reescrever.** `PreChat/Form.vue` (16 commits
upstream, +39 −33 desde a nossa base), `ChatInputWrap.vue` (17 commits), `ChatFooter.vue` (15) e
`store/modules/conversation/*` (+51 −8 em `actions.js`) **[R15 §B12.2-3]**. T-C3.3 (emitir
`prechat_submitted`) deve sair do **store/ação**, não do componente.

**RG4 — Um evento, uma emissão, dois consumidores.** Os eventos novos (`conversation_created`,
`prechat_submitted`, `csat_submitted`, `message_sent_by_visitor`, `campaign_shown`) são emitidos
**uma vez**, chegam ao `window` do site (frente de integração) e ao registro server-side (frente de
tracking) pelo mesmo caminho. **A9 fixa o mapa de nomes** entre os dois consumidores — `chatwoot:*`
no `window`, `chatspx_*` no tracking — e proíbe a segunda emissão, não o segundo nome.

**RG5 — Antes de começar, rodar o merge de `v4.16.2` sozinho.** Ele mexe em **113 arquivos** do
widget (+4.332 −7.635) **[R15 §B12.4, MEDIDO]**. Fazer isso *depois* das duas frentes é resolver dois
problemas embaralhados — e esta frente vai criar arquivos novos justamente para não piorar essa
conta.

---

# Parte D — As quatro verificações pendentes

Para cada uma: a pergunta, **o que esta task já respondeu**, como verificar o que falta (comando
concreto), se exige produção, e **o que muda no plano conforme a resposta**.

---

## D.1 Verificação 1 — o webhook do WhatsApp Cloud/WAHA entrega `referral` com `ctwa_clid`?

### O que esta task já respondeu

**[FATO]** A pergunta estava mal colocada, e a resposta é melhor do que o estudo supunha. Não é
"precisamos escrever código de ingestão": **a ingestão já existe e copia o objeto inteiro**.

| Peça | Estado | Evidência |
|---|---|---|
| Ingestão do `referral` (WhatsApp Cloud / 360dialog) | **existe** | `app/services/whatsapp/incoming_message_base_service.rb:194` — `attrs[:referral] = message[:referral].to_h if message[:referral].present?` |
| Destino do dado | `messages.content_attributes['referral']` | mesma linha; `build_content_attributes` alimenta `create_message` (`:177-188`) |
| Consumo pela IA | **existe** | `enterprise/app/services/captain/open_ai_message_builder_service.rb:100-117` (`referral_note`, com `headline`, `body`, `media_type`) |
| Exibição no painel | **existe** | `app/javascript/dashboard/components-next/message/ReferralCard.vue`, acionado por `Message.vue:971-972` |
| **`ctwa_clid` dentro do objeto** | **[NÃO VERIFICADO]** | depende do que a Meta envia; **se enviar, já está gravado**, porque não há allowlist na cópia |
| Cobertura WAHA | **fora do caminho** | WAHA entra pelo canal API público (`public/api/v1/inboxes/messages_controller.rb:23,34,38`); `app/jobs/webhooks/waha_events_job.rb:9-16` só trata `poll.vote` |

### Como verificar o que falta

**Exige produção** (leitura apenas — nenhuma escrita, nenhum restart). O banco de homologação desta
VM tem **zero** mensagens com `referral` **[MEDIDO]**, portanto não serve de amostra.

Consulta pronta e testada contra o schema real (Ap.A2). Rodar em cada VM da frota que tenha
inbox `Channel::Whatsapp`:

```sql
SELECT count(*)                                                            AS msgs_com_referral,
       count(*) FILTER (WHERE content_attributes->'referral' ? 'ctwa_clid') AS com_ctwa_clid,
       count(*) FILTER (WHERE content_attributes->'referral'->>'source_type' = 'ad') AS source_ad,
       min(created_at) AS primeira, max(created_at) AS ultima
FROM messages
WHERE content_attributes ? 'referral';
```

E, para ver **quais chaves** a Meta está mandando de fato (sem exibir valores):

```sql
SELECT DISTINCT jsonb_object_keys(content_attributes->'referral') AS chave
FROM messages
WHERE content_attributes ? 'referral'
ORDER BY 1;
```

**Se ninguém puder rodar em produção agora, o caminho alternativo** é ligar o modo de teste de uma
inbox WhatsApp Cloud e disparar um anúncio Click-to-WhatsApp de R$ 1 para um público de uma pessoa —
o que é uma ação comercial, não técnica, e precisa de autorização do Walisson.

### O que muda no plano

| Resposta | Efeito |
|---|---|
| **`ctwa_clid` presente** | **T-C9.7 já está respondida.** C9/CTWA passa de **G** para **M**: falta só promover o campo (T-C9.8) e montar o evento `business_messaging` (T-C9.9). Sobe de prioridade — **[R07 §2.10]** avalia que pode valer mais que o pixel do site |
| **`referral` presente, `ctwa_clid` ausente** | A Meta não está enviando (versão da API, tipo de anúncio, ou configuração da conta). Investigar a versão da Graph API configurada antes de concluir. C9/CTWA continua **M**, mas com uma incógnita externa |
| **Nenhum `referral` na frota** | Ou nenhum cliente roda CTWA, ou a inbox é WAHA. Nos dois casos, **C9/CTWA sai da onda ε** e vira item de oportunidade comercial ("vamos vender CTWA para quem?"), não de engenharia |
| **Só WAHA na frota** | Item fica **[NÃO VERIFICADO]** e fora de escopo. Não inventar suporte antes de ter uma amostra real de payload |

---

## D.2 Verificação 2 — existe DPA cobrindo PII hasheada para Meta/Google?

### Estado

**[NÃO VERIFICADO]**, e **não é verificável por código**. Busca no repositório por documentos de
contrato/DPA não encontra nada que sirva (os arquivos que casam com o termo são de outros
contextos). É pergunta jurídica, e a resposta muda o que pode ir ao ar.

**O que está em jogo, tecnicamente** **[R07 §3.9]**: ao processar PII do visitante do cliente para
enviar a terceiros, o ChatSPX atua como **operador** por conta do cliente. Isso precisa estar em
contrato/DPA e visível no painel: lista de destinos por inbox, log dos campos enviados, botão de
desligar, retenção definida.

### Como verificar

Não é comando: é uma pergunta ao jurídico/comercial, com três itens objetivos:

1. O contrato vigente com os clientes da frota prevê tratamento de dados **por conta deles**, com
   finalidade de medição publicitária e subcontratação (Meta/Google) declarada?
2. Existe aditivo? Se não, qual o prazo para produzir um?
3. Quem é o encarregado (DPO) que assina, e qual o processo para clientes que **não** aceitarem?

### O que muda no plano

| Resposta | Efeito |
|---|---|
| **DPA existe e cobre** | C5 completo, com PII hasheada. Nada muda no roadmap |
| **Não existe, mas está em produção** | **C5 vai ao ar em modo "sem PII" (T-C5.9)**: envia `fbp`, `fbc`, `gclid`, `external_id`, IP e UA — nada de `em`/`ph`/`fn`/`ln`. O EMQ cai (fica na faixa "OK", não "Great"), mas o server-side já recupera parte dos 20–40% perdidos por bloqueador. **É a diferença entre atrasar tudo e entregar 60%** |
| **Não existe e não haverá tão cedo** | C5 fica só no modo sem PII; **C9/offline com `user_identifiers` fica bloqueado** (Enhanced Conversions **é** PII hasheada, por definição); o `gclid` puro ainda permite o import offline básico |
| **Existe, mas exige aceite por cliente** | Vira campo de configuração: a inbox só liga o modo com PII se a conta tiver o aceite registrado, com data e responsável. É **P** sobre T-C1.1 |

**[INFERÊNCIA] Recomendação:** construir T-C5.9 (modo sem PII) **primeiro**, independentemente da
resposta. Ele não depende do jurídico, entrega valor sozinho, e transforma a resposta do DPA de
"bloqueio de projeto" em "chave que liga mais matching".

---

## D.3 Verificação 3 — quantas conversas da frota já têm `utm_`/`gclid`/`fbclid` no `referer`?

### O que esta task já respondeu

**[MEDIDO]** nesta VM de homologação (`chatwoot_production` local, 12/08/2026):

| Métrica | Valor |
|---|---:|
| Conversas totais | 3.140 |
| Com `additional_attributes->>'referer'` preenchido | 4 |
| Com query string no `referer` | **0** |
| Com `utm_` | **0** |
| Com `gclid` | **0** |
| Com `fbclid` | **0** |
| Inboxes `Channel::WebWidget` | 1 |

**[INFERÊNCIA] Isso não diz nada sobre a frota** — diz que homologação não tem tráfego de site real
e **não serve de amostra**. O valor da medição é outro: a consulta do Ap.A1 está **testada
contra o schema real** e roda sem ajuste em produção.

### Como verificar

**Exige produção** (leitura apenas). Rodar o Ap.A1 em cada VM da frota. Recomendo rodar
junto o recorte por conta e por mês, porque a distribuição importa mais que o total: se 90% do
volume estiver em duas contas, C0 vira uma conversa com dois clientes, não um projeto de plataforma.

### O que muda no plano

| Resposta | Efeito |
|---|---|
| ~~**Volume alto**~~ | **Cenário encerrado em 13/08/2026 (D6).** Ele descrevia o que fazer se o histórico tivesse origem: subir o backfill e vender "olha de onde vieram seus últimos 6 meses". **O histórico não tem** — 0 de 3.180 [mestre M12] — e a decisão do produto é não perseguir o passado. Nenhuma tarefa deste plano depende mais de qual cenário se confirma |
| ~~**Volume médio, concentrado em poucas contas**~~ | Idem — encerrado com o backfill |
| **Volume baixo ou zero** | **Achado importante, não fracasso.** Significa que o tráfego dos clientes chega ao chat **sem** parâmetro de campanha na URL de abertura — o que reforça C2 (coletor de origem real, com landing page e `document.referrer`), porque a origem está se perdendo entre a landing page e a abertura do chat. **T-C0.4 é descartado; T-C0.1/2/3/5/7 continuam** |
| **`referer` majoritariamente nulo** | Investigar a invalidação de `conversation.rb:536-539` antes de qualquer conclusão: pode ser URL malformada sendo anulada, não ausência de dado |

---

## D.4 Verificação 4 — quais headers de cache o `/packs/` devolve?

### Respondida nesta task

**[MEDIDO]** `curl -sSI https://hmlchat.simplexsolucoes.com.br/packs/js/sdk.js` (12/08/2026):

```
HTTP/2 200
content-type: text/javascript
content-length: 28834
last-modified: Thu, 23 Jul 2026 20:08:25 GMT
cache-control: public, max-age=31556952
vary: Origin
```

Ou seja: **um ano de cache, sem `ETag`, sem fingerprint no path.**

**[FATO] E a origem do header não é o nginx:**

- `config/environments/production.rb:23-26` — `config.public_file_server.headers = { 'Cache-Control' => "public, max-age=#{1.year.to_i}" }`. `1.year.to_i` = 31.556.952 s, exatamente o valor observado.
- `/etc/nginx/sites-enabled/nginx_chatwoot.conf` — `location / { proxy_pass http://backend; … }`. Nenhum `expires`, nenhum `add_header` de cache.
- `app/models/channel/web_widget.rb:64-82` — o snippet aponta para `BASE_URL + "/packs/js/sdk.js"`, sem query de versão.

> **DIVERGÊNCIA declarada** com o enunciado do estudo (*"quais headers de cache o nginx devolve"*):
> **é o Rails.** A consequência é favorável: a correção é código nosso, entra pelo deploy normal e
> **não** exige mexer no nginx de cada VM da frota.

### O que ainda falta verificar

Uma coisa só, e é barata: se algum proxy à frente de alguma VM de produção reescreve o header.
Comando (leitura pura, endpoints públicos — Ap.A4):

```bash
for h in <host1> <host2> …; do
  echo "== $h"; curl -sSI "https://$h/packs/js/sdk.js" | grep -iE 'cache-control|etag|last-modified|cf-cache|age'
done
```

E se algum cliente auto-hospeda o `sdk.js` (cópia própria no CDN dele) — nesse caso nenhuma
mitigação nossa o alcança, e isso precisa constar da comunicação de rollout.

### O que muda no plano

| Resposta | Efeito |
|---|---|
| **Confirmado 1 ano em toda a frota** (cenário esperado) | **T-C2.0 é obrigatória e vem antes de C2/C4/C7.** Recomendação: opção (a) reduzir o `max-age` do `sdk.js` com revalidação **+** opção (c) SDK como carregador fino com URL versionada vinda da config (§A.4.1) |
| **Algum proxy já reduz o TTL** | T-C2.0 continua, mas com prazo menor de convivência entre versões |
| **Cliente auto-hospedando** | Entra na comunicação de rollout como exceção conhecida, e o plano de C4 precisa tolerar SDK antigo conversando com backend novo (compatibilidade retroativa do contrato de mensagens do `postMessage`) |

**Consequência transversal que vale registrar:** este mesmo achado afeta o **redesenho visual do
widget**, não só esta frente. Qualquer mudança no `sdk.js` (posição da bolha, teaser, chrome) tem o
mesmo problema de propagação. Corrigir em T-C2.0 paga duas frentes.

---

# Parte E — Sequenciamento e critérios de pronto

## E.1 As cinco ondas

| Onda | Conteúdo | Esforço agregado | Depende de verificação | Se parar aqui |
|---|---|:---:|---|---|
| **α** | **C0** (parser **prospectivo**, D6) ‖ **I1** (estabilização + os dois furos de HMAC + `postMessage` + retry de webhook) | **M** | **nenhuma** — a verificação nº 3 foi encerrada com o backfill | Produto honesto: **"a partir da entrada em produção, toda conversa nasce sabendo de onde veio"** e **para de prometer o que não cumpre**. *A frase anterior — "responde de onde veio o lead para a base inteira" — era exatamente o que não se cumpria, e saiu por isso* |
| **β** | **C3** (contrato + eventos que faltam) · **I2** (visibilidade/confiança) · **C1** (config por inbox) · **I5** (webhooks) | **G** | — | O cliente **vê** o dado chegando no painel e no CRM dele. É a onda de maior retorno percebido |
| **γ** | **T-C2.0** (propagação do SDK) → **C2** (coletor) → **C7** (consentimento) → **C4** (ponte de tags) · **I3** · **I4** | **G** | nº 4 | "Colei dois IDs e vi a conversão no Gerenciador de Anúncios" |
| **δ** | **C5** (fila server-side) → **C6** (dedup) → **C8** (auditoria + doc pública) · **I6** | **G** | **nº 2 (DPA)** | Recupera os 20–40% perdidos; EMQ alto; dedup que **nem a Leadster faz** |
| **ε** | **C9** (offline import + `ctwa_clid`) | **G** / **M** | **nº 1** | Espaço em branco do mercado: otimização por receita, não por volume de lead |

**Regra de ouro do sequenciamento** **[R10 §4.2]**: *"fazer C4 antes de C0 é construir a vitrine
antes de saber se há estoque."*

## E.2 Critério de pronto por onda — verificável, não declarativo

**Onda α.**
- Uma conversa antiga com `utm_` no `referer` mostra origem no painel e é encontrável por filtro.
- ~~Backfill rodado duas vezes não muda nada na segunda passagem.~~ **Sai com T-C0.4 (D6).**
- Com enforcement em `obrigatório`, os dois caminhos de escrita de identidade **não** alteram o
  contato — comprovado por teste, não por leitura.
- `postMessage` de outra origem **não** grava cookie.
- Webhook contra endpoint 500 registra N tentativas com o **mesmo** `X-Chatwoot-Delivery`.
- Os sete métodos de dados devolvem `Promise` e falham ruidosamente.

**Onda β.**
- `setCustomAttributes({carrinho_valor: 4200})` sem cadastro prévio aparece no painel **na mesma
  sessão**, em seção própria, com selo de origem — validado em navegador real, **light e dark**.
- Uma conversa iniciada emite, na ordem: `widget_opened` → `conversation_created` (com id) →
  `prechat_submitted` → `lead_identified`, observáveis por `addEventListener` no site.
- Um webhook de conta recebe `conversation_resolved` e o evento de CSAT; a tela de log mostra a
  entrega e permite reenviar.
- Um webhook configurado para **uma** inbox **não** recebe eventos das outras.
- O endpoint de config do widget e o `show.html.erb` devolvem o mesmo conjunto de chaves de tracking.

**Onda γ.**
- Uma versão nova do `sdk.js` chega a um navegador que já tinha a antiga, em minutos — não em meses.
- Visitante que chega por `?utm_source=…&gclid=…`, navega 5 páginas e abre o chat: a conversa nasce
  com `first_utm_source` e `gclid` corretos.
- Safari, 7+ dias sem visita: a origem **sobrevive**, porque está no servidor.
- Página com 3 pixels: o evento **não** vaza. Página sem pixel: **não** há `PageView` duplicado.
- CMP negando: **zero** disparos client-side.
- `dataLayer` sem PII em claro.

**Onda δ.**
- No Events Manager do cliente, `Lead` aparece com **Browser e Server**, total **não dobrado**, e a
  dedup reconhecida no Test Events com o mesmo `event_id`.
- EMQ ≥ 6,0 (alvo 8,0 nos eventos com PII).
- Bloqueador ligado: client-side falha, server-side entrega.
- Destino 5xx: retry acontece e o resíduo aparece na DLQ visível.
- Log de auditoria **sem nenhum valor de PII**.
- Página pública de contrato de eventos no ar, com todos os eventos da §A.6.

**Onda ε.**
- Venda fechada 30 dias depois aparece como conversão com valor real no Google Ads.
- Conversa vinda de Click-to-WhatsApp é **atribuída ao anúncio** no Gerenciador — não apenas aceita.
- Negócio ganho fora da janela de 90 dias gera aviso, não silêncio.

## E.3 Como medir se a frente deu certo

**[R07 §7.7]**, adotado:

| Métrica | Alvo |
|---|---|
| % de inboxes Website com tracking configurado | > 40% em 90 dias |
| EMQ médio dos eventos `Lead` | ≥ 7,0 (idealmente 8,0+) |
| Taxa de entrega da fila server-side (2xx / total) | > 99% |
| Pares deduplicados corretamente (amostragem no Events Manager) | 100% |
| Chamados de suporte por 100 inboxes com tracking ligado | decrescente mês a mês |
| Diferença entre leads no ChatSPX e conversões reportadas no destino | < 10% |

E duas métricas próprias desta frente, que o estudo não propõe:

| Métrica | Alvo | Por quê |
|---|---|---|
| % de conversas com origem conhecida (qualquer sinal) | crescente, com linha de base medida na verificação 3 | é o número que prova que C0+C2 funcionaram |
| % de atributos vindos do site **visíveis** no painel | **100%** | enquanto for menor que isso, o gap 6 ainda está de pé **[R19 §D.3]** |

---

# Parte F — Riscos e mitigação

## F.1 Merge com o upstream

| Risco | Evidência | Mitigação |
|---|---|---|
| A cadeia de `else if` de `App.vue:258-345` conflita em todo merge | **[R09 §15.4]** | **RG1** — refatorar para mapa **antes** de estender (T-I1.5 = T-C3.8) |
| `IFrameHelper.js` é ponte e tem 10 commits upstream em 36 meses | **[R15 §B12.2]** | Tocar o mínimo: uma linha de registro de handler; toda lógica em `sdk/tracking/` (pasta nova) |
| `PreChat/Form.vue`: +39 −33 só desde a nossa base | **[R15 §B12.2]** | **RG3** — emitir `prechat_submitted` do store, não do componente |
| `api/endPoints.js`: +29 −11 desde a base | **[R15 §B12.3]** | Usar `custom_attributes` do `POST /widget/conversations`, que já é aceito, em vez de acrescentar parâmetro novo |
| `base_controller.rb#permitted_params` é área de alto atrito | **[R09 §15.5]** | Idem — `custom_attributes` (linha 44) já existe |
| Bits de `channel_web_widgets.feature_flags` esgotados | **[R10 §6.1]** + memória do projeto | Configuração estruturada em `additional_attributes` (jsonb), **nunca** bitmask |
| Toda config nova precisa entrar em **dois** lugares | **[R09 §6.2]** | **T-C1.4** trata os dois explicitamente, e o critério de aceite compara os dois |
| Upstream lançar tracking antes de nós | **[R07 §6.4]** — issues #5965, #7642, #7981 abertas há 3 anos sem entrega | Baixo. Manter em módulo isolado de qualquer forma. Decisão **N8**: contribuir upstream só a infraestrutura (validação de `origin`, `targetOrigin`), manter proprietário o produto |
| Colisão de timestamp de migration em merges do fork | memória do projeto | Detectar com `uniq -d` antes de subir; `git mv` para timestamp único |

## F.2 Produto, dado e conformidade

| Risco | Impacto | Mitigação |
|---|---|---|
| **Quebrar a medição do site do cliente** (sobrescrever `gtag`, duplicar `PageView`) | Altíssimo — perda de confiança irreversível | RC2 + `skipPageView` + `trackSingle`/`send_to` + modo "somente `dataLayer`" como padrão de fábrica (T-C4.10) |
| **Conversão contada em dobro** | Alto — o cliente decide mídia com número inflado | C6 obrigatório em todo evento com par client/server; RC8 no GA4; T-C6.4 (teste de contagem) |
| **PII no `dataLayer` ou nos params do `fbq`** | Altíssimo — incidente LGPD | RC5 + teste que barra campos sensíveis no payload client-side + lista negativa de §B.3.5 |
| **Segredo no navegador** | Altíssimo | RC10 + T-C1.2 + critério de aceite que inspeciona o corpo das respostas |
| **Peso do `sdk.js`** | Médio | T-C2.8/T-C4.9 (carregamento sob demanda) + orçamento no CI |
| **Prompt injection pelo atributo do site** | Alto | T-I2.5 (allowlist + delimitação + simetria com `feature_contact_attributes`) + T-I1.9 (teto de chaves) |
| **Suporte: "não apareceu no Gerenciador"** | Alto (custo recorrente) | C8 inteiro — e a página pública, que é onde a Leadster é fraca **[R07 §4.1.7]** |
| **O plano andar e a história não ser contada** | Alto | **[R10 §6.7]**: das 16 vantagens verificáveis do estudo, **nenhuma** aparece hoje em material comercial. C8.6 (contrato público) é a peça de engenharia que mais ajuda a narrativa |

## F.3 O risco específico desta frente

**[INFERÊNCIA]** O maior risco não está nas tabelas acima: é **construir C4 (a ponte de tags) sem
I1 (a estabilização)**. A tentação é real — C4 é o que o comprador vê, I1 é invisível. Mas C4
depende de eventos que ainda não existem (C3), que dependem de uma API que hoje falha em silêncio
(I1). Uma ponte de tags montada sobre eventos que não confirmam nada produz exatamente o sintoma
que o estudo inteiro documentou: **o dado chega, o painel não muda, e a conclusão do cliente é "não
funcionou"** — com o site jurando que mandou e o atendente jurando que não vê, **os dois certos**.

---

# Apêndice A — Consultas e comandos de verificação

> Todos testados nesta task contra o schema real (HEAD `ee87f5e799`) no banco desta VM de
> homologação. **São somente leitura.** Rodar em produção exige autorização — e é leitura, não
> escrita.

## Ap.A1 Volume de origem no `referer` (verificação 3)

```sql
SELECT
  count(*) FILTER (WHERE additional_attributes->>'referer' IS NOT NULL
                     AND additional_attributes->>'referer' <> '')      AS com_referer,
  count(*) FILTER (WHERE additional_attributes->>'referer' ILIKE '%utm_%')   AS com_utm,
  count(*) FILTER (WHERE additional_attributes->>'referer' ILIKE '%gclid%')  AS com_gclid,
  count(*) FILTER (WHERE additional_attributes->>'referer' ILIKE '%fbclid%') AS com_fbclid,
  count(*) FILTER (WHERE additional_attributes->>'referer' LIKE '%?%')       AS com_querystring,
  count(*)                                                                   AS total
FROM conversations;
```

Recorte por conta e por mês (a distribuição importa mais que o total):

```sql
SELECT account_id,
       date_trunc('month', created_at) AS mes,
       count(*) FILTER (WHERE additional_attributes->>'referer' ILIKE '%utm_%')  AS utm,
       count(*) FILTER (WHERE additional_attributes->>'referer' ILIKE '%gclid%') AS gclid,
       count(*) AS total
FROM conversations
GROUP BY 1, 2
ORDER BY 2 DESC, 5 DESC;
```

Só as inboxes de site (o universo relevante de C0):

```sql
SELECT i.id, i.name,
       count(c.*) AS conversas,
       count(*) FILTER (WHERE c.additional_attributes->>'referer' LIKE '%?%') AS com_querystring
FROM inboxes i
JOIN conversations c ON c.inbox_id = i.id
WHERE i.channel_type = 'Channel::WebWidget'
GROUP BY 1, 2 ORDER BY 3 DESC;
```

## Ap.A2 `referral` e `ctwa_clid` (verificação 1)

```sql
SELECT count(*)                                                                     AS msgs_com_referral,
       count(*) FILTER (WHERE content_attributes->'referral' ? 'ctwa_clid')          AS com_ctwa_clid,
       count(*) FILTER (WHERE content_attributes->'referral'->>'source_type' = 'ad') AS source_ad,
       min(created_at) AS primeira, max(created_at) AS ultima
FROM messages
WHERE content_attributes ? 'referral';
```

```sql
-- quais chaves a Meta manda de fato (nomes, não valores)
SELECT DISTINCT jsonb_object_keys(content_attributes->'referral') AS chave
FROM messages
WHERE content_attributes ? 'referral'
ORDER BY 1;
```

## Ap.A3 Baseline de canais (para saber onde as consultas acima fazem sentido)

```sql
SELECT channel_type, count(*) FROM inboxes GROUP BY 1 ORDER BY 2 DESC;
```

**[MEDIDO]** nesta VM: `Channel::Api` 13 · `Channel::Instagram` 2 · `Channel::Whatsapp` 1 ·
`Channel::WebWidget` 1.

## Ap.A4 Cache do `sdk.js` (verificação 4)

```bash
curl -sSI https://<host>/packs/js/sdk.js | grep -iE 'cache-control|etag|last-modified|age|cf-cache'
```

**[MEDIDO]** em `hmlchat.simplexsolucoes.com.br`: `cache-control: public, max-age=31556952`, sem
`ETag`, `content-length: 28834`.

## Ap.A5 Confirmação de que o header é do Rails, não do nginx

```bash
grep -n "public_file_server" config/environments/production.rb
grep -rn "expires\|Cache-Control\|add_header" /etc/nginx/sites-enabled/
```

**[MEDIDO]**: o primeiro devolve `config/environments/production.rb:23-26`; o segundo, **nada**.

---

# Apêndice B — Checklist de QA da integração de tracking

Adaptado de **[R07 §8.2]**, com os itens desta frente acrescentados (marcados ✚).

1. [ ] Instalar em página **sem** pixel: instala? dispara `PageView` duplicado? (não deve)
2. [ ] Instalar em página **com** o mesmo pixel: há duplicidade? (não deve)
3. [ ] Página com **3 pixels diferentes**: o evento vaza? (não deve, com `trackSingle`)
4. [ ] Events Manager: o evento aparece com `Browser` **e** `Server`, e o total **não** dobra
5. [ ] Events Manager: EMQ ≥ 6,0 (idealmente 8,0)
6. [ ] Test Events com `test_event_code`: os dois eventos com o **mesmo** `event_id`
7. [ ] GA4 DebugView: o evento chega com `session_id` e a origem **não** é "(direct)"
8. [ ] GA4: o evento **não** é contado duas vezes (client + MP)
9. [ ] Google Ads: conversão registrada, com valor e moeda
10. [ ] `gclid` persistido no contato e legível no painel
11. [ ] Bloqueador ligado: client-side falha, server-side entrega
12. [ ] Safari (ITP): a origem sobrevive porque está no servidor
13. [ ] CMP negando: nenhum evento client-side dispara; server-side respeita o estado
14. [ ] `dataLayer` **não** contém e-mail, telefone ou nome em claro
15. [ ] Log de auditoria registra o envio **sem** armazenar valores de PII
16. [ ] Erro 5xx do destino: retry acontece; após N falhas vai para a DLQ visível
17. [ ] Console do navegador limpo no site do cliente
18. [ ] `window.gtag` e `window.dataLayer` do cliente continuam funcionais
19. ✚ [ ] Uma chamada malformada dentro de uma tag do GTM **não** derruba as tags seguintes
20. ✚ [ ] Chamada feita **antes** do boot é aplicada depois, com o mesmo efeito
21. ✚ [ ] Atributo enviado pelo site **sem definição** aparece no painel, em seção própria, com selo
22. ✚ [ ] Versão nova do `sdk.js` chega a um navegador que já tinha a antiga (T-C2.0)
23. ✚ [ ] Webhook: N tentativas com o **mesmo** `X-Chatwoot-Delivery`
24. ✚ [ ] Webhook configurado para uma inbox **não** recebe eventos das outras
25. ✚ [ ] Validação visual em navegador real, **light e dark**, das telas de painel tocadas

---

# Apêndice C — Rastreabilidade

| Seção deste documento | Entradas principais | Verificação própria nesta task |
|---|---|---|
| §0.3, §1.1 achados | — | `incoming_message_base_service.rb:194`; `open_ai_message_builder_service.rb:100-117`; `ReferralCard.vue`; `Message.vue:971-972`; `waha_events_job.rb:9-16`; `public/api/v1/inboxes/messages_controller.rb:23-151`; `curl` do `sdk.js`; `production.rb:23-26`; nginx; SQL A.1/A.2/A.3 |
| §A.0 linha de base | R07 §6.1-6.3, R09 §4, R10 §4.0 | `DOMHelpers.js:42-64`; `endPoints.js:18,35,53`; `base_controller.rb:38-44,62`; `conversation.rb:83,536-539`; `automation_rule.rb:38`; `events_controller.rb:4-8`; `routes.rb:593-625`; `IFrameHelper.js:105,206-207,213,253,298`; `sdkEvents.js` (íntegro) |
| §A.1 regras de conduta | R07 §2.1-2.7, §3.1-3.9, §7.3-7.6; decisões N4/N5 | — |
| §A.2–A.12 camadas | R10 §4.1 (C0–C9), R07 §7 | `web_widget.rb:64-82`; `inbox.rb:50`; `configs/create.json.jbuilder`; `widgets/show.html.erb`; `webhooks/_webhook.json.jbuilder:6` |
| §A.6 tabela de eventos | R07 §7.2, R10 §4.1 C3 | — |
| §A.13 sGTM | R07 §3.6, §5.4 | — |
| §B.0 defeitos | R20 §1.2, R17, R18, R19 | `IFrameHelper.js:105`; `webhook.rb:28-34`; `lib/events/types.rb:14,23` |
| §B.1 I1 | R20 §6 Fase 1 | idem |
| §B.3 dicionário | R20 §2.1, R19 §A | — |
| §B.4 vias | R20 §2.2, R17 §5.1 | — |
| §B.5 webhooks | R18 §A.2-A.3, §D.10-D.13 | `webhook.rb:28-34`; `lib/events/types.rb:23` |
| §B.8 proativa | R18 §D.13 | — |
| §C fronteira | R20 §5, R15 §B12 | — |
| §D verificações | DECISOES.md, R07 §8.4, R10 §4.3 | tudo de §0.3 |
| §F riscos | R07 §7.6, R09 §15, R10 §6, R15 §B12 | — |

---

# Apêndice D — Lacunas explícitas deste plano

Registro para que ausência de dado não vire mito interno.

1. **Não executei nada além de leitura.** As verificações são leitura de código, uma consulta SQL
   read-only e um `HEAD` HTTP. Nenhum furo de segurança foi explorado; nenhuma configuração foi
   alterada.
2. **Homologação não é amostra.** As medições SQL desta task valem como teste de sintaxe das
   consultas, não como retrato da frota (verificação 3).
3. **Não sei se a Meta está enviando `ctwa_clid`** para as contas da frota (verificação 1) — e não
   dá para saber sem produção.
4. **Não sei a versão da Graph API** configurada em cada inbox WhatsApp da frota, o que afeta a
   presença de campos novos no `referral`.
5. **Não verifiquei WAHA em profundidade**: sei que ela entra pelo canal API e que nosso job de
   webhook só trata `poll.vote`; **não sei** se a aplicação externa envia contexto de anúncio dentro
   de `content_attributes`. Sem amostra de payload real, qualquer afirmação seria chute.
6. **Não sei quantos clientes da frota já usam `setUser` com HMAC** — isso dimensiona o custo real
   de qualquer mudança de compatibilidade em I1/I3 e não foi levantado por nenhum relatório
   **[R20 Anexo A, item 4]**.
7. **Não medi o impacto de peso** que C2 + C4 + C7 somam ao `sdk.js`. Os três moram no mesmo arquivo
   de 28.834 bytes com orçamento declarado de 40 KB. Somar três componentes sem medir é como o
   orçamento estoura **[R20 Anexo A, item 8]**.
8. **Não verifiquei os headers de cache das VMs de produção** — só de homologação. O header é do
   Rails, mas um proxy à frente pode reescrever.
9. **Não há resposta jurídica sobre o DPA** (verificação 2), e ela não é obtível por código.
10. **Não avaliei custo de infra** da fila server-side em escala (C5, C9), nem o custo de chamada
    das APIs de terceiros por volume de evento.
11. **Nada aqui foi validado em navegador real** — este é um plano, não uma implementação. A regra
    da casa (validar UI em light e dark com Playwright antes de declarar pronto) se aplica a cada
    tarefa que toque tela, e está nos critérios de aceite das ondas β e γ.

---

**Fim do plano.** Nenhum arquivo de código do repositório foi alterado por esta task. O único
artefato produzido é este markdown.

---

## Correções aplicadas em 12/08/2026 (pós-auditoria)

Edição cirúrgica para propagar as arbitragens do `PLANO-MESTRE.md` §5 (bloqueador **B1** do
`auditoria/35-VEREDITO.md`). A instrução que contradizia a decisão arbitrada **saiu do lugar onde o
dev lê** — não ficou como alternativa embaixo de um aviso.

| Onde (linha atual) | O que mudou | Origem |
|---|---|---|
| `:208` — §A.2 | "sem risco de merge" → risco **Baixo**, porque agora há **uma** linha em arquivo do upstream (a chamada do saneamento) | §5 **A6** |
| `:232-247` — §A.2, "Arquivos" | **"Não tocar: `app/models/conversation.rb`" saiu.** Agora: tocar com **uma linha só** (a chamada), com a lógica em `lib/url_helper.rb:3-10`. Bloco de arbitragem com a medição que sustenta (o método `validate_referer_url` é byte-idêntico entre v4.12.1 e v4.16.2; o helper teve 0/0), o porquê de não deixar como está, e a rejeição mantida de sanear em `base_controller.rb#permitted_params` | §5 **A6** |
| `:296` — **T-C1.1** | A premissa *"jsonb livre, sem tocar em `EDITABLE_ATTRS`"* estava meio errada: `EDITABLE_ATTRS` de fato não é tocado, mas o jsonb **não é livre** — strong params rejeita chave não declarada. A chave `widget_tracking: {}` entra na **edição única** do bloco 3.01, e esta tarefa **não reabre o controller**. Dependência deixou de ser "—" | §5 **A1** |
| `:329` — §A.3, "Arquivos" | "Não tocar `EDITABLE_ATTRS`" passa a ser explicitamente **desta frente**, não global: o pré-chat **amplia** a constante (bloco 3.12 / `23` T2.1 / `24` BE-6) | `PLANO-MESTRE` §5 **A10** (bloco 3.12) |
| `:495-510` — §A.6 | Bloco de arbitragem **A9**: esta tabela é o vocabulário de **tracking**; o de `window` fica em `24` §17.1; **dois contratos, uma emissão**, mapa 1:1 publicado em 5.15. Marcado com ⚠ que `chatspx_csat_submitted` aparece no mapa do mestre mas **não está entre os 12 eventos desta tabela** — ponto a fechar em 5.15 antes de implementar | §5 **A9** |
| `:912` — **T-I1.10** | Dependência "—" → **0.2, o merge da v4.16.2** | §5 **A7** |
| `:1169` — §B.5.1 | Bloco de arbitragem: **T-I5.1 e T-I5.2 (= BK-02) dependem do merge**, com a razão medida (a v4.16.2 reescreveu `Webhooks::Trigger`, +30/−10, `SafeFetch`, `RetryableError`), a nota de que o defeito sobrevive ao merge e a de que T-I5.2 fica **mais barata** depois dele | §5 **A7** |
| `:1338` — §C.2 item 2 | O risco deixou de ser "dois vocabulários" e passou a ser **duas emissões**, que é o que A9 proíbe. Os dois nomes são contratos com públicos distintos | §5 **A9** |

**Verificações próprias feitas nesta correção** (leitura, sem escrita, HEAD `ee87f5e799`):
`lib/url_helper.rb:3-10` é o `url_valid?` (só aceita `URI::HTTP`/`URI::HTTPS`);
`app/models/conversation.rb:536-540` é o `validate_referer_url`, que grava `nil` no campo e deixa a
conversa salvar; `inboxes_controller.rb:217` é a lista fechada do `permit`;
`app/models/inbox.rb:50` tem o `store_accessor`.

