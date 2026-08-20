# Onda 6 — IA no widget · relatório da trilha `o6-ia`

Worktree: `/home/chatwoot/chatwoot-o2-config-resto` · branch `o6-ia` · autor único.
Base mergeada no início: `redesenho-integra` (fast-forward para `16a361ce48`).

---

## 0. A primeira coisa, porque muda a leitura de tudo abaixo

**O trabalho da instância anterior não se perdeu.** O coordenador abriu esta execução
dizendo que a Onda 6 começava do zero, sem commit e com o worktree limpo. O worktree
estava limpo pelo motivo oposto: **os três blocos já estavam commitados** — e não só
commitados, **já mergeados em `redesenho-integra`**:

```
16a361ce48 Merge branch 'o6-ia' into redesenho-integra
6f4404dd20 feat(6.03): a fonte deixa de ser prosa no prompt e vira metadado da mensagem
80da008d1f Merge branch 'o6-ia' into redesenho-integra
fb0b378808 feat(6.02): o eval vira coisa do cliente, com custo a vista e regressao contada
3f18024b56 Merge branch 'o6-ia' into redesenho-integra
dc089f95a8 feat(6.01): o gate deixa de anotar depois e passa a reter antes
```

O que de fato faltava era **este arquivo**: a instância anterior morreu entre o último
commit e a escrita do relatório. A disciplina de "commite cedo e com frequência" fez
exatamente o que se esperava dela.

Então **não reescrevi a Onda 6**. Recomeçar teria jogado fora 1.482 linhas de código
mergeado e produzido um segundo caminho para o mesmo aceite. O que fiz foi o que faltava:

1. **verificar**, medindo, se o que está commitado cumpre os aceites da §2.2 — inclusive
   refazendo o **vermelho**, que estava *afirmado* nas mensagens de commit e não medido
   por mim;
2. **fechar a lacuna de aparência do 6.03**, que existia só em jsdom (cicatriz nº 1);
3. escrever o relatório, com os **contratos** que a Onda 6 expõe (cicatriz nº 6).

---

## 1. Estado dos blocos

| Bloco | Estado | Commit | Aceite verificado |
|---|---|---|---|
| **6.01** guardrail de pré-envio | entregue | `dc089f95a8` | 5 de 5 |
| **6.02** eval como produto | entregue | `fb0b378808` | 4 de 4 |
| **6.03** citação de fonte | entregue | `6f4404dd20` + `3df3856242` | 4 de 4 |
| **6.05** teste A/B de fluxo | entregue | `dbb34aab55` + `5a6e2df695` + `2c5aa6b023` + `587729a227` | 4 de 4 — **§11** |
| **4.22** coexistência com campanhas legadas | entregue | `28b6fc0a3d` + `7101970b77` + `80459eabc7` | 4 de 4 — relatório próprio em `o3-coexistencia.md` |

Depois do 6.05 há ainda **§12** (o achado sobre o 3.15, que o coordenador me roteou) e **§13**
(um incidente de harness que eu causei e preciso declarar).

### Números medidos nesta execução

| Suíte | Resultado |
|---|---|
| RSpec — os 12 arquivos da Onda 6 | **110 examples, 0 failures** |
| Vitest — os 4 arquivos da Onda 6 | **66 tests, 0 failures** |
| Playwright — aceite de aparência do 6.03 (novo) | **10 passed** |
| Vitest — suíte completa do projeto | 6.187 passaram, **4 falharam** — *nenhuma da Onda 6*, ver §5 |

Banco de teste dedicado: `chatwoot_test_o6_ia` (criado com `db:create db:schema:load`;
nenhuma migration rodou fora dele). `N > 0` conferido em toda execução — nenhum
"0 examples" passou por verde.

---

## 2. Bloco 6.01 — o gate retém antes, em vez de anotar depois

Os três asserts determinísticos que viviam dentro de `Captain::EpisodeGateService` (que
roda **depois** do episódio, para alimentar o eval) foram extraídos para
`Captain::GateAsserts` — funções puras sobre dado cru, sem ActiveRecord e sem I/O — e
ligados no caminho de envio por `Captain::ResponseGuardrailService`.

**Onde exatamente o gate entra:** `ResponseBuilderJob#create_messages`, **depois** do
dedup e da regeneração. É deliberado: o que se verifica é o texto **final**, o mesmo que
o visitante veria. Verificar o candidato anterior deixaria a resposta regenerada passar
sem gate.

### Aceites, um a um

| Aceite (§2.2) | Como está verificado |
|---|---|
| A resposta que **nega** o que a ferramenta devolveu não é enviada; é retida e vira handoff, com motivo registrado | `response_builder_job_guardrail_spec.rb:47` — asserta que o texto da negativa **não** está em `messages.outgoing` e que a mensagem de transferência **está** |
| O mesmo caso **hoje** é só anotado no eval depois, e o teste prova a diferença | a sabotagem abaixo restaura exatamente esse comportamento antigo e derruba 9 asserções |
| O guardrail **não** chama LLM | asserção sobre contagem de chamadas; `GateAsserts` é regex e comparação de string, sem I/O |
| Falha do guardrail **nunca** derruba o atendimento | `rescue StandardError` em `guardrail_retains?` devolve `false` (**libera**) e loga |
| A verificação roda em **dry run**, nunca contra IA de cliente | nenhum spec instancia LLM; `WebMock.disable_net_connect!` ativo |

### Vermelho medido (não afirmado)

Sabotagem: `RETAINING_CATEGORIES = [].freeze` — é literalmente "o gate volta a só anotar".

```
26 examples, 9 failures
  expect(conversation.messages.outgoing.pluck(:content)).not_to include(negativa)
  expect(conversation.messages.outgoing.pluck(:content)).to include(handoff_message)
  expect(log).to be_present
  expect(account.usage_limits[:captain][:responses][:consumed]).to eq(0)
  expect(result.retains?).to be(true)   (×3)
  expect(result.reason).to include('buscar_imovel')
```

### A assimetria de dano, e por que ela aparece duas vezes com sinais opostos

O princípio ratificado nesta onda está aplicado **duas vezes no mesmo bloco**, e é
importante que não seja lido como incoerência:

- **Reter → handoff, nunca silêncio.** Quando o gate segura a resposta, o visitante
  recebe a **saída humana** (mensagem de transferência + OOO quando fora do horário).
  Barato: um atendimento a mais na fila. Caro: o visitante numa conversa que não anda, ou
  com uma afirmação falsa carimbada com a marca do cliente.
- **Erro dentro do guardrail → libera.** Um bug no verificador não pode calar o
  atendimento de ninguém. Aqui o barato é deixar passar uma resposta que talvez fosse
  retida; o caro seria um `NoMethodError` meu emudecendo a IA de toda a frota.

O que decide o sinal em cada caso é **de quem é o fato**: quando o fato é do domínio (a
ferramenta trouxe resultado e a resposta nega), reter é barato; quando o fato é sobre o
meu próprio código ter quebrado, reter é caro.

**Uma família NÃO retém, de propósito:** `ignorou_erro_da_tool` só registra. A ferramenta
ter falhado não torna a resposta falsa — a IA pode ter respondido de outra fonte, ou nem
depender daquele dado. Reter aí trocaria ruído por handoff em massa.

---

## 3. Bloco 6.02 — o eval vira coisa do cliente

Tela nova (`EvalTab.vue`), API (`eval_cases` / `eval_runs`), três tabelas
(`captain_eval_cases`, `captain_eval_runs`, `captain_eval_case_results`) e os serviços de
execução, custo e comparação.

| Aceite (§2.2) | Como está verificado |
|---|---|
| O cliente roda o conjunto **antes** de publicar e vê **quantos casos regrediram** | `comparison_service_spec.rb` — a comparação devolve `regrediram` / `melhoraram` por caso; a tela exibe a contagem |
| Dois vereditos do mesmo caso em versões diferentes ficam **lado a lado** | mesma comparação, pareada por `eval_case_id`, com o `prompt_fingerprint` de cada execução |
| Nenhum caso é executado contra IA de produção **sem `dry_run`** | o outro modo **não foi construído**; `dry_run: false` levanta `ArgumentError` |
| O **custo é exibido antes** de rodar | `CostEstimatorService` é chamado no `onMounted`, junto de casos e histórico — o número aparece **sem disparar nada** |

**A escolha que sustenta o terceiro aceite** merece registro: a garantia não é uma flag
que alguém pode desligar, é a **ausência do outro caminho**.
`Captain::Eval::AssistantResponder` roda `AgentRunnerService#run_raw` com
`conversation: nil` — nenhuma conversa criada, nenhuma mensagem gravada, nada entregue a
visitante. A coluna `dry_run` continua existindo, e não é decoração: ela registra sob que
regime cada número histórico foi obtido, para o dia em que o modo ao vivo existir.

### Vermelho medido

Sabotagem: trocar o `raise ArgumentError` por um atributo inócuo.

```
12 examples, 1 failure
  ./spec/enterprise/services/captain/eval/run_service_spec.rb:18
  # o modo de execução refuses to run outside dry_run — o outro modo não existe
```

### IA de verdade não foi chamada — e como isso está garantido

**Modo: dublê.** Todos os specs injetam `responder:` fixo. `run_service_spec.rb:43`
carrega a asserção explícita `expect(Captain::Assistant::AgentRunnerService).not_to
receive(:new)` — não é só "não chamamos", é "o teste falha se alguém chamar".
`WebMock.disable_net_connect!` está ativo na suíte inteira. Nenhuma requisição saiu para
Meta, OpenAI, Google ou GlitchTip nesta execução.

---

## 4. Bloco 6.03 — a fonte vira metadado da mensagem

`search_knowledge_tool.rb` **continua** mandando `"(fonte: X)"` como prosa para o modelo
[M19] — o modelo usa aquilo para escrever. O que muda é que a **mesma** fonte também
viaja como dado (`Captain::CitationWindow`) e é gravada em
`content_attributes.citations`.

| Aceite (§2.2) | Como está verificado |
|---|---|
| Resposta baseada em documento mostra **de onde veio**, e clica para abrir quando é público | `CitationList.vue` + os 9 testes de `citationList.spec.js`; link só quando `url` é HTTP(S) |
| Resposta sem base **não inventa citação** | duas guardas (abaixo), com vermelho medido |
| A citação **sobrevive ao reload** | está em `content_attributes` no banco, não na renderização; serializada em `index.json.jbuilder:7` |
| O widget **não cresce em peso *eager*** | `CitationList` sai do próprio registry (`message-types/index.js`), viajando no chunk que a bolha já carrega — A13 |

### As duas guardas contra citação inventada

1. **Sem retrieval não há citação.** A lista só contém o que a ferramenta empurrou para a
   janela. **Nada lê a resposta do modelo procurando "fonte:"** — é exatamente ali que a
   invenção moraria.
2. **Resposta que NEGA ter encontrado não leva citação.** Exibir "Fonte: X" embaixo de
   "não encontrei" ensina o visitante a desconfiar da referência justamente quando ela
   está certa.

### Vermelho medido

Sabotagem: remover a guarda da negativa em `citations_for`.

```
7 examples, 1 failure
  ./spec/enterprise/jobs/captain/conversation/response_builder_job_citation_spec.rb:72
  # o que NÃO ganha citação — an answer that denies having found anything
```

---

## 5. O que eu acrescentei: o aceite de aparência sai do jsdom

Commit `3df3856242`. Esta é a lacuna que encontrei ao auditar, e ela é **exatamente a
cicatriz nº 1**: a aparência da citação estava *afirmada* por 15 testes em jsdom, não
verificada.

O risco não é teórico. `CitationList` desenha com `color: rgb(var(--slate-11))`. Com o
token indefinido, a função CSS inteira é inválida e o Chromium cai no **preto herdado** —
e o teste de unidade fica verde do mesmo jeito. É a mesma armadilha que o verificador do
4.09 já documenta no próprio cabeçalho.

**Como foi medido.** O componente **real**, na hierarquia **real** da conversa
(`conversation-wrap > agent-message-wrap > agent-message`), com o CSS **real** do widget,
num Chromium de verdade. O fundo não é escrito no teste: sobe-se pelos ancestrais até o
primeiro opaco — porque a citação é **irmã** da bolha, e quem pinta atrás dela é a
conversa, não a bolha.

```
MEDIDO NO CHROMIUM:
  [claro]  citação rgb(96, 100, 108)  sobre rgb(249, 249, 251) = 5,65:1
  [escuro] citação rgb(176, 180, 186) sobre rgb(23, 23, 26)    = 8,59:1
  [claro]  nome acessível = "Abrir o documento Política de trocas e devoluções"
  [escuro] nome acessível = "Abrir o documento Política de trocas e devoluções"
  [claro]/[escuro] transbordo em 375 px = 0 px
```

Os dois passam o **AA de texto pequeno (4,5:1)**, que é a régua certa: o rodapé é 11 px.

**O nome acessível vem da árvore do próprio Chromium, por CDP** — não de
`getByRole({ name })`. A diferença importa: aquele matcher calcula o nome com a
implementação do Playwright, e o que precisa ser provado é o que o **navegador** computou,
que é o que o leitor de tela lê. (`page.accessibility` foi removida na 1.59; CDP é o
caminho que restou.)

**Transbordo medido por `getBoundingClientRect`, nunca por `scrollWidth`** — cicatriz
nº 5: em elemento com `overflow: visible` o `scrollWidth` devolve a largura da caixa e o
teste jamais falharia.

**Porta:** Vite em `middlewareMode` na porta **efêmera** (porta 0), com config próprio.
Não encostei em 3038/3999/8899, então não pedi a tranca e não disputei slot com trilha
nenhuma. Nenhuma das **20 baselines** de `spec/e2e/widget/snapshots/` foi tocada ou
regravada — a Onda 6 não altera pixel de tela existente (a citação só aparece quando há
citação, e nenhum cenário de snapshot tem uma).

### Vermelho medido, uma sabotagem por vez

| Sabotagem | Caem | Evidência |
|---|---|---|
| limpeza do emoji removida | 2 | nome recebido: `"Abrir o documento 🔥 Política de trocas e devoluções"` |
| sublinhado do link removido | 2 | `textDecorationLine` = `none` — cor viraria o único sinal de clicável |
| link desenhado mesmo sem URL pública | 2 | |
| cor trocada para `--slate-8` | 2 | **1,82:1** no claro, **2,85:1** no escuro |

---

## 6. Os três eixos que atravessam a onda

### 6.1 `button-name` — todo controle novo de IA nasceu com nome acessível

Os onze nós com `button-name` nos tipos ricos **não são meus** e não foram tocados. O que
me cabia era não aumentar a dívida, e não aumentei: **todos os controles novos das duas
telas de IA carregam `aria-label`** — 6 na `EvalTab`, e os dois estados da citação no
widget.

**Uma dívida a rotear, porque ela é o mecanismo pelo qual esses onze nós continuam
nascendo:** `AiButton.vue` (o primitivo do lado do *dashboard*) declara apenas
`variant`, `type` e `disabled`. **Ele não cobra `aria-label` por prop**, ao contrário dos
primitivos do widget do 2.01. Na `EvalTab` isso foi resolvido na mão, controle por
controle — o que funciona hoje e não impede o próximo botão mudo. Sugiro um bloco próprio
para `AiButton` exigir nome acessível quando não há texto visível, como o 2.01 faz.

### 6.2 Emoji no rótulo — símbolo na tela, texto limpo no nome

A varredura das strings de i18n novas dos três commits não encontrou **nenhum** emoji.

Mas o caso que importava aqui não era o das nossas strings: **o título do documento vem
do cliente**, e cliente põe emoji em nome de documento. Por isso a limpeza em
`CitationList` é de **runtime** (`\p{Extended_Pictographic}`), aplicada a dado, e não uma
regra sobre prop. Medido no Chromium: com emoji na tela e sem emoji no nome acessível, nos
dois temas. Sem a limpeza, o leitor de tela anunciaria "Abrir o documento **fogo** Política
de trocas".

### 6.3 Falha aberta por assimetria de dano

Aplicada em quatro lugares desta onda, sempre com o modo de falha barato escrito ao lado:

| Onde | Em erro, o que acontece | Por quê |
|---|---|---|
| `guardrail_retains?` | **libera** a resposta e loga | bug meu não pode calar o atendimento de ninguém |
| `process_guardrail_handoff` | retém → **handoff** (nunca silêncio) | o visitante vê a saída humana; o caro é a conversa que não anda |
| `log_guardrail_retention` | a retenção **permanece** | a decisão já foi tomada com o fato na mão |
| `record_citation` | a busca **continua** sem citação | resposta sem citação é pior; resposta nenhuma é muito pior |

---

## 7. Contratos que esta onda expõe (cicatriz nº 6)

Os três blocos são ponta de contrato. Escrevo os três com nome de chave, tipo, default e
o que acontece na ausência.

### 7.1 `content_attributes.citations` — servidor → widget (6.03)

```jsonc
"citations": [
  {
    "title":   "Política de trocas",      // String, obrigatório. Sem título não há citação (a entrada é descartada).
    "url":     "https://.../politica",    // String|null. SÓ http(s). "PDF:"/"TEXT:" viram null.
    "excerpt": "Trocas em até 30 dias..."  // String, truncada em 180 chars.
  }
]
```

- **Tipo:** array de objetos. **Máximo 3** (`CitationWindow::MAX_CITATIONS`), deduplicado
  por `title` + `url`.
- **Default / ausência:** a chave **não é escrita** quando não há citação — não existe
  `citations: []` no banco. O widget lê
  `messageContentAttributes?.citations || []` e **não renderiza nada**. Mensagem antiga,
  de antes deste bloco, cai nesse mesmo caminho: rodapé ausente, nada quebra.
- **Quem escreve:** só `ResponseBuilderJob#create_outgoing_message`, a partir da janela do
  retrieval. **Nunca** a partir do texto do modelo.
- **Numa rajada do humanizer**, a citação vai na **última** bolha — é rodapé da resposta
  inteira, não de um pedaço dela.
- **Ambos os caminhos de entrega carregam a chave** — conferido, porque é onde um defeito
  de junção se esconderia: `index.json.jbuilder:7` (carga inicial e reload) e
  `Message#push_event_data`, que faz merge de `attributes` inteiro (tempo real). Os testes
  de unidade passam a prop direto e **não** cobririam essa ponta.

### 7.2 A janela de tool calls — tools → guardrail (6.01)

`Captain::ToolTraceWindow`, em memória, por thread (`Current.captain_tool_traces`).

- **Contrato de ciclo:** quem gera a resposta **abre** antes e **fecha** num `ensure`.
  Fora de uma janela aberta, `record` é **no-op** — nenhum caminho passa a acumular por
  acidente e nada sobrevive à thread (Puma reusa threads).
- **Forma do item:** `{ tool_name:, status: 'ok'|'error', result_preview:, error: }`.
- **Teto:** 50 chamadas.
- **Quem alimenta:** `Captain::Tools::TraceRecorder`, *prependado* via
  `BasePublicTool.inherited` — **23 tools** hoje. Diferente do trace persistido em
  `captain_tool_calls`, a janela **não depende de `eval_enabled`**: o guardrail vale para
  toda conta, inclusive a que nunca ligou eval.
- **Na ausência:** janela vazia → o guardrail não encontra contradição → **libera**. É o
  lado barato, de novo.

### 7.3 O formato do *finding* — gate → eval → painel (6.01)

`Captain::GateAsserts.finding` produz o hash gravado em
`captain_conversation_evals.response_findings` (jsonb) **e** no payload do
`Captain::AssistantLog` de `guardrail_retained`:

```jsonc
{ "origem": "gate", "quem": "ia", "categoria": "contradisse_tool|ignorou_erro_da_tool|repeticao",
  "severidade": "alta|media", "message_id": null, "trecho": "…120 chars", "porque": "…" }
```

**Mudar este hash muda dois consumidores.** `RETAINING_CATEGORIES` é o que separa reter de
só registrar — hoje `contradisse_tool` e `repeticao`.

---

## 8. Escalações — 4 falhas de vitest, nenhuma da Onda 6

A suíte completa fecha em **6.187 passaram / 4 falharam**. O enunciado desta execução
dizia que a base estava com vitest verde; **não está**. Nenhuma falha é de arquivo da
Onda 6, e as quatro são **defeitos de junção entre outras trilhas** — cada lado verde
sozinho, vermelho no encontro. É a cicatriz nº 6 acontecendo, e por isso escalo em vez de
tocar: consertar bloco alheio dentro da minha trilha é como o defeito de junção nasce.

**(a) `sdk/specs/mobileBreakpoint.spec.js` — 2 falhas.** O bloco **2.09** unificou o
breakpoint em 768 e criou o teste que proíbe 667/668. O bloco **4.06** (`c7a0c2641f`, o
teaser) **reintroduziu** `max-width: 667px`:

```
app/javascript/sdk/IFrameHelper.js:157   window.matchMedia('(max-width: 667px)')
app/javascript/sdk/sdk.js:407            @media only screen and (max-width: 667px)
```

Falha recebida: `expected [ 'IFrameHelper.js', 'sdk.js' ] to deeply equal []` e
`expected Set{ 667, 767 } to deeply equal Set{ 767 }`. **As duas faixas de CSS se
sobrepõem em pixel real** — não é só teste chateado.

**(b) `widgetTrackingContract.spec.js` e `tracking/specs/noSecretLeak.spec.js` — 2
falhas.** Ambas asseveram que `SECRET_KEY_PATTERN` mora em
`app/models/concerns/widget_configurable.rb`. A constante **mudou de casa** para
`app/models/concerns/widget_secret_scanner.rb`. **A garantia continua existindo** — é o
teste de contrato que aponta para o endereço antigo. Conserto provável: uma linha em cada
spec. Recebido: `expected '# O lar da configuracao do widget (bl…' to contain
'SECRET_KEY_PATTERN'`.

**(c) Dívida de acessibilidade, não falha:** `AiButton` não cobra `aria-label` por prop
(§6.1).

**(d) Observação de fora do meu escopo, achada ao medir o fundo:** a classe
`bg-n-chat-bg` de `Messages.vue:22` **não gera regra nenhuma** no CSS compilado do widget
(`chat-bg` não existe em `_tokens_values.scss` nem no tema do Tailwind). Na prática o
fundo claro da conversa vem do `bg-n-slate-2` do ancestral. Não é defeito visível hoje —
o fundo herdado é o esperado — mas é uma classe morta que dá falsa sensação de token
próprio. Não toquei.

---

## 9. Limites — o que NÃO está verificado

- **A `EvalTab` não foi medida em navegador real.** Os 8 testes dela são jsdom. Pela
  cicatriz nº 1, o aceite de **aparência** dela está *afirmado*, não verificado. Fechei
  essa lacuna para o widget (6.03), que é onde o visitante vê; a tela do painel continua
  aberta. Os `aria-label` dela estão conferidos por leitura de código, não por árvore de
  acessibilidade.
- **Nenhuma IA real foi chamada** — em nenhum momento, por nenhum caminho. Modo: **dublê**
  (`responder:` injetado) com `WebMock.disable_net_connect!`, mais a asserção explícita de
  que `AgentRunnerService` não é instanciado. Nada saiu para serviço externo.
- **Não rodei a suíte RSpec completa** — só os 12 arquivos da Onda 6 (110 examples). Uma
  regressão que a Onda 6 tenha causado fora desses arquivos não seria vista por mim.
- **Não rodei os 20 snapshots do widget**: eles vivem no harness de porta fixa, que é slot
  único sob tranca. Verifiquei por inspeção que nenhum dos commits da Onda 6 toca os PNGs
  nem qualquer cenário deles.
- Nada foi pushado, nenhum PR, nenhum deploy, nenhum restart. Nenhuma migration fora de
  `chatwoot_test_o6_ia`.

---

## 10. Como reproduzir

```bash
# banco dedicado
eval "$(grep -E '^POSTGRES_(HOST|USERNAME|PASSWORD|PORT)=' /home/chatwoot/chatwoot/.env | sed 's/^/export /')"
export RAILS_ENV=test POSTGRES_DATABASE=chatwoot_test_o6_ia
bundle exec rails db:create db:schema:load

# backend da Onda 6 — 110 examples, 0 failures
bundle exec rspec \
  spec/enterprise/lib/captain/gate_asserts_spec.rb \
  spec/enterprise/services/captain/response_guardrail_service_spec.rb \
  spec/enterprise/jobs/captain/conversation/response_builder_job_guardrail_spec.rb \
  spec/enterprise/lib/captain/eval/expectations_spec.rb \
  spec/enterprise/services/captain/eval/comparison_service_spec.rb \
  spec/enterprise/services/captain/eval/cost_estimator_service_spec.rb \
  spec/enterprise/services/captain/eval/run_service_spec.rb \
  spec/enterprise/controllers/api/v1/accounts/captain/eval_cases_controller_spec.rb \
  spec/enterprise/controllers/api/v1/accounts/captain/eval_runs_controller_spec.rb \
  spec/enterprise/lib/captain/citation_window_spec.rb \
  spec/enterprise/lib/captain/tools/search_knowledge_tool_spec.rb \
  spec/enterprise/jobs/captain/conversation/response_builder_job_citation_spec.rb

# front da Onda 6 — 66 tests, 0 failures
npx vitest run \
  app/javascript/dashboard/components-next/agents/tabs/specs/EvalTab.spec.js \
  app/javascript/widget/components/specs/AgentMessageBubble.spec.js \
  app/javascript/widget/message-types/specs/citationList.spec.js \
  app/javascript/widget/message-types/specs/index.spec.js

# aparência do 6.03 em Chromium real — 10 passed, porta efêmera, sem tranca
npx playwright test --config spec/e2e/widget/citacao/playwright.config.js
```

---

## 11. Bloco 6.05 — teste A/B de fluxo, versionado

Quatro commits: `dbb34aab55` (designação + eventos), `5a6e2df695` (relatório + API),
`2c5aa6b023` (aceite de ponta a ponta), `587729a227` (contrato de eventos).

| Aceite (§2.2) | Como está verificado |
|---|---|
| Duas variantes do mesmo fluxo **recebem tráfego** e o relatório mostra **conversão e abandono por etapa** nas duas | `ab_end_to_end_spec.rb` — 40 visitantes reais pelo motor, sem dublê no meio |
| O mesmo visitante vê **sempre a mesma variante** | designação determinística; medido em 20 resoluções seguidas e em 3 conversas distintas do mesmo navegador |
| Publicar uma variante nova **não invalida** o histórico da anterior | `variant_version` viaja em cada evento; linhas antigas continuam legíveis na versão sob a qual foram obtidas |
| O teste **declara quando a diferença ainda não é distinguível do acaso** | três saídas de veredito, com o motivo escrito; vermelho medido com "o maior número ganha" |

### 11.1 A chave de estabilidade — o que o coordenador pediu por escrito

**Qual é:** `contact_inbox.source_id`.
**Onde mora:** no navegador do visitante, escrito pelo widget; no servidor, na linha de
`contact_inboxes`. É o **mesmo** identificador que o 4.21 usa na `dedup_key` da abordagem e
que o 4.18 grava como `session_id` do lead incompleto — não inventei uma terceira noção de
"quem é este visitante".
**Por que não a conversa:** o id da conversa faria o mesmo visitante trocar de variante a cada
conversa nova, e o teste passaria a medir o acaso.

**O que acontece quando ela não existe:** `Flow::AbExperiment.assign` devolve `nil`, o resolver
segue com o vencedor normal do 4.02 e **nenhuma exposição é emitida** — o visitante fica fora
do experimento. A alternativa seria sortear, e aí o mesmo visitante veria variantes diferentes
a cada requisição. A assimetria de dano decide: o barato é perder uma linha do relatório que
esse visitante nem saberia que existia; o caro é ele entrar nos dois braços e contaminar os
dois lados do número que o cliente vai usar para decidir.

**Não é sorteio, por construção.** `assign` é função pura de (chave do experimento, chave do
visitante): SHA-256 sobre as duas, módulo a soma dos pesos. Sem `rand`, sem gravação, sem
estado. **SHA-256 e não o `hash` do Ruby** — o `hash` é semeado por processo
(`RUBY_HASH_SEED`), então dois workers designariam o mesmo visitante a variantes diferentes,
defeito que só apareceria em produção com mais de um Puma.

### 11.2 Sem migration, e onde a variante é declarada

Duas variantes são **dois flows** que declaram a mesma `experiment.key` em `trigger_config` —
o mesmo jsonb onde o 4.02 já publica o alvo do fluxo, com o mesmo contrato de defaults.
`flows.version` [M20] entra na propriedade do evento. `weight: 0` pausa uma variante **sem
apagar o histórico dela**.

**Fronteira com o 4.02:** o experimento só **redistribui** tráfego entre fluxos que o desempate
já considerava elegíveis — ele não promove ninguém. Quem não declara `experiment` (toda a
frota hoje) cai exatamente na regra de sempre e não emite evento nenhum. Há teste para as duas
metades: a variante que a URL excluiu não entra no sorteio, e um fluxo não-experimento com
prioridade maior continua ganhando de todo o experimento.

### 11.3 A trava herdada do 5.03 — e o teste que não conseguia falhar

Os três eventos passam `dedup_key` **explícita** sobre a chave natural do fato:
`flow_ab:<flow_id>:<conversation_id>:<sufixo>`.

**Encontrei um defeito no meu próprio teste antes de encontrá-lo no código.** A primeira versão
chamava `record` três vezes seguidas e afirmava "uma linha só" — mas a derivação padrão da
`dedup_key` usa `occurred_at.to_i`, então três chamadas no mesmo segundo colidem **sozinhas**.
O teste ficava verde com e sem a chave explícita: ele não conseguia falhar. O retry de um job
Sidekiq acontece segundos ou minutos depois, e é exatamente ali que a derivação para de
proteger. Com `travel` entre as chamadas, o teste passou a morder.

**Vermelho medido** removendo a chave explícita: 4 de 11 caem, nos **dois** sentidos que a §2.1
do contrato descreve — retry 30 s depois vira 2 conversões (conta demais) e duas etapas
genuínas no mesmo segundo viram 1 (conta de menos).

### 11.4 A honestidade estatística

Três saídas, nunca duas. `inconclusivo` não é o consolo de quem perdeu: é a resposta certa
enquanto o dado não sustenta outra.

| Motivo | Quando |
|---|---|
| `amostra_insuficiente` | menos de 30 exposições em qualquer braço |
| `aproximacao_nao_vale` | sucessos ou fracassos esperados < 5 (a normal não descreve a binomial) |
| `diferenca_dentro_do_acaso` | \|z\| < 1,96 |

Só depois dos três é que sai `melhor_que_o_controle` / `pior_que_o_controle`, com `z` e `p`
(bilateral por `Math.erf`). A comparação é sempre **contra o controle** (a variante de menor id,
a que já estava no ar) e nunca todas contra todas — comparação múltipla infla a chance de achar
diferença onde não há.

**Vermelho medido** com o defeito que o aceite proíbe, "o maior número ganha": 4 de 14 caem,
inclusive o caso de 12 visitantes por braço em que a variante converte 4× mais e ainda assim
não dá para saber.

### 11.5 O que o teste de ponta a ponta pegou e os de unidade não pegariam

Rodando os 40 visitantes de verdade, o funil mostrou que **o nó do `wait` entra no relatório
com `reached: 0` e o abandono creditado a ele**. Minha primeira asserção esperava que ele não
aparecesse — **o código estava certo e o teste errado**. Omitir aquela linha esconderia
exatamente a etapa onde o visitante desistiu, que é o que o aceite pede para ver.

Vermelho medido nas duas pontas da junção: o resolver voltar a ignorar o experimento derruba 3
(só uma variante recebe tráfego); a exposição deixar de ser emitida derruba 4 (denominador
vazio).

### 11.6 Contrato (cicatriz nº 6)

A família nova está registrada na **§2.2 do `docs/tracking/contrato-de-eventos.md`**, no molde
da §2.1 do 4.21: os três nomes, quando disparam, onde no código, os quatro parâmetros de
vocabulário fechado e a `dedup_key`. Emitir nome novo sem registrá-lo ali seria criar
vocabulário invisível para a próxima trilha.

**Nenhuma IA foi chamada** neste bloco — ele não toca IA. Nenhuma migration: a tabela de
`tracking_events` já existia (5.03) e a variante não precisa de coluna.

---

## 12. O achado sobre o 3.15 — a atribuição está errada, e a causa é o 2.06

O coordenador me roteou quatro baselines vermelhas de pré-chat, atribuídas ao meu bloco
**3.15**. **Reproduzi as quatro** e a atribuição **não se sustenta**. A causa é o bloco
**2.06**.

### 12.1 O que a imagem mostra

Nada foi acrescentado nem removido: os mesmos dois campos (Full Name, Email), a mesma caixa de
mensagem, o mesmo botão. **Tudo está deslocado verticalmente**, e o deslocamento começa no
cabeçalho.

Medido, procurando o deslocamento que minimiza a diferença:

| Cenário | Sem deslocamento | Melhor deslocamento | Resíduo |
|---|---|---|---|
| `prechat-form-light-desktop` | 13,84% | **−12 px** | 2,00% |
| `prechat-form-dark-desktop` | 24,58% | **−12 px** | 3,04% |
| `prechat-form-light-mobile` | 13,05% | **−24 px** | ~1,7% (corpo) |
| `prechat-form-dark-mobile` | 24,80% | **−24 px** | ~2,0% (corpo) |

Por região, no desktop: corpo do formulário **0,67%** de resíduo depois do deslocamento —
ou seja, **idêntico**. O resíduo alto (16,7%) fica **no cabeçalho**, que é o que mudou.

### 12.2 Por que não pode ser o 3.15

O fixture do harness (`spec/e2e/widget/harness/widget-server.mjs:98`) declara **dois campos,
sem `step`, sem `show_if`, sem `help_text`**. Para esse fixture o 3.15 é **no-op**:

- `stepOf` devolve **1** para campo sem `step` (`preChatFieldRules.js:107-111`), então
  `fieldsForStep(campos, 1)` devolve **os dois** — o `v-for` renderiza o mesmo de antes;
- `hasMultipleSteps` é **falso**, então o botão "Continuar" **não** aparece e o `v-else` cai no
  mesmo botão de enviar de sempre;
- `isLastStep` é **verdadeiro**, então a caixa de mensagem **continua** aparecendo;
- `help_text` ausente vira `undefined`, e `delegatedErrors` devolve `[]`.

E a assinatura visual do 3.15 seria **campo a mais/a menos ou botão novo** — nada disso está no
diff de imagem.

### 12.3 Onde a causa está

`404bcd7680 feat(2.06): o cabeçalho ganha título de verdade, alvo de toque e a cor que o
servidor calcula` trocou, em `ChatHeader.vue`:

```diff
- <header class="flex justify-between w-full p-5 bg-w-brand gap-2">
+ <header class="flex justify-between w-full min-h-14 px-4 py-2 bg-w-brand gap-2 items-center">
+   <button class="... min-w-11 min-h-11 md:min-w-10 md:min-h-10 ...">
```

`p-5` (20 px em cima e embaixo) virou piso de 56 px com `py-2`. O cabeçalho **encolheu**, e
tudo abaixo dele subiu. O alvo de toque de **44 px** (`min-w-11/min-h-11`) só vale abaixo do
breakpoint `md`, o que explica o deslocamento ser **maior no mobile (24 px) que no desktop
(12 px)** — dois números diferentes com uma causa só.

**É mudança intencional**: o 2.06 tem aceite próprio de geometria de cabeçalho e até um
verificador em navegador (`header-geometry.check.mjs`). O que faltou foi regravar as baselines.

### 12.4 Por que isso também explica o `home-*-mobile`

O coordenador tratou o `home-*-mobile` como "defeito separado, deslocamento de cabeçalho, já
roteado a outra trilha". **É o mesmo defeito**, com a mesma causa. O histórico das baselines
mostra o padrão:

- **8 baselines** (`home-*` ×4 e `prechat-form-*` ×4) **nunca foram regravadas** desde a captura
  original `f26db6ee81`;
- **12 baselines** (`messages`, `unread`, `rich-types`) foram regravadas pelo bloco **2.03**
  (`b8b8d3e07c`).

As que falham são exatamente as que ninguém regravou. **Ponto que não fechei:** no commit do
2.03 o `ChatHeader.vue` ainda era o antigo (`p-5`, sem `min-h-14`), então aquelas 12 também
foram gravadas com o cabeçalho velho — e mesmo assim passam. Não consegui resolver essa
pergunta porque não pude rodar a matriz completa (§13). **Não regravei nada**, e não recomendo
regravar as 4 isoladamente enquanto isso não fechar: seriam 4 por mim e 2 por outra trilha,
com duas explicações para uma causa só.

**Recomendação:** regravar as **6** (ou as 8 nunca regravadas) num commit só, atribuído ao
**2.06**, por quem tiver o slot — e só depois de entender por que as 12 do 2.03 passam.

---

## 13. Incidente do harness — declarado, porque foi meu

O coordenador me disse que as portas 3038/3999/8899 estavam livres. **Não estavam**, e eu não
conferi o dono antes de agir.

O que aconteceu, na ordem: rodei os 4 cenários de pré-chat e a corrida terminou. Depois vi as
portas 3038 e 3999 ocupadas, **presumi que fossem sobras da minha própria corrida** e matei os
dois processos. Eram da trilha **`o2-config-prechat`** — descobri isso só quando a corrida
seguinte falhou em 8899 e eu li o `cwd` dos processos em `/proc`:

```
pid 2255736  cwd=/home/chatwoot/chatwoot-o2-config-prechat  host-server.mjs (8899)
```

Aquela trilha estava, no mesmo momento, num laço `curl` esperando o `widget-server` da 3999
ficar pronto — **o servidor que eu tinha acabado de matar**. Não sei quanto trabalho isso
custou a ela; o warmup do widget-server é caro (medido em até 214 s em cache frio).

**Como evitar da próxima:** `readlink /proc/<pid>/cwd` responde de quem é o processo em um
comando, e eu deveria tê-lo rodado **antes** do `kill`, não depois. Ocupação de porta não
prova propriedade.

Encerrei tudo que era meu; o `host-server` da outra trilha continua no ar e **não encostei
nele**. O Puma da 3000 nunca foi tocado.

**Consequência para o §12:** só rodei os 4 cenários de pré-chat. A matriz completa dos 20 eu
**não** consegui rodar, então não sei o estado atual dos outros 16 por medição própria.

### 13.1 Segunda tentativa de pegar o slot — e o mesmo erro de informação, agora evitado

Depois que a reconciliação (`chatwoot-cb`) confirmou o diagnóstico do §12 e liberou o slot
dizendo *"confirmei agora: as três portas estão livres"*, conferi antes de encostar — e **não
estavam**. Medido às 23:01:57:

```
pid 3840759  3038  cwd=…/chatwoot-o2-config-prechat  início 22:58:37  cpu  10,0%
pid 3841304  3999  cwd=…/chatwoot-o2-config-prechat  início 22:58:38  cpu   114%
pid 3841685  8899  cwd=…/chatwoot-o2-config-prechat  início 22:58:38  cpu   0,1%
+ 3 processos irmãos da mesma trilha (22:58:34-35)
```

Não eram sobra: subiram três minutos antes, e o da 3999 estava a **114% de CPU** — o
widget-server aquecendo o grafo do Vite. Uma corrida daquela trilha estava começando.

**A mesma informação errada chegou pela segunda vez, e a única coisa que mudou foi eu
conferir o `cwd` antes em vez de depois.** Não subi servidor, não matei nada.

O mecanismo é o problema, não quem informou: "a porta está livre" e "a trilha X disse que
derrubou" têm janela de corrida grande demais para servir de tranca — as duas afirmações
podem estar certas no instante em que foram feitas e falsas um minuto depois. Sugeri à
reconciliação um arquivo de posse com **pid + worktree**, conferido contra processo vivo:
arquivo velho de dono morto é detectável; porta ocupada não diz de quem é.

### 13.1.1 A tranca nasceu com o defeito que ela existe para evitar

A reconciliação implementou a tranca sugerida (`/tmp/claude-1001/harness-slot`, com
`status` / `acquire` / `release`). Conferi antes de confiar, e ela **mente no cabeçalho**:

```
$ harness-slot status
TRANCA ORFA de o2-config-prechat (pid 3928319 morto ou cwd mudou) — pode sobrescrever
--- portas ---
  3038  pid 3840759  /home/chatwoot/chatwoot-o2-config-prechat
  3999  pid 3841304  /home/chatwoot/chatwoot-o2-config-prechat
  8899  pid 3841685  /home/chatwoot/chatwoot-o2-config-prechat
```

"Pode sobrescrever" com as três portas ocupadas e seis processos alheios vivos. Quem ler só
a primeira linha — a que parece a resposta — sobrescreve a tranca no meio da corrida alheia.

**Causa, em uma linha do script:** ele grava `"$$"`, o pid do **próprio** `harness-slot`, que
sai no instante seguinte. Toda tranca nasce órfã, então (a) `status` sempre diz "órfã, pode
sobrescrever" e (b) em `acquire` a guarda de propriedade é **código morto**.

O que salva a ferramenta hoje é a **segunda** guarda, a das portas — que me recusou
corretamente, com `exit 1`. Ou seja: a proteção real é justamente a checagem que a tranca
deveria superar.

**Conserto sugerido** (a peça já existe no script): a vivacidade tem de vir de quem **segura
a porta**, não do pid de quem chamou — trocar `vivo "$pid" "$wt"` por *"alguma das três
portas está com processo cujo `cwd` é `$wt`"*, usando o `donos_das_portas()` que já está lá.

Um erro meu de medição, no caminho: li o `exit` de um `head` no fim de um pipe e quase
reportei "exit 0" (que faria `acquire && rodar` prosseguir apesar da recusa). Medi de novo
sem o pipe: o `exit` real é **1**, e compõe corretamente.

### 13.1.2 A tranca corrigida, e o que ela ainda não resolve

A reconciliação corrigiu o defeito (a vivacidade passou a vir de quem segura a porta, via
`porta_do_worktree()`) e acrescentou uma **janela de partida de 300 s** — buraco que o meu
diagnóstico não cobria: entre o `acquire` e os servidores subirem não há porta tomada, e sem
a janela a tranca seria inútil justamente ali. Conferido contra varredura independente de
`/proc`: o cabeçalho agora bate com a lista de portas.

**O que a tranca não resolve, e é anterior a ela:** os servidores do harness servem **o
worktree de onde foram subidos** —
`widget-server.mjs:9-10` deriva `repositoryRoot` do caminho do próprio arquivo e o passa como
`root` do Vite (`:210`). Logo, quem sobe os três define o código sob teste para **todo mundo**
que apontar para `127.0.0.1:8899`, venha o spec de onde vier.

Isso torna a ideia de "emendar duas corridas de trilhas diferentes na mesma janela de
servidores" incorreta por padrão: a segunda trilha mediria a árvore da primeira. Levantei o
fato e recomendei serializar (≈4 min de warmup a mais) em vez de compartilhar — a decisão é
de quem conhece o que o outro bloco mede.

### 13.2 A corrida de leitura dos 20 — instrumento, critério e o que ela decide

> ## ⚠️ O CRITÉRIO DESTA MEDIÇÃO NÃO É O DA SUÍTE — leia antes de cruzar números
>
> Esta medição roda com **`maxDiffPixelRatio: 0`**. O critério oficial da suíte é **`0,01`**
> (`playwright.config.js`, `expect.toHaveScreenshot`).
>
> **O zero é deliberado e não é um gate mais rigoroso: é um instrumento.** Ele força as 20 a
> "reprovarem" por construção, e é isso que faz o Playwright escrever o `-actual.png` de
> **todas** — inclusive das que passam no critério oficial. Relatório de passa/falha joga
> fora exatamente a diferença de quem passa, que é onde está a resposta da pergunta.
>
> **Consequência para quem cruzar relatórios:** um snapshot com diferença minúscula
> **reprova aqui e passa no oficial, e os dois estão certos**. A medição do bloco 0.11 (trilha
> o1-widget) usa `0,01`; esta usa `0`. Divergência entre os dois números é esperada, não é
> defeito de nenhum dos dois, e não deve virar discussão sobre "qual está errado".
>
> Nada aqui escreve baseline: **não há `--update-snapshots` em comando nenhum**, o
> `outputDir` aponta para fora do repo, e o md5 das 20 é conferido antes e depois.

A reconciliação pediu a **diferença medida das 20, inclusive das que passam** — a hipótese é
que as seis que passam também estejam deslocadas, só que abaixo do limiar, e que por isso
seis baselines estejam **obsoletas e verdes**. Se for verdade, *"passa" deixa de significar
"correta"*, e elas viram referência errada para a próxima pessoa que mexer no cabeçalho.

O instrumental já está escrito (fora do repo, no scratchpad):

- um config próprio com `maxDiffPixelRatio: 0`, apontando para as **mesmas** baselines, que
  faz as 20 "reprovarem" por construção — é o que obriga o Playwright a escrever o
  `-actual.png` de **todas**. Mantém iguais ao config raiz o `snapshotPathTemplate`, o
  viewport, a locale, o fuso e os dois argumentos de fonte; mudar qualquer um mediria a
  minha configuração, não a diferença;
- um script que mede, por arquivo, **dois** números: a porcentagem de pixels diferentes e o
  **deslocamento vertical que a minimiza** (varredura de −60 a +60 px).

O segundo número é o que decide: se `home-desktop` e as `unread` mostrarem diferença
não-nula **e** o mínimo cair em −12 px no desktop e −24 px no mobile, é o mesmo deslocamento
de cabeçalho medido nas quatro do pré-chat, e o escopo da regravação vira **as 12 do 2.03**.
Se der zero, a hipótese morre.

**Ordem acertada com a reconciliação: serializado, não compartilhado** (§13.1.2). Eu adquiro,
subo do **meu** worktree, meço, derrubo, libero; só então a o1-widget adquire e sobe do dela.
Uso o config **com** `webServer` próprio; o config sem `webServer` fica guardado — a janela
compartilhada volta a valer no dia em que o `repositoryRoot` do harness vier de variável de
ambiente, e aí é uma linha.

Conferido por `require()`, não pelo comportamento: caso B tem 3 `webServer`, caso A não tem
nenhum, o `outputDir` está fora do repo e o `snapshotPathTemplate` aponta para as baselines
reais.

---

## 14. A medição das 20 — resultado

Slot adquirido (`harness-slot acquire o6-ia`, exit 0) depois de três verificações
independentes concordarem: `/proc` sem processo de harness, as três portas livres por
`/dev/tcp`, e a ferramenta dizendo LIVRE. Liberado ao fim. **As 20 saíram com o mesmo md5
com que entraram** — nenhuma baseline tocada, árvore do repo limpa.

> **Critério: ratio ZERO, não o 0,01 oficial** — ver o aviso na §13.2. Um snapshot com
> diferença minúscula reprova aqui e passa no gate oficial, e os dois estão certos.

| snapshot | dif@0px | dy ótimo | dif@dy | contraste baseline | contraste atual |
|---|---:|---:|---:|---:|---:|
| `home-dark-desktop` | 3,12% | **0** | 3,12% | **2,27:1** | **9,24:1** |
| `home-light-desktop` | 1,72% | **0** | 1,72% | **2,27:1** | **9,24:1** |
| `home-dark-mobile` | 4,65% | −20 | 3,69% | *ver ressalva* | |
| `home-light-mobile` | 4,65% | −20 | 4,22% | *ver ressalva* | |
| `prechat-form-dark-desktop` | 23,93% | **+12** | 4,54% | | |
| `prechat-form-light-desktop` | 13,84% | **+12** | 2,00% | | |
| `prechat-form-dark-mobile` | 24,80% | **+24** | 3,13% | | |
| `prechat-form-light-mobile` | 13,05% | **+24** | 3,04% | | |
| `rich-types-light-mobile` | 2,49% | 0 | 2,49% | | |
| `messages-*` (4), `rich-types-*` (3), `unread-*` (4) | 0,00% | 0 | 0,00% | idênticas | |

### 14.1 Duas famílias de obsolescência, e um eixo só pega metade

**Geométrica** — as 4 do pré-chat: deslocamento real de +12 px (desktop) e +24 px (mobile),
com o corpo do formulário idêntico depois dele. Causa: o 2.06 (§12).

**Cromática** — as 2 de `home-*-desktop`: **deslocamento ótimo zero** e ainda assim
diferentes. A baseline documenta o título em **branco sobre a marca (2,27:1**, que reprova o
AA de 3:1 até para texto grande); o render atual usa **preto (9,24:1)**. São as únicas
*obsoletas e verdes* do conjunto — passam no gate oficial documentando um estado errado.

**Se eu tivesse medido só geometria, teria passado direto por elas:** "deslocamento 0" leria
como "baseline correta".

### 14.2 A verificação que derrubou metade da minha primeira leitura

Ia reportar que **as quatro** de `home` documentam tinta branca. Testei antes: se é a mesma
massa de glifo repintada, as contagens de pixel têm de bater.

```
home-light-desktop  baseline 973 brancos / 0 pretos    ->  atual 90 brancos / 999 pretos
home-dark-desktop   baseline 883 brancos / 100 pretos  ->  atual  0 brancos / 1036 pretos
home-light-mobile   baseline 437 brancos               ->  atual  0 brancos / apenas 28 pretos
```

Desktop bate — é repintura. Mobile **não** bate (437 contra 28): ali é outro elemento, não
troca de cor. A afirmação cromática vale para as **duas** de desktop e não vale para as de
mobile.

### 14.3 O `dy` ótimo não pode ser lido sozinho

O que prova deslocamento é o **tamanho da queda**, não o argmin — que sempre devolve algum
número:

```
prechat desktop  13,84% -> 2,00% com +12   queda de 85%   deslocamento REAL
prechat mobile   24,80% -> 3,13% com +24   queda de 87%   deslocamento REAL
home mobile       4,65% -> 3,69% com -20   queda de 21%   NAO e deslocamento, e ruido
```

### 14.4 Duas divergências com o inventário, declaradas e não resolvidas

`home-*-mobile` (4,65%) e `rich-types-light-mobile` (2,49%) constam do inventário como
**corretas**, e as duas passam de 1% — reprovariam também no critério **oficial**, então não
é efeito do ratio zero.

Hipótese, e é só hipótese: esta árvore está em `80459eabc7` com merges recentes da integra, e
pode estar **à frente** daquela em que essas baselines foram gravadas. Se for isso, elas não
estão erradas — estão atrasadas em relação à HEAD. Quem tem a linhagem é quem decide.

### 14.5 `rich-types-light-mobile` — caracterizado: deslocamento **subpixel**

Único achado que não pertence a nenhuma das duas famílias. A reconciliação verificou que a
baseline é idêntica nas duas árvores e que nenhum dos 5 commits entre a gravação e a medição
toca componente de renderização. Caracterizei pelo `-actual.png`, sem slot:

| evidência | `rich-types-light-mobile` | `prechat-form-light-desktop` (deslocamento real, p/ comparar) |
|---|---|---|
| onde | espalhado, y 0→1200, x 40→320 | concentrado, blocos |
| magnitude > 150 | **0,0%** | **53,2%** |
| par dominante | (253,253,253)→(208,228,217) | (45,196,111)↔(249,249,251) |
| sobre borda / chapado | 50,8% / 49,2% | 12,1% / 87,9% |

**Uma leitura visual minha estava errada e a medição a derrubou.** No recorte ampliado "vi"
o botão e o card mais arredondados, e quase reportei mudança de `border-radius`. Medi o
perfil do canto linha a linha — onde começa o verde em cada `y` do topo do botão — e as duas
imagens dão a **mesma** sequência (72, 71, 70, 70, 70, 69, 69, …). Era artefato do zoom
`NEAREST`.

O que muda de fato, na linha mais divergente (y=955, borda superior do card de CSAT):

```
x=54     baseline (57,143,95)     -> atual (88,156,118)
x=55     baseline (29,130,74)     -> atual (54,144,94)
x=60..65 baseline (253,253,253)   -> atual (208,228,217)   [constante, área chapada]
```

E o fecho, contando as cores verde-escuras dominantes:

```
rich-types-light-mobile  BASELINE  (29,130,74) x530
rich-types-light-mobile  ATUAL     (63,149,101) x261
rich-types-light-desktop BASELINE  (29,130,74) x546   (e o desktop e byte-identico hoje)
```

A borda de 1 px que na baseline atinge o verde **sólido** no atual nunca chega nele — fica
num verde intermediário e "engorda" para o branco vizinho.

**Inferência sustentada (não fato provado): um deslocamento vertical FRACIONÁRIO no layout a
390 px.** Explica as quatro observações de uma vez — todo traço de 1 px re-mistura (área
chapada muda de cor), todo glifo re-serrilha (borda muda), nenhuma magnitude fica grande
(nada troca de lugar) e o `dy` inteiro ótimo é 0 (o deslocamento é menor que 1 px).

**Consequência para a decisão:** ao contrário das duas de `home-*-desktop` — onde a baseline
documenta um estado que **reprova AA**, e regravar corrige um erro — aqui a baseline não
documenta conteúdo errado, e regravar persegue o sintoma. Se a origem é um valor fracionário
de layout, qualquer mexida próxima desloca de novo e a baseline volta a reprovar **atribuída
ao commit errado**. Recomendei registrar como achado aberto em vez de regravar.

---

## 15. Três armadilhas nomeadas da perícia de baseline

Saíram desta execução, e as três produziram — ou quase produziram — um número errado com
cara de certo. Ficam aqui como regra, não como observação.

### 15.1 Recorte ampliado com `NEAREST` não serve para julgar geometria

O zoom `NEAREST` cria bordas duras que o olho lê como raio, sombra ou espessura. Olhando o
recorte 2× eu "vi" o botão e o card **mais arredondados** no render atual e quase reportei
mudança de `border-radius`.

**Medir o perfil desmentiu:** onde começa o verde em cada `y` do topo do botão, linha a
linha, dá a **mesma** sequência nas duas imagens — 72, 71, 70, 70, 70, 69, 69, … Raio
idêntico.

> **Regra:** imagem ampliada serve para *localizar* o que investigar, nunca para *concluir*
> sobre geometria. A conclusão vem do perfil medido.

### 15.2 O `argmin` do deslocamento sempre devolve um número

Varrer `dy` e pegar o mínimo **sempre** retorna algum valor, haja deslocamento ou não. O que
prova deslocamento é o **tamanho da queda**:

```
prechat desktop  13,84% -> 2,00% com +12   queda de 85%   deslocamento REAL
prechat mobile   24,80% -> 3,13% com +24   queda de 87%   deslocamento REAL
home mobile       4,65% -> 3,69% com -20   queda de 21%   ruido com argmin bonito
```

> **Regra:** reportar `dy` sem a queda ao lado inventa deslocamento que não existe. Foi o que
> quase me fez descrever um deslocamento de −20 px em `home-*-mobile`.

### 15.3 "Passa" não significa "correta", e um eixo só pega metade

Duas famílias de obsolescência, e medir só geometria enxerga uma:

| | sinal | exemplo |
|---|---|---|
| geométrica | `dy` ótimo ≠ 0 com queda grande | as 4 do pré-chat (+12 / +24) |
| cromática | `dy` ótimo **= 0** e mesmo assim difere | `home-*-desktop` (2,27:1 → 9,24:1) |

As duas de `home-*-desktop` **passam** no gate oficial documentando um título que reprova o
AA. Lidas só pela geometria, "deslocamento 0" leria como "baseline correta".

> **Regra:** ao periciar baseline, meça geometria **e** cor. E o par (baseline, render) tem
> de ser confirmado como o mesmo elemento — a contagem de pixels da tinta é o que separa
> *"a cor mudou"* de *"é outro elemento"* (973 brancos → 999 pretos é repintura;
> 437 brancos → 28 pretos não é).
