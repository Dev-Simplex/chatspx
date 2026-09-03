# Onda 0 — Terreno · RELATÓRIO FINAL

> **A onda fechou em 17/08/2026.** Este arquivo é o relatório da onda, por convenção do briefing
> (§8.1 do `PROMPT-ORQUESTRADOR.md`). Ele substitui o índice provisório que morou aqui durante a
> execução e o texto do orquestrador anterior, preservado inteiro e sem correção em
> [`onda-0-relatorio-codex-13ago.md`](onda-0-relatorio-codex-13ago.md).
>
> **Branch entregue:** `redesenho-base` = `5fd08050fc`. Commit local apenas — **nenhum push,
> nenhum PR, nenhum deploy**. Quem decide o que sobe é o dono do produto.


**Coordenador:** Claude Opus 5 · Run Orca `run_d71297edb110` · 17/08/2026
**Antecessor:** Codex, Run `run_26dd5a774ba8` — relatório `onda-0.md` de 13/08, **desatualizado**
(ver `onda-0-reconciliacao.md`)
**Escopo:** Tozi · HML/SaaS · VM local `192.168.8.232` · conta 3
**Executores:** 13 terminais Claude (`opus`, esforço `xhigh`), um worktree por frente

> Este relatório é o índice da onda. Cada afirmação aqui tem um artefato que a sustenta, e o
> artefato traz a saída real do comando — não a paráfrase dela.
>
> **Procedência:** o texto consolida os artefatos das frentes; os números foram **conferidos pelo
> coordenador contra os relatórios de origem** antes de entrarem aqui. Uma divergência foi
> encontrada e corrigida nessa conferência (a contagem de DADO — ver a nota em §2.3). Onde este
> índice e um relatório de frente divergirem, **o relatório de frente é a fonte**, e a divergência
> vira nota aqui em vez de sumir.

---

## 0. Fecho da onda — a integração

Todas as frentes fecharam e foram integradas em `redesenho-merge`:

```
5fd08050fc  chore(0.5): gate de peso mede o grafo e nasce vermelho no teto de 300 kB
c142b022ca  merge(0.7-0.9): limpezas e coerencia do dashboard
721ef835ae  merge(0.2): correcoes da auditoria do merge v4.16.2
   3dccaebb3f  fix(0.2 item 26): editar integracao para de apagar a credencial
   5525a161ab  fix(0.2 item 23): excluir conversa volta a excluir
   ... + 6 commits de correção por grupo
8684f07304  build(0.3): reconcilia o vite do upstream e devolve o caminho de teste
6ad7a9ec6e  fix(e2e): aquece o Vite antes do /__ready e encerra o harness
93571c69db  merge v4.16.2  ← o merge recuperado do disco
```

**Uma decisão de integração que evitou sujeira na história:** o `redesenho-build` continha o
commit do bloco 0.3, que **já estava** no merge como cherry-pick. Mesclar a branch inteira
reaplicaria o mesmo trabalho. A integração pega de lá **só o que vem depois do 0.3** — e o script
recusa rodar se sobrar qualquer commit `WIP(` em qualquer frente.

Conferências após integrar: colisão de timestamp **0**, marcador de conflito **0**, worktree
limpa, e o `playwright.strict.config.js` (instrumento de medição descartável) removido.

### A régua rodou de novo, sobre a branch integrada — e passou

Não basta cada frente ter fechado verde isolada; o que vai para revisão é a **soma delas**.

```
pnpm exec vitest --no-watch --no-cache
  Test Files  471 passed (471)
       Tests  4619 passed (4619)          exit 0
  (eram 4586 antes das correções — os 33 novos são os testes que as próprias correções trouxeram)

pnpm exec playwright test --project=widget
  20 passed (5.2m)                        exit 0
  os 16 snapshots continuam batendo contra o baseline pré-merge, na branch com TUDO dentro
```

Isto fecha a pergunta que importa: **as correções não quebraram o widget**, e o baseline do
bloco 0.1 continua sendo régua válida depois de 8 commits de correção, 3 blocos de limpeza e a
reconciliação do build.

### O gate do 0.5 nasceu verde — e isso era o defeito

O WIP em disco tinha o gate **passando**, porque alguém havia colocado o número medido
(`widgetGraphGzip: 422_599`) **como teto**. Isso é exatamente a negociação de aceite numérico que
a §4 do plano proíbe: o gate mediria o grafo e continuaria dizendo verde. O executor devolveu o
teto para **300.000 B**, o gate passou a falhar (exit 1), e a mensagem de falha carrega a **linha
de base do dia** (422.599 B, 17/08/2026) separando **dívida conhecida** de **regressão nova** —
sem isso, um CI permanentemente vermelho vira cego e ninguém percebe quando piorar de 41% p/ 60%.

---

## 1. Resultado por bloco

| Bloco | Estado | Onde está a prova |
|---|---|---|
| **0.1** harness + 16 baselines | ✅ **VALIDADO** — 8/8 aceites | `onda-0-validacao-baseline.md` |
| **0.11** fixture anti-erro | ✅ **VALIDADO** — sem precisar de correção | idem |
| **0.2** merge da v4.16.2 | ✅ **FECHADO** — 16 snapshots 20/20; 8 commits de correção, **26 itens aplicados**, os dois P0 finais inclusive | `onda-0-dod-merge.md` + 6 auditorias |
| **0.3** reconciliar o build | ✅ **PASS — 5/5 aceites com mecanismo executado** · commit `301bbdfdf9`, integrado como `8684f07304` | `onda-0-bloco-0.3.md` |
| **0.4** compressão | ✅ **PASS local 4/4** (era 0/4 em 13/08) | `onda-0-infra-0.4-0.10.md` |
| **0.5** gate de peso | ✅ **FECHADO** — commit `5fd08050fc`. O gate passa a medir o **grafo** e **nasce vermelho** no teto de 300 kB (+122.599 B, **+40,87%**), de propósito | `onda-0-bloco-0.5.md` |
| **0.6** paridade dos montadores | ✅ **PASS** (herdado, commit `1a45399b2a`) | `onda-0-relatorio-codex-13ago.md` |
| **0.7 / 0.8 / 0.9** limpezas e coerência | ✅ **FECHADOS** — 3 commits locais em `redesenho-config` (`a6f20de5eb`, `3a07565337`, `c172432f34`), com vermelho-antes provado e as proibições verificadas uma a uma | `onda-0-blocos-0.7-0.8-0.9.md` |
| **0.10** Active Record Encryption | ✅ **PASS local** nos 3 itens | `onda-0-infra-0.4-0.10.md` |

> A topologia dos cinco worktrees e a ordem de integração estão em `onda-0-topologia.md`.

### 1.1 A inversão de dependência 0.2 ↔ 0.3, e um erro do coordenador registrado

**O 0.3 virou pré-requisito do 0.2, contra o que a coluna *Depende* da §2.2 diz.** A inversão está
medida, não suposta (`onda-0-dod-merge.md` §9, run 2):

`sdk-server.mjs` e `widget-server.mjs` sobem um Vite em `middlewareMode` com
`configFile: vite.config.ts` depois de setar `TEST=true`. O `vite.config.ts` **pré-merge** lia essa
variável e, em modo teste, montava os plugins **sem** `vite-plugin-ruby` — o `root` continuava
sendo a raiz do repositório. O `vite.config.ts` **pós-merge** (o do upstream) não tem esse branch:
`ruby()` entra sempre, lê `config/vite.json` e reescreve o `root` para `app/javascript`. Efeito
exato, medido com `curl` contra o servidor do próprio executor:

| URL | pré-merge | pós-merge |
|---|---|---|
| `/app/javascript/entrypoints/sdk.js` — a que o harness pede, hardcoded em `host-server.mjs:72` | **200** | **404** |
| `/entrypoints/sdk.js` | — | 200 (o `root` foi reescrito) |

Consequência: o widget nunca carrega e **nenhum dos 16 snapshots chega a ser comparado** —
`find test-results -name '*-actual.png' -o -name '*-diff.png'` → **0 imagens**, nos dois runs.
O aceite do 0.2 (*"os 16 snapshots revisados um a um"*) é, portanto, inalcançável antes do 0.3.

> **Erro do coordenador, registrado porque o relatório vale mais honesto que impecável.** Uma
> versão anterior desta seção afirmava o contrário — que o 0.3 *não* bloqueava o 0.2 — apoiada em
> duas evidências verdadeiras mas insuficientes: o `bin/vite build` deu exit 0 com o conjunto de
> entradas idêntico, e o harness *subiu*. Ambas continuam certas e nenhuma responde à pergunta:
> o harness sobe e **só então** dá 404 no SDK. A evidência decisiva (o run 2 com servidores
> próprios) estava sendo escrita pelo executor no mesmo minuto em que o coordenador concluiu o
> contrário. É o mesmo erro que este plano cobra dos executores — afirmar a partir de evidência
> parcial — e vale igual para quem coordena.

**O que continua valendo da decisão anterior, por outro motivo:** o 0.3 **não** roda dentro de
`chatwoot-redesenho-merge`. Dois executores estavam editando ali; foram parados antes de qualquer
alteração (`git diff` dos quatro arquivos de vite: vazio). O worktree do merge é o único lugar
onde a v4.16.2 existe isolada, e misturar 0.3 nele tornaria impossível separar depois o que veio
do upstream do que veio de nós. O 0.3 roda em worktree própria e o resultado é integrado — o
levantamento já feito em `onda-0-bloco-0.3.md` é o estado-de-partida do redespacho.

---

## 2. O que esta onda descobriu, e que ninguém sabia ao começá-la

### 2.1 O merge existia, estava resolvido, e ninguém o tinha commitado

Encontrado em disco: `MERGE_HEAD` presente há três dias, **3.463 arquivos no index, 0 conflitos
pendentes, 0 marcadores**. Um `git checkout` teria apagado tudo. Primeira ação da onda foi
transformá-lo em objeto git permanente — **dois** refs, porque o index e a árvore de trabalho
divergiam em 8 arquivos que um `write-tree` sozinho teria descartado em silêncio.

A decisão de **aproveitá-lo em vez de recomeçar** foi tomada com base em medição, não em
economia de tempo: as três travas que a auditoria upstream de 03/08 declarara bloqueantes
estavam resolvidas — e a do bitmask de `feature_flags` foi resolvida pelo caminho **certo e não
óbvio** (mecanismo `feature_flags_ext_1` + realocação dos nossos 2 excedentes). Quem resolveu o
merge entendia o fork.

### 2.2 O merge é bom na infraestrutura e ruim no que o cliente sente

Esta é a frase que resume as cinco auditorias. **558 arquivos de colisão auditados, cobertura
100% em todas as áreas:**

| Área | Arquivos | OK | PERDA | RISCO | DADO |
|---|---:|---:|---:|---:|---:|
| Ruby de aplicação (`app/`, `lib/`) | 121 | 104 | 3 | 14 | 0 |
| Enterprise / Captain / specs / config / db | 117 (+40 migrations) | 100 | 7 | 10 | **2** |
| Widget / shared / SDK / build | 53 | 49 | 2 | 2 | 0 |
| Dashboard / i18n | 267 | 250 | 11 | 6 | 0 |

O que **sobreviveu** é a espinha dorsal do fork: `compute_all_counts` intacto (1 linha mudada num
arquivo com 304 linhas nossas), WhatsApp de grupos com 18 de 19 arquivos byte-idênticos, 9º dígito
BR, Meta Lead Ads, `lib/url_helper.rb` byte-idêntico nos quatro SHAs, o contrato de `postMessage`
com os mesmos 16 eventos, favicons e manifest com a nossa marca, `theme/colors.js` e
`tailwind.config.js` com 100% das nossas linhas.

O que **se perdeu** é quase todo comportamento de IA e de tela — o que nenhum teste acusa:

- `fix_property_links` foi apagado, e **o produtor do dado continua vivo com um comentário que
  descreve o consumidor apagado**. Efeito: a IA da Tozi volta a mandar URL de imóvel inventada ao
  cliente final.
- A descrição do `handoff_tool` voltou à do upstream — e o comentário nosso que **condena
  exatamente essa descrição** sobreviveu três linhas acima. O arquivo se autocontradiz. Efeito:
  lead qualificado deixa de chegar ao humano.
- 7 das 13 regras de conduta em pt-BR do `assistant.liquid` viraram 3 bullets em inglês.
- O resumo de conversa voltou a ser gerado em inglês.
- O card de conversa expandido do upstream **não implementa o isolamento por agente**: em tela
  ≥1024px, o preview de mensagem restrita a outro agente aparece em texto cru.

### 2.3 Duas migrations do upstream destroem dado de cliente da frota

> **Nota de conferência do coordenador.** O relatório da área de enterprise traz três contagens
> que não fecham entre si: o cabeçalho dele diz *"3 DADO · 7 PERDA · 17 RISCO · 130 OK"* e a
> CONTAGEM FINAL do mesmo documento diz *"DADO 0 · PERDA 7 · RISCO 10 · OK 100"*. Conferi as
> seções de detalhe: são **2 DADO**, os dois migrations (§2.2 e §2.3), e a tabela de migrations
> dele lista exatamente esses dois. A divergência é de contabilidade — o cabeçalho somou
> migrations junto com arquivos de colisão, a contagem final só contou os 117 arquivos. **O número
> vigente é 2**, e é o que está na tabela acima. Os achados em si estão corretos e verificados.

| Migration | O que faz | Exposição medida |
|---|---|---|
| `purge_pending_captain_assistant_responses` | `DELETE FROM captain_assistant_responses WHERE status = 0` — no upstream é lixo, no fork é FAQ pendente viva | **0 linhas nesta VM** (87 responses, todas aprovadas); frota **não medida** |
| `enqueue_validate_openai_hooks_job` | Enfileira job que faz `hook.destroy!` na integração OpenAI de toda conta cuja chave falhe um `GET /v1/models`. Sem `down`, assíncrono | **1 hook** nesta VM; `CAPTAIN_OPEN_AI_ENDPOINT` não configurado, então o cenário catastrófico (gateway que responde 401) **não se aplica aqui** — nas demais VMs, desconhecido |

E **seis** migrations `repurpose_*` teriam apagado features vivas do fork (bits 29 e 39 =
`message_sequences` e `ai_assistant_v2`) — **o merge já as neutralizou**, uma a uma, verificado.

### 2.5b O pior defeito da onda não estava em nenhum arquivo de conflito

Vale isolar este achado porque ele diz algo sobre o método, não só sobre o merge.

**Abrir "Editar" numa integração e clicar em salvar apaga a credencial do banco.** Sem erro, sem
aviso, sem log. Seis integrações, quatorze chaves: `openai.api_key`,
`dialogflow.credentials`, `google_translate.credentials`,
`meta_lead_ads.{app_secret,page_access_token,verify_token}`, `leadsquared.secret_key`,
`dyte.api_token`.

O que o torna especial é que **nenhum dos dois lados está errado sozinho**:

- o **upstream** passou a filtrar `settings` por `visible_properties` no
  `_hook.json.jbuilder` — isolado, isso é **mais seguro**: para de devolver segredo na API;
- o **nosso** `EditHook.vue` (arquivo que só existe no fork) repopula o formulário a partir
  daquele campo e reenvia tudo;
- e o `HooksController#update` **sobrescreve** o jsonb em vez de mesclar.

Cada peça é defensável. A composição destrói credencial de cliente. **Por isso passa por 100% dos
testes verdes** — e por isso não existe suíte que o pegasse: o defeito não mora em nenhum dos
arquivos, mora na junção.

Três consequências de método, e são elas que valem para as ondas seguintes:

1. **Auditoria por arquivo não encontra defeito de composição.** Foi encontrado porque o auditor
   perguntou *"quem consome esta chave?"* e foi ver o consumidor no front — não porque leu o
   jbuilder com atenção.
2. **O arquivo que só o fork tem é o mais perigoso do merge.** O upstream nunca o testa, e ele
   assume um contrato que o upstream acabou de mudar.
3. **A correção certa não é desfazer o upstream.** Devolver segredo no JSON trocaria perda de
   dado por vazamento. O conserto é o `update` mesclar em vez de sobrescrever.

### 2.7 A régua sobreviveu ao merge — e isso foi provado, não presumido

**Os 16 snapshots passaram: 20/20, `EXIT=0`, 6,7 min**, no HEAD `8684f07304`, comparados de verdade
contra o baseline pré-merge — verificado byte-idêntico ao `f26db6ee81` **antes e depois** do run, e
com `--update-snapshots` jamais usado.

O que faz esse resultado valer é que **o executor não aceitou o "passou"**. O verde veio com
`maxDiffPixelRatio 0.01` — cerca de 3.300 pixels de folga num quadro de ~400×600 — e o `App.vue`
tinha mesmo mudado (ganhou `bg-n-slate-2 dark:bg-n-solid-1` no container raiz). Um verde com folga
não responde à pergunta *"o merge muda o widget?"*; responde *"a diferença cabe na folga"*. Então
ele **endureceu** a medição: re-rodou com tolerância **zero**.

| Medição com `maxDiffPixels: 0` | Resultado |
|---|---|
| idênticos até o último pixel | **10 dos 16** |
| divergem só em contorno de glifo | 6 — e **metade alterna entre 0 e ~6.000 px de um run para outro**, ou seja, *flaky* de antialiasing, não mudança do merge |
| fundo do `home-dark-mobile` | `#17171A` **idêntico nos dois lados** — a classe nova pinta exatamente a cor que o elemento já herdava |
| faixas com delta > 32 | todas caem **sobre linhas de texto**; delta máximo 87/255, nenhum pixel acima de 96 |

**Veredito: o merge não muda o widget, e nenhum dos 16 precisa de baseline re-aprovado.** A régua
do bloco 0.1 vale para as Ondas 1–6 exatamente como está.

Três ressalvas que ele registrou em vez de omitir, e que eu mantenho:

1. O `ArticleViewer` (`bg-white` → `bg-n-solid-1`) é mudança real no código, mas fica **fora** da
   matriz de 4 views — **não foi medido**, e nada se afirma sobre ele.
2. A tolerância oficial tem folga real, que engoliria uma mudança visual pequena e localizada.
   O verde oficial é legítimo; a certeza vem da segunda medição, não dele.
3. O worktree **não estava exclusivo** durante a medição — apareceu arquivo de outro executor e um
   arquivo dele foi apagado no meio de um run. **A falha de coordenação é do coordenador**, que
   afirmou "harness livre" sem fechar a porta para os demais. Não invalidou o resultado (o baseline
   foi conferido byte a byte antes e depois), mas podia ter invalidado.

### 2.6 O veredito da régua: **o bloco 0.2 não passa como está**

O executor da DoD rodou os 9 comandos do §10.4 e recusou o bloco, com o cuidado de **não chamar
dívida antiga de regressão**: rodou `rubocop`, `eslint` e os 5 specs mais problemáticos **também
no `f26db6ee81`**, em worktree descartável e banco próprio.

| Item | Resultado | Leitura |
|---|---|---|
| `vitest` | **4586/4586** | ✅ |
| `bin/vite build` | 8 entradas idênticas ao baseline; SDK **IIFE** | ✅ |
| colisão de timestamp | vazio, 257 migrations | ✅ |
| boot em `test` | `4.16.2`; **63 default + 14 ext_1** | ✅ (a coluna default fica **exatamente no teto** de 63 bits) |
| `eslint` | 786 (103 err) · baseline **741 (103 err)** | delta **+45 warnings, 0 errors** — já falhava antes |
| `rubocop` | 674 · baseline **659** | delta **+15** — já falhava antes |
| `pnpm size` | reporta 27,89 kB | ⚠️ **verde falso**: o first-paint real é **416,28 kB gzip** contra teto de 300 kB |
| `rspec` | 4774 exemplos, **219 falhas** | 110 medidas nos dois lados → **+60 do merge**; as outras 109 declaradas **não medidas**, não extrapoladas |
| `playwright` | 19 failed / 1 passed em 3 runs | **0 dos 16 comparados** — bloqueado pelo 0.3. **Desbloqueado em 17/08 14:07** e re-medindo |

**As três regressões reais do merge**, todas com prova:

1. **`vite.config.ts` perdeu o branch `isTestMode`** → o `vite-plugin-ruby` reescreve o `root` para
   `app/javascript`, o SDK dá 404 e os 16 snapshots morrem antes de qualquer comparação de pixel.
   Zero imagens `-actual`/`-diff` nos três runs; `--update-snapshots` **nunca** usado; baseline
   segue byte-idêntico.
2. **`.joins(:messages)`** do `filtered_counter.rb` novo colide com o `has_many`
   instance-dependent do `team_message_isolation` → `ArgumentError` em runtime nos contadores.
   41 falhas. Mitigado hoje só porque as duas flags estão desligadas.
3. **`key_validator.rb`** novo faz HTTP síncrono de até 5s para `api.openai.com` dentro de uma
   validação do ActiveRecord. 51 falhas contra **0** no baseline — número que derrubou a
   hipótese inicial do próprio executor de que era falta de `.env`.

> O mesmo executor confirmou que o `6ad7a9ec6e` (o fix do harness que entrou no worktree durante
> a medição dele) corrige o cold-start mas **não toca** `vite.config.ts` — então o 404 persiste,
> e **`0.3` é pré-requisito de `0.2`, não sucessor**. É a inversão de dependência da §3.

### 2.4 O plano tinha quatro números errados, e eles foram corrigidos antes da Onda 1

A §4 do PLANO-MESTRE manda corrigir aceite inatingível **antes** da onda, nunca na revisão. Foi
o que se fez, com medição independente do coordenador (§12 do PLANO-MESTRE):

| Bloco | Era | É |
|---|---:|---:|
| 1.04 — `n-brand` | 25 linhas / 16 arquivos / 7 em `shared/` | **26 / 18 / 8** |
| 1.08 — CSS do widget | 1.103.132 B | **1.692.256 B** |
| 1.09 — `App.vue` | 386 linhas (conta: 303) | **390** (conta: **307**, margem cai de 7 para 3) |
| 0.5 — linha de base do `sdk.js` | 28.834 B / 9.508 B gzip | **29.014 B / 9.595 B gzip** |

E o bloco **1.23 mudou de escopo**: o upstream já implementou a fila **pré-conversa**.
Reimplementá-la por cima criaria **duas filas**, e o atributo seria enviado duas vezes.

### 2.5 A régua do projeto estava quebrada — e o defeito produzia verde

Três defeitos do harness, todos achados por execução real, nenhum por leitura:

1. **`/__ready` mentia.** Respondia 200 assim que a porta abria, mas o Vite em `middlewareMode`
   compila SFC sob demanda: o primeiro teste pagava ~45s de compilação contra um orçamento de
   ~45s. Resultado intermitente: 13/16.
2. **Os servidores não morriam.** `process.once('SIGTERM')` cancelava o encerramento default do
   Node e as conexões keep-alive seguravam o event loop — as portas ficavam presas e a execução
   seguinte morria.
3. **O readiness check não verifica identidade.** Com as portas ocupadas por outro worktree, o
   Playwright viu o `/__ready` **de outro checkout** responder e seguiu em frente. É o falso verde
   na forma mais cara: a suíte mede o código errado e reporta sucesso.

Os dois primeiros estão corrigidos (`d21794862b`). O terceiro está documentado com a correção
proposta e **não foi feito nesta onda** — ver §5.

---

## 3. Decisões tomadas pelo coordenador (registradas, não escondidas)

| # | Decisão | Por quê |
|---|---|---|
| 1 | **Aproveitar o merge** em vez de recomeçar | 0 conflitos, 3 travas resolvidas, bitmask tratado corretamente. Refazer custaria dias no bloco de maior risco do plano, e a segunda resolução não seria melhor |
| 2 | **Antecipar o bloco 0.3** para antes de o 0.2 fechar | O merge quebrou o caminho de build de que a régua depende. A dependência declarada no plano se inverteu na prática |
| 3 | **`assignment_v2` volta a `enabled: false`** | Merge não muda produto. Adotar o motor v2 como padrão é decisão legítima — mas se toma de propósito, não como efeito colateral |
| 4 | **Card expandido: Opção A** (neutralizar, não portar) | Restaura exatamente o comportamento de hoje com superfície mínima. Portar as 4 customizações é trabalho deliberado, não conserto de merge |
| 5 | **Título do portal: manter o do upstream** | Produto white-label: o título do Help Center do cliente é o nome do portal dele, não a nossa marca cravada |
| 6 | **Não migrar `copilot/` e `resolve-gate/` para o fixture anti-erro** | O aceite do 0.11 nomeia `spec/e2e/widget/` e só. Migrar as outras duas provavelmente as deixa vermelhas no dia 1 — é trabalho real, não uma linha de import, e o plano não o pediu |

### Um erro do coordenador, corrigido por quem foi auditar

O coordenador classificou como RISCO a realocação de dois feature flags para
`feature_flags_ext_1`. **Dois auditores independentes refutaram** com prova aritmética: aqueles
eram os bits 64 e 65 de uma coluna `bigint`, cujas máscaras (`1<<63`, `1<<64`) excedem o tipo —
os flags nunca foram graváveis, logo não havia estado a preservar. Os três achados de partida
foram entregues **com a instrução explícita de confirmar por conta própria**. Um dos três caiu.
É para isso que a instrução existia.

---

## 4. Checklist de pré-deploy da frota (não é código, e não pode se perder)

Levantado pelas auditorias. Nenhum destes é defeito do merge — são consequências dele que só
aparecem no deploy.

| # | Verificar antes de subir | Se ignorar |
|---|---|---|
| 1 | `SAFE_FETCH_ALLOW_PRIVATE_NETWORK` no `.env` de cada VM (default do upstream é `false`) | Todo webhook para IP privado (WAHA interna, n8n, receptor local) falha **silenciosamente** |
| 2 | `InstallationConfig['ACCOUNT_LEVEL_FEATURE_DEFAULTS']` contém `response_bot` ou `report_v4`? | Se contiver, duas migrations o salvam de `NoMethodError` na criação de conta nova; se não, são no-op |
| 3 | Templates de e-mail globais duplicados por `(name, template_type, locale)` | `add_inbox_scope_to_email_templates` **aborta o `db:migrate`** no meio da fila |
| 4 | `captain_documents.external_link IS NULL`, e URLs do mesmo assistant que só diferem depois do byte 255 | `change_captain_document_external_link_to_text` **aborta o `db:migrate`** (duas formas) |
| 5 | Consumidores externos de webhook de `Channel::Api` / `AgentBot` (WAHA, n8n) | `backfill_agent_bot_and_channel_api_secrets` muda o contrato de assinatura |
| 6 | `captain_assistant_responses` com `status = 0` por VM | É a FAQ pendente que a migration neutralizada teria apagado |
| 7 | `CAPTAIN_OPEN_AI_ENDPOINT` apontando para gateway que responde 401 em `/v1/models` | O job de validação **apaga as integrações de IA da VM inteira** |
| 8 | **`rake assets:precompile` é OBRIGATÓRIO neste deploy** — não é opcional nem "por segurança" | O bloco 0.3 mudou o hash de **31 chunks**. O executor não deixou isso como mistério: provou com um terceiro build que o bundler é **determinístico** e rastreou a cascata a uma causa única e desejada — o `lord-icon` restaurado tira o `resolveComponent` do `dashboard.js`, que encolhe 10 B e muda de nome; como o hash tem sempre 8 caracteres, os importadores mudam de **conteúdo** sem mudar de **tamanho**, e a cascata segue até o widget pelo chunk compartilhado do `EmojiPicker`. Subir sem precompile serve manifest velho — o modo de falha que esta frota já conhece |

### 4.1 Configuração ausente — os três P0 que só a auditoria *upstream-only* enxergou

Esta subseção existe por um motivo de método: **a auditoria de colisão é cega para arquivo que só
o upstream mudou**, e os três itens abaixo estão exatamente aí. Nenhum deles apareceu nos 558
arquivos auditados; todos quebram caminho vivo da frota, e dois quebram **em silêncio**.

| chave | onde vive | efeito com ela ausente | prioridade |
|---|---|---|---|
| `SAFE_FETCH_ALLOW_PRIVATE_NETWORK` | `.env` (default `false` em `lib/safe_fetch.rb:39`) | Webhook para host interno, **tool HTTP do Captain para IP privado** e avatar de storage interno passam a levantar `SafeFetch::UnsafeUrlError`. Era permitido antes do merge | **P0 — `=true` em toda VM** |
| `FB_APP_SECRET` / `INSTAGRAM_APP_SECRET` | `InstallationConfig` (não é `.env`, escapa de qualquer grep no `.env.example`) | **401 em 100% dos webhooks do Instagram.** Não gera exceção: falha silenciosa | **P0**, em toda VM com canal IG/Messenger |
| `WHATSAPP_APP_SECRET` | `InstallationConfig` | **401 nos webhooks** de canal `whatsapp_cloud` com `source: embedded_signup` | **P0**, em toda VM com embedded signup |

E uma armadilha de limite que ninguém escolheu: `RATE_LIMIT_REPORTS_DRILLDOWN_API_USER_LEVEL`
nasce **derivada** (`RATE_LIMIT_REPORTS_API_USER_LEVEL / 10` = **10 req/min por usuário**). Quem
explorar a tela de relatórios clicando métrica a métrica toma **429**. Nenhuma das 6 variáveis
novas de runtime está no `.env.example`.

> **Nota de método, registrada porque melhora o próximo levantamento:** a primeira passada do
> auditor usou `grep` por linha e **perdeu** um caso — `ENV.fetch(` com o nome da variável na
> linha seguinte. Ele refez com `tr '\n' ' '` por arquivo e achou a variável que faltava. O
> número vigente (158 nomes no merge · 111 na base · 142 no nosso) é o da segunda passada.

---

## 5. Pendências declaradas

**Do bloco 0.4:** brotli não existe nesta VM (precisa `sudo apt`), `gzip_vary` continua comentado,
e as demais VMs da frota **não foram medidas** — não reprovadas.
**Do bloco 0.10:** o inventário e o provisionamento nas demais VMs. `Chatwoot.encryption_configured?`
foi provado `true` **nesta** VM, com round-trip de cifra, sem tocar em nenhuma linha do banco.
**Nenhuma senha foi pedida e nenhum comando privilegiado foi executado.**

**Do harness:** o defeito de identidade do `/__ready` (H1) segue aberto, com a correção escrita.
Enquanto não for feito, dois worktrees não podem rodar o harness ao mesmo tempo — a onda contornou
isso serializando.

**Dívida de tradução:** o merge trouxe **95 chaves novas sem `pt_BR`**. Não é perda (0 chaves
nossas foram destruídas) e não bloqueia; é dívida conhecida, com o número à vista.

**`swagger/swagger.json`** caiu de 353 para 90 paths e **não tem conserto barato**: o pipeline que
gerava os 353 nunca foi versionado e não existe mais na VM.

---

## 6. Índice dos artefatos

| Arquivo | O que traz |
|---|---|
| `onda-0-reconciliacao.md` | a divergência entre o relatório do antecessor e o disco, e a decisão irreversível |
| `onda-0-validacao-baseline.md` | os 8 aceites do 0.1/0.11, com saída real de três execuções |
| `onda-0-dod-merge.md` | a Definition of Done numérica do 0.2, comando a comando |
| `onda-0-auditoria-ruby.md` | 121 arquivos de `app/` + `lib/` |
| `onda-0-auditoria-enterprise.md` | 117 arquivos + as 40 migrations novas, uma a uma |
| `onda-0-auditoria-widget.md` | 53 arquivos de widget, shared, SDK e build |
| `onda-0-auditoria-dashboard.md` | 267 arquivos de dashboard e i18n |
| `onda-0-auditoria-widget-upstream.md` | os 82 arquivos que só o upstream mudou no widget, e o efeito no plano |
| `onda-0-auditoria-backend-upstream.md` | o mesmo, no backend |
| `onda-0-correcoes-pendentes.md` | a lista fechada de correções — é a autoridade do executor |
| `onda-0-infra-0.4-0.10.md` | os dois blocos de infra, medidos |
| `onda-0-bloco-0.3.md` | a reconciliação do build |
| `dados/` | `triagem.tsv`, `colisao.txt` e os recortes por área |
</content>

---

## 7. Fecho da onda — integração e estado final

**Branch integrada:** `redesenho-base` = `redesenho-merge` = `5fd08050fc`, árvores idênticas.
Nada foi pushado, nenhum PR foi aberto, nenhum deploy foi feito.

### 7.1 Os 11 blocos

| Bloco | Estado | Prova |
|---|---|---|
| **0.1** harness + 16 baselines | ✅ **VALIDADO 8/8** | `onda-0-validacao-baseline.md` |
| **0.11** fixture anti-erro | ✅ **VALIDADO**, sem precisar de correção | idem |
| **0.2** merge da v4.16.2 | ✅ **os 3 aceites literais** + 22 correções aplicadas | `onda-0-dod-merge.md`, `onda-0-correcoes-aplicadas.md` |
| **0.3** reconciliar o build | ✅ 8 entradas, SDK IIFE, Leaflet deletado | `onda-0-bloco-0.3.md` |
| **0.4** compressão | ✅ **4/4 local** (era 0/4) | `onda-0-infra-0.4-0.10.md` |
| **0.5** gate de peso | ✅ mede o grafo; **nasce vermelho de propósito** | `onda-0-bloco-0.5.md` |
| **0.6** paridade dos montadores | ✅ herdado (`1a45399b2a`) | relatório do antecessor |
| **0.7 / 0.8 / 0.9** | ✅ os três, aceites conferidos pelo coordenador | `onda-0-blocos-0.7-0.8-0.9.md` |
| **0.10** Active Record Encryption | ✅ **local** nos 3 itens | `onda-0-infra-0.4-0.10.md` |

### 7.2 A régua sobre a árvore integrada

```
pnpm exec vitest --no-watch --no-cache   → 471 arquivos, 4619 passed, 0 failed   EXIT=0
pnpm exec playwright test --project=widget → 20 passed (16 snapshots + 4 contratos) EXIT=0
ls db/migrate | cut -d_ -f1 | sort | uniq -d → vazio (258 migrations)
git grep -nE '^(<<<<<<< |>>>>>>> )'      → vazio
```

Os 4586 testes do vitest viraram **4619**: as correções trouxeram 33 exemplos novos, todos com
vermelho-antes produzido.

### 7.3 O número que resume a onda

**Os 16 PNG e o `baseline.json` continuam byte-idênticos a `f26db6ee81`.** Quatro executores
diferentes rodaram a suíte visual dezenas de vezes, três deles com autorização explícita para
consertar o harness, e **`--update-snapshots` nunca foi usado**. Era o risco número um do projeto —
regravar a régua para fazer o merge passar — e ele não se materializou em nenhum momento.

### 7.4 O que a onda descobriu e ninguém procurava

Nenhum dos quatro achados abaixo gera exceção. Todos passariam para produção com a suíte verde.

1. **Excluir conversa não excluía, e a API respondia `200 OK`** (`5525a161ab`). Três peças, e a
   terceira só apareceu na validação: a correção da FK **sozinha não fecha o defeito**, porque a
   ordem de execução dos triggers depende da **ordem de criação das constraints** — que diverge
   entre um banco carregado de `schema.rb` (a suíte) e um banco onde a migration correu por cima
   (**a frota**). Teste verde, produção quebrada, dentro de um job com retry.
2. **Editar integração apagava a credencial no banco** (`3dccaebb3f`) — 6 integrações, 14 chaves.
   Defeito de **composição**: nenhum dos três lados está errado sozinho. E encadeava com o item 8:
   a chave apagada arma o job do upstream que **destrói a integração inteira**.
3. **Duas migrations do upstream destroem dado de cliente** e **seis `repurpose_*`** teriam
   desligado features vivas do fork na frota inteira — estas últimas o próprio merge já havia
   neutralizado, uma a uma.
4. **Comportamento de IA trocado em silêncio**: prompts, regras de conduta em pt-BR e a descrição
   do tool de handoff voltaram às do upstream. O caso mais claro é o `fix_property_links`, apagado
   com **o produtor do dado ainda vivo** e o comentário dele descrevendo o consumidor que sumiu.

### 7.5 Duas coordenações em paralelo — o que aconteceu e o que fica

O processo do terminal coordenador reiniciou no meio da onda e **a instância anterior continuou
viva**, coordenando em paralelo por cerca de duas horas. As duas alternaram o binding do Run a
tarde inteira, e o `check --wait` de uma **consumia a fila FIFO** da outra.

Não houve divergência de julgamento — as decisões das duas bateram quando comparadas. Houve
duplicação de autoridade, e ela custou: um bloco executado duas vezes (`0.3`, com resultado
byte-idêntico), o limite de **50 PTYs** estourado (75 terminais), uma medição destruída por engano
(um instrumento movido com o processo dono rodando) e — a mais grave — **uma autorização que
nenhum coordenador assume**, aceita de boa-fé por um executor.

Três coisas ficam registradas, e valem além desta onda:

- **Fechar task por artefato validado, e nunca por `worker_done`, foi o que salvou a onda.** O
  canal de mensagens esteve não-confiável por horas sem que ninguém percebesse; o disco não.
- **Autorização precisa ser conferível.** Um executor que não consegue conferir a origem deve
  registrar *"autorização não conferível"* e deixar a decisão a descoberto — foi o que acabou
  acontecendo, e o registro honesto vale mais que qualquer das duas versões anteriores.
- **Um coordenador.** O handover está em `onda-0-handover-coordenador.md`, escrito pela instância
  que parou. Ele contém decisões que não estavam em relatório nenhum.

### 7.6 O que fica pendente, nomeado

| Pendência | Onde | Por quê não foi feito |
|---|---|---|
| **Checklist de pré-deploy da frota** | §4 deste relatório + `onda-0-auditoria-backend-upstream.md` §2 | Não é código. **1 variável de `.env` P0** (`SAFE_FETCH_ALLOW_PRIVATE_NETWORK`) + `FB_APP_SECRET`/`INSTAGRAM_APP_SECRET` + 4 verificações que **abortam o `db:migrate`** se ignoradas |
| **brotli, `gzip_vary`, e as outras 3 VMs** | `onda-0-infra-0.4-0.10.md` | Exige `sudo`. Nenhuma senha foi pedida |
| **Inventário de `ACTIVE_RECORD_ENCRYPTION_*` na frota** | idem | Exige acesso às outras VMs |
| **110 arquivos de `views/`** | `onda-0-auditoria-views.md` | Auditados; as correções P0 saíram, o resto é dívida declarada |
| **H1 — identidade no `/__ready`** | `onda-0-correcoes-pendentes.md` | O harness ainda aceita servidor de outro checkout. Contornado por serialização nesta onda |
| **H5 — diagnosticabilidade do `isTestMode`** | idem | A regressão **é** pega; a mensagem é que não explica |
| **`swagger.json`: 353 → 90 paths** | `onda-0-auditoria-widget.md` §C4 | Sem conserto barato: o pipeline que gerava os 353 nunca foi versionado |
| **Dívida de i18n do upstream** | `onda-0-auditoria-dashboard.md` | Chaves novas só em `en`. **Zero chave nossa foi destruída**; criar bloco de tradução por conta própria seria crescer escopo |

### 7.7 Correções feitas no próprio PLANO-MESTRE

A §4 do plano manda corrigir aceite inatingível **antes** da onda, nunca na revisão. Foram
**quatro números** e **um orçamento**, todos remedidos e conferidos de forma independente pelo
coordenador antes de entrarem — estão na **§12** e na **§12.3** do `PLANO-MESTRE.md`. Sem isso, a
Onda 1 começaria reprovando execução correta.
