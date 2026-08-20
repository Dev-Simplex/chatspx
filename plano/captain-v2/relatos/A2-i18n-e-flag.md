# A2 / F0 — i18n do painel V2 consertado, e o que descobri sobre a flag

**Worker:** A2 · **Data:** 28/07/2026 · VM 192.168.8.232 (homologação), branch `homologacao`, base `ee87f5e799`
**Escopo entregue:** i18n dos dois locales + spec de regressão + diagnóstico da flag.
**Sem commit, sem build, sem deploy, sem migration, sem SSH para outra VM.**

---

## 1. Resultado em uma linha

O painel V2 pedia **109 chaves** de tradução e **nenhuma delas resolvia** — 0%, nos dois idiomas.
Agora resolvem **109 de 109**, em pt-BR e en, com spec travando isso na suíte.

---

## 2. O diagnóstico, conferido antes de corrigir

O relatório P2 §7.2 dizia "83 chamadas pedem `CONVERSATION.AI_ASSISTANT_PANEL.*`". Conferi e o
problema é **maior** do que o relatado, em duas frentes:

| | P2 dizia | Medido |
|---|---|---|
| Namespaces quebrados | 1 (`AI_ASSISTANT_PANEL`) | **2** — `COPILOT_ERRORS` está igualmente na raiz e o `AIErrorBanner.vue` pede `CONVERSATION.COPILOT_ERRORS.*` (15 chamadas) |
| Chamadas | 83 | **133** |
| Chaves distintas | — | **109** |

### A causa, mecanicamente

`app/javascript/dashboard/i18n/locale/<loc>/index.js` importa cada JSON e as **chaves de topo de
cada arquivo viram namespaces globais planos**. Logo:

- `CONVERSATION.COPILOT.*` → o bloco `COPILOT` mora **dentro** de `CONVERSATION` ✅ funciona
- `CONVERSATION.AI_ASSISTANT_PANEL.*` → o bloco morava **na raiz** ❌ não resolve
- `CONVERSATION.COPILOT_ERRORS.*` → idem ❌

vue-i18n, quando não acha a chave, **devolve a própria chave** — que é literalmente o que aparecia
na tela (`CONVERSATION.AI_ASSISTANT_PANEL.EMPTY.SUBTITLE`).

### Baseline medido (código de agora × JSON do HEAD `ee87f5e799`)

```
chaves pedidas: 109
  pt_BR: resolviam 0/109 (0%)  -> 109 chaves cruas na tela
  en:    resolviam 0/109 (0%)  -> 109 chaves cruas na tela
```

Zero chaves são montadas dinamicamente (nenhum template literal, nenhuma concatenação), então o
cruzamento é completo — não há caminho que o script deixe passar.

---

## 3. A escolha: opção (a), mover as strings. E por quê

**Escolhi (a) — mover os dois blocos para dentro de `CONVERSATION` nos dois JSONs.**
Não toquei em nenhum `.vue`/`.js` de componente. **Não precisei do `AIAssistantPanel.vue` (A4).**

Três razões, em ordem de peso:

**1. É o que o repo já faz.** `CONVERSATION.COPILOT.*` (o painel V1) já vive dentro de
`CONVERSATION`. Todo componente da tela de conversa usa esse prefixo. Deixar o V2 na raiz seria a
exceção, e a exceção é justamente o que quebrou.

**2. Merge com o upstream: (a) é dramaticamente mais barato.** Medi contra `upstream/develop`:

- A opção (b) mexeria em **133 call sites** espalhados por 9 arquivos — incluindo
  `ReplyBox.vue` (>3.000 linhas, arquivo que o upstream toca com frequência) e
  `composables/useCaptain.js`. Conflito quase certo no próximo merge.
- A opção (a) toca **2 arquivos JSON**, e num ponto escolhido: o objeto `CONVERSATION` do upstream
  termina em `VOICE_WIDGET`; tudo o que vem depois no nosso arquivo (`TEAM_ISOLATION`,
  `AGENT_ISOLATION`, `TAKEOVER_*`, `ACCESS_BLOCKED`) é **100% SPX-only**. Inseri logo após
  `ACCESS_BLOCKED` — zona onde o upstream nunca escreve.

**3. Propriedade.** A opção (b) exigiria editar `AIAssistantPanel.vue`, do worker A4, no mesmo
momento em que ele está reescrevendo o arquivo. A opção (a) evita o conflito por construção.

---

## 4. O que mudou, arquivo a arquivo

| Arquivo | O que |
|---|---|
| `app/javascript/dashboard/i18n/locale/pt_BR/conversation.json` | `COPILOT_ERRORS` e `AI_ASSISTANT_PANEL` movidos da raiz para dentro de `CONVERSATION` (após `ACCESS_BLOCKED`, linha ~650); textos revisados; 29+9 chaves novas |
| `app/javascript/dashboard/i18n/locale/en/conversation.json` | idem, espelhado |
| `app/javascript/dashboard/i18n/specs/ai-assistant-panel-ptbr.spec.js` | **novo** — 12 testes que travam o conserto |

Nenhum outro arquivo tocado. `+432 / −288` linhas nos dois JSONs somados.
Total final: **108 strings** em `AI_ASSISTANT_PANEL` + **26** em `COPILOT_ERRORS`, idênticas em
número e chave nos dois locales.

---

## 5. Cruzamento mecânico — o número pedido

Script: `/tmp/.../scratchpad/check_i18n.py` (a mesma lógica está no spec, que é a versão que fica).

```
========================================================================
CRUZAMENTO i18n — painel AI Assistant V2
========================================================================
Chamadas encontradas no código : 133
Chaves DISTINTAS pedidas       : 109
Chaves montadas dinamicamente  : 0 (cruzamento é completo)

--- pt_BR ---
  presentes em CONVERSATION.* : 109/109 (100%)
  FALTANDO                    : 0
    dos quais só na RAIZ      : 0
    inexistentes em qualquer  : 0
  strings vazias              : 0

--- en ---
  presentes em CONVERSATION.* : 109/109 (100%)
  FALTANDO                    : 0
    dos quais só na RAIZ      : 0
    inexistentes em qualquer  : 0
  strings vazias              : 0

Paridade pt_BR x en: OK — idênticas
RESULTADO: OK — 100% das chaves pedidas existem nos 2 locales
```

**Quantas faltavam: 109 (todas).** Quantas presentes agora: 109. Nos dois idiomas.

### ⚠️ Aviso de corrida — leia antes de commitar

O A4 está reescrevendo `AIAssistantPanel.vue` **enquanto eu trabalhava**. As chaves pedidas subiram
de **85 → 91 → 109** em ~25 minutos. Cobri as três levas. Mas se ele continuar, o número muda de
novo.

**Por isso o cruzamento virou spec** (`ai-assistant-panel-ptbr.spec.js`): ele varre o código-fonte
na hora em que roda, então pega chave nova sem ninguém precisar lembrar. **Rode-o antes do commit.**

```bash
npx vitest run app/javascript/dashboard/i18n/specs/ai-assistant-panel-ptbr.spec.js
```

### Chaves presentes e hoje não usadas (25)

Não removi nenhuma — remover chave em cima de um arquivo que outro worker está reescrevendo é risco
puro, e o custo de manter é zero. São de dois tipos:

- **16 legadas**, que o A4 acabou de deixar de usar ao reescrever o painel (`ACTIONS.APPLY`,
  `PROMPTS.*`, `SECTIONS.*`, `TEXTAREA.HINT`…). Se a reescrita dele estabilizar sem elas, dá para
  varrer depois — é limpeza, não bug.
- **9 que eu adicionei de propósito** para o contrato C1 (`COPILOT_ERRORS.UNAUTHORIZED`,
  `RATE_LIMITED`, `PROVIDER_DOWN`, `CANCELLED`) — ver §7.

---

## 6. Português de verdade — o que reescrevi

Revisei o tom das strings, seguindo o mockup aprovado. O padrão: **dizer o que houve, não culpar a
conexão do usuário, e dizer o que fazer.**

| Chave | Antes | Agora |
|---|---|---|
| `COPILOT_ERRORS.CAPTAIN_UNSTABLE.BODY` | "Tente de novo em alguns minutos" | "O serviço de IA não respondeu. **Isso não é problema da sua conexão** — tente de novo em alguns minutos." |
| `COPILOT_ERRORS.RATE_LIMIT.TITLE` | "Muitas solicitações" | "Muitos pedidos em pouco tempo" |
| `COPILOT_ERRORS.RATE_LIMIT.BODY` | "Aguarde {seconds}s e tente outra vez" | "O serviço de IA pediu uma pausa. Espere {seconds}s e peça de novo." |
| `COPILOT_ERRORS.EMPTY_RESPONSE.TITLE` | "Não recebi resposta válida" | "A resposta veio vazia" |
| `COPILOT_ERRORS.EMPTY_RESPONSE.BODY` | "Algo deu errado no Copilot. Quer tentar gerar de novo?" | "O serviço de IA devolveu um texto em branco. Peça de novo — costuma resolver." |
| `COPILOT_ERRORS.NETWORK.BODY` | "Verifique sua internet e tente de novo" | "Não consegui falar com o servidor. Confira sua internet e tente de novo." |
| `AI_ASSISTANT_PANEL.LOADING` | "Gerando resposta..." | "Escrevendo…" |
| `AI_ASSISTANT_PANEL.PROMPTS.SUMMARIZE.DESCRIPTION` | "Vê os pontos principais" *(troca de pessoa no meio do bloco)* | "Entrego os pontos principais em poucas linhas" |
| `AI_ASSISTANT_PANEL.PROMPTS.SENTIMENT.DESCRIPTION` | "Analiso o tom do cliente" *(repete a própria label)* | "Digo se ele está calmo, com pressa ou irritado" |
| `AI_ASSISTANT_PANEL.EDGE_CASES.WHATSAPP_EXPIRED_*` | "WhatsApp desconectado / Algumas ações ficam indisponíveis até reconectar a sessão." *(descrevia a coisa errada — não é desconexão, é a janela de 24h)* | "Janela do WhatsApp fechada / Passaram-se 24h da última mensagem do cliente. Dá para rascunhar aqui, mas o envio só sai por modelo aprovado." |
| `AI_ASSISTANT_PANEL.SECTIONS.*` | `"ENTENDER A CONVERSA"` *(caixa alta no dado)* | "Entender a conversa" — o `uppercase` já é CSS (`AIAssistantPanel.vue:719`); caixa alta no JSON só atrapalhava leitor de tela |
| `AI_ASSISTANT_PANEL.ACTIONS.RETRY` | "Gerar outra" | "Refazer" *(termo do mockup)* |
| `AI_ASSISTANT_PANEL.ACTIONS.APPLY` | "Usar no composer" *("composer" não é palavra do agente)* | "Usar como resposta" *(termo do mockup)* |
| `AI_ASSISTANT_PANEL.TOAST.APPLIED` | "Resposta aplicada no composer" | "Resposta jogada no campo de mensagem" |

Nenhuma string diz "Desculpe, ocorreu um erro". Nenhuma culpa a conexão do agente quando o problema
é do provedor.

**Uma escolha que deixo registrada:** o mockup grafa o produto como **"Copiloto"**; o resto do app
(V1, botão do composer, `CONVERSATION.COPILOT.TITLE`) usa **"Copilot"**. Mantive "Copilot" para não
criar duas grafias na mesma tela. Padronizar é uma varredura à parte, e é decisão de produto —
não fiz por conta própria.

---

## 7. Estados de erro do contrato C1 (o que o A1 vai emitir)

Adicionei em `CONVERSATION.COPILOT_ERRORS`, nomeados **exatamente pelo `code` do evento SSE** em
UPPER_SNAKE, para o consumidor poder mapear sem tabela mental:

| `code` no evento SSE | Chave i18n | Estado |
|---|---|---|
| `unauthorized` | `COPILOT_ERRORS.UNAUTHORIZED` | **novo** |
| `rate_limited` | `COPILOT_ERRORS.RATE_LIMITED` | **novo** (canônico) |
| `timeout` | `COPILOT_ERRORS.TIMEOUT` | já existia, texto revisado |
| `provider_down` | `COPILOT_ERRORS.PROVIDER_DOWN` | **novo** |
| cancelado pelo usuário | `COPILOT_ERRORS.CANCELLED` | **novo** |

O texto de `unauthorized` é o do mockup, com o "o que fazer" acrescentado — e é o estado mais
provável de o agente encontrar:

> "Não consegui responder agora: o serviço de IA recusou a credencial. Isso não é problema da sua
> conexão — avise quem administra a conta."

**Para o A4:** `AIErrorBanner.vue` ainda mapeia os nomes antigos (`RATE_LIMIT`, `CAPTAIN_UNSTABLE`).
Mantive os dois conjuntos vivos para não quebrar o arquivo enquanto você mexe nele. Quando apontar o
`VARIANTS` para os nomes do contrato, `RATE_LIMIT` e `CAPTAIN_UNSTABLE` podem sair.

Também cobri o sub-namespace `AI_ASSISTANT_PANEL.ERRORS.*` que o A4 criou no painel reescrito
(`UNAUTHORIZED`, `GENERIC`, `RETRY`, `DISMISS`).

O spec tem um teste dedicado a isso: *"covers the error codes the streaming endpoint emits
(contract C1)"* — se o A1 emitir um code sem string, o banner ficaria mudo, e o teste pega.

---

## 8. A flag — como ligar para uma conta só

**Flag:** `ai_assistant_v2` · `config/features.yml:144` (`enabled: false`, `premium: false`,
`chatwoot_internal: false`) · constante `FEATURE_FLAGS.AI_ASSISTANT_V2` em
`app/javascript/dashboard/featureFlags.js:47`.

### O bitmask NÃO é problema aqui

O vault avisa que o bitmask está no limite. **Verificado, e não se aplica a esta flag:**

```
posicao no bitmask: 39 (bit 274877906944 = 2^38) | total features: 65 | teto signed bigint: 63
```

`ai_assistant_v2` é a **39ª de 65** — folgada dentro do bigint. O aviso do vault vale para features
**novas** (a 64ª estouraria). Ligar esta por conta é a via normal, não precisa de gambiarra.

### Como ligar numa conta só

```ruby
# na VM de homologação, RAILS_ENV padrão
bundle exec rails runner 'Account.find(3).enable_features!("ai_assistant_v2")'

# desligar (rollback)
bundle exec rails runner 'Account.find(3).disable_features!("ai_assistant_v2")'

# conferir
bundle exec rails runner 'puts Account.find(3).feature_enabled?("ai_assistant_v2")'
```

Isso escreve só na linha daquela conta. **Não mexe em `config/features.yml`** — mudar `enabled: true`
lá é o que ligaria globalmente, e não fiz.

### ⚠️ Estado atual do banco: a flag JÁ ESTÁ LIGADA em 3 contas

Li o banco (só leitura, não escrevi nada):

```
1    SimplexIA                 ai_assistant_v2=false
3    Simplex Tecnologia        ai_assistant_v2=TRUE
4    Colégio Alternativo       ai_assistant_v2=false
5    Realizare Imobiliária     ai_assistant_v2=false
6    Account 1                 ai_assistant_v2=TRUE
7    Account 1                 ai_assistant_v2=TRUE
```

O P2 §7.3 afirmava "nenhuma conta desta base tem a flag ligada" — **está desatualizado.**
A conta 3 (Simplex Tecnologia) já é a piloto de fato.

### Override por navegador (para testar sem tocar no banco)

`useAIAssistantFlag.js:46-59` resolve nesta ordem: `sessionStorage.chatspx_ai_panel_v2_session` →
`localStorage.chatspx_ai_panel_v2` → flag de servidor → OFF.

```js
// no console do navegador, e RECARREGUE a página
sessionStorage.setItem('chatspx_ai_panel_v2_session', 'on'); location.reload();
```

`?aiv2=1` na URL faz o mesmo, mas **só funciona com reload** — o override é aplicado no `mounted` do
`Dashboard.vue:68` e o computed não reage a `sessionStorage` em navegação SPA. Confirmado no P2.

### ⚠️ Segundo bug, que é decisão do coordenador (perguntei, aguardo)

`useAIAssistantFlag.spec.js` **falha no HEAD limpo** — conferi com `git diff HEAD`: nem o composable
nem o spec foram tocados por worker nenhum, a falha veio de fábrica.

```
FAIL  useAIAssistantFlag > returns false when server flag is disabled (kill-switch)
  expected true to be false
```

O teste declara que a flag de servidor **desligada** deve sobrepor os overrides de navegador.
A implementação faz o contrário: `sessionStorage`/`localStorage` ganham do servidor.

**O que isso custa na prática:** se você ligar na conta piloto e depois precisar de rollback,
desligar a flag **não tira o painel** de quem já testou — o `localStorage` continua lá. **Não existe
kill-switch de verdade hoje.**

O docblock (linhas 35-37) justifica o comportamento dizendo que o override de cliente é necessário
"porque o bit da flag estouraria a capacidade do bigint". **Essa justificativa não se sustenta** —
é a posição 39 de 63 (§ acima). A via de servidor funciona.

Não corrigi por conta própria: mexer na precedência do gate muda o comportamento de rollout e o
arquivo é consumido pelo A4. Mandei `ask` ao coordenador com as opções A (corrijo, kill-switch real)
/ B (só relato). **O `ask` expirou em 10 min sem resposta** (`ask timeout after 600000ms`,
thread `msg_634badcecb69`), então fiquei na opção conservadora: **não toquei no composable.**

O conserto, quando você decidir, é de ~6 linhas em `useAIAssistantFlag.js:45-60` — ler o servidor
primeiro e sair com `false` se ele estiver desligado, deixando os overrides de cliente atuarem só
dentro do que o servidor libera:

```js
const serverEnabled = Boolean(
  isFeatureEnabledonAccount.value(accountId, FEATURE_FLAGS.AI_ASSISTANT_V2)
);
if (!serverEnabled) return false;          // kill-switch: servidor sempre vence
const session = safeRead('sessionStorage', SESSION_KEY);
if (session) return session === 'on';
const local = safeRead('localStorage', LOCAL_KEY);
if (local) return local === 'on';
return true;
```

Isso deixa os 6 testes do arquivo verdes. **Custo:** perde-se o "ligar só pra mim numa conta onde o
servidor está OFF" — que hoje é como um QA testaria sem tocar no banco. Como a conta 3 já está com a
flag ligada no servidor, o piloto não depende disso.

---

## 9. Validação — o que provei e o que não deu

### ✅ JSON válido nos dois locales

```
$ python3 -m json.tool app/javascript/dashboard/i18n/locale/pt_BR/conversation.json > /dev/null
pt_BR: JSON VALIDO
$ python3 -m json.tool app/javascript/dashboard/i18n/locale/en/conversation.json  > /dev/null
en: JSON VALIDO
```

### ✅ Cruzamento mecânico 100% (§5)

### ✅ Spec novo — 12/12 verdes

```
✓ app/javascript/dashboard/i18n/specs/ai-assistant-panel-ptbr.spec.js (12 tests)
```

O que ele trava:
1. o regex acha as chaves no fonte (guarda contra o próprio teste apodrecer);
2. **toda** chave pedida resolve — pt_BR e en;
3. os namespaces **não** voltam para a raiz (é o bug original, agora com alarme);
4. pt_BR e en têm o mesmo conjunto de chaves;
5. nenhuma string em branco;
6. os 5 códigos de erro do contrato C1 têm TITLE e BODY nos dois idiomas;
7. pt-BR é tradução de verdade, não cópia do en.

### ✅ Prova de que não há chave crua na tela — via vue-i18n real

Este é o teste que substitui o screenshot, e é mais determinístico que ele: instancio o
**`createI18n` de verdade** com os **locales de verdade** (`dashboard/i18n/locale/pt_BR` e `/en`, os
mesmos objetos que `entrypoints/dashboard.js` carrega) e resolvo as 109 chaves.

vue-i18n devolve a própria chave quando não acha a tradução — então `t(key) === key` é exatamente o
texto que o agente veria renderizado. O teste exige que essa lista seja **vazia**:

```js
const raw = [...requested.keys()]
  .map(key => `CONVERSATION.${key}`)
  .filter(fullKey => t(fullKey) === fullKey);
expect(raw).toEqual([]);   // verde nos dois locales
```

### ✅ Suíte de i18n inteira, sem regressão

```
✓ captain-ptbr.spec.js (2)  ✓ reply-gate-ptbr.spec.js (3)  ✓ in-attendance-ptbr.spec.js (5)
✓ attendance-mode-ptbr.spec.js (4)  ✓ ai-assistant-panel-ptbr.spec.js (12)
Test Files  5 passed (5)   Tests  26 passed (26)
```

### ✅ ESLint limpo

```
$ npx eslint app/javascript/dashboard/i18n/specs/ai-assistant-panel-ptbr.spec.js
(sem saída)
```

Único `.js` que escrevi. Não toquei em nenhum `.vue`.

### ❌ Não abri o painel no navegador — e por que não

**Não consegui, e não tentei forçar.** Duas razões:

1. **O bundle servido está velho.** `public/vite/.vite/manifest.json` é de **14:02**; minhas
   mudanças são de **17:5x**. Mudança em JSON de i18n só chega na tela depois de rebuildar o Vite —
   e `assets:precompile`/build está **explicitamente proibido** para mim (briefing §5.3 e a própria
   task). O que eu veria no navegador agora seria o JSON antigo, ou seja, prova nenhuma.
2. **Buildar agora capturaria trabalho pela metade.** O A4 está reescrevendo `AIAssistantPanel.vue`
   neste momento (o arquivo passou de ~800 para 1.100+ linhas durante a minha execução). Um build
   fotografaria um estado intermediário dele.

Recebi o aviso de que a chave OpenAI voltou a ser válida — mas isso destrava a geração real, não o
build do front, que é o que falta aqui.

**O que fica para o coordenador fazer depois do `assets:precompile`:** abrir a conta 3 em light e
dark, `Ctrl+J`, e conferir que nenhum texto na tela casa com `CONVERSATION.` — o vault cobra
Playwright em light+dark antes de declarar fase pronta
(`feedback_playwright_obrigatorio_light_dark`). O teste do §"prova de que não há chave crua" cobre a
resolução das chaves; o que ele **não** cobre é layout, contraste e ícone.

---

## 10. Riscos e o que ficou de fora

| # | Risco / pendência | Gravidade |
|---|---|---|
| 1 | **Corrida com o A4.** Chaves pedidas subiram 85→109 durante a execução. Se ele adicionar mais, o número muda. Mitigado pelo spec, que varre o fonte na hora — **rode antes de commitar**. | média, mitigada |
| 2 | **Kill-switch da flag furado** (§8). Rollback não tira o painel de quem tem `localStorage` setado. Aguardando sua decisão. | **alta** — é operacional |
| 3 | **Validação visual não feita** (§9). Depende do seu build. | média |
| 4 | 25 chaves presentes e não usadas, 16 delas legadas da reescrita do A4. Limpeza, não bug. | baixa |
| 5 | Ligar a flag muda **dois** comportamentos, não um: além do painel, as ações inline do composer passam a renderizar chip de sugestão (`ReplyBox.vue:1917-1927`, P2 §7.3). Vale saber antes de ligar na piloto. | média |
| 6 | **Fora do meu escopo, achado de passagem:** `en/conversation.json` tem `CONVERSATION.WHATSAPP_WINDOW_EXPIRED.*` **escrito em português** (TITLE "Janela de 24 horas expirada"…). Não é do painel, não mexi. | baixa |

**O que eu não fiz, de propósito:** não commitei, não buildei, não liguei flag nenhuma, não editei
arquivo de outro worker, não fiz migration, não toquei em `Captain::Assistant` nem em nada dos
Agentes de IA, não abri SSH para VM alguma.
