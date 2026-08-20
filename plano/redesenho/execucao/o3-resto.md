# Onda 3 — trilha COMPLEMENTAR (blocos 4.04, 4.05, 4.07, 4.08, 4.11)

Worktree: `/home/chatwoot/chatwoot-o3-resto` · branch `o3-resto` · base `e0ae8e5759`
(`redesenho-integra`: Onda 0 inteira, quase toda a Onda 1, três trilhas da Onda 2).

Escrito conforme avanço. Cada bloco: o que a base tinha, o que fiz, o mecanismo que executa o
aceite, e o resultado REAL do mecanismo.

---

## 0. O terreno, medido antes da primeira linha

O worktree não existia; criei com `git worktree add -b o3-resto … redesenho-integra`, então a base
**é** a integrada — nenhum merge pendente.

| Dependência | Onde | Existe? |
|---|---|---|
| **3.02** — schema dos gatilhos | `app/models/concerns/widget_triggers_schema.rb` | ✅ |
| **3.20** — abordagem em três níveis | mesmo arquivo (`APPROACHES`, `MOBILE_APPROACHES`) | ✅ |
| **3.06** — rascunho, barra de salvar, guard | `inbox/widget/composables/` | ✅ |
| **3.03** — `WidgetProfile.resolve` | `app/services/widget_profile.rb` | ✅ |
| **3.10** — preview com tokens reais | `modules/widget-preview/` | ✅ |
| **4.03** — (para o 4.08) | trilha `o3-flows-captura` | ❌ em curso |

**Bloqueados, registrados e não tocados:** 4.05 (espera o 4.04, que é meu e vem primeiro), 4.07
(espera 3.10 ✅ + 4.04), **4.08 (espera 4.03, da trilha `o3-flows-captura`)**.

---

## 1. O contrato de `widget_triggers`, escrito antes do código

A cicatriz nº 4 do briefing pede isto explicitamente: *quando o seu bloco é uma ponta de contrato,
escreva o contrato no relatório — nome da chave, tipo, default, e o que acontece na ausência.*

Fonte: `app/models/concerns/widget_triggers_schema.rb` (3.02 + 3.20) e
`app/models/concerns/widget_config_resolvable.rb#resolved_widget_approach`.

| Chave | Tipo | Valores | Default **na ausência** | Quem resolve |
|---|---|---|---|---|
| `version` | integer ≥ 1 | — | ausente | — |
| `enabled` | boolean | — | ausente ⇒ o SDK não dispara nada | SDK |
| `approach` | string | `discreet` · `bold` · `aggressive` | **`bold`** | servidor (`resolved_widget_approach`) |
| `approach_mobile` | string | `discreet` · `bold` — **`aggressive` é 422** | **herda o desktop**; se o desktop for `aggressive`, cai para `bold` | servidor |
| `degrade_on_return` | boolean | — | **`true`** | servidor |
| `defaults.cooldown_seconds` | integer | 0 … 2.592.000 (30 d) | ausente | — |
| `defaults.max_per_session` | integer | 0 … 20 | ausente | — |
| `triggers[]` | array ≤ 20 | `{id, desktop, mobile, cooldown_seconds}` | ausente ⇒ lista vazia | — |
| `triggers[].id` | string | `time_on_page` · `scroll_depth` · `exit_intent` · `idle` · `element_click` · `element_visible` · `return_visit` | obrigatório | — |
| `triggers[].desktop/mobile` | object | `{enabled: bool, value: 0…86.400, selector: 1…200 ch}` | ausente | — |
| `audience.url` | object | `{operator: contains·not_contains·equals·starts_with·ends_with, values: ≤50 × ≤500 ch}` | ausente ⇒ toda página | SDK |
| `audience.utm` | object | mapa chave → lista (≤50 × ≤200 ch) | ausente ⇒ qualquer origem | SDK |
| `audience.device` | array ≤ 2 | `desktop` · `mobile` | ausente ⇒ os dois | SDK |

**`additionalProperties: false` no topo e em todos os níveis.** Consequência dura, e ela já mordeu:
qualquer chave a mais faz o **PATCH inteiro** voltar 422 — não é o campo que é ignorado, é a
gravação que falha.

### 1.1 Duas divergências que já estavam na base, e que este bloco corrige

O `DEFAULT_TRIGGERS` do front foi escrito na Onda 2 (bloco 3.06) **antes** de o schema existir. Com
o schema na mão, ele diverge em dois pontos:

| campo | front (na base) | schema/servidor | consequência |
|---|---|---|---|
| **`rules: []`** | existe | **não existe** | `additionalProperties: false` ⇒ **422 no PATCH inteiro**. A tela salvaria e o banco não mudaria |
| `approach_mobile` | `'discreet'` fixo | **herda o desktop** | admin escolhe "Chamativo" no computador e o celular fica "Discreto" sem ninguém pedir |

Isso é exatamente o defeito de **junção** da cicatriz nº 4: nenhum dos dois lados está errado
sozinho. O front foi escrito contra o contrato do plano, o backend contra o schema — e a soma não
grava.

---

## 2. Bloco 4.04 — a tela de gatilhos e a abordagem (T3.1–T3.6, T3.9 · D1)

Commit `227014b6a3`. Arquivos: `inbox/widget/triggers/` (5 componentes + specs),
`composables/widgetTriggersContract.js`, i18n nos dois idiomas, 5 sítios em `Settings.vue`,
`spec/e2e/triggers/` (harness próprio na porta **3062** — não toca 3038/3999/8899).

### 2.1 As duas divergências de contrato, corrigidas antes de qualquer tela

O teste que lê o Ruby nasceu **antes** dos componentes, e achou as duas na primeira execução:

```
× o rascunho da tela não carrega chave que o schema não conhece
  → expected { chave: 'rules', conhecidaPeloSchema: false }
                        to deeply equal { chave: 'rules', conhecidaPeloSchema: true }
```

`rules` era invenção do front (escrito na Onda 2, antes de o schema existir). Com
`additionalProperties: false`, ela não seria ignorada: derrubaria **o PATCH inteiro** com 422 — a
tela diria "salvo" e o banco não mudaria. E `approach_mobile: 'discreet'` fixo faria o celular
divergir do computador sem ninguém pedir, porque o servidor **herda o desktop**.

`DEFAULT_TRIGGERS` passou a ser `{ enabled: false, approach: 'bold', degrade_on_return: true,
triggers: [] }`. O `enabled: false` é deliberado: inbox que nunca abriu a tela não dispara nada, e
salvar outro campo não pode ligar convite proativo sem alguém pedir (regra A4).

### 2.2 Os aceites, e o mecanismo de cada um

| Aceite do bloco | Mecanismo | Resultado |
|---|---|---|
| Os três níveis com **Chamativo pré-selecionado** | vitest (o `checked`) **e** Chromium (o `outlineColor` do cartão ativo ≠ dos outros dois) | passa |
| **Agressivo** abre o aviso do 4.20 | vitest + Chromium (`dialog[open]` visível) | passa |
| e **não liga nada em celular** | o `PATCH` conferido: `approach_mobile: 'bold'` | passa |
| ligar só "tempo" mostra o aviso de gatilho composto | vitest + Chromium (visível **e** com contraste ≥ 4,5:1) | passa |
| seletor CSS inválido rejeitado **no blur** | vitest (não reclama ao digitar; reclama no blur) + Chromium | passa |
| a tela diz, em uma frase, o que a degradação faz | asserção no texto exibido | passa |
| `grep -rn "Google"` nas strings desta tela → vazio | teste que varre TRIGGERS e APPROACH nos dois idiomas por `google|seo|ranking` | passa |

**A força dos testes foi medida por sabotagem**, não afirmada:

```
gravar o Agressivo sem abrir o aviso        → 4 testes caem
herdar `aggressive` no celular              → 1 teste cai (o do PATCH)
validar o seletor a cada tecla, não no blur → 1 teste cai
                                              Tests  5 failed | 14 passed
```

E o aceite de política foi verificado no sentido contrário: acrescentei *"O Google penaliza isso em
celular desde 2017"* à descrição do nível Agressivo e o teste caiu, nomeando a string. Frase
removida; `grep -c Google` → 0.

### 2.3 O navegador reprovou o que o jsdom aprovou — outra vez

13 testes no Chromium, nos dois temas. Na primeira execução, **3 falharam**:

1. **O aviso do gatilho composto era ilegível no tema claro: 4,245:1** (o `Banner` do dashboard pinta
   o texto com o tom **11** da escala; contra o próprio fundo, no claro, isso reprova AA). O
   `axe-core` acusou o mesmo no aviso *slate* da segmentação. **Um aviso que ninguém lê não protege
   ninguém.** Corrigido com o tom **12** nos meus três avisos — sem tocar no componente
   compartilhado, que é de todas as telas.
2. **Meu próprio teste media o elemento errado**: pegava a cor do container do `Banner`, não a do nó
   que tem o texto. Corrigido para medir o nó com texto e o fundo do ancestral que pinta.
3. **`data-testid` duplicado**: o `Input` do dashboard repassa os atributos ao `<input>` **e** o
   fallthrough do Vue os coloca também na `div` raiz — dois nós com o mesmo id, e o Playwright
   reclama de ambiguidade. Resolvido com `input[data-testid=…]` no teste e um id próprio para o
   bloco.

Registro para as outras trilhas: **o `Banner` do dashboard, nos tons 11, reprova AA no tema claro.**
Toda tela que usa `Banner` para aviso tem o mesmo problema. Não é escopo deste bloco corrigir o
componente; está escalado.

### 2.4 i18n: consumir em vez de duplicar

A abordagem **não** ganhou namespace novo. As strings já existiam em `INBOX_WIDGET.APPROACH`,
declaradas pela trilha do backend junto do schema de 3.20 — **sem consumidor**. Esta tela passou a
ser o consumidor, e acrescentou só o que faltava (a frase da degradação, o aviso de desligada e a
linha do nível aplicado em celular). Um segundo namespace daria duas verdades para o mesmo nível, e
uma delas envelheceria calada.

### 2.5 Os sítios em `Settings.vue`

Cinco, declarados: o import, o registro, a aba nova (só para inbox de site), o `v-if` no template, e
o `onTabChange` — que passou a consultar **as duas** telas de rascunho (aparência e gatilhos) em vez
de só a primeira. Sem isso, sair da aba de gatilhos com pendência perderia tudo em silêncio.

---

## 3. Bloco 4.11 — o piscar do título e o som opt-in (W4.6)

Commit `5f06f19ee0`. Arquivos: `sdk/titleFlasher.js` (novo), `sdk/IFrameHelper.js`,
`widget/helpers/WidgetAudioNotificationHelper.js`, i18n do **widget** (`TITLE_FLASH_ALERT` em pt_BR
e en).

### 3.1 O que o bloco encontrou, e não era o que a descrição sugeria

O bloco diz "som **desligado** por default, opção por inbox". Medido no código: **o som toca por
padrão hoje**. O caminho é este, e ele não passa por configuração nenhuma:

```
widget/helpers/actionCable.js:74   playNewMessageNotificationInWidget()   ← toda msg de agente
  → sdk/IFrameHelper.js  events.playAudio  → window.playAudioAlert()
  → setupAudioListeners registra 4 eventos de interação e baixa o mp3
```

Ou seja: não é "ligar uma opção nova", é **inverter um default que está em produção**.

### 3.2 Onde a política foi colocada, e por quê

No **SDK**, que é quem toca — e não só no widget, que é quem pede. Se um dia alguém esquecer o guard
do lado do widget, o som continua desligado. Defesa em profundidade num caso em que o erro é audível
no site do cliente.

Consequência de bytes, e ela é a favor: **sem opt-in o mp3 nem é baixado** — não há listener nem
request. O visitante não paga bytes por um recurso que ninguém ligou.

**Piscar e som são independentes**: o piscar acontece mesmo com o som desligado, porque ele é o
aviso de quem está com a aba em segundo plano. Um teste garante exatamente isso.

### 3.3 O que o piscar protege

| Regra | Razão |
|---|---|
| 650 ms de intervalo, 60 s de duração | são os números do W4.6; um título que pisca a cada 2 s não chama atenção, e um que pisca para sempre faz a pessoa fechar a aba |
| só com a aba oculta | piscar com a pessoa olhando é ruído |
| para no `visibilitychange` | no instante em que ela volta |
| **não reentra** | mensagem nova durante o piscar guardaria "Nova mensagem" como título original — e a aba ficaria com o texto do alerta **para sempre** |
| sem texto de alerta, não pisca | título vazio na aba é pior que nada |

**Peso medido** (o `sdk.js` é o único arquivo que 100% dos visitantes de todos os clientes baixa —
arbitragem A13): `esbuild --minify | gzip -9` no arquivo novo → **350 bytes**.

### 3.4 O mecanismo

13 testes novos (7 do piscar com fake timers e um `document` falso; 6 do opt-in), dentro de **167**
que a suíte de `sdk/` + `widget/helpers/` roda verde.

Sabotagem, para medir a força:

```
piscar com a aba visível + permitir reentrada + tocar sem opt-in
  × NÃO pisca com a aba visível
  × NÃO reentra: segunda mensagem não cria um segundo ciclo
  × sem opt-in, o evento playAudio NÃO toca nada
  × o piscar é INDEPENDENTE do som
  Tests  4 failed | 9 passed
```

### 3.5 O que falta, e não é meu

Para a **opção aparecer na tela de configuração**, falta uma linha em `app/models/channel/web_widget.rb`:

```ruby
has_flags 1 => :attachments, …, 5 => :allow_mobile_webview,
          6 => :notification_sound,        # ← esta
          :column => 'feature_flags', :check_for_column => false
```

Não precisa de migration (a coluna é bitmask e já existe). **Não fiz**: `web_widget.rb` é backend e
não está na lista de arquivos deste bloco. O consumo já está pronto — o SDK lê
`enabledFeatures.includes('notification_sound')`, que hoje é sempre `false`, e **`false` é o
comportamento correto** enquanto a flag não existir. Escalado ao coordenador.

**Contrato, para quem for fechar a outra ponta:**

| chave | tipo | default na ausência | quem lê |
|---|---|---|---|
| `notification_sound` (em `enabledFeatures`) | booleano por presença na lista | **ausente ⇒ som desligado** | `sdk/IFrameHelper.js` |
| `title` (no evento `playAudio`) | string já traduzida | ausente ⇒ não pisca | `sdk/titleFlasher.js` |

---

## 4. Bloqueados — registrados, não tocados

| Bloco | Espera | Situação |
|---|---|---|
| **4.05** — vínculo teaser ↔ campanha | **4.04** | destravado agora que 4.04 fechou; é o próximo desta trilha |
| **4.07** — teaser no preview | 3.10 ✅ + **4.04** | idem |
| **4.08** — saída para WhatsApp no perfil marketing | **4.03**, da trilha `o3-flows-captura` | segue bloqueado; não toquei em `message-types/` nem em `ChatFooter.vue` |

---

## 5. Blocos 4.05 e 4.07 — o teaser: a mensagem e o preview

Commit `8aa34c79ec`. Eles estavam listados como bloqueados **por 4.04**, que era meu; com o 4.04
fechado, destravaram na mesma trilha.

### 5.1 4.05 — campanha é mensagem, gatilho é momento

A tela de gatilhos ganhou a seção da **mensagem**, e ela edita a **campanha de chat ao vivo que a
inbox já tem**. O único despacho possível é `campaigns/update`.

O aceite do bloco tem uma metade **negativa** — *"não nasce uma campanha por gatilho"* —, e é o tipo
de coisa que passa despercebida até o cliente ter dez campanhas iguais na lista. Por isso o teste é
sobre o **nome da ação despachada**:

```js
const acoes = dispatch.mock.calls.map(([acao]) => acao);
expect(acoes).toEqual(['campaigns/update']);
expect(acoes).not.toContain('campaigns/create');
```

**Onde mora o vínculo, e por que não é um campo novo:** o vínculo é a própria inbox — a campanha de
chat ao vivo dela. Um `campaign_id` dentro de `widget_triggers` seria recusado pelo schema
(`additionalProperties: false`, o mesmo que derrubaria o `PATCH` inteiro) e, pior, seria um segundo
apontador para o mesmo fato. Caixa sem campanha **não ganha uma criada em silêncio**: a tela diz
onde criar.

### 5.2 4.07 — o teaser no preview, com o gatilho simulado

`widget-preview/components/WidgetTeaser.vue` + um interruptor "simular o gatilho" na tela.

**Duas formas, um componente**: `discreet` é o `bold` com a foto e os chips escondidos. Dois
componentes dobrariam a chance de o que o cliente vê não ser o que o visitante recebe — e no SDK
(bloco 4.06) dobrariam bytes no arquivo que 100% dos visitantes baixa.

**Os chips são reais**: são os `home_intents` da inbox — as **mesmas** opções nomeadas que o
visitante vê na tela inicial, campo que já existe no schema da aparência. Não inventei um segundo
campo de chips: além de o schema recusar, seriam dois textos para a mesma escolha. Teto de **4**,
porque acima disso vira menu, não convite.

**Cor**: `bg-w-brand` / `text-w-on-brand`, os tokens que o servidor emite. Um teste falha se aparecer
cor literal no componente.

### 5.3 Duas armadilhas do terreno que os testes pegaram

1. **`data-testid` em dois nós.** O `Input` do dashboard repassa os atributos ao `<input>` **e** o
   fallthrough do Vue os coloca também na `div` raiz. `find('[data-testid=…]')` pega a `div`, e
   `setValue` numa `div` falha. Resolvido com `input[data-testid=…]` — no vitest e no Playwright.
2. **Mock preguiçoso de `useMapGetter`.** O spec do 4.04 devolvia `{ value: 'ltr' }` para qualquer
   chave; quando a página passou a ler as campanhas, `campanhas.value.find` explodiu e derrubou 6
   testes que não tinham nada a ver com o assunto. Mock que responde igual para tudo é mock que
   mente.

---

## 6. Bloco 4.08 — a saída para o WhatsApp (W3.6)

Commit `8184643c4a`. Estava bloqueado por **4.03**, da trilha `o3-flows-captura`; ele chegou na base
integrada (`ebf9b18768`), mergeei (`40c2b03368`) e o bloco destravou.

Arquivos: `widget/components/WhatsAppExit.vue` (novo), casca de `ChatFooter.vue`, i18n do widget.

### 6.1 As três regras, e a terceira não estava no texto do aceite

| Regra | Por quê |
|---|---|
| `primaryExit: 'none'` **esconde** | é o aceite escrito: suporte não empurra para outro canal quem já está num chamado |
| o link leva o **contexto** | é o aceite escrito |
| **sem número configurado, não renderiza** | **não está no aceite, e é o que mais machuca**: um botão que abre `wa.me/` sem destino leva o visitante para uma tela de erro do WhatsApp — pior que não ter botão |

**O que viaja no contexto, e o que não viaja.** Vai o nome do site e **a primeira coisa que o
visitante escreveu**. Não vai o que o agente disse, nem a segunda pergunta, nem identificador
interno: a URL fica visível na barra do WhatsApp dele e em qualquer proxy do caminho. Há teste sobre
o que **não** vai junto.

**Sabotagem:** renderizar sem número e mandar a conversa inteira derrubam 3 testes.

### 6.2 O contrato que falta, e ele não é meu

O payload de boot **não tem para onde mandar**: `primaryExit: 'whatsapp'` diz *que* há saída, não
*para onde*. Procurei nos dois montadores e no `WidgetProfile` — não existe número em lugar nenhum.

| chave | tipo | onde | default na ausência | quem lê |
|---|---|---|---|---|
| `whatsAppExitNumber` | string (só dígitos são usados) | `show.html.erb` **e** `configs/create.json.jbuilder` (a paridade 0.6 cobra os dois) | **ausente ⇒ a saída não aparece** | `widget/components/WhatsAppExit.vue` |

A ponta consumidora está pronta e degrada para o comportamento de hoje. **Não toquei nos montadores**
— é backend, não está na lista deste bloco, e acrescentar chave em só um dos dois quebraria a
paridade. Escalado.

---

## 7. Fecho da trilha

| Bloco | Commit | Estado |
|---|---|---|
| **4.04** | `227014b6a3` | ✅ 43 testes vitest + 13 no Chromium |
| **4.11** | `5f06f19ee0` | ✅ 13 testes novos (167 na suíte do SDK) |
| **4.05** | `8aa34c79ec` | ✅ |
| **4.07** | `8aa34c79ec` | ✅ 34 testes no preview |
| **4.08** | `8184643c4a` | ✅ 7 testes (69 na suíte do widget) |

**Os cinco blocos da trilha estão entregues.** Nenhum ficou bloqueado no fim: 4.05 e 4.07 esperavam o
4.04 (meu) e 4.08 esperava o 4.03, que chegou durante a execução.

### As três pontas de contrato que ficam abertas, com nome, tipo e default

Escritas aqui porque **o pior defeito desta execução foi de junção**, e a cicatriz nº 4 do briefing
pede exatamente isto:

| # | O que falta | Onde | Default na ausência (o que acontece hoje) |
|---|---|---|---|
| 1 | bit `6 => :notification_sound` no `has_flags` | `app/models/channel/web_widget.rb` | som **desligado** — e é o comportamento correto |
| 2 | `whatsAppExitNumber` no payload de boot | `show.html.erb` + `configs/create.json.jbuilder` | a saída para WhatsApp **não aparece** |
| 3 | o SDK consumir `widget_triggers` | `sdk/` (bloco **4.06**, outra trilha) | nenhum gatilho dispara; a tela grava e nada acontece ainda |

Nenhuma delas quebra alguma coisa hoje: as três degradam para o comportamento atual. E as três estão
com a ponta consumidora pronta.

### O que este relatório não pode dizer

Não rodei `rspec` nesta trilha — nada do que entreguei toca Ruby. Toda validação é `vitest` e
Playwright (config próprio na porta 3062; o harness de porta fixa continua sob a tranca do
coordenador e não foi usado).

---

## 8. Recado ao coordenador (o canal está revogado — vai por aqui, como manda o briefing)

Tentei mandar o `worker_done` desta trilha e o relay respondeu **"Dispatch ctx_db2d43dded1f
capability is revoked"**: a credencial que tenho é a da task da Onda 2, e o despacho desta trilha
chegou sem credencial nova. Não há como sinalizar conclusão pelo canal. Como o briefing diz que **a
entrega é o arquivo do relatório**, o que eu diria por mensagem está aqui.

**Estado:** cinco blocos entregues, quatro commits, working tree limpo em `8184643c4a`, branch
`o3-resto`. O worktree **não existia** — criei com `git worktree add -b o3-resto … redesenho-integra`
(e instalei `node_modules` e os hooks do husky, que também não vinham).

**Três coisas que valem para outras trilhas, não só para a minha:**

1. **O `Banner` do dashboard reprova AA no tema claro.** Ele pinta o texto com o tom 11 da escala;
   contra o próprio fundo isso dá **4,24:1** (medido no Chromium, e o `axe-core` confirmou no aviso
   *slate*). Toda tela que usa `Banner` para aviso tem o mesmo problema. Contornei nos meus três
   avisos com o tom 12; **não** mexi no componente, que é de todas as telas.
2. **`data-testid` no `Input` cai em dois nós.** O componente repassa os atributos ao `<input>` e o
   fallthrough do Vue os coloca também na `div` raiz. `find('[data-testid=…]')` pega a `div`, e
   `setValue` numa `div` falha — no vitest e no Playwright. Use `input[data-testid=…]`.
3. **As strings da abordagem já existiam sem consumidor.** `INBOX_WIDGET.APPROACH` foi declarado pela
   trilha do backend junto do schema de 3.20. Minha tela passou a consumi-lo em vez de criar um
   segundo namespace — se outra trilha precisar dos mesmos rótulos, eles estão lá.

**O que preciso que alguém decida ou faça** (as três pontas da §7, todas com a ponta consumidora
pronta e degradando para o comportamento de hoje):

| # | Ação | Quem |
|---|---|---|
| 1 | `6 => :notification_sound` no `has_flags` de `web_widget.rb` (uma linha, sem migration) | backend |
| 2 | `whatsAppExitNumber` nos **dois** montadores (a paridade 0.6 cobra os dois) | backend |
| 3 | o SDK consumir `widget_triggers` — é o **4.06**, que esperava o meu 4.04 e agora está livre | trilha do widget |

**Uma pergunta que não consegui fazer, e que respondi sozinho para não parar:** o layout da §B.3.4 do
plano 23 desenha campos que o schema de 3.02/3.20 **não comporta** — "dias de dispensa", "re-ping",
"não aparecer com banner de cookies", "abaixo de 768 px", "fora do horário comercial" e
"visitante novo/recorrente". Com `additionalProperties: false`, qualquer um deles derruba o `PATCH`
inteiro. **Construí só o que o schema aceita** e registrei aqui. Se esses campos forem para a v1, o
schema precisa crescer antes — e aí a tela acompanha em uma tarde.

---

# Parte II — blocos 5.06 e 5.15 (retomada de 19/08)

Base: `git merge redesenho-integra` (`8d3859bc6a`), que trouxe o bloco 5.03 — as tabelas
`tracking_events` / `tracking_deliveries` e o documento `docs/tracking/contrato-de-eventos.md`.

## 9. Bloco 5.06 — a Tela 4 (rastreio)

Commit `fcdf31dea6`. Arquivos: `inbox/widget/tracking/` (5 componentes + 4 specs),
`composables/widgetTrackingContract.js`, i18n nos dois idiomas, 5 sítios em `Settings.vue`,
`spec/e2e/tracking/` (harness próprio na porta **3063**).

### 9.1 O `SecretField` e as duas metades da regra

O briefing foi explícito, e tinha razão: *"nunca re-exibe" é metade da regra — a outra metade é
**salvar sem re-exibir não pode apagar**.*

O componente resolve por construção: **enquanto não houver valor novo digitado, ele não emite evento
nenhum**, e ausência de evento é o que significa "não mexa nisto". Cancelar não emite. Campo vazio
não pode ser confirmado (o botão fica desabilitado) — porque string vazia, chegando ao servidor,
significa "apague".

Sabotagem nos dois sentidos, e a primeira **reproduz o defeito real desta base**:

```
cancelar passa a emitir string vazia   → × "abrir a troca e CANCELAR não emite"
o campo abre já preenchido             → × "ao trocar, o campo abre VAZIO"
                                         Tests  2 failed | 7 passed
```

### 9.2 "Nenhum segredo em HTML, config, `index` ou log" — quatro superfícies, quatro mecanismos

| # | Superfície | Como é verificada | O que ela garante |
|---|---|---|---|
| 1 | `show.html.erb` | lê o arquivo e exige que **toda** interpolação de tracking use `public_widget_tracking` | publica a projeção por lista branca, nunca o hash cru |
| 2 | `configs/create.json.jbuilder` | idem | idem |
| 3 | `_inbox.json.jbuilder` | afirma que ele devolve `additional_attributes` **inteiro**, e que quem protege é `SECRET_KEY_PATTERN` no modelo | impede alguém "resolver" filtrando na view e achar que resolveu na origem |
| 4 | painel de diagnóstico | monta com `field_names` e confere o que é desenhado | mostra **nomes**, nunca valores — inclusive se o servidor mandar `{em: 'ana@…'}` no lugar de `'em'` |

**Sabotagem:** troquei `public_widget_tracking` por `widget_tracking` cru no jbuilder e o teste caiu
nomeando o arquivo.

Registro honesto: as superfícies 1–3 são **verificação estática** (o que os arquivos interpolam).
Não substituem um request spec Ruby — que é do lado do backend e não foi rodado nesta trilha.

### 9.3 Mais uma divergência de contrato, achada pelo teste que lê o Ruby

`DEFAULT_TRACKING` no front (escrito na Onda 2, antes de o backend existir) carregava `destinations`
e `events`. A projeção pública **descarta** as duas: seriam gravadas no banco e **nunca chegariam ao
widget** — a tela pareceria funcionar. Substituídas pelas seis chaves reais.

É a terceira vez que esse padrão aparece nesta execução (`rules` nos gatilhos, os defaults da
aparência, agora o tracking): **front escrito contra o plano, backend contra o schema, e a soma não
funciona**. O teste que lê o arquivo Ruby é o que fecha isso.

### 9.4 O que ficou de fora, nomeado na própria tela

| O que | Bloco | O que a tela faz enquanto isso |
|---|---|---|
| guardar token da Meta / API Secret do GA4 | **5.02** (espera as chaves de cifra do **0.10**) | o campo de segredo aparece **desabilitado**, com a razão nomeando o bloco |
| OAuth de um clique | **5.02** | idem |
| leitura do log de entregas | **5.14** | o painel diz que as entregas já são gravadas desde o 5.03 e que falta o endpoint |

O identificador **público** (Pixel ID, Measurement ID, `send_to`) já funciona e já vai para o site.

### 9.5 Navegador: 9/9, e a mesma dívida do `Banner` pela terceira vez

Os avisos desta tela nasceram com o tom 12 da escala — porque o bloco 4.04 já tinha medido que o tom
11 do `Banner` dá **4,24:1** no tema claro. O teste mede o contraste computado dos dois avisos
(interruptor geral e modo teste expirado) nos dois temas.

O `axe-core` acusou, no tema claro, as **abas do `TabBar`** e o `.text-n-blue-11` — os mesmos
componentes compartilhados que a Onda 2 já havia nomeado. Estão listados como exceção herdada, com
id e seletor, para que qualquer violação **nova** reprove. É a terceira tela onde essa dívida
aparece; segue escalada.

---

## 10. Bloco 5.15 — o guia de integração

Commit `ed34649e6b`. `docs/tracking/guia-de-integracao.md` (195 linhas) + o spec que o cobra.

**Não reescreve o contrato**: aponta para `contrato-de-eventos.md` sempre que precisa de nome de
evento ou de campo. O teste confirma que a tabela dos doze eventos aparece **uma vez só** no
repositório.

### 10.1 Como um aceite subjetivo virou mecanismo

O aceite é *"um integrador que nunca viu o produto instala, identifica um usuário e dispara um evento
**só com o documento**"*. Isso não é verificável por robô do jeito que um humano verificaria. O que é
verificável — e é a condição **necessária** — é que **tudo o que o guia manda digitar exista**:

| O que o teste cruza | Contra o quê |
|---|---|
| cada `window.$chatwoot.X(` citado | `entrypoints/sdk.js` |
| cada chave de `chatwootSettings` documentada | `OVERRIDABLE_BY_SITE` do schema da aparência |
| cada `chatspx_*` citado | `contrato-de-eventos.md` |
| o caminho de ponta a ponta que ele ensina | `TrackingEventListener` — o único evento que o servidor emite hoje |
| a promessa do link de contato alternativo | `web_widget.rb` (`showFallback`) |

**Sabotagem:** troquei `setCustomAttributes` por um `identifyLead` inventado e acrescentei
`autoOpenAfter` ao exemplo de `chatwootSettings` — 2 testes caíram, nomeando o método e a chave.

### 10.2 O que o guia diz que **não** existe

`window.chatwootSDK.track()` para evento próprio do site é o bloco **5.16**. O guia diz isso, em vez
de ensinar uma API imaginária — e o teste confirma que o SDK realmente **não** a tem, de modo que
quando o 5.16 entrar o próprio teste avisa que o guia precisa mudar.

O caminho de ponta a ponta que ele ensina é o que funciona hoje: instalar → conversar → **resolver a
conversa** → `chatspx_conversation_resolved` → conferir no `dataLayer` ou no Diagnóstico.
