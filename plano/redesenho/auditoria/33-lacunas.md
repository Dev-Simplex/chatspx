# TASK 33 — Auditoria adversarial: o que ficou de fora

> **Pergunta desta auditoria.** Não é "o que foi feito está certo?" — é **"o que não foi feito e
> deveria ter sido?"**. Caço omissão, não defeito de execução.
>
> **Objeto auditado:** `plano/redesenho/` (PLANO-MESTRE.md, 22, 23, 24, 25, `shared/`, 9 mockups),
> contra `plano/estudo-chat-web/` (22 relatórios, `DECISOES.md`, `10-gap-analysis.md`).
>
> **Regra que segui:** nenhuma marcação `[MEDIDO]` foi aceita por estar marcada. Refiz por
> amostragem (§0.2). Nenhum arquivo do repositório ou dos artefatos auditados foi alterado — este
> markdown é a única escrita desta task.
>
> **Data:** 12/08/2026 · **Branch:** `homologacao`, HEAD `ee87f5e799`

---

## 0. Método

### 0.1 O que conferi, item a item

| Universo de entrada | Itens | Conferidos |
|---|---:|---:|
| Matriz de paridade (`10 §2`) | 68 capacidades | 68 |
| Balde 🔴 MESA (`10 §3.1`) | 15 | 15 |
| Balde 🟢 DIFERENCIAL (`10 §3.2`) | 15 | 15 |
| Balde ⚪ RUÍDO (`10 §3.3`) | 12 | 12 |
| Balde 🔵 VANTAGEM (`10 §3.4`) | 16 | 16 |
| Decisões (`DECISOES.md` partes 1–4) | 24 | 24 |
| Defeitos verificados (`DECISOES.md` parte 0) | 6 | 6 |
| Verificações pendentes (`DECISOES.md`) | 4 | 4 |
| Dependências de backend do plano 23 (`BE-1`…`BE-8`) | 8 | 8 |
| Dívidas do plano 23 (`D1`…`D11`) | 11 | 11 |
| Lacunas declaradas (`shared/LEIA-ME.md §8.6`) | 6 | 6 |
| **Total** | **185** | **185** |

### 0.2 Medições que refiz nesta task (amostra de verificação)

| Afirmação auditada | Fonte que a fez | Reconferência | Veredito |
|---|---|---|---|
| `sdk.js` = 28.834 B | `25 §T-C2.8`, `10 §2` (cap. 10) | `ls -la public/packs/js/sdk.js` → **28834** | ✅ exato |
| CSS do widget = 1.103.132 B | `22 §E.4`, `PLANO-MESTRE §1` | `public/vite/assets/widget-B98UQrMr.css` → **1.103.138** | ✅ (Δ 6 B entre builds) |
| Leaflet 150 KB no grafo | `09 §12`, `22 §E.4` | `leaflet-58r2EQLt.js` → **150.679 B** | ✅ |
| `size-limit` casa múltiplos hashes | `22 §E.4` | 4 arquivos `widget-*.js` no diretório | ✅ |
| 2 `aria-label` no widget inteiro | `09 §13.2` | `grep -rn aria-label app/javascript/widget/` → **2**; em `sdk/` → **0** | ✅ |
| `bubbleHelpers.js:46` = `fill '#FFFFFF'` | `22` item 34 | linha 46 é exatamente isso | ✅ |
| `title = 'Open chat window'` (inglês) | `09`, bloco 1.06 | `bubbleHelpers.js:60` | ✅ |
| `:hover` verde em `sdk.js:132` | risco **R2** | `app/javascript/sdk/sdk.js:132` → `background: #2dc46f` | ✅ |
| Snippet sem stub queue | gap **M15** | `web_widget.rb:64-80`: `g.onload` → `run()`, nada antes | ✅ |
| `createBubbleIcon` sem campo de imagem | pergunta do Walisson | `bubbleHelpers.js:28-61`: SVG montado de `bubbleSVG` fixo | ✅ |

**Conclusão do §0.2:** as medições do estudo e dos planos **se sustentam**. Dez de dez conferiram.
Isso é elogio e acaba aqui — o resto do documento é o que falta.

### 0.3 Classificação

**BLOQUEADOR** — impede uma tarefa planejada de ser executada como está escrita, ou destrói uma
vantagem medida sem que nenhum aceite perceba. **GRAVE** — omissão que vira retrabalho ou promessa
quebrada ao cliente. **MÉDIO** — buraco real, contornável. **MENOR** — imprecisão que custa tempo.
**COSMÉTICO** — forma.

---

## 1. Veredito, em cinco frases

**1.** O planejamento cobre **o que ele mesmo se propôs a cobrir** — as duas superfícies declaradas
(widget e telas de configuração) estão cobertas com densidade alta e rastreabilidade interna
honesta (277 tarefas → 106 blocos, §2.3).

**2.** Mas ele **não cobre o que o estudo mandou cobrir**: de 68 capacidades, **19 não aparecem em
nenhum bloco nem na lista §8 de recusas**; de 15 diferenciais, **8 sumiram sem uma linha**; e o
balde inteiro de IA (capacidades 47–54) evaporou.

**3.** Três omissões são **BLOQUEADORAS por construção**: a Tela 1 tem sete campos sem chave onde
gravar (**BE-2**), o mockup aprovado da Tela 3 promete duas seções que não existem em bloco nenhum
(**BE-5** e o aviso de privacidade), e o SDK — a vantagem nº 1 do inventário — recebe código de
**oito blocos** sem que um único aceite meça o peso dele.

**4.** O **pedido direto do Walisson** (trocar o ícone da bolha) está coberto por exatamente **uma
linha** do plano 22, e essa linha não troca ícone nenhum: troca a cor do preenchimento.

**5.** A frase da §2.3 — *"Cobertura — nada ficou de fora"* — é verdadeira sobre as **quatro frentes
de planejamento** e falsa sobre o **estudo**: ela confere `W*`/`T*`/`BK-*`/`T-C*`/`T-I*` contra si
mesmos, e nunca confere nada contra `10-gap-analysis.md` ou `DECISOES.md`, que são os documentos que
definiram o escopo.

---

## 2. Rastreabilidade completa

Legenda: **✅** coberto por bloco nomeado · **🟡** parcial (declaro o que falta) · **🚫** recusado
explicitamente em `PLANO-MESTRE §8` (legítimo) · **❌ NÃO COBERTO** (nem bloco, nem recusa).

### 2.1 As 68 capacidades da matriz de paridade

#### Bloco A — Instalação e integração (1–8)

| # | Capacidade | Estado hoje | Bloco que cobre | Veredito |
|---:|---|:---:|---|:---:|
| 1 | Snippet de 1 script colável | ✅ | 3.11, 5.18 | ✅ |
| 2 | **Stub global síncrono com fila antes do bundle** | ❌ | 1.23 cobre a fila **dentro do `sdk.js`**, não no snippet | 🟡 |
| 3 | **Instalação documentada em WordPress / Wix / GTM** | ❔/❌ | nenhum | **❌** |
| 4 | `baseUrl` configurável / self-host | ✅ (vantagem) | — (nada ameaça) | ✅ |
| 5 | API JS pública rica | ✅ | 1.23, 5.16, 5.17 | ✅ |
| 6 | `CustomEvent` no `window` do host | ✅ | 5.04 | ✅ |
| 7 | **Ponto de montagem customizado no DOM do cliente** (`custom_launcher_selector`) | ❌ | nenhum. `grep` por `custom_launcher_selector` nos 5 planos → **vazio** | **❌** |
| 8 | **Modo inline/embutido (não flutuante)** | ❌ | nenhum | **❌** |

#### Bloco B — Arquitetura, peso e robustez (9–18)

| # | Capacidade | Hoje | Bloco | Veredito |
|---:|---|:---:|---|:---:|
| 9 | Isolamento por iframe | ✅ | §8 item 1 preserva | ✅ |
| 10 | Loader leve (< 40 KB) | ✅ | **nenhum bloco o protege** — ver **L-03** | 🟡 |
| 11 | App sob demanda (facade) | ❌ | 2.18 reduz o eager; **não** implementa facade | 🟡 |
| 12 | CSS enxuto | ❌ | 1.08 | ✅ |
| 13 | Chunks limpos (Leaflet) | ❌ | 0.3, 0.5 | ✅ |
| 14 | Orçamento vigiado em CI | 🟡 | 0.5 (widget). **SDK fora do gate** | 🟡 |
| 15 | Reconexão robusta | ✅ | 2.07 **mexe** em `BaseActionCableConnector.js` sem aceite de não-regressão | 🟡 |
| 16 | Retomada de mensagens perdidas | ✅ | — | ✅ |
| 17 | **Preservação de estado em SPA React/Vue Router puros** | 🟡 | nenhum. `grep` "React Router"/"Vue Router" → vazio | **❌** |
| 18 | Fila offline / retry | ❌ | 2.16, 2.15 | ✅ |

#### Bloco C — Proatividade e UX de abordagem (19–28)

| # | Capacidade | Hoje | Bloco | Veredito |
|---:|---|:---:|---|:---:|
| 19 | Teaser/balão de convite | 🟡 | 4.06 | ✅ |
| 19b | **…com rotação de mensagens** (a Leadster gira) | ❌ | 4.05 vincula **uma** campanha; rotação não aparece | **❌** |
| 20 | Gatilho por tempo | ✅ | 4.04 | ✅ |
| 21 | Gatilho por scroll | ❌ | 4.04 | ✅ |
| 22 | Exit intent | ❌ | 4.04 | ✅ |
| 23 | Inatividade / cliques / nº de páginas | ❌ | 4.04 | ✅ |
| 24 | Seletor CSS do site | ❌ | 4.04 | ✅ |
| 25 | Config separada desktop × mobile | ❌ | 4.04 | ✅ |
| 26 | Cooldown por gatilho | 🟡 | 4.04 | ✅ |
| 27 | Ocultar após conversão (N dias) | 🟡 | 4.04 ("frequência") — mas o critério "quem já conversou nunca mais vê" **não é citado como correção** | 🟡 |
| 28 | **Esconder o widget quando o teclado virtual abre** | ❌ | 2.09 trata o **composer atrás do teclado**; esconder o launcher no `focusin` não aparece | **❌** |

#### Bloco D — Captura e formulário conversacional (29–40)

| # | Capacidade | Hoje | Bloco | Veredito |
|---:|---|:---:|---|:---:|
| 29 | Fluxo conversacional no widget | ❌ | 4.01, 4.02, 4.03 | ✅ |
| 30 | Editor sem canvas (wizard) | ❌ | 3.14 (3 modos) | ✅ |
| 31 | Pre-chat form | ✅ | 3.12, 3.14, 3.15 | ✅ |
| 32 | Multi-etapa / condicional | ❌ | 3.14 (E/OU aninhado recusado, §8 item 15) | ✅ |
| 33 | Máscaras BR | ❌ | 3.13 | ✅ |
| 34 | Anti-lixo | ❌ | 3.13 | ✅ |
| 35 | Quick replies no 1º turno | 🟡 | 4.10, mockup 21 ("atalhos de intenção, até 4") | ✅ |
| 36 | **Lead incompleto com sync incremental** | ❌ | **BE-5, sem bloco.** `grep "lead incompleto"` no PLANO-MESTRE → **zero** | **❌ BLOQUEADOR** |
| 37 | **Dropout por etapa** | ❌ | nenhum. `grep "dropout"` nos 5 planos → **zero** | **❌** |
| 38 | **Lead scoring por resposta** | 🟡 | nenhum | **❌** |
| 39 | **Teste A/B** | ❌ | nenhum. `grep "teste A/B"` → zero | **❌** |
| 40 | **Página de captura hospedada** | ❌ | nenhum | **❌** |

#### Bloco E — Canais, handoff e continuidade (41–46)

| # | Capacidade | Hoje | Bloco | Veredito |
|---:|---|:---:|---|:---:|
| 41 | Redirect WhatsApp pré-preenchido | ❌ | 4.08 | ✅ |
| 42 | **Roleta entre N números** | ❌ | nenhum | **❌** |
| 43 | Handoff site→WhatsApp costurando identidade **e transcript** | ❌ | 4.08 diz "carregando o contexto"; **transcript e código curto opaco não aparecem** | 🟡 |
| 44 | Continuidade entre sessões | ✅ | — | ✅ |
| 45 | Continuidade por e-mail | ✅ | — | ✅ |
| 46 | Base de conhecimento no widget | 🟡 | 3.17 (flag). Busca: 🚫 §8 item 25 | ✅ |

#### Bloco F — IA (47–54) — **o bloco que evaporou**

| # | Capacidade | Hoje | Bloco | Veredito |
|---:|---|:---:|---|:---:|
| 47 | RAG sobre base própria | ✅ | — | ✅ |
| 48 | Contextual retrieval + RRF | ✅ | — | ✅ |
| 49 | **Reranker** (TODO no nosso próprio código) | ❌ | nenhum. `grep "reranker"` → zero | **❌** |
| 50 | **Ingestão por sitemap** | 🟡 | nenhum. `grep "sitemap"` → zero | **❌** |
| 51 | **Intenções próprias com desvio de fluxo** | 🟡 | nenhum | **❌** |
| 52 | Handoff com dossiê e distribuição | ✅ | — | ✅ |
| 53 | **Guardrail executável** ("gap nº 1 da nossa IA") | ❌ | nenhum. `grep "guardrail"` → zero | **❌** |
| 54 | **Eval/QA como produto de gestão** | 🟡 | nenhum. `grep "eval"` nos 5 planos casa só com "avaliação"/`eval` de CSP | **❌** |

#### Bloco G — Tracking e atribuição (55–63)

| # | Capacidade | Bloco | Veredito |
|---:|---|---|:---:|
| 55 | UTM/`gclid`/`fbclid` | 1.19, 1.21, 5.08 | ✅ |
| 56 | `_fbc`/`_gcl_aw` first-party | 5.08 | ✅ |
| 57 | Meta Pixel client-side | 5.10 | ✅ |
| 58 | GA4 / Ads client-side | 5.10 | ✅ |
| 59 | `dataLayer.push` documentado | 5.10, 5.15 | ✅ |
| 60 | Meta CAPI server-side | 5.11 | ✅ |
| 61 | GA4 MP + Enhanced Conversions | 5.11 | ✅ |
| 62 | Dedup por `event_id` | 5.03, 5.05, 5.13 | ✅ |
| 63 | Import de conversão offline | 5.21 | ✅ |

**O bloco G é o mais bem coberto do documento inteiro.** Nove de nove, com bloco nomeado, aceite e
dependência. Registro e sigo.

#### Bloco H — Segurança, identidade e conformidade (64–68)

| # | Capacidade | Bloco | Veredito |
|---:|---|---|:---:|
| 64 | Verificação de identidade | 1.11, 4.15, 4.16, 5.19 | ✅ |
| 65 | Enforcement "só verificados" | 4.15 | ✅ |
| 66 | Restrição de domínio validada | 0.8 **avisa** que `allowed_domains` vazio abre o `frame-ancestors`; não muda o default | 🟡 |
| 67 | **Consentimento LGPD dentro do widget** | 5.09 é **Consent Mode de tracking**; o aviso antes da coleta de PII só existe como *regra de conteúdo* em `22 §C.11` e como toggle **no mockup** — em nenhum bloco | 🟡 → ver **L-05** |
| 68 | Acessibilidade | 1.06, 2.01, 2.06, 2.08, 2.09, 2.11 | ✅ |

**Placar da §2.1:** de 68 capacidades — **43 ✅ · 9 🟡 · 16 ❌** (contando 19b). Das 16 não cobertas,
**zero** aparecem na lista §8 "o que NÃO vamos fazer".

### 2.2 Balde 🔴 MESA (15) — o que constrange na venda

| # | Gap | Bloco | Veredito |
|---|---|---|:---:|
| M1 | UTM/`gclid`/`fbclid` | 1.19, 1.21, 5.08 | ✅ |
| M2 | Evento de conversão para o site | 5.04, 5.10 | ✅ |
| M3 | Gatilhos além de URL+tempo | 4.04, 4.06 | ✅ |
| M4 | Validação BR no pre-chat | 3.13, 3.15 | ✅ |
| M5 | `widget_color` no header/botão | 1.02, 1.04, 1.05 | ✅ |
| M6 | App sob demanda | 2.18 (redução, não facade) | 🟡 |
| M7 | **Contador de não lidas ao host + eventos `connected`/`disconnected`** | 5.17 cobre o **getter** de não lidas (T-I3.3). Os eventos `connected`/`disconnected`: `grep` → **zero** | 🟡 |
| M8 | `open()`/`close()` idempotentes | nenhum bloco cita idempotência da API pública | **❌** |
| M9 | 1ª mensagem com 2–4 opções | 4.10 + mockup 21 | ✅ |
| M10 | **Aviso LGPD antes da coleta** | ver 67 acima | 🟡 |
| M11 | A11y mínima | 1.06 | ✅ |
| M12 | **Persistir posição/tipo/título da bolha no servidor** | **BE-2 — sem chave de destino.** Ver **L-01** | **❌ BLOQUEADOR** |
| M13 | **Analytics do widget** (abertos, iniciadas, leads, dropout) | 1.22 cobre **origem**; 5.21 cobre **estatística por gatilho**. Chats abertos, conversas iniciadas e **dropout**: nenhum | 🟡 |
| M14 | **Instalação documentada em WP/Wix/GTM** | nenhum | **❌** |
| M15 | **Stub queue no snippet** | 1.23 é fila **no SDK** (depois do `sdk.js` carregar). O snippet continua `g.onload → run()` | 🟡 |

**8 dos 15 gaps MESA não estão inteiros no plano.** O estudo dizia: *"oito são P (pequenos)… não
fazer os P é escolha, não restrição."* O plano fez a escolha **sem registrá-la**.

### 2.3 Balde 🟢 DIFERENCIAL (15) — onde valeria muito

| # | Diferencial | Bloco | Veredito |
|---|---|---|:---:|
| D1 | CAPI + GA4 MP server-side | 5.02, 5.11, 5.12 | ✅ |
| D2 | Dedup por `event_id` | 5.03, 5.05, 5.13 | ✅ |
| D3 | Conversão offline | 5.21 | ✅ |
| D4 | `ctwa_clid` | 5.21 + verificação V1 | ✅ |
| D5 | Handoff site→WhatsApp com identidade **e transcript** | 4.08 (só contexto) | 🟡 |
| D6 | Enforcement 1 clique + JWT | 4.15, 5.19 | ✅ |
| D7 | Tokens com validação de contraste | 1.02, 3.08, `shared/` | ✅ |
| D8 | **Eval de IA como produto de gestão** — *"a coisa de maior valor/esforço do inventário inteiro"* | nenhum | **❌ GRAVE** |
| D9 | **Guardrail executável** | nenhum | **❌** |
| D10 | Citação de fonte + "sou uma IA" | 4.09 cobre o **rótulo**; **citação de fonte** (flag `feature_citation`) não aparece | 🟡 |
| D11 | **Feriados brasileiros no horário** | nenhum. `grep "feriado"` → zero | **❌** |
| D12 | **Página de captura hospedada** | nenhum | **❌** |
| D13 | **"Panorama" publicado** | nenhum (o risco **R25** admite o problema de narrativa e aponta 5.15 como paliativo) | **❌** |
| D14 | **Referrer de IA generativa** (converte 7,80%) | nenhum. 1.19 parseia `utm_*`/`gclid`/`fbclid`/host/path — **não** classifica referrer de LLM | **❌** |
| D15 | **A/B por mensagem versionado** | nenhum | **❌** |

**8 de 15 diferenciais não têm uma linha.** Cinco deles (D8, D9, D11, D12, D14) eram classificados
como **P ou M** pelo próprio estudo — não saíram por serem caros.

### 2.4 Balde ⚪ RUÍDO (12) — o plano acertou aqui

Nenhum dos 12 itens de ruído vazou para dentro do plano. N4 e N7 estão explicitamente recusados
(§8 itens 2, 4, 24); N6 = decisão N7; os outros nove simplesmente não aparecem. **Está certo, e
acaba aqui.**

### 2.5 Balde 🔵 NOSSA VANTAGEM (16) — o plano preserva ou destrói?

| # | Vantagem | O plano a ameaça? | Evidência |
|---|---|---|---|
| V1 | **Loader 15,9× mais leve (28.834 B)** | **SIM — e sem rede de segurança** | **19 blocos** tocam `sdk/`, `IFrameHelper`, `bubbleHelpers`, `cookieHelpers` ou o snippet; **8 adicionam código eager** (1.23, 2.11, 2.14, 4.06 **G**, 4.11, 5.16, 5.17, 5.18). Ver **L-03** |
| V2 | Isolamento por iframe | Parcialmente, e **declarado** | 4.06 põe o teaser no `document` do host; risco **R13** assume e manda testar em 3 sites |
| V3 | API pública 14 métodos + 7 eventos | Não — é ampliada | 1.23, 5.16, 5.17 |
| V4 | HMAC com escopo | Não | 4.15 mantém `hmac_mandatory` |
| V5 | **Reconexão endurecida** | **Risco não coberto** | 2.07 reescreve o watchdog em `BaseActionCableConnector.js`; o aceite mede o **banner**, não o backoff/jitter/`visibilitychange` que são a vantagem. Nenhum teste de não-regressão de reconexão |
| V6 | Estado em SPA | Não | ninguém toca |
| V7 | **i18n 51–55 locales + RTL** | **Risco parcialmente coberto** | 2.18 faz "i18n sob demanda"; o único aceite de RTL é 1 snapshot em `dir="rtl"` (**R23**). Nenhum aceite verifica que os 51 locales continuam carregáveis sob demanda |
| V8 | `frame-ancestors` por inbox | Não — 0.8 melhora | ✅ |
| V9 | Continuidade por e-mail | Não | — |
| V10 | RRF k=60 | Não (ninguém toca IA) | — |
| V11 | Sistema de eval | Não toca — **e não expõe** (D8) | — |
| V12 | Camada de comportamento | Não | — |
| V13 | Sanitização de PII BR | Não | 5.11/5.12 reusam a ideia |
| V14 | Mesma IA site + WhatsApp | Não | 5.21 estende tracking ao WhatsApp |
| V15 | **Self-hosted / open-source** | **SIM, e não percebido** | 5.02 promete **"OAuth de um clique"** para Meta e Google numa plataforma que roda em **N VMs com N domínios**. Redirect URI por VM, App Review da Meta para `ads_management`, e quem é o "dono" do app OAuth: nada disso aparece. `25 §T-C1.7` marca o risco como **"Nenhum"** |
| V16 | 7 minors à frente | Não — 0.2 mantém | ✅ |

**Três vantagens ameaçadas** (V1, V5, V15) e **uma exposta sem cobertura de teste** (V7).

### 2.6 As 24 decisões do `DECISOES.md`

| # | Decisão | Bloco / destino | Veredito |
|---|---|---|:---:|
| N1 | Comprador-alvo: marketing sem abandonar suporte | 3.03, 3.07, os dois perfis | ✅ |
| N2 | Manter iframe | §8 item 1 | ✅ |
| I2 | JWT | 5.19 | ✅ |
| I4 | Dono do `track()`: tracking | 5.16 + arbitragem A9 | ✅ |
| F1 | Corpo 15 px | 2.03; §8 item 12 recusa 14 px como default | ✅ |
| F2 | Header colorido, texto por luminância | 1.02, 2.06 | ✅ |
| F3 | Manter textura | 2.04 (textura < 30 KB) | ✅ |
| F4 | **Launcher que fala: experimento em 2–3 contas, não default** | mockup 20 e `23 §B.2.2` expõem `standard\|expanded_bubble` como **campo de configuração**. **Não há infraestrutura de experimento em lugar nenhum** — o "experimento" virou toggle | 🟡 |
| F5 | Teaser nesta onda | 4.06 | ✅ |
| F6 | Dark `auto` | 2.10 | ✅ |
| F7 | Som e piscar do título | 4.11 | ✅ |
| F8 | Rótulo persistente de IA | 4.09 | ✅ |
| I1 | HMAC antes de tudo | 1.11 (Onda 1) — a recomendação era **"fora de fase, imediata"**; virou item de onda. Diferença registrada, não arbitrada | 🟡 |
| I3 | Auto-provisionar atributo | 1.16, 1.17, 4.17 | ✅ |
| I5 | **Contexto externo ao lado da conversa (card lateral), app depois** | **nenhum bloco.** `grep "ConversationBox"/"card lateral"/"Canvas Kit"` nos 5 planos → **vazio**. O "I5" que aparece no PLANO-MESTRE é o **I5 de webhooks** do plano 25 — homônimo | **❌ GRAVE** |
| I6 | Contrato público escrito junto | 5.15 | ✅ |
| N3 | Flows como fonte de verdade | 4.01, 4.02 | ✅ |
| N4 | Hash de PII no servidor | 5.11 + risco R10 | ✅ |
| N5 | Não instalar tag faltante por padrão | §8 item 5 | ✅ |
| N6 | Identidade opcional agora | 4.15 (3 estados) | ✅ |
| N7 | **IA por assinatura, não por resolução** | nenhum plano, nenhuma recusa em §8 | **❌** (fora de escopo de engenharia — mas sumiu sem dizer) |
| N8 | Contribuir upstream seletivamente | PLANO-MESTRE §3 e §9.3 | ✅ |
| N9 | **Publicar o "Panorama"** | nenhum | **❌** |
| N10 | **Extrair tools verticais do `tools.yml`** | nenhum. `grep "tools.yml"` → zero | **❌** |

**20 de 24 cobertas.** As 4 que sumiram (I5, N7, N9, N10) sumiram **em silêncio** — nenhuma consta
nas 25 linhas de §8, que é o lugar do documento onde recusa se registra.

### 2.7 Os 6 defeitos verificados — **cobertura integral**

| # | Defeito | Bloco |
|---|---|---|
| B1 | `widget_color` não chega | 1.02, 1.04, 1.05 |
| B2 | Contraste reprovando AA | 1.02, 2.03, 3.08 |
| B3 | Webhook sem retry | 1.13 (+ arbitragem A7: depois do merge) |
| B4 | `postMessage` sem origem | 1.09 |
| B5 | HMAC com duas portas | 1.11 (portas 1–2) + 4.16 (portas 3–4) |
| B6 | Atributo órfão | 1.16, 1.17, 1.18, 4.17 |

**6 de 6, com bloco, aceite e ordem.** É a melhor parte do planejamento. Segue.

### 2.8 As 4 verificações pendentes — **cobertura integral, com juros**

| Pendência do `DECISOES.md` | Virou | Bloqueia |
|---|---|---|
| `referral`/`ctwa_clid` no webhook | **V1** (§7) | 5.21 |
| DPA para PII hasheada | **V2** | 5.11 modo com PII |
| Conversas com `utm_` no `referer` | **V3** | dimensiona 1.21 |
| Headers de cache de `/packs/` | **V4** | 5.07 |

E o plano **acrescentou três** (V5 chaves de criptografia, V6 inventário de inboxes, V7
auto-hospedagem do SDK), cada uma com dono, gatilho e consequência. **Nada a apontar.**

### 2.9 As 8 dependências `BE-*` do plano 23 — **onde o buraco está**

O §2.3 do PLANO-MESTRE confere `W*`, `T*`, `BK-*`, `T-C*` e `T-I*`. **Não confere `BE-*`** — e é
justamente ali que faltam duas.

| # | Dependência | Bloco | Veredito |
|---|---|---|:---:|
| BE-1 | Ponto único no strong params | 3.01 + arbitragem A1 | ✅ |
| **BE-2** | **Configuração de apresentação** (tema, posição, offsets, formato e texto do lançador, esconder bolha, estilo do painel) + **regra de precedência banco × `chatwootSettings`** | **nenhum bloco.** `grep "BE-2"` no PLANO-MESTRE → **zero** | **❌ BLOQUEADOR** |
| BE-3 | Perfil + backfill | 3.03; backfill eliminado por A4 | ✅ |
| BE-4 | Gatilhos por inbox | 3.02 (+ arbitragem A5) | ✅ |
| **BE-5** | **Lead incompleto** — persistir resposta parcial antes de a conversa existir | **nenhum bloco.** `grep "lead incompleto"` no PLANO-MESTRE → **zero** | **❌ BLOQUEADOR** |
| BE-6 | `EDITABLE_ATTRS` do pré-chat | 3.12 | ✅ |
| BE-7 | Tokens no servidor | 1.02 | ✅ |
| BE-8 | Tracking + segredos + log | 5.01, 5.02, 5.06, 5.14 | ✅ |

### 2.10 As 11 dívidas `D*` do plano 23

| # | Dívida | Bloco | Veredito |
|---|---|---|:---:|
| D1 | Lançador no `localStorage` | 3.09 (tela) — **mas depende de BE-2**, que não existe | 🟡 |
| D2 | `ColorPicker` muta o store | 0.9 | ✅ |
| D3 | Snippet por corte de string | 3.11 | ✅ |
| D4 | Preview com 74 props literais | 3.10 | ✅ |
| D5 | `WidgetBuilder.vue` órfão | 0.7 | ✅ |
| D6 | 37 chaves só em pt-BR | 0.8 | ✅ |
| D7 | 2 chaves i18n órfãs | 0.7 | ✅ |
| D8 | `allowed_domains` vazio | 0.8 | ✅ |
| D9 | **ERB × jbuilder divergem** | 0.6 — mas diz **"allowlist das 2 divergências atuais"** e `23 §A.5` mediu **quatro** (`hasAConnectedAgentBot`, `api_host`, `auth_token`, `utcOffset`×`utc_off_set`) | 🟡 **MENOR** |
| D10 | Dashboard importa i18n do widget | 0.8 | ✅ |
| D11 | Default de cor divergente | 0.8 | ✅ |

### 2.11 As 6 lacunas declaradas em `shared/LEIA-ME.md §8.6`

| Lacuna declarada | O plano trata? |
|---|---|
| Outros navegadores (só Chromium 145) | **Só como risco R24.** Nenhuma tarefa, nenhum `--project=webkit`, nenhum aceite. O harness 0.1 é Chromium |
| `forced-colors: active` | ✅ aceite explícito em 2.08 |
| `prefers-contrast: more` | ✅ 2.08 |
| **Zoom 200% + text-spacing (SC 1.4.4 e 1.4.12)** | Zoom: ✅ `reflow.spec.js`. **`text-spacing` (1.4.12): zero ocorrências nos 5 planos** |
| **Leitor de tela** | **❌ zero.** `grep "leitor de tela"/"NVDA"/"VoiceOver"/"screen reader"` nos 5 planos → **vazio**. A frente de a11y inteira se apoia em `axe` + asserções de DOM |
| **Tooltip colado na borda em desktop** | **❌ zero.** O LEIA-ME diz "fica para a implementação"; a implementação não pegou |

---

## 3. Omissões classificadas

### L-01 · BLOQUEADOR · A Tela 1 não tem onde salvar sete campos

**Evidência.** `PLANO-MESTRE` bloco **3.01** cria exatamente três chaves: `widget_profile`,
`widget_triggers`, `widget_tracking` (linha 327). A arbitragem **A1** (linha 659) fixa isso como
regra e, na **razão 4**, justifica: as três são declaradas *"numa única edição do strong params"* em
`inboxes_controller.rb:217`, arquivo 🔴 (+53/−9 upstream, +87/−6 fork), *"a evolução posterior
acontece dentro dos jsonb"*.

Mas `23 §B.2.2` lista **sete** campos da Tela 1 cujo destino é literalmente **"novo — BE-2"**: modo
de tema, posição, distância da borda, formato do lançador, texto do lançador, esconder a bolha,
estilo do painel. Nenhum deles cabe **dentro** de `widget_profile` (escalar/enum), `widget_triggers`
(schema de gatilhos, validado por `json_schemer` em 3.02) ou `widget_tracking` (projeção pública de
tracking, com validação em 5.01 que **recusa** chave desconhecida).

E o aceite de **3.09** exige persistência de servidor, textualmente: *"Mudar posição para
'esquerda', salvar e abrir **em outro navegador e outro admin**: continua 'esquerda'."*

**Consequência concreta.** Quem executar 3.09 descobre no meio da tarefa que não há chave. As duas
saídas são: (a) abrir `inboxes_controller.rb` uma **segunda** vez para declarar `widget_appearance`
— que é exatamente a N-ésima edição no arquivo 🔴 que A1 existe para evitar, com o conflito de merge
que R14 prevê; ou (b) enfiar aparência dentro de `widget_triggers`, quebrando o schema de 3.02.
Nenhuma das duas está planejada, e **M12** (persistir posição/tipo/título no servidor, gap MESA)
depende dela.

**Correção:** declarar a quarta chave `widget_appearance` **em 3.01**, junto com as outras três, e
acrescentar a regra de precedência de BE-2 (banco é o padrão; `chatwootSettings` do site
sobrescreve; a tela avisa quando há override ativo). **Esforço: P**, se feito agora. **M**, se
descoberto durante 3.09.

### L-02 · BLOQUEADOR · O mockup aprovado da Tela 3 promete duas seções que não existem em bloco nenhum

**Evidência.** `mockups/22-config-prechat-fluxo.html` — que é o contrato visual aprovado — tem cinco
seções numeradas. A seção **"3. Quem responde pela metade"** entrega: *"Salvar lead incompleto"*,
*"Tempo até considerar abandonado"* (2/5/15 min) e *"Etiquetar como `lead-incompleto`"*. A seção
**"4."** entrega *"Aviso de privacidade… Mostrar link para a política de privacidade"* e
*"Barra de progresso"*.

O bloco **3.14** (Tela 3, esforço **G**) descreve: *"editor de campo, etapas com teto de 8,
condicional de etapa anterior, os 3 modos (Simples/Construtor/Fluxo) e i18n"*. As duas seções não
estão lá. E `grep -in "lead incompleto\|resposta parcial\|barra de progresso"` no PLANO-MESTRE
devolve **zero linhas**.

O próprio mockup admite a dependência: *"Unificar os dois exige mudar o momento em que a conversa
nasce — é o mesmo trabalho de backend que destrava o lead incompleto."* Esse trabalho é **BE-5**, e
BE-5 não tem bloco (§2.9).

**Consequência.** O mockup foi mostrado como o que a tela vai ser. Quem implementar 3.14 entrega
três das cinco seções e a tela chega diferente do que foi aprovado. Pior: **lead incompleto é
pré-requisito de dois gaps MESA** — M13 (analytics: quantos começam e não terminam) e a capacidade
37 (dropout por etapa) — e de **D15** (A/B só faz sentido se você mede quem desistiu). Sem BE-5, o
"widget que trabalha" da Onda 4 entrega leads e **não sabe quantos perdeu**.

**Correção:** criar o bloco de BE-5 (mudança do momento de criação da conversa + persistência
parcial + etiqueta), na Onda 4, com dependência de 4.01. **Esforço: M–G** (é mudança de momento de
criação da conversa, não de formulário). E acrescentar à 3.14 as duas seções do mockup, ou riscá-las
do mockup antes que alguém as prometa a cliente.

### L-03 · BLOQUEADOR · O SDK engorda em oito blocos e nenhum aceite mede

**Evidência medida nesta task.** `public/packs/js/sdk.js` = **28.834 B** (9,57 KB gzip). O teto
existe: `22 §E.4` fixa **15 KB gzip** — folga de **5,4 KB gzip**. Mas:

1. O teto vive num apêndice do plano 22. `grep "15 KB"/"loader"` no **PLANO-MESTRE** → nada; o
   bloco 0.5 (gate de peso) mede o **grafo do widget** e a trava nominal do Leaflet, e o aceite fala
   em *"~575 KiB"*. **O SDK não entra no gate.**
2. `25 §T-C2.8` declara um **segundo** orçamento: *"o `sdk.js` tem 28.834 bytes e orçamento declarado
   de 40 KB"* — que é o `size-limit` atual, em bytes **crus**. Dois orçamentos, duas unidades, para o
   mesmo arquivo. A §5 do PLANO-MESTRE arbitra doze divergências (A1–A12); **esta não está entre
   elas**.
3. **Dezenove blocos** tocam `sdk/`, `IFrameHelper`, `bubbleHelpers`, `cookieHelpers` ou o snippet.
   **Oito adicionam código eager**: 1.23 (Promise em todos os métodos + fila pré-boot), 2.11 (`Esc`
   + `inert`), 2.14 (degradação com canal alternativo), **4.06 (o teaser, esforço G)**, 4.11 (piscar
   do título), 5.16 (`track()`), 5.17 (getters + `company`), 5.18 (`data-*`). Só 5.08/5.09/5.10 são
   declarados "sob demanda".

**Consequência.** **V1** — *"loader 15,9× mais leve que a Leadster"*, a vantagem que o estudo
classificou como argumento de venda pronto e nunca dito — é a única vantagem que este plano pode
destruir **sem que um único aceite fique vermelho**. O teaser sozinho (DOM no host, gatilho
composto, cookie de dispensa, avatar, chips, i18n, `all: revert`) é plausivelmente maior que os
5,4 KB gzip de folga. E o dano é assimétrico: 575 KB dentro do iframe custam ao visitante que
**abriu** o chat; bytes no `sdk.js` custam a **100% dos visitantes de todos os sites de todos os
clientes**.

**Correção:** puxar o teto de 15 KB gzip do apêndice do plano 22 para o bloco **0.5**, como sexto
teto do gate, e arbitrar a divergência 15 KB gzip × 40 KB crus. Acrescentar ao aceite de **4.06**
uma medida de delta do `sdk.js`. **Esforço: P.**

### L-04 · GRAVE · O ícone do launcher — pedido direto, não coberto

Tratado inteiro na §4.

### L-05 · GRAVE · O bloco de IA inteiro sumiu sem constar em §8

**Evidência.** Capacidades 49, 50, 51, 53, 54 e diferenciais D8, D9, D10(parcial): zero ocorrências
de `reranker`, `sitemap`, `guardrail`, `eval` (no sentido de avaliação de IA) e `citação de fonte`
nos cinco planos. As únicas duas tarefas que tocam IA são 4.09 (rótulo de identidade) e 4.17
(delimitar atributos do site no prompt, `system_prompts_service.rb:312-322`).

A lista **§8 "O que NÃO vamos fazer"** tem 25 linhas e **nenhuma menciona IA**.

**Consequência.** O estudo chamou **D8** (eval como produto) de *"a coisa de maior valor/esforço do
inventário inteiro"* e **D9** (guardrail) de *"gap nº 1 da nossa IA"*, ambos **M**, ambos reusando
motor que já existe. Ao mesmo tempo, o plano coloca a IA **na frente do visitante** (o widget de
marketing conversa com IA; 4.09 põe rótulo; 4.03 é fluxo conversacional). Entregar IA mais exposta
sem guardrail de pré-envio é aumentar a superfície de erro exatamente onde ele custa mais caro — na
página do cliente, com a marca do cliente.

Se a decisão foi "IA fica para outro plano", isso é legítimo e é **uma linha em §8**. Como está,
lê-se como esquecimento.

### L-06 · GRAVE · A decisão I5 (contexto ao lado da conversa) sumiu — e é a única que dependia do redesenho

**Evidência.** `DECISOES.md` parte 3, **I5**: *"Contexto externo: ao lado da conversa ou aba? — Ao
lado primeiro, app embutido depois."* O original (`20-spec-integracao.md §P5`) é explícito:
*"**Esta é a única pergunta desta lista que realmente depende do redesenho de front** — as outras
cinco não"*, com o arquivo alvo nomeado (`ConversationBox.vue:159`).

`grep "ConversationBox\|card lateral\|Canvas Kit\|app embutido"` nos cinco planos → **vazio**.

Agrava: o PLANO-MESTRE **usa o rótulo "I5"** três vezes (bloco 4.12: *"BK-05 = I5 prioridade 1"*;
diagrama da Onda 4: *"trilha paralela: webhooks (I5)"*), mas se refere ao **I5 do plano 25**
(webhooks), não ao I5 das decisões. Quem conferir por ID vai marcar como coberto.

**Consequência.** A decisão de integração que mais dependia desta fase de redesenho é a única que
não sobreviveu a ela — e some atrás de um homônimo.

### L-07 · MÉDIO · Nenhuma rastreabilidade por identificador entre estudo e planejamento

**Evidência.** Os planos citam `10-gap-analysis.md` e `DECISOES.md` **duas vezes ao todo**, ambas no
PLANO-MESTRE (linhas 49 e 1003), ambas como inventário de entrada. Nenhum bloco da tabela mestra
tem coluna "gap do estudo". Pior: os espaços de identificadores **colidem** —

| Prefixo | Significa no estudo | Significa nos planos |
|---|---|---|
| `M1`–`M15` | gaps MESA | `M1`–`M11` = **medições** do PLANO-MESTRE §0.3 |
| `D1`–`D15` | diferenciais | `D1`–`D11` = **dívidas** do plano 23 |
| `V1`–`V16` | vantagens | `V1`–`V7` = **verificações pendentes** do PLANO-MESTRE §7 |
| `N1`–`N12` | ruído | `N1`–`N10` = **decisões de negócio** |
| `I5` | contexto ao lado da conversa | `I5` = frente de **webhooks** do plano 25 |

**Consequência.** É por isso que 16 capacidades, 8 diferenciais e 4 decisões puderam sumir sem
ninguém notar: a §2.3 *"nada ficou de fora"* confere **os planos contra si mesmos** (277 tarefas →
106 blocos) e nunca confere **os planos contra o estudo**. A checagem que faltava é esta tabela.

**Correção:** uma coluna "origem no estudo" na tabela mestra, ou um apêndice de rastreabilidade
inversa. **Esforço: P.** É o item de maior retorno desta auditoria.

### L-08 · MÉDIO · A decisão sobre as campanhas existentes foi declarada como custo e nunca tomada

**Evidência.** `23 §B.3.1`, última linha: *"**O que isso custa:** um endpoint novo **e a decisão do
que fazer com as campanhas existentes**."* A arbitragem **A5** do PLANO-MESTRE resolve a primeira
metade (sem endpoint novo na v1; a config vai no payload de boot). A segunda metade não é
mencionada em lugar nenhum.

**Consequência.** Hoje o widget já busca campanhas com `trigger_rules` (`url`, `time_on_page`) e
cacheia por 1 hora (`widget/store/modules/campaign.js:45-47`). Quando `widget_triggers` entrar
(3.02 + 4.04 + 4.06), uma conta com campanha ativa passa a ter **dois caminhos** que mostram
mensagem proativa, cada um com sua regra de tempo/URL, sem nada que os concilie. É o mesmo padrão do
"modo antigo" que já mordeu na tela de Automações. A verificação **V6** pergunta quantas inboxes têm
campanha ativa, mas só *"refina 3.03"* (o texto do diálogo de perfil) — não a migração.

**Correção:** decidir e escrever a coexistência (campanha legada continua? é importada para gatilho?
a tela avisa?) antes de 4.04. **Esforço: P** para decidir, **M** para a rampa.

### L-09 · MÉDIO · A11y planejada sem nunca rodar um leitor de tela

**Evidência.** A frente de acessibilidade tem 6 blocos (1.06, 2.01, 2.06, 2.08, 2.09, 2.11) e um
suite (`a11y.spec.js` com `@axe-core/playwright`). `grep "leitor de tela\|NVDA\|VoiceOver\|screen
reader"` nos cinco planos → **zero**. O `LEIA-ME §8.6` declarou a lacuna; o plano não a recolheu.
Idem `text-spacing` (SC 1.4.12): zero ocorrências.

**Consequência.** `axe` verifica presença de atributo, não **experiência anunciada**. Um
`role="log"` com `aria-live="polite"` pode existir, passar no axe e ainda assim anunciar a mensagem
inteira a cada token de streaming — que é o modo de falha clássico de chat com IA, e o widget vai
ter streaming (4.09 pede `aria-busy`). Sem uma passagem manual, a11y aqui é conformidade de
checklist.

**Correção:** uma tarefa de verificação manual com NVDA (Windows) ou Orca/VoiceOver ao fim da
Onda 2, com roteiro de 6 fluxos. **Esforço: P.**

### L-10 · MÉDIO · Toda a fundação visual é Chromium, e não há tarefa que saia dele

**Evidência.** `LEIA-ME §8.6` declara: *"Toda medição é Chromium 145. O fallback CSS depende de
relative color syntax e `pow()`; em Safari e Firefox não foi testado."* O plano responde com o risco
**R24**, cuja mitigação é *"a fonte de verdade é o servidor (1.02), não o CSS"*. Isso resolve **a
cor** — não resolve `dvh`, `env(safe-area-inset-*)`, `inert`, `overscroll-behavior`,
`:focus-visible`, `color-scheme` nem `prefers-reduced-motion`, todos usados em 2.08/2.09/2.10/2.11.
O harness (0.1) roda um projeto só, Chromium. `grep "WebKit"` → zero.

**Consequência.** O widget vive no site do cliente, onde o tráfego é do visitante, não nosso. R12 já
obriga teste manual em iOS Safari **só para 2.09**. Os outros quatro blocos que dependem de CSS
moderno não têm nenhuma cobertura fora do Chromium.

**Correção:** um `--project=webkit` no harness com o subconjunto de specs de layout/motion.
**Esforço: P.**

### L-11 · MÉDIO · A superfície do agente ganha componente novo sem desenho e sem auditoria

**Evidência.** Todo o lado do agente resume-se ao bloco **1.17** (seção "Dados recebidos do site
(N)" em `CustomAttributes.vue`) e ao painel de diagnóstico de 5.14. Há **9 mockups**: 3 do widget,
4 das telas de configuração, 1 do sistema visual, 1 índice. **Zero do painel do agente.**

**Consequência.** Ao fim do plano, o agente recebe na tela: ~12 atributos de origem (1.19), atributos
auto-provisionados com selo de confiança (1.16/4.17), IP mascarado (1.17), estado de identidade
verificada (4.15), e — se BE-5 existir — leads incompletos etiquetados. Isso é uma reorganização
real de uma barra lateral que ninguém desenhou. A decisão **I5** (§L-06) era exatamente sobre esse
espaço, e sumiu.

### L-12 · MÉDIO · Instalação e onboarding: superfície inteira sem dono

**Evidência.** `grep "onboarding"` no PLANO-MESTRE → **zero**. `grep "verificar instalação"` → zero.
`grep "wordpress\|wix"` nos cinco planos → zero. O gap **M14** (instalação documentada em WP/Wix/GTM,
"todos têm", esforço **P**) não aparece.

Mais incômodo: o **mockup 21 mostra uma aba "Instalação"** na barra de abas da inbox (*Aparência ·
Gatilhos · Pré-chat · Rastreio · Agentes · Horário · **Instalação***). Nenhum bloco a trata. 3.11
conserta **como o snippet é montado**; ninguém cuida **da tela onde ele é entregue** nem de o
cliente saber se ele está funcionando.

**Consequência.** É a primeira tela que o cliente novo vê e a última que alguém planejou. Nenhum
concorrente do corpus entrega o widget sem checador de instalação.

### L-13 · MENOR · 0.6 diz "2 divergências"; a medição diz 4

`23 §A.5` mede quatro divergências entre os dois montadores de config: `hasAConnectedAgentBot`,
`api_host`, `auth_token` e `utcOffset` × `utc_off_set`. O bloco **0.6** manda criar o spec de
paridade *"com allowlist das **2** divergências atuais"*.

**Consequência.** Quem escrever o spec vê quatro falhas contra uma allowlist de duas e ou alarga a
lista sem entender, ou trava. **Esforço de correção: P** (trocar o número).

### L-14 · MENOR · O "experimento" do launcher que fala virou toggle

Decisão **F4**: *"Experimento em 2–3 contas, não default."* O que existe no plano é um campo de
configuração (`standard|expanded_bubble`, `23 §B.2.2`) e o mockup correspondente. Não há
infraestrutura de experimento em lugar nenhum — nem para F4, nem para D15 (A/B). **Consequência:**
a decisão "não é default, é experimento" perde o mecanismo que a torna verdadeira; vira só mais um
switch, e ninguém mede se ajudou.

### L-15 · MENOR · Duas vantagens exercitadas sem teste de não-regressão

**V5** (reconexão endurecida): 2.07 reescreve o watchdog em `BaseActionCableConnector.js`; o aceite
mede o **banner** ("nada nos primeiros 3 s, faixa depois"), não o backoff+jitter nem os handlers
`visibilitychange`/`focus`/`pageshow` que **são** a vantagem. **V7** (51–55 locales + RTL): 2.18 faz
i18n sob demanda e o único aceite de idioma é 1 snapshot `dir="rtl"`. Nenhum verifica que os 51
locales continuam carregando.

### L-16 · COSMÉTICO · O tooltip da borda ficou órfão entre dois documentos

`LEIA-ME §8.6`: *"Posicionamento dinâmico… fica para a implementação."* A implementação (blocos
2.01, 3.06–3.14) não menciona tooltip nenhuma vez. Handoff perdido entre a fundação e as telas.

---

## 4. O ícone do launcher — o pedido direto do Walisson

### 4.1 O estado de hoje, reconferido

`app/javascript/sdk/bubbleHelpers.js`:

```js
export const bubbleSVG =
  'M240.808 240.808H122.123C56.6994 240.808 3.45695 187.562 3.45695 122.122C…';   // :10

export const createBubbleIcon = ({ className, path, target }) => {               // :28
  const bubbleIcon = document.createElementNS('http://www.w3.org/2000/svg','svg');
  bubbleIcon.setAttributeNS(null, 'viewBox', '0 0 240 240');                     // :36
  bubblePath.setAttributeNS(null, 'd', path);                                    // :45
  bubblePath.setAttributeNS(null, 'fill', '#FFFFFF');                            // :46
  target.title = 'Open chat window';                                             // :60
};
```

**Três fatos, verificados nesta task:** o desenho é um `path` fixo; a cor é `#FFFFFF` cravada; e não
existe caminho algum para uma imagem. Nem `<image>`, nem `background-image`, nem parâmetro de
configuração. O `title` é inglês hardcoded.

### 4.2 O que o planejamento cobre

**Uma linha, e ela não troca ícone.** `22-plano-widget.md:258`, item 34 da tabela de literais:

> \| 34 \| `sdk/bubbleHelpers.js:46` \| `bubblePath.setAttributeNS(null,'fill','#FFFFFF')` — o ícone
> do launcher \| `currentColor`, herdando `--w-on-brand` \|

Isso é o bloco **1.05**, e é **correção de contraste** (o ícone branco some numa marca amarela), não
troca de ícone.

O que a Tela 1 oferece para o launcher (`23 §B.2.2` + `mockups/20-config-perfil-aparencia.html`,
seção "Lançador"): **posição** (esquerda/direita), **distância da borda** (0–120, padrão 20/20),
**formato** (só o ícone / ícone + texto), **texto** (≤ 40 caracteres), **esconder a bolha**. O campo
**Avatar** existe na mesma tela, mas o texto do próprio mockup delimita: *"Aparece no cabeçalho do
widget **e no teaser**"* — explicitamente **não** no lançador.

**Buscas de confirmação, todas vazias nos cinco planos e nos nove mockups:** `createBubbleIcon`,
`bubbleSVG`, `foto humana`, `foto de pessoa`, `avatar no lançador`, `ícone personalizado`,
`imagem do lançador`, `logo do cliente`.

**Veredito: o pedido não está coberto.** Nem a troca de ícone, nem a foto de pessoa.

### 4.3 O que o estudo mediu, e o plano não recolheu

`frontend/11-teardown-visual.md §A10` (Leadster), medido em navegador:

| Propriedade | Valor medido |
|---|---|
| `div.nld-avatar` | 60 × 60 px, `border-radius: 30px` |
| Fundo | `rgb(23,113,240)` **+ `background-image`: a foto da atendente** (`storage.googleapis.com/neuro-cdn/…`) |
| Ícone | **não há** — o launcher é o rosto de uma pessoa |
| `box-shadow` | `rgba(0,0,0,0.15) 0 0 12px 0` (halo, sem deslocamento) |

E a frase que fecha: *"**9 dos 13 launchers medidos são um ícone de balão dentro de um círculo
colorido; o da Leadster é uma fotografia humana.**"*

Dado adicional do mesmo corpus, também não recolhido: o Zendesk usa `aria-label: "Abrir janela de
mensagens"` **localizado em pt-BR** — nosso `title` é `'Open chat window'` em inglês para todos os
locales (o bloco 1.06 corrige isso, ✅).

### 4.4 O que faltaria especificar — porque o launcher vive na página do cliente

Nada disto existe em nenhum plano. Levanto porque é um pedido direto e porque cada item é uma forma
de o recurso quebrar em produção:

| # | O que falta | Por que importa | Esf. |
|---|---|---|:---:|
| 1 | **Modelo do campo** — três modos: `default` (o balão de hoje), `image` (upload), `agent_photo` (reusa o avatar da inbox). O modo é o que impede o cliente de subir um PNG de 2 MB por engano | Sem enum, isso vira campo livre e cada cliente inventa um formato | P |
| 2 | **Onde grava** — é aparência, ou seja, **BE-2**, que não existe (**L-01**). Sem resolver L-01, este campo não tem chave | O pedido depende do bloqueador | — |
| 3 | **Peso e formato** — o launcher carrega no `document` do host, para 100% dos visitantes. Definir teto (sugestão: ≤ 20 KB), formato (WebP com fallback PNG) e **thumbnail servido pronto pelo servidor**, nunca a imagem original redimensionada por CSS | Uma foto de 400 KB no canto de todas as páginas anula o argumento V1 inteiro (**L-03**) | M |
| 4 | **De onde vem o byte** — `ActiveStorage` do nosso domínio, com URL estável e cache longo. **Nunca CDN externo**: `R18` já registra que CSP de cliente bloqueia origem estranha, e a Leadster serve de `storage.googleapis.com` — que é exatamente o que um CSP restritiva barra | Feature que funciona no teste e some no site do cliente com CSP | P |
| 5 | **`preload` / `fetchpriority`** — o launcher é a primeira coisa visível; a imagem precisa chegar antes do primeiro paint dele, ou o cliente vê um círculo vazio piscando | Sem isso, troca-se um SVG instantâneo por um buraco de 300 ms | P |
| 6 | **Fallback quando a imagem falha** — `onerror` volta ao `bubbleSVG` atual. Hoje não há caminho de erro nenhum porque não há imagem | Sem fallback, 404 na foto = launcher invisível = canal de contato sumido do site do cliente | P |
| 7 | **Anel/borda contra a cor da marca** — foto colada em fundo claro sobre site claro desaparece. Precisa de anel de contraste derivado de `--w-brand-border`, que **já existe** no sistema de tokens (`shared/tokens.css`) e já é validado a ≥ 3:1. O trabalho é aplicá-lo ao launcher | Requisito 1.4.11 (componente ≥ 3:1) e o motivo pelo qual a Leadster mantém o círculo azul **atrás** da foto | P |
| 8 | **Recorte e forma** — a geometria está congelada em 64 px circular (§8 item 2). Foto retangular precisa de `object-fit: cover` + `border-radius` herdado, decidido no servidor ou no CSS, não por cliente | Sem regra, cada cliente sobe uma foto de proporção diferente e o launcher fica torto | P |
| 9 | **Nome acessível** — com foto de pessoa, `title`/`aria-label` deixa de ser "Abrir chat" e passa a poder ser "Falar com a Marina". Precisa continuar traduzido (1.06 já criou a via) | A11y: um botão que é um rosto sem rótulo é um botão sem nome | P |
| 10 | **Preview** — o bloco 3.10 conserta o preview para consumir tokens reais. Se o ícone virar configurável, o preview precisa mostrá-lo, senão o cliente escolhe às cegas | O preview é a única forma de o cliente ver antes de publicar | P |
| 11 | **Modo escuro** — foto com fundo branco em site escuro. Ou o anel resolve, ou precisa de segunda variante | 2.10 torna o dark default `auto`; o problema aparece sozinho | P |

**Esforço total estimado: M**, e cai para **P–M** se entrar junto com **3.09** (a tela do lançador já
está sendo escrita) e **1.05** (o `fill` já vai ser mexido no mesmo arquivo, na mesma linha).

**Nota de honestidade sobre o mérito.** O estudo mediu que 9 de 13 usam balão em círculo colorido e
**um** usa foto. Isso é evidência de que foto é **desvio**, não de que foto **converte mais** —
nenhum relatório traz teste comparando launcher-ícone × launcher-foto. Recomendo entregar o campo
(é barato, é pedido, e destrava tanto o logo do cliente quanto a foto) e **não** prometer conversão.

---

## 5. Superfícies esquecidas

| Superfície | Cobertura no plano | Veredito |
|---|---|---|
| **Widget (iframe)** | Ondas 1, 2, 4 — 30+ blocos, 3 mockups | ✅ densa |
| **Telas de configuração** | Ondas 0, 3, 4, 5 — 4 telas, 4 mockups | ✅ densa |
| **Snippet / tela de instalação** | 3.11 (montagem), 5.18 (`data-*`), 2.14 (degradação). **A aba "Instalação" aparece no mockup 21 e não tem bloco** | 🟡 **L-12** |
| **Onboarding / verificador de instalação** | zero | **❌ L-12** |
| **Documentação pública** | 5.15 (contrato de integração para desenvolvedor). **Não** cobre instalação em WP/Wix/GTM (**M14**) | 🟡 |
| **Portal / Central de Ajuda** | 3.17 governa a exibição de artigos no widget; busca 🚫 recusada (§8 item 25). O portal em si não é objeto | ✅ escopo declarado |
| **Campanhas** | 4.05 vincula teaser ↔ campanha. **Coexistência com campanhas legadas não decidida** | 🟡 **L-08** |
| **Experiência do agente** | 1.17 e 5.14. Sem mockup; **I5 (card lateral) sumiu** | 🟡 **L-06, L-11** |
| **Relatórios** | 1.22 (conversas por UTM), 5.21 (estatística por gatilho). Sem funil do widget, sem dropout (**M13**) | 🟡 |
| **App mobile do agente** | **zero ocorrências** de `app mobile`, `React Native`, `Flutter`, `mobile app` nos cinco planos | **❌** |

**Sobre o app mobile — e sendo justo.** A ausência total só é problema porque `23 §A.5` registra que
o **segundo montador de config** (`configs/create.json.jbuilder`) é consumido, por inferência, por
*"clientes fora deste repositório (SDKs mobile)"* e que **quem exatamente consome está
`[NÃO VERIFICADO]`**. O bloco **3.04** entrega chaves novas **nesse arquivo**, e o bloco **0.6** cria
o teste que **obriga** toda chave nova a entrar nos dois montadores. Ou seja: o plano vai empurrar
chaves para um consumidor que ninguém identificou. Isso merecia uma oitava verificação pendente
("quem consome `POST /api/v1/widget/config`?"), custo **P**, e não tem.

---

## 6. O que o mercado tem, o estudo registrou, e o plano ignorou sem justificar

Filtro: presente no corpus medido, registrado no estudo com evidência, **ausente dos cinco planos
e ausente das 25 linhas de §8**.

| # | Item | Quem tem (medido) | Esforço no estudo |
|---|---|---|:---:|
| 1 | Instalação documentada WP/Wix/GTM (**M14**) | todos | P |
| 2 | Ponto de montagem customizado (cap. 7) | Leadster, Intercom, Kommo | P |
| 3 | Modo inline/embutido (cap. 8) | Blip, Kommo, Zenvia | M |
| 4 | Esconder no teclado virtual (cap. 28) | Leadster | P |
| 5 | Rotação de mensagens no teaser (cap. 19) | Leadster | P |
| 6 | Lead incompleto / sync incremental (cap. 36, **BE-5**) | Leadster | M |
| 7 | Dropout por etapa (cap. 37, **M13**) | Leadster | M |
| 8 | Lead scoring por resposta (cap. 38) | Leadster | M |
| 9 | Teste A/B versionado (cap. 39, **D15**) | Leadster | M |
| 10 | Página de captura hospedada (cap. 40, **D12**) | Leadster, Typeform, Landbot | M |
| 11 | Roleta entre N números no redirect (cap. 42) | Leadster | P |
| 12 | Reranker (cap. 49) | provável no Intercom; **TODO no nosso código** | M |
| 13 | Ingestão por sitemap (cap. 50) | Leadster, Intercom | M |
| 14 | Intenções próprias (cap. 51) | *lacuna declarada pela própria Leadster* | M |
| 15 | Guardrail executável (cap. 53, **D9**) | Sierra, Decagon | M |
| 16 | Eval como produto (cap. 54, **D8**) | Decagon, Zendesk QA | M |
| 17 | Citação de fonte por padrão (**D10**) | Fin, Ada — **`feature_citation` já existe** | P |
| 18 | Feriados brasileiros (**D11**) | Huggy **cobra por isso** | P |
| 19 | Referrer de IA generativa (**D14**) | ninguém — converte 7,80% | P |
| 20 | Contador de não lidas + `connected`/`disconnected` (**M7**) | 15/20 dos globais | P |
| 21 | `open()`/`close()` idempotentes (**M8**) | 20/20 | P |
| 22 | Stub queue **no snippet** (**M15**) | 20/20 | P |

**Vinte e duas.** Onze são **P**. O estudo já tinha antecipado a frase: *"Não fazer os P é escolha,
não restrição."* O problema não é a escolha — é que ela não está escrita em lugar nenhum, e a §8
existe exatamente para isso.

---

## 7. Onde está bom (uma linha cada, sem gastar espaço)

- Os **6 defeitos verificados** têm bloco, aceite e ordem — inclusive a arbitragem A7, que percebeu
  que corrigir B3 antes do merge é escrever duas vezes.
- As **4 verificações pendentes** viraram 7, com dono, gatilho e consequência por resposta.
- O **bloco G inteiro** (tracking, 9 capacidades) tem cobertura ponta a ponta, do parser ao ciclo
  fechado.
- O balde **RUÍDO** foi respeitado: nenhum dos 12 vazou.
- As **10 medições que reconferi bateram**, incluindo as incômodas (falso verde do `size-limit`, 2
  `aria-label`, hover verde em `sdk.js:132`).
- A arbitragem **A1** (jsonb em vez de coluna) elimina três migrations e o `DuplicateMigrationVersion`
  — a maior economia de risco do plano, e está certa. O problema é o que ela **não** cobriu (L-01).
- A §5 arbitra doze divergências entre frentes com medição ao lado. É trabalho de verdade.

---

## 8. Veredito

**O planejamento cobre o que se propôs a cobrir — e o que ele se propôs a cobrir é menor do que o
estudo pediu.**

Como plano de execução das quatro frentes, é sólido: 106 blocos, dependências reais, aceites
verificáveis, doze divergências arbitradas com medição, e uma ordem de ataque que passa pelos
arquivos mais seguros do repositório. Se alguém executar a tabela mestra na ordem, sai um widget
melhor e duas camadas novas de produto.

Como resposta ao estudo, tem três buracos que impedem a execução como está escrita — a Tela 1 não
tem chave onde gravar sete campos (**L-01**), o mockup aprovado da Tela 3 promete duas seções sem
bloco (**L-02**), e o SDK recebe código de oito blocos sem que nenhum aceite meça o peso da vantagem
que o estudo elegeu como argumento comercial nº 1 (**L-03**) — e três omissões que mudam o resultado
para o cliente: o ícone do launcher, que foi pedido diretamente (**L-04**); a frente de IA inteira,
que sumiu sem constar na lista de recusas (**L-05**); e a decisão I5, que era a única de integração
que dependia deste redesenho (**L-06**).

A causa comum é uma só e tem correção barata: **não existe rastreabilidade por identificador entre
o estudo e o planejamento** (**L-07**). A §2.3 se chama *"Cobertura — nada ficou de fora"* e confere
os planos contra si mesmos. Uma coluna "origem no estudo" na tabela mestra teria pego 16
capacidades, 8 diferenciais e 4 decisões antes de qualquer linha de código.

**Está à altura como plano de obra. Ainda não está à altura como resposta ao estudo.** A distância
entre os dois cabe em: uma quarta chave em 3.01, um bloco novo para BE-5, um teto no gate 0.5, um
campo de ícone em 3.09, e vinte e duas linhas na §8 dizendo o que não vamos fazer e por quê. Nada
disso é grande. Tudo isso é hoje, antes de a Onda 3 começar — depois, é retrabalho em arquivo 🔴.

---

### Anexo — comandos desta auditoria

```bash
# medições reconferidas
ls -la public/packs/js/sdk.js                      # 28834
ls -la public/vite/assets/widget-*.css             # 1103138 (+ 4 hashes = falso verde)
ls -la public/vite/assets/leaflet-*.js             # 150679
grep -rn "aria-label" app/javascript/widget/ | wc -l   # 2
sed -n '28,61p' app/javascript/sdk/bubbleHelpers.js    # createBubbleIcon
grep -n "2dc46f" app/javascript/sdk/sdk.js             # :42 e :132
sed -n '64,80p' app/models/channel/web_widget.rb       # snippet sem stub

# omissões (todas devolvem vazio)
cd plano/redesenho
grep -rin "lead incompleto\|barra de progresso" PLANO-MESTRE.md
grep -rin "dropout\|guardrail\|reranker\|sitemap\|teste A/B" *.md
grep -rin "createBubbleIcon\|foto humana\|ícone personalizado" *.md
grep -rin "ConversationBox\|card lateral\|Canvas Kit" *.md
grep -rin "leitor de tela\|NVDA\|VoiceOver\|text-spacing" *.md
grep -rin "wordpress\|wix\|onboarding\|custom_launcher_selector" *.md
grep -rin "tools.yml\|panorama\|feriado\|página de captura" *.md
grep -n "BE-2\|BE-5" PLANO-MESTRE.md
```
