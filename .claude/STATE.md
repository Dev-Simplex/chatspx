# Estado ChatSPX — atualizado 2026-09-08 (a janela de 7 dias do Instagram não é limitação do SPX: falta App Review)

> Single source of truth do que está **in-flight** no projeto.
> Coisas estáveis vão pro [`MEMORY.md`](../../../.claude/projects/C--Users-paulo-Workspaces-chatspx/memory/MEMORY.md) (per-projeto) ou pro vault Obsidian.
> Decisões com mais de 30 dias devem ser movidas pra `clientes/tozi-conversation-log.md` no vault.

> ✅ O handoff de 29/05 foi SUPERADO em 11/06: reconciliação executada, deploy AWS virou git, código paulao→prod Tozi completo. Sessão de decisões pendente: **[`docs/DECISOES-CLARA.md`](../docs/DECISOES-CLARA.md)**.

---

## 🚧 Em andamento

### [2026-09-28] 🧭 PLANO ÚNICO POR FRENTE — os dois handoffs de 28/09 consolidados (sessão integradora)

> Fontes conferidas em 28/09: `origin/producao` (#226 P0 em 22/09 · #257 abas Rodízio/Atenção em 25/09 ·
> #261 · #263/#264 Captador em 27/09), gestão CHAT (39 abertas) e Arena. Os dois handoffs batem com o
> código; única divergência: CHAT-127 diz "5 agentes", o handoff diz "6 de 9" (a Bruna é a sexta e tem
> tratamento próprio). O prompt de retomada está em `docs/PROMPT-RETOMADA-SPX-IA.md` (não versionado).
> **Regra desta sessão:** código só em worktree filha `spx/<frente>` (Orca), config de IA daqui com
> antes/depois e ok do Paulo; o detalhe mora na Arena, o problema no gestão.

**Organização (28/09, noite): Paulo pediu que esta sessão seja a ORQUESTRADORA.** Arena = frente → bloco
(tarefa macro) → checklist numerado; gestão = só o problema. A posição se diz como "Dado certo 1/6".

**Tozi — corrigir a estrutura das IAs** (conta 6, VM `3.94.9.51`)
- *Fazer as IAs usarem o dado certo:* 1 `vazio_completo` nunca gravado · 2 retorno da tool cortado do contexto
  (CHAT-169; `captain_tool_context=true` na conta 6, teto 6×700) · 3 telefone inventado (CHAT-159) ·
  4 `knowledge_mode` (CHAT-127) · 5 inventário de ferramentas (CHAT-168) · 6 prompts corrigidos (CHAT-136)
- *Fazer o atendimento andar depois da IA:* 1 follow-up não dispara (CHAT-164) · 2 mensagem agendada sem IA
  (CHAT-165) · 3 marcadores novos + troca manual (CHAT-166, decisão já tomada) · 4 rodízio em `designacao`
  (CHAT-125) · 5 lead no Vista sem depender do rodízio (CHAT-133/134)
- *Medir e aprender:* 1 20 `contradisse_tool` por causa · 2 oportunidade perdida (CHAT-147) · 3 re-medir
  baseline (CHAT-135) · 4 Jev em sombra (CHAT-151 — sugestão do Paulo de potencializar as IAs com o Jev)
- Fora dos blocos: disparo dos contatos parados (só sai com "pode soltar" do Paulo).

**SPX — destravar entregas paradas e perdas em curso**
- *Branches paradas → PR:* CHAT-128, 129, 130, 131 + decidir 3 branches sem PR
- *Destravar o Instagram na Meta:* CHAT-156 **não é bug de código** — conserto no ar desde 25/08 (PR #63),
  a Tozi roda `dac5a6dce`, mas **0 eventos `changes` em 7 dias** contra 314 de DM: a Meta não entrega
  comentário. Caminho: endpoint de exclusão (CHAT-160) → App Review (Paulo) → token (CHAT-158) → diagnóstico (CHAT-157)
- *Terminar campanhas (CHAT-167):* espera o Paulo listar o que falta no uso
- *Captador × Vista* · *Arrumar docs e scripts* (taxonomia, fluxograma, `fabrica.sh`)
- Defeitos da auditoria de 20/09 sem tarefa viraram CHAT-163.

**CD Solar (CHAT-161) / Rocket (CHAT-162)** — seguem os itens que já estavam na Arena.

**Decisões do Paulo que travam:** CHAT-125 (ligar rodízio) · CHAT-126 (sinal MCMV) · CHAT-146 (coexistência).
As 16 tarefas CHAT-126..151 ficam como estão (decidido 28/09).

### [2026-09-25] 🔴 O P0 ESTÁ NO AR E `vazio_completo` NUNCA FOI GRAVADO — a diferenciação não chega ao banco

> Achado ao procurar o sinal estrutural para os casos A e B. **Não é dívida técnica: é o pré-requisito
> do detector de maior retorno do mapa.**

- O código em produção declara `Captain::Tools::Result::CONFIRMADOS = ["ok", "vazio_completo", "parcial"]`.
- **O banco tem dois valores, em toda a história:** `ok` **28.003** · `error` **2**. `vazio_completo` e
  `parcial` **nunca foram gravados**.
- **E não é falta de tempo de vida:** das 768 chamadas registradas **depois** do deploy do P0
  (23/09 00:22 → 25/09 14:47 UTC), **todas** com status `ok`.
- **O que isso invalida:** o gate do eval passou a ler `Result::CONFIRMADOS`, mas lê um campo que
  **nunca varia**; o `ignorou_erro_da_tool` que devia subir de volume não tem como subir; e a query do
  detector A/B devolve **zero**.
- **Causas possíveis, nenhuma investigada:** (a) o `TraceRecorder` não desembrulha o `Result` e grava
  literal `ok` · (b) os ramos que produzem `vazio_completo` não são exercitados · (c) o mapeamento para
  a coluna persistida (há uma constante `STATUS_PERSISTIDO`) · (d) o desembrulho se perde porque a gem
  `agents` recebe String. Registrado em **CHAT-103**, que já pedia "validação do trace".

### [2026-09-25] ⭐ A HISTÓRIA DAS 17:20 — atribuir é o que mata, não o handoff

> **Paulo:** *"17:20 cliente pede casa para alugar até 3000 perto do centro, a IA atendia mas já
> mandava para aguardando atendimento, o lead ainda estava recebendo imagens para escolher, a Maria
> Vitória via às 17:30 (final de expediente), atribuía a um consultor que calava a IA, e o humano só
> iria responder no dia seguinte."*

- **O mecanismo da plataforma está certo.** O handoff marca, roteia e **não solta o espelho** — a IA
  segue respondendo (`captain_can_respond?` olha o espelho, não o marcador).
- ⭐ **O que mata a conversa é a ATRIBUIÇÃO MANUAL.** Setar `assignee` dispara
  `reset_agent_bot_when_assignee_present`, que **zera o espelho** e cala a IA na hora. **Não foi o
  handoff que calou — foi o ato de atribuir.** E no pior momento possível: **17:30**, quando nenhum
  humano vai agir nas 14 horas seguintes, com o cliente **no meio do fluxo**, escolhendo entre fotos.
- ⭐ **A Maria Vitória não tem como rotear sem calar a IA.** A única ferramenta na mão dela é atribuir.
  **O erro não é dela — é falta de um caminho.** E o caminho existe e está desligado:
  **`modo_posse: designacao`** (*"só registra a designação; `assignee` segue nulo, o espelho sobrevive
  e a IA continua atendendo até alguém assumir"*).
- ⭐ **Isso reordena tudo:** a razão de ligar o rodízio **não é justiça de distribuição** — é que o
  rodízio em `designacao` é **o único jeito de rotear sem calar a IA**. **CHAT-125 e CHAT-144 deixam de
  ser melhoria de operação e passam a ser conserto de defeito com dano medido.**
- **Regra dura do desenho:** *handoff não cala a IA; só um humano **falando** cala.*

### [2026-09-25] Correções do Paulo: estados reais, padrão de texto recusado, e o caminho de volta

- **Os estados de hoje são `aguardando atendimento` e `aguardando encerramento`** — eu havia inventado
  "em atendimento"/"atenção". Medido: `aguardando_humano_desde` **6** (transitório) ·
  `aguardando_encerramento_desde` **336** · `encerramento_avisado_em` **0**. **336 na fila de
  encerramento e nenhuma avisada** — a fila existe, o aviso não sai.
- ❌ **Padrão de texto determinístico RECUSADO como gatilho**, e com razão: *"seria mais uma coisa pra
  ficar olhando porque aconteceu isso se a IA falou isso em outro sentido"*. Falso positivo mata
  indicador. **Substituído pelo sinal ESTRUTURAL** — a ferramenta confirmou ausência (`vazio_completo`),
  não a frase da IA. **O estrutural PENEIRA (barato, sem ambiguidade), a Jev JULGA** ("esta ausência era
  negociável?"). Nenhum dos dois lê texto.
- **O caminho de volta ganhou dono:** *"se humano pegar a conversa e esfriar, o supervisor deverá ficar
  sabendo e ele decidir devolver ao rodízio"*. Não é a IA que retoma nem o humano que devolve — é o
  **supervisor notificado**. Vira requisito de **CHAT-149**, e a população já está medida: **5 dos 7
  `urgent` por pressão de janela JÁ têm assignee**.
- 🔴 **Fábrica autorizada mas BLOQUEADA:** `scripts/ops/fabrica.sh` aponta para
  `Obsidian/clientes/fabrica-atacadao-oculos.md` (a nota migrou para `spx-os/clientes/` em 13/08) **e**,
  no caminho certo, o campo `senha:` no formato esperado **não existe mais** (rotação de agosto tirou
  `credenciais/` do git). **Não contornei caçando credencial** — é decisão do Paulo consertar o helper.
  Até lá a coluna "ótica" da taxonomia é **inferência, não medição**.

### [2026-09-25] ⚠️ EU LI UMA VERSÃO VELHA DO RODÍZIO — o PR #257 já está em `producao`

> **O Paulo avisou e estava certo:** *"O Rodizio foi implementado por outro desenvolvedor já com
> 'atenção' e 'Rodizio', não sei se você tem acesso à nova versão."* Meu checkout de `homologacao`
> estava atrás e eu não vi. **Toda afirmação sobre rodízio que eu fiz entre 23 e 25/09 precisa ser
> reconferida** contra `origin/producao`.

- **Onde está:** PR #257, branch `feat/abas-rodizio-atencao` — `50264fee81` (24/09), `e4d9d4d760`,
  `6fdc281bf0`, `97731812f1` (25/09), autoria `simplex`.
- 🔴 **A "Atenção" implementada NÃO é a que o Paulo desenhou.** De `constants/globals.js`:
  `PENDING_CLOSURE` = *"'Atenção' (só admin/supervisor): conversa parada/encerrada marcada pra um
  humano JULGAR O FECHO"* → é a fila `aguardando_encerramento` (as 336). A "atenção" da V2 do Paulo
  é **julgar se vai para o rodízio**, ANTES do handoff. **Mesmo nome, momentos opostos** — resolver
  no desenho antes que o time se confunda.
- `RODIZIO` = designação aberta do Motor, com **escopo por papel**: admin/supervisor veem todas, o
  agente só as que estão **na vez dele**.

### [2026-09-25] ✅ Os dois cenários do Paulo JÁ ESTÃO em produção — falta só o online

A escada de precedência do `pick` (`distribuir_service.rb`, `origin/producao`):

| | Degrau | Consome a vez? |
|---|---|---|
| 0 | `@motivo_forcado` — repasse fura a fila, vai direto ao rodízio | — |
| — | `sem_lead_novo` — já tem dono, não há lead novo | — |
| 1 | `quem_ja_atende` | não |
| 2 | ⭐ **`preferencia_do_cliente`** — o cliente pediu pelo nome | **SIM** |
| 3 | ⭐ **`consultor_anterior`** — gateado por `continuidade_dias` (30) | **não** |
| 4 | `proximo_rodizio` — ponteiro por time | sim |

- **"Cliente pede alguém específico" existe.** Lê `custom_attributes[PREFERENCIA]`; **quem detecta e
  grava é a CONDUTA DA IA**, o rodízio só lê. Casamento **estrito** (id, nome completo, ou primeiro
  nome único); ambíguo devolve `nil` de propósito — *"mandar o lead pro 'Bruno errado' é pior que
  mandar pro rodízio"*.
- ⭐ **E consome a vez, com a justificativa certa:** *"se não contasse, viraria porta dos fundos —
  bastava o corretor dizer aos contatos 'peça por mim' pra furar a fila inteira"*.
- **"Conversa reaberta com a mesma pessoa" existe** e **não** consome a vez: *"é RETORNO de cliente
  que já era dele"*.
- 🔴 **O status online NÃO é consultado.** O dado existe (`AccountUser#availability` enum
  `{online, offline, busy}` + `OnlineStatusTracker` no Redis), mas `distribuir_service.rb` tem **zero
  ocorrências** de availability/online/presence. E as duas peças que ligariam isso estão mortas:
  `so_online` aparece **só** no controller (default false, strong params, nunca lido no `build_pool`)
  e `modo: 'online'` é **no-op** (`distribui?` só aceita `rodizio` e `fila`).
- **A decisão que isso abre:** hoje preferência e continuidade designam **mesmo offline**. Se o online
  entrar, decidir por degrau. **Recomendação registrada: o online PONDERA, não FILTRA** — entre dois
  candidatos do mesmo degrau prefira o online, mas nunca deixe de designar por ninguém estar online
  (gating sem fallback esvazia o pool fora do expediente). Exceção explícita para o **pedido nominal**:
  vence o online, porque o cliente já escolheu esperar aquela pessoa.

### [2026-09-25] O ponteiro único sobrevive — e apareceu o gancho certo para consertá-lo

- `proximo_rodizio` **continua** lendo `State.last_user_id` por **time**, sem faixa. O PR #257 **não**
  resolveu o problema do lead ruim que queima a vez.
- ⭐ **Mas existe `CONSOMEM_VEZ` / `consome_vez?(motivo)`** — o código **já separa quem gasta a vez de
  quem não gasta. É o gancho onde o ponteiro por faixa se encaixa.**
- ⚠️ **Não é substituto:** se o lead ruim simplesmente não consumir a vez, ele vai sempre para a
  **mesma** pessoa (a da vez atual), que passa a receber todo o lixo. Ponteiro por faixa segue sendo
  o desenho justo.

### [2026-09-25] 🗺️ TAXONOMIA DO ATENDIMENTO COM IA — 6 eixos, 10 frentes · `docs/TAXONOMIA-ATENDIMENTO-IA.md`

> Paulo pediu **todas as hipóteses** do que pode acontecer num atendimento conduzido por IA, **para
> qualquer segmento**, e definiu meu papel: *"você não vai implementar, você será orquestrador das
> frentes e gerenciar as tarefas no gestão"*.

- ⭐ **O insight que muda o instrumento: os casos A e B NÃO SÃO ERROS.** Nada alucinado, nenhuma regra
  quebrada, harness e FactGuard verdes — e o eval deu **nota média 8,52** nos 21 descartes da IA.
  A falha é: **a IA responde a pergunta feita; um vendedor responde a necessidade por trás.** A IA trata
  o que o cliente declara como **filtro rígido**; um vendedor trata como **posição inicial de
  negociação**.
  - **A** (casa R$ 8 mil que não existia no acervo): *"não tenho"* devia ser **"posso captar"** — e era
    o melhor lead do mês, disposto a pagar **2,3× o teto**.
  - **B** (terreno para investir em outra cidade): *"só temos em Sinop"* devia ser **"a cidade é
    premissa sua, não minha"** — para quem **investe**, geografia é negociável. A IA aplicou regra de
    **moradia** a intenção de **investimento**.
- ⭐ **Consequência operacional:** não se detecta A e B olhando **o que a IA fez de errado** — detecta-se
  olhando **o que a IA DISSE que encerra conversas**. É **classificador da forma do "não"**
  (*não temos · só atendemos em · acima do que temos · não trabalhamos com · é necessário*),
  determinístico, sem LLM na 1ª passada, e **serve qualquer segmento** — só os substantivos mudam.
  **É a peça de maior retorno do mapa.**
  - ⚠️ **Não pode virar regra de prompt** proibindo a IA de dizer "não temos" — isso produz **invenção
    de estoque**, pior que perder o lead. A IA segue dizendo a verdade; **o sistema marca**.
- **Os 6 eixos:** (1) 12 **saídas falsas** · (2) 10 **mortes silenciosas** · (3) os **erros** — 22
  categorias que o eval já tem + **5 que faltam** · (4) **estados de posse** (a máquina da V2) ·
  (5) **6 relógios**, nenhum notifica ninguém · (6) **o que varia por segmento** (11 dimensões,
  imobiliária × ótica × clínica × serviço).
- **Duas transições que o Eixo 4 revelou:** *"em atendimento" → "ATENÇÃO"* **não existe hoje** (é o
  estado novo da V2); e **humano → IA não tem caminho de volta** — ninguém tinha pensado nisso.
- **Sobre a Jev:** faz sentido para **decisão fechada** (forma do "não", faixa, merece humano, encerrar)
  e como **2ª opinião em sombra**. **Não** faz sentido para decidir **quando chamar tool** — é latência e
  ponto de falha no caminho crítico, e a auditoria já mostrou que isso se conserta em **camada 1-3**
  (0/6, 0/6, 0/8). A restrição do Paulo (dataset humano antes de decidir) **continua valendo**, mas
  **sombra não precisa do dataset — ela o produz**: desacordo entre dois decisores é fila de revisão
  mais rica que amostra aleatória. Pegadinhas já registradas: `confidence` de `Choice` é **normalizado
  pelo nº de opções** (falha em silêncio, e aqui há decisões de 2, 4 e 8 opções) · critério manda mais
  que modelo · lista vazia é resposta.
- **10 frentes mapeadas contra o gestão, sem duplicar:** F1 **CHAT-146** · F2 **CHAT-147** (maior
  retorno) · F3 **CHAT-148** (caso C) · F4 **CHAT-143** (caso D) · F5 **CHAT-144**+125 · F6
  **CHAT-149** · F7 **CHAT-151** · F8 **CHAT-137** · F9 **CHAT-150** · F10 dentro de 146.
  **Ordem:** F1 → F2/F3/F6/F9 em paralelo → F4+F5 juntas → F7 depois de F9 → F8 consome tudo.
- 🔴 **LACUNA DECLARADA: os 5 agentes da Fábrica (conta 1) NÃO foram lidos** — `3.87.182.184` exige OK
  do Paulo **por vez**. A coluna "Ótica" do Eixo 6 é **inferência pelo segmento, não medição**. Sem ler
  a Fábrica há risco real de **desenhar para imobiliária e chamar de plataforma**.

### [2026-09-25] 🔴 O PONTEIRO ÚNICO DO RODÍZIO: lead ruim CUSTA à pessoa o lead bom seguinte

> **Objeção do Paulo, e ele está certo:** `meta_campanha` presente **não é sinal de compra** — "muitas
> vezes são leads puramente desqualificados". E o problema não é a classificação: é o que ela causa
> na **distribuição**.

- **Provado no código** (`distribuir_service.rb:208-215`): `distribuicao_states` tem índice **único em
  `team_id`**. **Um ponteiro por time, uma rotação, zero noção de qualidade.**
  ```ruby
  last = State.find_or_initialize_by(team_id: @team.id).last_user_id
  ordered = pool_ids.index(last) ? pool_ids.rotate(idx + 1) : pool_ids
  ```
- ⭐ **O dano é pior que "A recebeu lixo":** o lead desqualificado **avança o ponteiro** e portanto
  **custa a A o lead bom seguinte**. B recebe o qualificado *porque* o lixo queimou a vez de A. O
  prejuízo de A não é ter atendido lixo — **é ter perdido o bom.**
- **É a mesma família do incidente da Catatau de 15/09** (*"queimava a vez de cinco vendedores em
  cinco minutos"*). Lá a causa era o menu do flow; aqui é a qualidade do lead. **O ponteiro único é o
  defeito comum.**
- **Conserto justo por construção: um ponteiro por FAIXA**, `(team_id, faixa)` em vez de `team_id` —
  migration pequena. Lead ruim só queima a vez na rotação dos ruins; cada pessoa recebe parcela
  proporcional de cada faixa, **sem ranquear gente**. Combina com "não empurrar a faixa baixa" (ela
  fica no pull, que é o que a Tozi já faz à mão). A opção de dar os bons aos melhores closers
  maximiza receita e destrói a equipe — descartada.
- ⚠️ **CHAT-126 SUSPENSA.** Eu havia fechado o critério ("sinal de compra + dentro do expediente") e
  fechei cedo: ele só **move** o problema para o rodízio. Marcar mais leads sem consertar a
  distribuição distribui injustiça mais rápido. **Caiu** `meta_campanha` como gatilho suficiente —
  anúncio é **origem**, não intenção. Direção provável: a origem qualifica OUTRO sinal; o gatilho é
  **interação demonstrada**, como o próprio Paulo disse ("leads em potencial, **que interagiram e
  responderam**, mas com ordem de prioridade").
- **Criada CHAT-146 — DESENHO da coexistência IA × humano**, dona das 4 peças que têm de ser decididas
  juntas: (1) distribuição × faixa · (2) **follow-up** — hoje o marcador **para a cutucada**, então
  lead 3 dias na fila não é cutucado por ninguém · (3) **horário** — 3 fontes divergentes e nenhuma
  resposta para "o que a IA faz fora do expediente" · (4) handoff (o mecanismo está certo; falta o
  *quando*). **CHAT-126, 143 e 144 passam a depender dela.**
- 🔴 **RESTRIÇÃO DURA que o Paulo reforçou: "o SPX não atende somente a Tozi".** Todo o levantamento
  está escrito em *corretor, imóvel, MCMV, Vista* — **a Fábrica (conta 1, ótica, 5 agentes) não tem
  nenhum dos quatro.** O desenho sai em vocabulário neutro: **faixa de prioridade, pool de
  atendentes, sinal de intenção, fonte de horário**; cada peça opt-in por conta, default = hoje.

### [2026-09-25] ✅ Diretriz: "eliminar qualquer coisa que faça a IA alucinar" — e o conserto tem DUAS metades

- CHAT-127 deixa de ser "decidir por agente" e passa a execução. Mas **trocar `knowledge_mode` é só
  metade**: o defeito é **regra dura apontando para fonte vazia**, e passar `hybrid → faq` conserta a
  **ferramenta** e deixa **a linha do prompt** ("consulte a base antes de afirmar") apontando para o
  nada. Os dois lados por agente, junto com [[CHAT-136]] (render/lint), não em duas passadas.
- ⚠️ **Na Bruna trocar o modo pode PIORAR:** 4.188 msgs/30d em locação; sem base e sem `hybrid` ela
  para de inventar da base e passa a inventar do nada. Recomendação registrada: **alimentar a base**
  na Bruna; **trocar o modo** em Letícia, Marina, Rafa e Helena, cujo volume não justifica o esforço.

### [2026-09-24] ⚠️ TRÊS FONTES DE HORÁRIO NA CONTA 6, E ELAS JÁ DIVERGEM

> Descoberto ao fechar o critério da **CHAT-126**. É a mesma doença que o `UnitAtendimento`
> documenta no próprio comentário — só que agora são **três**, não duas.

| Fonte | seg-sex | sáb | Quem usa |
|---|---|---|---|
| **`Unit 1`** (`UnitAtendimento`) | `07:30-17:30` interv. `11:30-13:30` | `09:00-11:30` | a tela viva, `Units::ScheduleEvaluator` |
| **`assistant.behavior['business_hours']`** | `07:30-11:30` e `13:30-17:30` | `09:00-11:30` | **a IA** (`Captain::Behavior::BusinessHoursChecker`) |
| **`inbox.working_hours`** (caixa 91) | **`09:00-17:00`** | **FECHADO** | away message, widget, métrica |

- A unidade e o behavior **concordam** — é o mesmo turno partido escrito de dois jeitos. **A caixa
  diverge em 1h30 toda manhã e no sábado inteiro.**
- **7 dos 9 agentes** têm `behavior['business_hours']['enabled'] = true` com `schedule` próprio de 7
  dias (só Helena `nil` e Feirão `false`). A mesma informação em três lugares editáveis.
- **Decisão registrada nas duas tarefas:** usar **`UnitAtendimento` como fonte única** — para o gate
  do critério de marcação (CHAT-126) e para o cálculo de minutos úteis (CHAT-143). Usar o behavior
  criaria a **quarta** divergência.
- ⚠️ **Limite do que medi:** comparei só a caixa **91**, que tem `working_hours_enabled=false` (não
  impõe nada, então a divergência dela é latente). As caixas **61 e 62 têm `enabled=true`** e eu
  **não** conferi os horários — se divergirem da unidade, a mensagem de ausência dispara em hora
  errada. **Conferir antes de implementar.**
- Uma caixa (**93 "Notas"**) **não tem `unit_id`** — sem grade, sem pressão de janela. Recomendação
  registrada: **não aplicar** (ausência de grade não pode virar urgência inventada).

### [2026-09-24] ✅ CHAT-126 DEIXOU DE SER DECISÃO — critério de "aguardando atendimento" fechado

> **Marca quando:** há sinal de compra (`meta_campanha` **ou** `meta_imovel_codigo` **ou** o contato
> respondeu N mensagens) **e** está dentro do expediente pela grade da **unidade**, em
> `modo_posse: designacao` — a IA **continua respondendo** até alguém puxar (já é o comportamento da
> plataforma; nada a codar para isso).

- **Não descarta ninguém.** Quem não tem sinal entra na fila com prioridade mais baixa, não fica fora
  dela. O corte é de **ordem**, não de porta.
- **Fora do expediente NÃO marca — e isso não custa nada.** O efeito colateral do marcador é **parar
  a cutucada** (`followup_job.rb:118`); marcar às 22h desliga o follow-up numa sala vazia. E não
  precisa marcar, porque **a pressão de janela não depende do marcador**: de madrugada a conversa não
  é marcada mas **já é classificada**, e quando o expediente abre a fila já está na ordem certa.
- ⭐ **Os 17 MCMV parados TODOS vieram de anúncio** — o sinal `meta_campanha` sozinho já os teria
  marcado. O critério resolve o caso que originou a tarefa.
- Único número ainda aberto: o **N** do sinal de interação (quantas respostas do contato contam).
  Ajustável depois.

### [2026-09-24] 🔴 72% DA FILA ABERTA DA TOZI TEM A JANELA JÁ FECHADA — 1.844 de 2.550

> Simulação dos cortes de prioridade na conta 6 (somente leitura). Grade da unidade:
> seg-sex `07:30-17:30`, sáb `09:00-11:30`.

| das 2.550 abertas | 1ª conta (ERRADA) | **corrigida** |
|---|---|---|
| sem janela (canal sem janela, ou sem inbound) | 621 | 621 |
| **janela JÁ FECHADA** | 1.844 | **1.843 — 72%** |
| dentro da janela, > 4h úteis | 74 | 67 |
| dentro da janela, 1 a 4h úteis (`high`) | 10 | **16** |
| dentro da janela, < 1h útil (`urgent`) | 1 | **7** |
| **acenderiam** | 11 | **23 — 0,9%** |

> **Por que a 1ª conta estava errada:** li `open_hour`/`close_hour` e ignorei
> `break_start`/`break_end`. O turno partido **existe e está preenchido** — a Unit 1 é
> `07:30-11:30` + `13:30-17:30` = **480 min/dia**, não 600. Contei 2h úteis a mais por dia.
> **A conclusão não muda** (0,9% está longe de painel vermelho), mas o número é 23.

- ✅ **O medo do "painel todo vermelho" não se confirma: só 11 acendem.** Escopo amplo é seguro — e
  agora por medição, não por chute. Isso liberou a decisão de escopo da [[CHAT-143]].
- 🔴 **O achado maior que a pergunta:** as 1.844 **não podem ser respondidas de graça** — toda
  resposta exige template. Passivo invisível: a conversa aparece aberta e o atendente descobre que
  não pode responder só ao tentar. **Reenquadra as 700 em que "o cliente falou por último"** — a
  maioria já está inalcançável sem HSM. Número registrado em **CHAT-98** (sugerir o template certo
  na retomada fora da janela), que é onde o assunto mora; **não criei tarefa nova**.
- **Simetria útil:** a Tozi ganhou 9 templates UTILITY em 22/09 (WABA hoje 11 utility × 49 marketing)
  e a régua confirmada contra a Meta é que utility **nomeia uma solicitação anterior do cliente**.
  Os 1.844 são o caso de uso que justifica a biblioteca.
- **Decisões fechadas na CHAT-143:** sinais da v1 = `meta_campanha` + `meta_imovel_codigo` +
  contagem de interação · cortes `<4h úteis → high`, `<1h útil → urgent` (conservador, ajustar
  depois de medir) · **todos os setores e canais** — sai de graça, porque `messaging_window` devolve
  `nil` em canal sem janela · **vocabulário nenhum**, os 4 níveis nativos como estão (decisão
  delegada a mim: "quente/frio" tem 2 níveis contra 4, mapa por conta é config que diverge, e o
  painel já renderiza com i18n; nome próprio de cliente vira override de i18n, não modelo de dados).
- ⭐ **Refinamento do Paulo que virou o teste principal: MEDIR é universal, SINALIZAR é restrito.**
  Calcular `minutos_uteis_na_janela` em toda conversa aberta; escrever `priority` só dentro da janela
  e passado o corte. E **a pressão de janela NÃO depende de qualificação** — com `priority = o mais
  alto entre qualificação e pressão`, conversa crua (cliente falou, ninguém respondeu, zero
  qualificação) vira `urgent` pelo relógio. Hoje `priority` só muda se alguém **opinar** (automação
  à mão ou copilot); **a pressão de janela é a única entrada que não precisa de julgamento** — nem
  humano nem de LLM. **O primeiro caso de teste é a conversa crua, não o lead qualificado.**
- ⚠️ **Ressalva do meu script:** li `open_hour`/`close_hour` e ignorei `break_start`/`break_end`, então
  se houver turno partido contei minutos úteis **a mais** e o `urgent` real é um pouco maior. A
  implementação deve usar `UnitAtendimento`, que já resolve turno partido e exceção.

### [2026-09-24] 🧮 PRIORIDADE DA FILA: os 3 ingredientes existem e ninguém juntou — CHAT-143 e CHAT-144

> **O pedido do Paulo:** lead que interagiu e respondeu **não é descartado** por não atender
> requisito — vai para "aguardando atendimento" **com ordem de prioridade**. E a classificação tem
> de servir setor que não é venda: não só quente/frio, mas urgente/alta/baixa. MCMV é público
> econômico de alto volume — **não é descarte, é `low`/`medium`**; muda a ordem, não a fila.

- ✅ **`Conversation#priority` é NATIVO e o painel JÁ CONSOME.** Enum `{low:0, medium:1, high:2,
  urgent:3}`, índice em `priority` e em `(status, priority)`; `CardPriorityIcon.vue`, filtro em
  `filterHelper.js`, ordenação `priority_desc_created_at_asc` no `ConversationFinder`. **Não precisa
  campo novo** — "quente/frio" é vocabulário de vendas para `urgent/high`, não coluna.
- ✅ **`Conversations::MessageWindowService#hours_remaining` já existe** e deriva do MESMO
  `messaging_window` do `can_reply?` — WhatsApp 24h, Instagram 24h ou 7d pela flag, TikTok 48h, API
  configurável. A conta regressiva acompanha o canal sozinha.
- ✅ **`UnitAtendimento` já resolve o expediente por data**, com exceção e **turno partido** — a Tozi
  é `07:30-11:30` e `13:30-17:30`. `Units::ScheduleEvaluator` já roda em produção.
- 🔴 **O que falta é só a junção:** ninguém escreve `priority` automaticamente (3 caminhos, todos
  manuais: `action_service.rb`, o copilot `change_priority_service`, e nada mais);
  `hours_remaining` tem **um** consumidor (`agent_runner_service.rb:288`, como
  `janela_horas_restantes` — **a IA sabe, o painel não**); e **nada cruza janela × expediente**.
- ⭐ **O insight do Paulo é mais forte que `hours_remaining`.** Cliente diz "ok, aguardo" às 7:00; a
  janela fecha 7:00 do dia seguinte; o expediente abre 7:30. `hours_remaining` diria **"23,9h
  restantes"** e pareceria tranquilo — **o tempo ÚTIL é zero**. A métrica que importa é
  **minutos de expediente restantes dentro da janela**, não hora de relógio. Deixar como primitivo
  reusável (`minutos_uteis_na_janela`): o SLA de pickup também vai querer.
- **O desenho: uma prioridade, duas entradas.** `priority` = o mais alto entre a **qualificação**
  (conteúdo) e a **pressão de janela** (relógio). A segunda **promove** — lead morno vira `urgent`
  quando o tempo útil acaba. É o que nenhuma medição de conteúdo pega.
- **Como a Tozi opera hoje (Paulo):** uma pessoa pega as conversas em "aguardando atendimento" e
  distribui à mão. O rodízio existe em código e o trabalho é feito por gente. Daí o **CHAT-144**:
  **480 handoffs (34,2%) ninguém assumiu**, 440 deles COM `AssistantLog` — a IA fez a parte dela.
  `sla_assumir_minutos` (30) e `repasse_automatico` (**false**) existem e estão desligados.
- ⚠️ **Ordem:** ligar `repasse_automatico` sem a guarda de dono repete a conv 194 da Catatau
  (16/09). A guarda existe (`guarda_de_dono.rb`, `repasse_service.rb`) e tem de subir junto.

### [2026-09-24] 🎯 O MCMV NÃO É PROBLEMA DE HANDOFF — A IA NUNCA MARCA. E dois comentários do código mentem

> **O Paulo esclareceu o desenho (24/09):** o papel da IA é qualificar para enriquecer a informação
> ao humano. Lead com sinal de compra, DENTRO do expediente, pode ser marcado como "aguardando
> atendimento" **e a IA continua a conversa** até alguém assumir. Não é dicotomia.

- ✅ **Isso já é o comportamento da plataforma.** `captain_can_respond?`
  (`response_builder_job.rb:988`) checa só duas coisas — status `pending`/`open` e o espelho captain
  ainda ser do assistente. **Não olha `aguardando_humano_desde`.** Conversa em "Aguardando
  atendimento" segue sendo respondida. Quem cala a IA é um humano pegar o `assignee`
  (`reset_agent_bot_when_assignee_present` zera o espelho).
- ⚠️ **DOIS COMENTÁRIOS DO CÓDIGO ESTÃO ERRADOS e me enganaram primeiro:**
  - `human_handoff_service.rb`, **cabeçalho**: *"a IA silencia"* — **errado**. O corpo do MESMO
    arquivo diz certo: *"NÃO solta o espelho — a IA continua dona/respondendo"*.
  - `followup_job.rb:132`: *"a IA para de cutucar **e de responder**"* — para de cutucar, não de
    responder.
  O marcador faz outra coisa: põe na fila, **para a cutucada**, não agenda follow-up preventivo, sai
  da auto-resolução.
- 🔬 **MEDIDO: são DOIS problemas, e eu tinha misturado os dois.**

  | População | Hipótese | Números |
  |---|---|---|
  | **21 MCMV** | **H1 — a IA nunca marca** | 17 sem log/degrau/marcador · 4 marcou |
  | **480 gerais** | **H2 — marca e ninguém puxa** | 440 das 480 TÊM `AssistantLog` de handoff |

  O mecanismo funciona: a IA chamou handoff **440 vezes em 30 dias**. O MCMV é problema de
  **critério**; os 480 são problema de **SLA de pickup**, da operação — merece tarefa própria.
- **Os 17 MCMV são idênticos:** `log=false degrau=false marcador=nao assignee=-`, de 10 a 31 dias.
  Os dois únicos com `log=true` (#63806 2d, #63656 4d) têm **assignee=107** — handoff funcionou e
  um humano pegou.
- ❌ **H3 (horário) caiu:** dos 39 com mensagem de cliente, **26 (67%) falaram entre 8h e 18h**.
  Dois terços dentro do expediente. Horário é fator minoritário, não a causa.
- 🔴 **O achado mais afiado: `marcador setado = 0` nos 45.** Os 17 MCMV **não estão em fila nenhuma**
  — nem em "Aguardando atendimento" (nunca houve marcador), nem com alguém (`assignee` nulo). Só
  `open` e esquecidos. **Não foi negligência do time: eles não apareciam em lugar algum.**
- **CHAT-126 reenquadrada** (comentário longo lá). A pergunta deixou de ser "transferir ou
  qualificar" e passou a ser **qual sinal dispara a marcação** — e, pela tese da auditoria, isso não
  pode ser linha de prompt (camada 1-3, não camada 4: medido 0/6, 0/6, 0/8). Candidatos que já são
  dado: `meta_campanha`, `meta_imovel_codigo`, renda informada, pergunta de entrada/financiamento,
  mais o recorte de expediente.

### [2026-09-23] 📋 O PLANO SAIU DA CONVERSA: `docs/PLANO-ACOES-2026-09-23.md` + CHAT-126..137

> **Próximo passo desta frente:** a decisão da conduta MCMV (**CHAT-126**). É a única coisa na fila
> que é dinheiro parado — ~25 leads de anúncio há 22-31 dias, sem assignee, notas 1 a 5.

- **Plano completo:** `docs/PLANO-ACOES-2026-09-23.md` — 20 ações em 7 blocos, cada uma com
  evidência, tamanho (P/M/G/D) e a decisão que a destrava. Versionado, o time lê.
- **12 tarefas criadas no gestão (projeto CHAT), todas com responsável Paulo:** 126 decisão MCMV ·
  127 `hybrid` com base vazia · 128 PR do harness · 129 PR do `disparo-guarda` · 130 PR do
  `fix-fotos-handoff-hml` · 131 PR do FactGuard · 132 repescagem dos 45 · 133 lead na lista do Vista ·
  134 card no pipeline · 135 re-medir baseline · 136 render/lint do prompt · 137 revisão amostral.
- **Responsável é o Paulo em todas, e isso está certo:** as 4 branches sem PR são **100% commits
  dele** (`disparo-guarda` 4 · `fix-fotos-handoff-hml` 10 · `resultado-tipado-de-tool` 15 ·
  `factguard-shadow` 1). O que pode ir para Nicolas/Thalysson são as de campanha (A15-A17) e higiene
  (A19-A20), **deliberadamente não criadas** — segundo turno.
- **6 tarefas antigas receberam comentário de cruzamento**, nenhuma reaberta: **CHAT-125** recebeu o
  levantamento do rodízio inteiro (era o que ela pedia) · **CHAT-109/110** seguem `Concluído` porque
  "construir" e "medir" foram feitos — faltou **entregar** (→128) e **re-medir** (→135) · **CHAT-106**
  depende de 128 · **CHAT-103** está metade feita (Tozi no ar; resta a Fábrica) · **CHAT-111** teve a
  fronteira de escopo acertada com 136.
- ⚠️ **O `comentar_tarefa` do MCP `spx-gestao` usa o parâmetro `texto`, não `comentario`** — erra
  quatro chamadas de uma vez com `{"erro": "faltou informar: texto"}`.

### [2026-09-23] 📊 VARREDURA DAS FRENTES + CHAMADOS PARADOS — 51 de 58 frentes mergeadas, e o que está no ar quase não é usado

> Levantamento pedido pelo Paulo. **Só leitura na `3.94.9.51`** (scripts em `/tmp`, nada escrito,
> nada enviado). Corte de deploy identificado com precisão.

- **O "deploy de 22/09 20h" é o restart do `chatwoot-web.1`:** `ActiveEnterTimestamp=2026-09-23
  00:00:09 UTC` = **22/09 20:00 Cuiabá**. HEAD naquele instante: `41318fd1a` (PR #227). Logo o **P0
  (PR #226, `fix/tool-result-tipado`) ESTÁ no ar** desde então — resolve a dúvida que ficou aberta.
- ✅ **CORRIGIDO 23/09 21h pelo Paulo — existe restart noturno e eu não sabia.**
  `chatwoot-restart-noturno.timer`: `OnCalendar=*-*-* 20:00:00 America/Cuiaba`, `Persistent=false`,
  reinicia **web e workers, nunca a VM**. Logo **não existe passo de deploy manual na Tozi**: a
  cadência é *mergeado e puxado antes das 20h → no ar naquela noite*. O restart de
  `2026-09-23 00:00:09 UTC` que eu li como "o deploy de 22/09 20h" **era este timer** — a conclusão
  sobre o P0 estar no ar segue certa, o mecanismo é que eu atribuí a uma ação humana. Os 5 PRs abaixo
  subiram às **20h de 23/09** (`ActiveEnterTimestamp = 2026-09-24 00:00:13 UTC`, HEAD `501d10eb0`).
  O que eu vi era uma **janela** entre o pull e o restart, não defeito.
- 🔴→✅ **5 merges estavam no disco sem rodar quando medi (14h-18h de 23/09):** #246 (EA-01 pedir conversa),
  #219 (t45 tela distribuição), #220 (t04 ações caladas), #221 (t05 exports), #236 (tema aba oculta).
  Reflog: 23/09 15:03/15:18/15:33/19:35 UTC, todos após o restart. **`db:migrate:status` = 0 down**,
  então restart é seguro e libera os 5. Worker reiniciou 23/09 06:21 UTC, também antes deles.
- **Frentes `spx/*`: 58 no `origin`, 51 mergeadas em `producao`, 7 fora.** A maior fora é
  `spx/fix-fotos-handoff-hml` com **10 commits de conserto de IA** parados (recursão infinita em
  `track_imoveis`, retry do Vista, follow-up viciado em `[IGNORAR]`, campo `Condominio` para separar
  fechado de avulso pelo dado, remoção de exemplos copiáveis das tools).
- **Mergeado ≠ em uso.** Medido na conta 6: eval 🟢 19.077 avaliações (última 23/09 17:07) ·
  NPS 🟢 15.836 respostas (2.100/30d) · flows 🟢 24 de 27 ativos · rodízio 🔴 **1 policy inativa,
  pool vazio, 0 states, 0 logs** · catálogo de produtos do rodízio 🔴 **0 linhas**.
- ⚠️ **DUAS LEITURAS MINHAS ESTAVAM ERRADAS, corrigidas em 23/09 com o Paulo:**
  - **Unidades está CERTO.** `Unit` = **filial** (um endereço com horário próprio que agrupa
    caixas) — a Tozi tem **uma**, então 1 linha é o número correto, não abandono. Conferido:
    "Tozi Imóveis", `America/Cuiaba`, coordenadas preenchidas, **7 working_hours** (grade
    completa), **23 exceções** (feriados), **5 das 6 caixas** vinculadas. Só falta
    `address_number` (coluna nova de 21/09) e 1 caixa sem unidade.
  - **Campanhas NÃO parou no teste.** `campaign_recipients` = **24.110 linhas**, e a campanha #29
    ("Mega Feirão — base completa") disparou **13.391 destinatários em 21 minutos** (08/09,
    17:29→17:50 UTC). As 10 "TESTE" eram o ensaio dela. **24.575 de 41.859 conversas** têm
    `campaign_id`. O motor funciona em escala; o que falta é **superfície de controle** (BACKLOG
    § Módulo Disparo).
  - **Lição:** contagem baixa numa tabela não é sinal de abandono sem antes entender a unidade de
    medida do modelo. Nos dois casos eu li o número antes de ler o `# comentário` do modelo.
- 🔴 **`knowledge_mode=hybrid` com ZERO documentos em 6 dos 9 agentes** — Bruna, Letícia, Marina,
  Rafa e Helena com `docs=0`, e só Júlia (20), Sofia (3) e Clara (1) têm base. O handoff só nomeava
  a Bruna; é regra dura apontando para fonte vazia em quase toda a frota da conta.
- **Chamados parados:** 2.543 conversas `open` (39.300 resolved). **700 têm o cliente falando por
  último** — 335 há 7-30 dias e 262 há mais de 30. **486 handoffs (34,2% de 1.421) ninguém assumiu**;
  96 dessas conversas seguem abertas. Do balde que o juiz já denunciou (`precisava_nao_fez`/`tardio`),
  **45 continuam abertas**.
- **Padrão dominante nos 45, e não é aleatório:** ~25 são leads de anúncio **MCMV / "entrada
  facilitada"**, IDs 51xxx-54xxx, 22 a 31 dias, **sem assignee**, com o mesmo enredo — a IA
  qualificou em profundidade e deu condição comercial em vez de transferir. Casa com o item
  `🟡 Simulação de financiamento na conduta MCMV — parado por decisão` do `BACKLOG.md`: a decisão
  parada está custando leads.
- **A medição pós-deploy não conclui, e o motivo não é falta de dado:** 202 conversas depois × 1.311
  antes (7d) — nota 7,78 × 7,83, limpas 73,76% × 74,07%. Nada se moveu porque **o P0 não era mudança
  de conduta**; ele tipa falha de ferramenta. `contradisse_tool` subiu (26,8 → 32,1 por 100) e
  `outro` saltou (13,8 → 34,0), os dois dentro do ruído de n=202.

**Armadilha registrada:** existem duas branches quase homônimas — `fix/tool-result-tipado` (virou o
PR #226 e está em `producao`) e `fix/resultado-tipado-de-tool` (carrega o **harness nível 1 + CI**,
`origin` tem, **sem PR**). Confundir as duas custa uma hora.

### [2026-09-22] 🟢 A TOZI GANHOU 9 TEMPLATES UTILITY — e a Meta aceitou os 9 · allowlist já estava ligada

> Onda 0 do plano de templates (CHAT-82), autorizada pelo Paulo. **Zero código** — usa a tela que já
> existe. Biblioteca vinda do *Manual de Templates de Utilidade para Imobiliárias* (v1.0, 21/09).

- **O gargalo do utility nunca foi a IA: era a prateleira vazia.** Antes disto a WABA da Tozi tinha
  **2 UTILITY, e um deles era o `hello_world` de demonstração da Meta** — ou seja, **um** utility real
  (`tozi_novo_numero`) contra 49 marketing.
- ✅ **9 criados, e a Meta manteve UTILITY em 9 de 9** (`previous_category` ausente em todos, zero
  rebaixado): `tozi_retorno_solicitado` · `tozi_confirmacao_visita` · `tozi_atualizacao_atendimento` ·
  `tozi_informacao_imovel` · `tozi_reagendamento_visita` · `tozi_pendencia_documental` ·
  `tozi_atualizacao_proposta` · `tozi_atualizacao_contratual` · `tozi_retorno_corretor`.
  **WABA hoje: 11 UTILITY × 49 MARKETING** (60 no total).
- **Criados 2 primeiro, de propósito**, para ver o veredito antes de queimar 9 nomes — nome de template
  apagado fica travado ~4 semanas na Meta. Os dois voltaram UTILITY, e aí os outros 7 saíram.
- **A régua do manual se confirmou contra a Meta:** o que passa como utility **nomeia uma solicitação
  anterior do cliente**. É a mesma linha que separava o `tozi_novo_numero` (sobreviveu) dos três
  rebaixados em [[meta-rebaixa-utility-para-marketing]].
- **Três regras da Meta respeitadas no gerador, com guarda que aborta antes de gastar o nome:**
  variáveis em ordem crescente no corpo · corpo não termina em variável (o texto do manual para
  confirmação de visita terminava, e foi ajustado) · toda variável leva exemplo.
- ✅ **Os 9 saíram APPROVED como UTILITY** (acompanhados por monitor externo até fecharem — **e
  precisar de monitor externo para isso é exatamente o argumento da Onda 2**, o webhook
  `message_template_status_update`). **Zero rebaixado**, o que distingue estes dos três antigos, que a
  Meta rebaixou justamente na aprovação.
- ✅ **`sync_templates` rodado:** o canal saiu de 51 para **60** templates e os 9 já estão no banco
  local. **A allowlist segue com 3 nomes de propósito** — o atendente não viu mudança, e marcar os 9
  é decisão do Paulo (expõe os templates ao time antes de ele saber quando usar cada um).
- 🔴 **CORREÇÃO minha: marcar os 9 na allowlist NÃO depende do deploy do #222.** A allowlist é código
  antigo, já em produção; só o cabeçalho de mídia depende do deploy. Registrei a correção na CHAT-94.
- 🔴 **CORREÇÃO de uma afirmação minha de ontem: a allowlist NÃO estava desligada.** A inbox 91 já tinha
  `allowed_template_names` com **3 nomes** (`tozi_encerramento_atendimento`, `tozi_venda_abertura`,
  `tozi_lancamento_interagir`). O atendente vê **3**, não 51. Consequência prática: **os 9 utility não
  vão aparecer no seletor enquanto não forem marcados** na tela de templates.
- ✅ **App ID da Meta gravado na inbox 91** (`whatsapp_app_id = 1147301410628990`), em
  `additional_attributes`, com backup em `/tmp/inbox91_addattr.bak-*.json` na VM. Aditivo e conferido:
  as demais chaves sobreviveram. **Só passa a ter efeito depois do merge + deploy do #222** — nenhum
  código em produção lê essa chave hoje.

### [2026-09-21] 🟢 TEMPLATE COM CABEÇALHO DE MÍDIA NUNCA FUNCIONOU — consertado no PR #222 · e a Meta rebaixou 3 utility sem ninguém ver

> Tarefa CHAT-82. O pedido original dizia "criar template na API oficial, hoje só consulta" — **falso**:
> serviço, rota, controller, API do front e as duas telas já existem. O que não existia era o upload.

- 🔴 **O defeito:** `TemplateBuilder.vue` pedia uma **URL** e a jogava em `example.header_handle`. A Meta
  não aceita URL nesse campo — exige um **handle** emitido pela Resumable Upload API dela. Resultado:
  **todo** template com cabeçalho de imagem, vídeo ou documento era recusado, com erro que não explicava
  nada. O i18n ainda prometia por escrito que a URL seria "usada pela Meta na aprovação".
- **A origem do bug, provável:** na **leitura** a Meta devolve uma URL nesse mesmo campo (está assim no
  `templateFixtures.js:274`, fixture do upstream). Quem escreveu o builder copiou o formato da leitura
  para a escrita. O campo é assimétrico.
- ✅ **[PR #222](https://github.com/Dev-Simplex/chatspx/pull/222)** contra a `homologacao`
  (`PauloSeze/templates-oficiais`, 5 commits, 12 arquivos, +599/−29, `MERGEABLE`). **Não mergeado, não
  deployado.**
- 🟢 **Dois fatos que só a execução revelou, e que a doc não deixa clara** — provados contra a API real
  da Tozi antes do commit (upload não cria template; nada foi gravado):
  1. O upload roda contra o **App ID**, não contra a WABA. Medido: WABA da Tozi = `905788818829319`,
     App ID = `1147301410628990`. ⚠️ **A nota do STATE de 18/08 que chamava `1147301410628990` de
     "WABA TOZI" está ERRADA** — é o App ID.
  2. O segundo passo exige `Authorization: **OAuth**`. `Bearer`, usado em todo o resto da Graph API, é
     recusado ali. (O script de junho mandava o token na query string; o header é melhor e não vaza em
     log de URL — a lição do vazamento da `site_api_key` em 12/09.)
  3. **O token do próprio canal autentica o upload num app diferente do WABA** — não precisa de
     credencial nova, só do App ID.
- **Onde o App ID mora:** `inbox.additional_attributes['whatsapp_app_id']`, mesmo caminho do
  `allowed_template_names`. **Não** em `provider_config`, porque alterar o provider_config dispara
  `validate_provider_config`, que bate na Meta e pode invalidar credencial de cliente.
- **Sem App ID o cabeçalho de mídia nem aparece como opção**, e a tela diz o que falta — falha visível
  em vez de deixar montar o template e estourar no fim (mesmo princípio do #136).
- 🔴 **ACHADO DE DINHEIRO: a Meta rebaixou 3 templates de UTILITY para MARKETING e ninguém via.**
  `previous_category` e `rejected_reason` **só chegam se forem pedidos no `fields`** — e não eram.
  Medido na WABA da Tozi: 51 templates, **49 MARKETING × 2 UTILITY** (e um dos dois é o `hello_world`
  de demonstração da Meta, então **sobra 1 utility real**). Os rebaixados: `tozi_convite_whatsapp`,
  `tozi_lead_meta_utility` e `tozi_followup_horario_combinado`.
  - **O padrão que separa quem sobreviveu:** o `tozi_novo_numero` ficou utility porque **nomeia uma
    solicitação anterior do cliente** (*"você pediu pra eu te chamar neste número sobre {{2}}"*). Os três
    que caíram perguntam se a pessoa pode conversar. O `tozi_followup_horario_combinado` abre com
    *"tudo bem?"*, que é literalmente o 1º item da tabela de textos inadequados do manual de utility.
  - ⚠️ **Erro meu de leitura, pego antes de virar afirmação:** a primeira medição deu "0 reclassificados"
    — porque eu não tinha pedido o campo, não porque o fato não existia. Ausência de campo não é
    ausência de fato.
  - Detalhe: `rejected_reason` volta **`'NONE'` nos 51** (só tem valor quando o status é REJECTED) e
    `quality_score` volta `UNKNOWN` em todos (volume por template baixo demais). A tela trata os dois.
- 🟢 **JÁ EXISTIA e ninguém usava: `allowed_template_names`** — a allowlist que esconde template do
  seletor do atendente está pronta ponta a ponta (tela, store e getter). Hoje o atendente da Tozi vê
  **51 templates** na lista. Ligar é config, não código.
- **CI (.232):** pasta `spec/services/whatsapp/` **353/0 contra baseline 339/0** (+14, zero regressão) ·
  os 3 specs do PR **23/0** · rubocop **0 no ramo (7 arquivos) × 0 no baseline (3)** — os 4 arquivos
  novos não somam offense · **mutação:** `Bearer` no lugar de `OAuth` faz **exatamente 1 exemplo falhar**.
- ⚠️ **Dois tropeços meus na CI:** (1) o factory `channel_whatsapp` **já cria a inbox** no
  `after(:create)` — a minha `let!(:inbox)` criava uma segunda, e `channel.inbox` devolvia a primeira,
  então o app id ia para a inbox errada (9 exemplos vermelhos); (2) a linha do `fields` passou de 150
  chars e quebrou o `Layout/LineLength` — virou a constante `LIST_FIELDS`.
- ⚠️ **`--no-verify` nos commits e no push:** o husky da worktree não está bootstrapado
  (`.husky/_/husky.sh` ausente), então o hook **não roda** — mesma situação do #135. Os dois checks dele
  foram rodados à mão: `bin/validate_push` exit 0 e `check_vue_template_refs.py` com 183 arquivos e
  0 problemas.
- ⏭️ **O escopo foi ampliado pelo Paulo em 21/09 e vira ondas próprias** (tudo na CHAT-82): webhook de
  aprovação (`message_template_status_update` + `template_category_update`, que avisaria a
  reclassificação) · editar template · **placeholder atrelado a campo real, autopreenchido no disparo**
  (é onde já houve dano: em junho 6 pessoas receberam *"Oi , sou a Kettlen"*) · IA que escreve o texto ·
  **o classificador de categoria, que o Paulo está construindo em paralelo com o Jev** — o PR deixa o
  contrato `avaliar(...)` esperando · carrossel e demais formatos · e a retomada assistida fora da
  janela de 24h, que é o problema de origem: o atendente só tem marketing na mão.
- ⏭️ **Gabarito para medir o classificador:** `spx-os/clientes/tozi-docs/templates/gabarito-meta-2026-09-21.json`
  (51 templates com o rótulo da própria Meta). ⚠️ Está 49/2 — responder "marketing" sempre acerta 96%,
  então acurácia bruta não mede nada; o que vale é precisão na classe rara. Aprendizado em
  `spx-os/aprendizados/meta-rebaixa-utility-para-marketing.md`.
- ✅ **Sem sobras na `.232`:** as worktrees de CI, os `.env` copiados e os scripts de mutação foram
  removidos ao fim.
- **Mutação, completa:** sem mutação **23/0** · `Bearer` no lugar de `OAuth` → **1 falha** · `fields`
  sem os campos novos → **1 falha** · guarda fraca no upload (volta ao `blank?`) → **1 falha**. Cada
  quebra derruba exatamente o exemplo que a cobre, e nenhum outro.

### [2026-09-15] 🔴 CLIENTE NA PORTA FECHADA NO FERIADO — a causa é uma decisão minha, escrita no código

> Paulo, com a conv **9022**: *"A IA fica marcando horário com cliente, fazendo ele vir até a
> empresa e não ser recebido. Foi justamente no feriado municipal que havíamos acrescentado no
> /units."*

- **O desfecho, na conversa:** 14/09 12:52 a Bruna disse *"Te espero aqui a partir das 13h30"*.
  O cliente chegou **13:33**, escreveu *"Estou aqui"*, depois *"Não tem ninguém ainda / Vai abrir?"*
  e às **13:55** *"estou indo embora"*. O Adrian pediu desculpas no dia seguinte, nomeando a causa:
  *"foi uma falha da nossa assistente virtual"*.
- ✅ **O time cadastrou CERTO:** `UnitException #7` — "Aniversário da cidade de Sinop", categoria
  `feriado`, 14/09/2026, `closed_all_day: true`. E a ferramenta responde certo **quando se pede a
  data**: `quando: 'ontem'` devolve *"Segunda-feira, 14/09/2026: fechada (exceção nesta data:
  Aniversário da cidade de Sinop)"*.
- 🔴 **Não foi uma conversa: foram 6 convites ao escritório em 4 conversas no dia**, mais **2
  marcados na véspera (domingo 13/09) para as 07h30 de segunda**:

  | conversa | consultou a unidade? | o que houve |
  |---|---|---|
  | 9022 | **nunca** | marcou 13h30 · cliente esperou 22 min e foi embora |
  | 11212 | **nunca** | *"amanhã você pode passar a partir das 07h30"* |
  | 41997 | sim, `quando: "hoje"` | consultou **domingo**, prometeu **segunda** |
  | **42025** | sim, **sem data** | recebeu a **grade habitual** num dia fechado |
  | 42015 · 42032 | **nunca** | *"passa aqui no escritório"* |

- 🔴 **A CAUSA É MINHA, e está escrita no `Spx::UnidadeEventos`:** *"FERIADO fica de fora de
  propósito: ele só muda o horário, e a linha de horário já responde por ele."* **A premissa é
  falsa** — a linha de horário só responde para uma data RESOLVIDA. Sem data pedida o retorno traz
  *"Nenhuma data foi pedida, então abaixo está o horário habitual"* + *"seg a sex … 13:30 às
  17:30"*. 14/09 era segunda. **A conv 42025 é a prova**: ela chamou a ferramenta, sem data, e foi
  induzida ao erro pelo retorno.
- **Escala do convite (45 dias):** 52 convites ao escritório em 45 conversas · **15 cravam quando**
  (hora/hoje/amanhã), 37 só descrevem o processo · **7 num domingo**, dia em que a unidade não
  abre · 19 fora do expediente.
- ✅ **[PR #141](https://github.com/Dev-Simplex/chatspx/pull/141)** (`PauloSeze/unidade-fechada-no-retorno`,
  3 commits), duas metades porque as duas aparecem no dado: (1) **feriado passa a entrar na linha de eventos**, que
  sai em toda consulta com ou sem data — rótulo nomeia a causa, o `funcionamento` que já existia diz
  o efeito (*"unidade FECHADA nesse período"*); (2) **o retorno do `buscar_imovel` carrega o
  fechamento** (janela curta de hoje+amanhã, antes da regra, onde sobrevive ao corte de 700 da nota),
  porque **3 das 5 conversas nunca chamaram a ferramenta de unidade** — o retorno que elas leram foi
  o da busca, que é quem manda passar no escritório.
- 🟢 **MEDIDO em produção (N=6, transação revertida), e o conserto muda o comportamento:**

  | cliente pergunta se pode passar hoje | avisou o fechamento | convidou **sem** avisar |
  |---|---|---|
  | hoje | 0/6 | **6/6** |
  | com o aviso | **6/6** | **0/6** |

  E não é calar: ela **redireciona** — *"hoje o escritório está fechado — é aniversário da cidade.
  Mas amanhã você já consegue passar pra retirar a chave, até as 16h30."* O lado A reproduziu a
  9022 palavra por palavra: *"Pode sim! Você passa aqui no escritório…"*
- **CI (.232):** ramo **384/0** contra baseline **369/0** (+15 exemplos, zero regressão) · rubocop
  **18 = 18** · **mutação: 9 falhas** contra o código velho — os 6 do serviço e os 3 do aviso; os de
  não-regressão (rótulo de evento/manutenção, janela curta, evento que não fecha) passam dos dois
  lados, como contraprova.
- ⚠️ **Erro meu de CENÁRIO na 1ª medição** (9ª vez que detector/cenário grosseiro me dá leitura
  errada): o A/B deu "aviso não muda nada, 6/6 dos dois lados" — porque o aviso que injetei dizia
  *"seg 14/09"*, **ontem**, e o modelo corretamente o ignorou. Refeito com a data resolvida em
  tempo de execução. **A data do cenário se valida contra o relógio antes de virar número.**
- ⏭️ **NÃO fecha a classe, e isso é decisão do Paulo:** em 45 dias são **52 convites ao escritório**
  e a maioria não passa pela ferramenta de unidade. O PR cobre o caminho que essas conversas leem
  (busca de avulso de locação com a condição configurada). A rede completa é uma **guarda
  determinística na saída** — a IA não poder afirmar dia/hora de atendimento em dia fechado, mesma
  família da que já troca endereço inventado pelo real. Mais cara, mexe na saída, frente própria.

### [2026-09-12] 🟢 O DOMÍNIO DO SITE SAIU DO CÓDIGO DA FROTA — config aplicada na conta 6 + PR

> Paulo, depois da explicação da dívida: *"Então configure e remova"*. Ordem invertida seria
> incidente: remover antes de configurar deixaria a Tozi com **todo link de imóvel quebrado**
> (`https://www./imovel/...`), porque ninguém tinha o campo preenchido.

**Passo 1 — CONFIGURADO em produção (conta 6), sem mudança de comportamento:**

- `AccountIntegration` provider `vista` da conta 6 ganhou `site_domain = toziimoveis.com.br` —
  exatamente o valor que a constante dava. O que muda é que passa a ser **declaração da conta**,
  não coincidência.
- ⚠️ **Correção de um diagnóstico meu:** eu havia dito que a conta 6 "não tem config nenhuma".
  Falso — eu consultei `integrations_hooks`, que é o **modelo errado**. O certo é
  `AccountIntegration`, e ela já tinha o registro `vista` (com `site_api_key`, e `enabled=false`,
  que **não** gateia a leitura — `integration_setting` lê as settings direto).
- **Verificado depois da escrita:** `site_domain` resolvido e `fallback_url` **idênticos** aos de
  antes · `site_api_key` preservada · backups em
  `/tmp/account_integration_vista_c6.bak-20260912143224.json` (e `...143253`).

**Passo 2 — ✅ [PR #136](https://github.com/Dev-Simplex/chatspx/pull/136) ABERTO**
(`PauloSeze/site-domain-por-conta`, 4 commits): `DEFAULT_SITE_DOMAIN` (o domínio de UM
cliente em código de frota) **removido**. Sem config, `site_domain` é `nil` e a ausência é tratada
onde importa: `build_url` → nil · `site_api_url` não deriva `https://www./...` · `track_urls` não
grava nil no `urls_imoveis` (mas segue gravando `dados_imoveis`, que é o que alimenta a guarda de
preço) · a linha da listagem sai sem link e sem pontuação solta. **Falha visível no lugar de link
errado.**

- **CI (.232):** suíte de tools **373/0** contra baseline **369/0** (+4 exemplos, zero regressão) ·
  rubocop **19 = 19**, histograma idêntico · **mutação: exatamente os 4 exemplos novos falham**
  contra o código velho.
- 🔴 **A CI pegou um defeito REAL meu, pelo spec que eu mesmo escrevi:** o `track_urls` saía em
  `return if novos.empty?` — sem domínio o mapa de URLs nasce vazio, então o **`dados_imoveis`
  também não era gravado**. Uma conta sem domínio ficaria sem a guarda de preço, que não depende
  de link nenhum. Os dois mapas são independentes; a saída antecipada passou a olhar os dois.
- 🔴 **E um erro no MEU script de CI:** ele fazia `fetch` só da branch, nunca da `homologacao`.
  Baseline e mutação rodaram contra uma cópia **anterior ao #134** — baseline deu 358 em vez de
  369 e a mutação "acusou" specs que a homologação já tem. **Eu teria publicado comparação falsa.**
  Regra: fetch das DUAS refs antes de comparar.
- **Os dois PRs compõem e não conflitam** (arquivos disjuntos): com o #136, numa conta sem domínio
  o #135 deixa de montar ficha em vez de montar a ficha do acervo errado. Registrado como
  comentário no #135.
- **Exposição real do default até aqui: ZERO.** Medido nas duas boxes — nenhuma outra conta tem
  `property_ref_context`, `site_domain` ou integração Vista. Era dívida com relógio (o próximo
  cliente imobiliário), não incidente.
- ⏭️ **Irmãs que ficam, mesma classe:** `DEFAULT_VISTA_BASE_URL`, `DEFAULT_OFFICE_LAT/LNG/NAME`
  (a dívida do pin, já registrada) e `DEFAULT_GEO_CITY`. Mesmo caminho: configurar a conta, depois
  remover — cada uma com seu consumidor.

- 🔴 **ERRO MEU DE SEGURANÇA NESTA SESSÃO:** um script de diagnóstico meu **imprimiu a
  `site_api_key` da Tozi em texto claro**. O produto está correto — `site_api_key` ESTÁ em
  `AccountIntegration::SECRET_KEYS` e a API mascara (`masked_settings` no jbuilder). Eu é que
  chamei `AccountIntegration.settings_for`, o acessor **interno**, que devolve o valor cru, e não
  mascarei aquela linha. ⏭️ **Recomendado rotacionar a chave do site da Tozi.** Regra para script
  de inspeção: imprimir **chaves**, nunca valores — e quando precisar do valor, mascarar na origem.


### [2026-09-12] 🟢 PR #135 — a ficha do imóvel passa a sair também pelo LINK · e a premissa anti-invenção escrita

> Paulo: *"Sim, abra PR, mas como fazer com que um agente não invente dados? Isso deveria ser uma
> premissa clara."* O PR é o conserto do caso; a premissa é o registro abaixo.

- ✅ **[PR #135](https://github.com/Dev-Simplex/chatspx/pull/135)** contra a `homologacao`
  (`PauloSeze/ficha-imovel-por-link`, 3 commits). O `PropertyRefContextService` — que **já existia
  e já está LIGADO na conta 6** (`property_ref_context = true`) — só reconhecia `(Ref: NNNN)`.
  Quem cola o **link** não gerava ficha, e era esse o caminho da 41803.
- **Medido em produção, N=6, estado real da 41803, transação revertida:**

  | cliente manda só o link | inventou preço |
  |---|---|
  | hoje | **2/6** (R$ 2.500 — valor que também não existe) |
  | com a ficha | **0/6** |

- 🔴 **A medição do outro lado quase fez o PR piorar o produto:** com a ficha no contexto o agente
  **deixa de chamar a busca**. Como a ficha não trazia condomínio, a resposta ficava certa e **mais
  pobre** que a de hoje — sumia R$ 731,55/mês da conta do inquilino. Corrigido no 2º commit
  (`ValorCondominio` + `format_brl` deixando de arredondar, que publicaria **732**):

  | cliente pergunta o valor | aluguel | condomínio |
  |---|---|---|
  | hoje (busca dispara) | 6/6 | 6/6 |
  | ficha sem condomínio | 6/6 | **0/6** |
  | **ficha com condomínio** | **6/6** | **6/6** |

- **CI (.232):** spec **13/0** (o serviço não tinha spec nenhum) · rubocop **4 = 4**, histograma
  idêntico cop a cop, as 4 pré-existentes e o spec novo somando 0 · **mutação: 6 falhas** contra o
  código velho — 4 do link e 2 dos valores, com o do condomínio provado pelo caminho `Ref:` para
  isolar a mudança de valores da mudança de link.
- ⚠️ **Dívida pré-existente que o PR encosta:** `site_domain` cai num `DEFAULT_SITE_DOMAIN`
  **hardcoded com o domínio de um cliente** no concern compartilhado, e **nenhuma conta o
  configura** — a 6 inclusive. Para a Tozi dá certo por coincidência do default. Conserto barato:
  preencher `site_domain` por conta. Não mexi (a constante é lida por todo o caminho de URL).
- ⚠️ `--no-verify` nos commits: o husky da worktree não está bootstrapado (`.husky/_/husky.sh`
  ausente), então o hook **não roda** — não é check falhando. Lint e specs rodaram na CI.

**A PREMISSA (resposta à pergunta do Paulo), com os números que este projeto já produziu:**

- 🔴 **Conduta escrita no prompt NÃO segura invenção** — medido à exaustão aqui: cutucada 0/6 em 3
  formulações · perguntar o nome 0/6 em 3 · locação na Júlia 0/8 em 3 versões · condomínio, nenhuma
  versão moveu o ponteiro. **Premissa não é frase; é propriedade do sistema.**
- **A premissa em uma linha:** *nenhum fato do acervo (preço, endereço, código) sai na fala sem ter
  ENTRADO por um caminho determinístico nesta conversa.* Quatro camadas, ordenadas por quanto
  dependem de o modelo cooperar:
  1. **Dar o fato antes de ele precisar inventar** — é o #135. Não depende de obediência.
  2. **Instrução junto do dado** (retorno de ferramenta, não prompt) — #134 levou o horário de
     retirada de 0/6 a 6/6; a mesma informação no prompt dava 0/6.
  3. **Não entregar o que não pode vazar** (máscara) — endereço em venda, #75.
  4. **Guarda determinística na saída** — a única que não depende do modelo. Já existem duas:
     `fix_office_address` (troca endereço inventado pelo da unidade) e `fix_property_links`
     (remove link inventado e derruba link cujo preço citado não bate).
- 🔴 **O buraco estrutural que a 41803 revelou: as guardas de saída são FAIL-OPEN.**
  `fix_property_links` só roda se a resposta tem link · `preco_desmente_link?` só opina se há
  `dados_imoveis` · a trava de fotos só age se `codigos_buscados`/`urls_imoveis` não está vazio.
  **Conversa sem busca = as três dormem** — a premissa vale onde já há procedência e falha
  exatamente onde ela falta, que é quando o risco é maior.
- ⏭️ **Próximo passo barato e de alto retorno:** a ficha REGISTRAR o código que resolveu em
  `urls_imoveis`/`dados_imoveis`. Um ponto de escrita acorda as três guardas de uma vez. Fora do
  #135 de propósito (o serviço roda no builder, caminho de leitura, várias vezes por turno).
- ⏭️ **Guarda de preço em texto (sem link) — desenhar com dado, não com regex às cegas:** dos 831
  casos de "preço sem busca" em 30 dias, **543 são a copy do MCMV** ("a partir de R$ 500") e quase
  todo o resto é a IA ecoando o aluguel que o CLIENTE paga. Detector grosseiro ali estraga centenas
  de mensagens legítimas — e detector grosseiro já me deu leitura errada **8 vezes** neste projeto.


### [2026-09-11] 🔴 CONV 41803: R$ 2.400 numa casa de R$ 3.200 — a causa é ACÚMULO de contexto, não o resumo

> Paulo: *"IA passou valor de R$ 2.400 para uma casa de R$ 3.200??????"*. O imóvel é real; o
> preço não existe em lugar nenhum.

- **O caso:** o cliente mandou **só o link** do 9412. A Bruna respondeu em 56s — *"3 quartos
  (1 suíte), 2 vagas de garagem, por R$ 2.400 de aluguel"*. No Vista: Casa, Santorini Residence,
  3q/1st/2vg, **ValorLocacao 3200** + condomínio **731,55**. Acertou os três atributos e errou o
  preço.
- 🔴 **Ela não leu nada: `buscar_imovel` foi chamada ZERO vez na conversa.** As ferramentas do
  atendimento foram `salvar_info_lead`/`atualizar_resumo`/`transferir_para_agente` (Clara) e
  `enviar_fotos_imovel`/`enviar_localizacao_imovel` (Bruna) — **nenhuma devolve preço**. E não há
  casa a R$ 2.400 no Santorini: as três de locação são **4.500, 3.900 e 3.200**.
- **A causa, isolada com N=6 por variante** (mesmo turno, transação revertida):

  | contexto da conversa | buscou | preço |
  |---|---|---|
  | vazio (só o link) | **6/6** | 6/6 certo |
  | **controle: 6 atributos irrelevantes** | **6/6** | 6/6 certo |
  | `sobre_cliente` sozinho | 6/6 | 6/6 |
  | `tozi_status_lead` sozinho | 6/6 | 6/6 |
  | `ia_transferencias` sozinho | 6/6 | 6/6 |
  | os dois últimos juntos | **4/6** | 4/6 |
  | os três juntos (= estado real pós-triagem) | **0/6** | 2/6 inventaram **R$ 2.500** |

- 🔴 **DUAS hipóteses minhas caíram, a segunda pelo código:** (1) *"o resumo da Clara faz a Bruna
  se sentir informada"* — isolado ele dá 6/6; (2) pior, **`resumo_atendimento_ia` nem chega ao
  modelo**: o `sem_maquinario` do `AgentRunnerService` o remove (lista `MAQUINARIO`), junto de todo
  `followup_*` (prefixo) e `*_imoveis` (sufixo). **Eu publiquei a hipótese antes de ler o filtro.**
- **O controle é o que fecha o diagnóstico:** 6 atributos inventados, sem relação com imóvel, dão
  **6/6**. Então **não é volume de contexto — é conteúdo**. Os três campos que sobrevivem ao filtro
  dizem, cada um à sua maneira, que o lead já foi triado e caracterizado; somados, a IA conclui que
  a fase de descoberta acabou e parte para relacionamento **sem consultar o acervo**. Bate com a
  pesquisa de 28/08: a adesão cai com a CONTAGEM de condições, não com o tamanho de cada uma.
- ⚠️ **Furo vizinho que o caso expôs — a trava anti-alucinação de fotos é FAIL-OPEN:**
  `if vistos.any? && !vistos.include?(cod)`. Sem nenhuma busca na conversa, `codigos_conhecidos`
  volta **vazio** e a trava **não age**. Aqui deu certo por sorte (o código veio do link do
  cliente); com código suposto, a foto sairia errada e nada impediria. É a mesma trava que segurou
  a casa inventada da 4809 — ela só passa a existir depois que alguém buscou uma vez.
  ⚠️ Ela vive em `Captain::Tools::ImoveisConhecidos` e serve **duas** ferramentas
  (`enviar_fotos_imovel` e `apresentar_imoveis`): o conserto do fail-open vale para as duas.
- **Escala (30 dias, conta 6):** 831 mensagens da IA com preço sem busca prévia — mas **543 são o
  *"a partir de R$ 500"* do MCMV** (vem do criativo do anúncio, legítimo) e quase todo o resto é a
  IA **ecoando o aluguel que o próprio cliente paga**. Filtrado isso, **a 41803 é o único caso
  visível de preço de imóvel da Tozi afirmado sem consulta**. É raro — e caro.
- ⏭️ **Conserto recomendado (NÃO executado, decisão do Paulo):** a exigência de consultar tem que
  chegar **junto do dado**, não no prompt — o **retorno da `transferir_para_agente`** é o ponto de
  decisão natural (é lido no instante em que a Bruna assume) e deve dizer que o imóvel citado ainda
  não foi consultado. Mesma lição do #134. Alternativa mais barata e parcial: mover
  `sobre_cliente` e `tozi_status_lead` para o `sem_maquinario` — eles servem ao painel do time, não
  ao agente.
- ⚠️ **Operacional:** o cliente perguntou às **17:35** o valor final com IPTU + condomínio e ficou
  **sem resposta**; conversa aberta com a **Evellyn** (time de locação). Ele saiu com R$ 2.400 na
  cabeça e o valor é **3.200 + 731,55**.


### [2026-09-11] ✅ #134 LIGADO NA BRUNA — horário de retirada 0/6 → 6/6 · e o 4/6 do harness era variância

- **Ligado em produção:** `condicao_visita_avulso = ["visita a imóvel avulso", "retirada e entrega
  de chave"]` na Bruna (14) + passo a passo **removido** do prompt dela. Backups
  `/tmp/assistant_14_{ins,config}_liga134.bak-20260911180411`.
- **Medição ao vivo:** documento com foto **5/6** · devolução no mesmo dia **5/6** · **horário de
  retirada certo 6/6 (era 0/6)** · fechamento 0/6.
- 🔴 **O harness acusou "visita em condomínio" 4/6 (piso 5) e eu ia reverter.** Antes disso, **A/B
  com N=8 de cada lado no cenário byte a byte igual ao do YAML: atual 7/8 × anterior 8/8** — uma
  rodada de diferença. E o instrumento matou a hipótese de contaminação: **`blocoAvulso` ausente
  nas 8 rodadas**, ou seja o código novo **nem roda** nesse cenário (o imóvel é de condomínio).
  Rodado de novo, o harness voltou **com todos os cenários dentro do piso**. **Não revertido.**
- ⚠️ O placar exato do cenário de condomínio na 2ª rodada **não ficou registrado** — meu `tail`
  cortou a saída. O que está provado é *"nenhum abaixo do piso"* + o A/B.


### [2026-09-11] 🟢 A REGRA DE VISITA CHEGA JUNTO DO IMÓVEL — e a medição achou dois defeitos meus antes do commit

> Paulo, depois da reversão de hoje de manhã: *"Faz"* o PR do conserto em código. Branch
> `PauloSeze/visita-avulso-unidade` (worktree `Temp/finalidade`, base `origin/homologacao` `4b7b4b63e4`).

- **Desenho:** quando o `buscar_imovel` devolve imóvel **[AVULSO]** em busca de **locação**, o
  próprio retorno traz as condições da unidade. O **nome** das condições é config do assistente
  (`condicao_visita_avulso`, nome OU lista) — código compartilhado não sabe como cada cliente chama a
  regra. Só com **uma** unidade ativa. Injetado em `format_listings`, por onde passam os **sete**
  ramos de listagem (comum, por código, ampliado, três geográficos, por título). Em venda não entra.
- 🔴 **Defeito 1, achado na prova contra a produção:** anexei a regra **no fim** do retorno. Ela caía
  na posição **711** do retorno por código e **1565** do comum — fora do corte de **700** que a
  `ToolContextNote` aplica ao turno seguinte, e no comum fora até dos **1500** do registro da
  chamada. Resultado: documento 6/6, mas mesmo dia **3/6** e regra no contexto do "quero ver"
  **0/6**. **Movida para antes da lista → contexto 6/6.**
- 🔴 **Defeito 2, achado lendo as respostas:** a condição de visita diz *"no horário de retirada de
  chave"*, e esse horário mora na **condição vizinha**. Com só uma no retorno, **4 de 6** respostas
  inventaram o horário pela grade de funcionamento. **O defeito é anterior ao código:** a produção de
  hoje (texto no prompt: "dentro do horário de atendimento") dá o fechamento em **5 de 6**. **Config
  em lista (visita + retirada) → 6/6 com o horário certo.**
- **Medido na produção, prompt da Bruna SEM o passo a passo, transação revertida, N=6, dois turnos
  reais (busca por código → "gostei, quero ver"):**

  | | produção atual | só visita | lista |
  |---|---|---|---|
  | documento com foto | 5/6 | 6/6 | **6/6** |
  | devolução no mesmo dia | 5/6 | 6/6 | **6/6** |
  | horário de retirada certo | 0/6 | 0/6 | **6/6** |
  | deu o fechamento | 5/6 | ≥1/6 | **0/6** |

- ⚠️ **Detector grosseiro de novo** (8ª vez): contou como "certo" resposta com o 16h30 e o sábado
  errado, e como "faltando sábado" uma que dizia *"até 16h30 hoje (sexta)"* — que é certa. Todas as
  classificações da tabela foram conferidas contra a frase real.
- **CI definitiva (.232, sobre `4b7b4b63e4`):** pasta de tools **369/0** contra baseline **358/0** ·
  rubocop **idêntico ao baseline, cop a cop** · **mutação A** (código da homologação + spec novo):
  falham **os 6 positivos** · **mutação B** (condições NO FIM, o defeito da produção): falham
  **exatamente os 2** de posição e de contrato com o contexto; os outros 9 passam.
  - ⚠️ Três tropeços meus no caminho, todos pegos antes do commit: (1) `update_all` num spec gerou
    `Rails/SkipsModelValidations` → trocado por `update!`; (2) `regras_de_visita` estourou
    **complexidade 8/7** → extraídos `nomes_de_condicao` e `unidade_unica`, mesmo retorno; (3) **o
    gerador do mutante falhou DUAS vezes por escape de barra invertida atravessando heredoc**, e nas
    duas o rspec rodou contra o código final e deu "0 falhas" que não provava nada — só valeu na 3ª,
    com arquivo `.py` real e `chr(92)`, e com abort explícito se o mutante não existir.
- ✅ **[PR #134](https://github.com/Dev-Simplex/chatspx/pull/134)** aberto contra a `homologacao`
  (branch `PauloSeze/visita-avulso-unidade`, commit `effebbdf14`, 2 arquivos, +170/−1). **Não
  mergeado, não deployado** — isso é do Nicolas.
- ⚠️ **Sobras:** `/tmp/ci-urbase` na `.232` (cópia de ontem, não worktree — remover exige `rm -rf`,
  não feito sem pedido) · na VM da Tozi, os scripts de prova em `/tmp` (`prova_definitiva.rb`,
  `horario_visita.rb`, `va_buscar_imovel_tool.rb`…) — os backups `.bak` de prompt e unidade ficam de
  propósito, são a reversão.
- ⏭️ **Depois de merge + deploy (Nicolas):** ligar na Bruna `condicao_visita_avulso =
  ["visita a imóvel avulso", "retirada e entrega de chave"]`, **aí sim** tirar o passo a passo do
  prompt dela, e remedir. O código nasce desligado.
- ⚠️ **Limite declarado:** numa busca cruzada (Júlia buscando locação), o aviso de finalidade (~300
  chars) vem antes das condições (~500) e a soma passa dos 700 da nota. Nesse caso ela transfere e a
  Bruna refaz a busca.


### [2026-09-11] 🔴→↩️ PASSO A PASSO DA VISITA: migrei para a unidade, a medição caiu, REVERTI o prompt

> Paulo confirmou as regras do balcão para migrar: documento com foto, devolução no mesmo dia, e
> "não agendamos nem reservamos". Tentativa feita com as duas linhas de base antes, e desfeita.

- **Onde vivia:** só na **Bruna**, seção `# Visita e chave`, e amarrado a avulso × condomínio —
  "não agendamos" vale **só para avulso** (condomínio fechado é agendado e acompanhado, régua de
  28/08). Por isso a condição cadastrada traz a exceção por extenso.
- **Linha de base (09:49):** harness de visita **4 cenários 6/6** · fato na resposta: documento com
  foto **5/6**, mesmo dia **5/6**, consultou `buscar_unidades` **1/6**. O harness só exige "chave"
  ou "escritório": **ele não mede o fato que eu ia migrar** — por isso a medição própria.
- **Migração (09:52):** condição *"visita a imóvel avulso"* na unidade + parágrafo da Bruna trocado
  por "consulte a buscar_unidades e explique pelo que ela devolver" (mantendo o *"não existe
  agendamento nem reserva"*, que é o gatilho de conduta).
- 🔴 **Depois (09:55):** harness ainda dentro do piso (condomínio 6/6 → 5/6) — **mas documento
  5/6 → 3/6, mesmo dia 5/6 → 3/6, e a consulta NÃO subiu (1/6)**. As respostas viraram *"retira a
  chave e conhece quando for melhor pra você"*, sem documento e sem prazo de devolução.
- ↩️ **Revertido (09:57), byte a byte:** prompt da Bruna restaurado. **A condição na unidade FICOU**
  — serve à tela e aos outros agentes, e não muda o que a Bruna diz enquanto ela não consultar.
  Reversão da condição, se quiser: `/tmp/unit_1_atributos.bak-20260911095205`.
- **O diagnóstico, e é o que distingue de ontem:** a chave migrou bem (6/6) porque *"até que horas
  pego a chave?"* é pergunta **sobre a unidade** — dispara a consulta. *"Gostei, quero ver"* é sobre
  o **imóvel**: a Bruna não associa à ferramenta de unidade, e a frase no prompt não mudou isso.
- ⏭️ **O conserto durável é código, e é decisão do Paulo:** quando o `buscar_imovel` devolve um
  imóvel **[AVULSO]**, o próprio retorno traz o passo a passo lido da condição da unidade. Fonte única
  (a unidade, editável pela tela) entregue **no ponto de decisão** — a lição que se repete no projeto:
  a instrução que chega junto do dado decide, a do prompt não. Aí o parágrafo sai da Bruna.
- **Estado agora:** duplicado de propósito — o passo a passo está na unidade **e** no prompt da Bruna,
  até o conserto acima existir. Duplicação conhecida é melhor que regressão ao cliente.


### [2026-09-10] 🟢 A REGRA DA CHAVE SAIU DO PROMPT — o fato virou dado da unidade, e a medição sustentou

> Pergunta do Paulo: *"como ficou a questão das regras como horário para retirada de chaves?"*
> Estava pronta para receber e **ainda não migrada** — a regra seguia escrita em 4 prompts. Migrada
> agora, com medição.

- **O parágrafo misturava duas coisas**, e por isso a separação importa: o **FATO** (até 16h30 de
  segunda a sexta, até 10h40 no sábado) e a **CONDUTA** ("se perguntarem, é esse; não prometa
  depois"). O fato foi para `units.atributos`; a conduta ficou no prompt, apontando a consulta.
- ✅ **Aplicado (banco conta 6):** condição *"retirada e entrega de chave"* na unidade #1, e o
  parágrafo trocado em **Bruna, Letícia, Marina e Rafa** — cada prompt **encolheu 67 chars**. A
  seção da Júlia **não foi tocada**: a dela é sobre venda, onde não existe retirada de chave.
- 🟢 **Medido em fio limpo, N=6 por cenário:** Bruna *"até que horas consigo pegar a chave?"*
  **6/6 certo**, Letícia **6/6 certo** — e **as 12 chamaram `buscar_unidades`**. Zero respostas com
  o horário de FECHAMENTO (17h30), que é o erro que a regra existe para evitar.
- ⚠️ **Um `[IGNORAR]` apareceu em 4 de 6** no cenário *"consigo retirar às 17h?"* — e **não é da
  mudança**: restaurando o prompt antigo dentro de transação revertida, o placar é **idêntico
  (5 calou / 1 respondeu dos dois lados)**. São 18h03 e a unidade fecha 17h30; é a conduta de fora
  de expediente, que segue como estava. Sem baseline eu teria creditado isso à migração.
- **Não medido:** Marina e Rafa (mesma troca de texto, volume baixo — 287 e 24 msgs/30d).
- **Reversão:** `/tmp/assistant_{14,15,16,17}_ins_chave.bak-20260910180055` e
  `/tmp/unit_1_atributos.bak-20260910180055` na VM.
- ⏭️ **O que isso abre:** o time passa a editar esse horário pela tela, sem tocar em prompt. E o
  mesmo caminho serve para toda regra do balcão que hoje vive em texto duplicado.


### [2026-09-10] 🟢 MAPA VISUAL DAS IAs DA TOZI — `tozi-docs/ia/mapa-das-ias.html`

- Diagrama de arquitetura interativo gerado com a skill `archify`, a partir dos números reais de 30
  dias: entrada (canais, anúncio, campanha) → triagem → especialistas → dados (Vista, unidades) →
  time humano, com volume por agente e contagem de transferências/handoffs em cada seta.
- **Medido:** `validate --quality showcase` = **9/9 artifact checks, 0 erro, 0 warning** ·
  `deliver` ok (720.059 bytes, sha `9cb3b2eac7dba060`) · `visual-check` **ok em todos os viewports**
  (1440×900, 1600×1000, 1920×1080, 2048×1320, claro e escuro).
- ⚠️ **Dois defeitos que só a revisão da IMAGEM pegou** — os checks automáticos passavam nos dois:
  o campo `tag` **não é renderizado**, então o volume por agente estava invisível (movido para o
  `sublabel`); e a seta Clara→Apoio serpenteava por **10px** de desalinhamento entre os centros.
  Evidência de navegador não é revisão perceptual.
- **Limite declarado no próprio desenho:** Vista e Unidades aparecem ligados só à Bruna para manter
  o traçado limpo — a Júlia usa as mesmas ferramentas, e isso está dito nos cards.


### [2026-09-10] ✅ #129 MERGEADO E NO AR · Feirão cadastrado · e o Nicolas achou DOIS furos meus na revisão

- **O Nicolas mergeou e deployou o #129** (VM em `aeb044f26`), com um commit de correção por cima:
  `062fb072a`. Os dois defeitos eram meus, e o primeiro teria virado incidente:
  1. 🔴 **Evento sem horário próprio FECHAVA A CAIXA o dia inteiro.** Eu relaxei a validação e
     conferi **um** consumidor do campo (`UnitAtendimento#faixas_em`), não todos. O
     `ScheduleEvaluator#closed_by_rule_now?` — que o `Inbox#out_of_office?` usa — faz
     `minutos_de(nil, nil)` valer **0**, então a caixa ficaria fora do expediente na sexta e no
     sábado do Feirão. A unidade #1 tem `applies_to_inboxes = true`: seria a inbox 91, ao vivo.
     Correção dele: a regra que não fecha e não traz faixa **não disputa o dia**.
  2. 🔴 **A tela abriria vazia e o próximo salvar apagaria as condições:** faltou `json.atributos`
     no `_unit.json.jbuilder`. O `permit` aceitava e o banco gravava, mas a leitura não devolvia —
     e o comentário dele registra que é *"a mesma armadilha da coordenada"*. **Meu spec olhava
     `Unit.last.atributos` no banco, não o ciclo tela → API → tela.**
- ✅ **Feirão cadastrado em produção:** `UnitException #5` — *Feirão Tozi Imóveis 2026*, 11 e
  12/09, **sem horário próprio** (vale o horário de sempre). Reverter:
  `UnitException.find(5).destroy!`.
- **Conferido depois do cadastro, na produção:** o retorno traz *"Evento na unidade: Feirão Tozi
  Imóveis 2026 — sex 11/09 e sáb 12/09, no horário de funcionamento de sempre"* · a sexta mantém
  **07:30–11:30 e 13:30–17:30** (pausa preservada) · e **`inbox.out_of_office? = false`**, que é
  exatamente o furo nº 1 fechado.

### [2026-09-10] 📚 DOCUMENTAÇÃO COMPLETA DA IA DA TOZI — `spx-os/clientes/tozi-docs/ia/` (1,3 MB, 38 arquivos)

> Pedido do Paulo: *"todas as IAs, os system prompts, as tools, tudo — preciso revisar manualmente"*.
> Depois ele apontou duas lacunas da 1ª versão, as duas corrigidas: **faltavam as descrições e os
> formatos de retorno das ferramentas**, e **a base de conhecimento estava só listada, não extraída**.

- **Conteúdo:** índice · infraestrutura (caixas, times, roteamento, transferências reais, unidades) ·
  **catálogo das 18 ferramentas** (descrição e parâmetros como o modelo os lê + retorno REAL de
  produção + respostas fixas do código) · índice da base · **114 perguntas e respostas** · **24
  documentos com texto integral e os 302 trechos indexados** · um arquivo por agente com config,
  behavior, guardrails e o system prompt inteiro.
- Credenciais varridas (7 mascaradas, zero vazada); telefone e e-mail mascarados nos exemplos.
- **O que a extração revelou, e vale a revisão:**
  - 🔴 **A lista de ferramentas da tela não é a real:** `handoff` e `faq_lookup` entram em TODO
    agente pelo runtime (`Captain::Assistant#agent_tools`), e `search_knowledge` quando o modo
    inclui trechos. São as mais usadas — **3.291 handoffs em 30 dias** contra 156 e 203.
  - 🔴 **37 linhas idênticas repetidas em 3+ prompts**, 17 delas nos oito agentes.
  - 🔴 **A Clara está em modo `faq`** — o Playbook dela (19 trechos) **nunca é recuperado**.
  - 🔴 **A Bruna (locação, 4.188 msgs/30d) tem ZERO documento** e 12 perguntas — em `hybrid`, com
    `search_knowledge` sem nada para buscar.
  - 🔴 **A Sofia, aposentada (0 caixas), segura 127 trechos**, incluindo o Catálogo de
    Empreendimentos (#7, 83k chars, 114 trechos) — a maior peça da base está num agente desligado.
  - Cópias entre agentes: Playbook (#5/#6), Tabela ETNA (#9/#27), Fronteira MCMV (#28/#29) — é como
    o produto funciona (base por assistente), mas é onde o dado diverge.
- ⏭️ Ponteiro adicionado em `spx-os/clientes/tozi.md`. ⚠️ O `spx-os` está com **26 arquivos não
  commitados** e último commit de 03/09.


### [2026-09-10] 🟢 REGRA E EVENTO DE UNIDADE CONSTRUÍDOS — e a resposta medida: a especialista consulta, a triagem às vezes nega

> Pedido do Paulo: a IA saber a regra de retirada de chave e eventos como o **Feirão Tozi Imóveis
> 2026** *sem* base de conhecimento. E a pergunta que ele fez junto, que é a que importa:
> *"as IAs vão saber consultar quando for perguntado?"*

**O que foi construído** (commit `1a54c27771`, branch `PauloSeze/unidade-regras-eventos`):

- **Condições de atendimento** (`units.atributos`) viram campo editável na tela, em pares
  nome/valor. A ferramenta **já** as imprimia; faltava o time alcançar o campo — estava fora dos
  strong params, então só console escrevia nele.
- **Evento, obra e temporada** em curso ou nos próximos **14 dias** entram no retorno **mesmo sem
  data pedida**, em linha própria. Antes, `excecoes_das` fazia `return [] if datas.empty?`: evento
  marcado pra depois de amanhã era invisível em qualquer pergunta que não citasse o dia exato.
- **Feriado fica de fora**, de propósito: só muda horário, e a linha de horário já responde por ele.
- **A descrição da ferramenta passou a dizer que ela responde por condição do local e por evento** —
  sem isso o agente não associa a pergunta a ela. Foi essa linha que mudou o comportamento.
- Extraído `Spx::UnidadeEventos` (mesmo padrão de `UnidadeExpressaoTemporal`/`UnidadeProximidade`):
  a tool estourou `ClassLength` e a extração devolveu o rubocop ao baseline.
- **Medido:** ramo **53 exemplos / 0 falhas** contra baseline **42 / 0** · rubocop **3 = 3**,
  histograma idêntico (o arquivo novo soma 0) · eslint **0 erros / 25 warnings** dos dois lados ·
  `zeitwerk:check` All is good! · **mutação: 5 exemplos novos falham contra o código antigo**.

**A resposta à pergunta do Paulo, medida na prod (transação revertida, cadastro e conversas):**

| agente | pergunta | resultado |
|---|---|---|
| Bruna (locação) | condição do local | **5/6** consultou e respondeu pelo dado (1 encaminhou ao consultor) |
| Bruna | evento, sem citar data | **6/6** |
| Júlia (vendas) | evento | **6/6** |
| Clara (triagem) | condição do local | **6/6** |
| Clara | evento (N=12, duas rodadas) | **8 certos · 3 NEGARAM · 1 handoff** |

- 🔴 **A negação é o defeito que sobra, e é o pior desfecho** — pior que transferir: *"Não achei
  informação sobre feirão aqui na base"* sobre um evento que existe. Nas negações ela **não chamou**
  a ferramenta; em duas delas chamou `faq_lookup`, respondeu pela base de conhecimento e parou.
- ✅ **Conduta aplicada no banco da conta 6 (sem deploy) e ela moveu o ponteiro:** a Clara tinha uma
  **lista fechada** (*"Dados FIXOS da Tozi — são exatamente estes"*) com endereço, telefone e
  horário; tudo fora dela virava "não existe". A lista virou origem aberta, numa linha só. Nos
  outros 5 agentes, a frase que já existia passou a cobrir condição e evento. Antes: Clara **1/6
  consultou** e 4/6 negavam. Depois: 8/12 certas.
- ⚠️ **Duas leituras erradas MINHAS de detector nesta sessão**, as duas pegas relendo as respostas:
  `[IGNORAR]` contado como acerto de endereço, e a frase de negação (*"não achei"*) casando com o
  padrão do acerto porque continha a palavra procurada. **É a 6ª e a 7ª vez.** Detector se valida
  contra a frase real antes de virar número — e negar tem que ser categoria própria, nunca o
  complemento de "acertou".
- **Helena ficou fora de propósito** (RH, não atende cliente sobre unidade).
- **Reversão:** `/tmp/assistant_{7,13,14,15,16,17}_ins_unidade.bak-20260910140718` na VM.
- 🔴 **"O Feirão é no horário normal" expôs um defeito, e ele era perigoso:** a validação exigia
  hora de abrir e de fechar sempre que a regra não fechasse o dia. Então cadastrar um evento que
  não muda o funcionamento obrigava inventar uma faixa — e **faixa de exceção SUBSTITUI a grade do
  dia**: um Feirão gravado das 8h às 18h numa sexta **apagaria a pausa do almoço**, e a IA passaria
  a dizer que a unidade abre direto. O cálculo (`UnitAtendimento#faixas_em`) já entendia o dado
  ausente como "vale o horário de sempre"; era só a validação que impedia gravá-lo. Corrigido, com
  meia faixa ainda recusada (com só a abertura, o que a pessoa digitou sumiria sem aviso).
- ✅ **Provado contra a produção com o evento REAL** (sexta 11 e sábado 12/09, horário normal):
  o retorno traz *"Evento na unidade: Feirão Tozi Imóveis 2026 — sex 11/09 e sáb 12/09, no horário
  de funcionamento de sempre"*, a grade da sexta **mantém as duas faixas com a pausa**, e a Bruna
  responde **4/4** com o horário certo de cada dia (sexta 7h30–11h30 e 13h30–17h30, sábado 9h–11h30).
- ⏭️ **Falta, e NÃO é meu:** merge + deploy são do Nicolas. Correção do Paulo em 10/09, quando eu
  comecei a mergear por causa do prazo do Feirão: *"Não precisa de merge, só push. Se já foi feito,
  abortar."* Abortado sem mergear nada. **Depois do deploy** eu cadastro o Feirão (a validação em
  produção ainda é a antiga, então o registro sem horário próprio só entra depois dele) · e **decidir se `notes`
  continua invisível** para a IA — hoje ele não é editável nem lido, e a decisão registrada é
  mantê-lo interno ao time.


### [2026-09-10] 🔵 REGRA E EVENTO DE UNIDADE: as peças JÁ EXISTEM e estão desencontradas (levantamento, nada aplicado)

> Pedido do Paulo: a IA de locação precisa saber o **horário de retirada de chaves** e eventos como o
> **"Feirão Tozi Imóveis 2026" (sexta e sábado)** — *sem* base de conhecimento. Levantado no código
> consolidado (`units`) e no estado real da conta 6.

| peça | existe? | o time edita? | a IA vê? |
|---|---|---|---|
| `units.atributos` (jsonb livre) | ✅ | 🔴 **não** — fora dos strong params e do form | ✅ a tool imprime `Chave: valor` |
| `units.notes` (texto) | ✅ | ✅ no `UnitForm` | 🔴 **não** — a tool não devolve |
| `unit_exceptions` (`category: feriado/evento/manutencao/temporada`, nome, `starts_on..ends_on`, recorrência, `reminder_days_before`) | ✅ | ✅ API + calendário | ⚠️ **só se o cliente pedir uma data** |

- 🔴 **O furo do evento é uma linha:** `excecoes_das` (buscar_unidades_tool) faz `return [] if datas.empty?`
  — sem data pedida, **nenhuma exceção é carregada**. Então um Feirão de sexta e sábado só existe pra IA
  se a pessoa perguntar *"vocês abrem sábado?"*. Em qualquer outra pergunta, o agente não sabe que existe.
- 🔴 **`notes` e `atributos` são metades trocadas:** o time edita o campo que a IA não lê, e a IA lê o campo
  que o time não edita.
- **Estado na conta 6 hoje:** unidade 1 com `atributos = {creci}`, `notes = ""`, **0 exceções cadastradas**.
  E a regra da chave (**16h30 / 10h40 no sábado**) está escrita em **4 prompts** — Bruna, Letícia, Marina e
  Rafa. Texto duplicado diverge: é a mesma classe do R$21 em duas FAQs.
- ⏭️ **Desenho proposto (um caminho, não um menu):**
  1. **Regra específica vira `atributos`**, não prompt nem knowledge — a tool já imprime. Falta abrir
     `atributos` nos strong params + editor chave/valor no `UnitForm`, e então **remover a regra da chave
     dos 4 prompts**. Fato ancorado na unidade, consultado, não recuperado por similaridade.
  2. **Evento continua sendo `unit_exception` de categoria `evento`** — o que muda é a tool **enxergar
     evento vigente/próximo mesmo sem data pedida**, em linha própria (`Evento na unidade: <nome> — <dias>,
     <horário>`), com janela pra não poluir.
  3. **`notes` fica INTERNO** e a tela passa a dizer isso. Texto livre longo no retorno da ferramenta é o
     caminho de volta pro prompt inchado; o que é fato pro cliente cabe em `atributos`, curto e nomeado.
- ⚠️ **O Feirão é sexta e sábado — depende de merge + deploy pra IA enxergar sem data pedida.** Sem isso,
  a única cobertura hoje é a pessoa perguntar pela data exata. Conduta temporária no prompt resolveria a
  semana, mas é dívida que alguém precisa lembrar de remover — e é justamente a dor que o módulo de exceção
  nasceu pra matar ("a exceção tem data e morre sozinha", 18/08).
- ⏭️ **Falta o Paulo passar os dados do Feirão** (dias, horário, se muda o funcionamento da unidade) pra
  cadastrar.


### [2026-09-10] 🟢 CONV 41573: o endereço errado de hoje saiu 4h ANTES do conserto entrar no ar — e agora mede 12/12

> Paulo: *"Agora de fato teremos o endereço resolvido? Pois hoje foi passado novamente endereço errado."*
> A mensagem existe e está errada. Mas a linha do tempo mostra que ela é anterior ao conserto.

- **A mensagem:** 10/09 **08:06**, Bruna, conv 41573 — *"Nosso endereço: Av. das Embaúbas, 1950 - Setor
  Comercial, Sinop."* O Adrian corrigiu à mão às 09:17, mandando o endereço certo.
- 🔴 **Ela não consultou nada:** `buscar_unidades` foi chamada **0 vezes** na conversa inteira.
- **A linha do tempo, medida na VM:** mensagem **08:06** · `Unit #1` (a unidade que a ferramenta lê hoje,
  depois da consolidação do Nicolas) criada **08:16** · código da guarda no disco **09:51** · **worker
  reiniciado 12:06**. O processo que atendeu às 08:06 rodava o código velho, e a unidade que a tool nova
  lê ainda não existia. **Nenhuma das duas peças estava valendo.**
- ✅ **Prova de que a guarda pega esse caso:** passando o texto EXATO daquela mensagem pela guarda que está
  no ar agora, ela vira *"Av. das Figueiras, 1646 - Sala 01, Centro, Sinop/MT, CEP 78550-150"*.
- 🟢 **Medido agora, em fio LIMPO** (conversa nova, sem o endereço em lugar nenhum do histórico, transação
  revertida): **12 de 12 certos**, em duas formulações da pergunta — e **as 12 chamaram `buscar_unidades`**.
  A guarda não precisou agir em nenhuma: a IA consultou e respondeu pelo dado. Zero invenção.
  - ⚠️ A primeira medição, feita **dentro da 41573**, não valia: o Adrian já tinha escrito o endereço certo
    ali, e 5 de 6 rodadas caíram em `[IGNORAR]` (conversa encerrada, humano dentro). Cenário contaminado —
    refeito em fio limpo. E `[IGNORAR]` **não é acerto**: o detector passou a separar calou × certo ×
    inventou × sem endereço.
- **O tamanho do estrago até aqui (72h, mensagens da IA com endereço de escritório): 7 erradas × 2 certas** —
  Julio Campos 1470, Embaúbas 671, Avencas 1280, Embaúbas 1140, Inajás 404, Tarumãs 1260, Embaúbas 1950.
  Todas **anteriores** às 12:06 de hoje. Em 72h a `buscar_unidades` foi chamada **1 vez**.
- ⏭️ **O que ainda NÃO está no ar, e é o buraco que sobra:** a guarda vigente só corrige quando a frase diz
  de quem é o endereço (*"nosso escritório fica na…"*). Resposta que **começa direto pelo logradouro**
  escapa — é o commit `538329c95b` (branch `PauloSeze/guarda-endereco-pergunta`), **ainda sem push**.
- ⏭️ **Dívida vizinha, intocada:** o PIN não vem da unidade — `enviar_localizacao` lê `office_coords` da
  integração `vista`, com fallback numa constante da Tozi **em código compartilhado**. Duas fontes para o
  mesmo fato (batem em 20 m hoje), e o nome do cliente em código de frota.


### [2026-09-10] 🟢 OS DOIS FUROS MEDIDOS DEPOIS DO MERGE ESTÃO CONSERTADOS — 2 commits, sem push

> Depois de #120 e #116 mergearem, a medição em produção mostrou que cada um tinha um caminho
> que a guarda não alcançava. Os dois são o MESMO tipo de erro meu: a regra foi escrita para o
> formato da falha que eu tinha na mão, não para o caminho por onde o cliente chega.

**1. Endereço: a guarda não agia quando a resposta COMEÇA pelo endereço.**

- Medido: a Bruna respondendo *"Qual o endereço de vocês?"* 6 vezes — **3 sem chamar
  `buscar_unidades`**, cada uma com uma rua inventada diferente (Embaúbas 1030, Embaúbas 1059,
  Tarumãs 2821). Passando as três pelo guard vivo: **"❌ passou errado" nas três**, porque não há
  marcador de dono antes do logradouro — a IA responde só o endereço.
- ✅ Quem diz de quem é o endereço, nesse caso, é a **PERGUNTA**. `perguntaram_o_endereco_da_empresa?`
  lê a última mensagem do cliente; quando ela é sobre onde a empresa fica **e não cita imóvel**,
  todo logradouro da resposta é resposta a ela.
- **O veto pesa tanto quanto o gatilho:** *"qual o endereço da casa?"* segue intocado — trocar
  aquele endereço mandaria a pessoa ao lugar errado, que é o estrago que a guarda existe pra evitar.
- **Medido:** suíte **100 exemplos / 0 falhas** contra baseline **95 / 0** · rubocop **19 = 19**,
  histograma idêntico cop a cop · **mutação: 2 dos exemplos novos falham contra o código velho**
  (os 3 de veto passam dos dois lados, de propósito — é a contraprova de que a guarda não virou
  "troca todo logradouro") · **as 3 respostas reais passam pelo guard novo em produção e saem
  corrigidas**, com os dois vetos intactos, em transação revertida.
- ⏭️ Commit `538329c95b` na branch `PauloSeze/guarda-endereco-pergunta`, **NÃO pushado**.

**2. Finalidade cruzada: o aviso não alcançava a busca por CÓDIGO.**

- 🔴 O ramo `codigo.present?` retorna cedo e **nunca passava pelo aviso** — e ele é o caminho de
  quem chega com placa, anúncio ou link do site. É por aí que a **conv 36940** passou: a Júlia
  chamou `buscar_imovel` com `codigo: "7573", status_tipo: "locacao"`, o aviso não saiu e ela
  seguiu conduzindo. **0/6 transferências** na medição pós-merge.
- ✅ O gatilho lê a finalidade **PEDIDA**, não o `Status` do imóvel achado — e a diferença é o
  próprio caso: o imóvel do anúncio é de **venda** (cód 7573 = `"Venda"`, conferido no Vista) e o
  cliente disse que queria alugar. O `Status` continua decidindo o que já decidia: se o endereço
  sai mascarado.
- **Que o parâmetro é sinal, e não ruído de preenchimento, foi medido antes de escrever código**
  (60 dias, conta 6): a agente de **vendas pediu locação por código 127 vezes** e a de locação
  pediu venda 12; das **115 conversas** com busca cruzada por código, **100 estão hoje no time de
  LOCAÇÃO** contra 7 em vendas — melhor que os 89,7% do replay que embasou o #116.
- Código **não encontrado também leva o aviso**: a intenção do cliente não muda porque o número
  estava errado, e é aí que a conversa costuma continuar no especialista errado.
- **Medido:** pasta de tools **349 exemplos / 0 falhas** contra baseline **340 / 0** · rubocop
  **18 contra 19** (a extração do `por_codigo` tirou uma offense do `perform`) · **mutação pelo
  caminho PÚBLICO**: com o código velho, `perform(status_tipo: "locacao", codigo: "7573")` **não
  avisa** e o exemplo falha, enquanto o negativo passa dos dois lados · **prova contra a produção
  nos 4 sentidos** (Júlia→Bruna avisa, Júlia→venda não, Bruna→Júlia avisa, Bruna→locação não), com
  o imóvel apresentado junto do aviso em todos.
- ⚠️ A mutação **pelo método privado prova pouco** (o método é novo, então tudo falha por
  `NoMethodError`) — foi por isso que os 2 exemplos pelo `perform` entraram. Vale como regra: prova
  de mutação tem que passar pela interface que o modelo chama.
- ⏭️ Commit `c12c830bca` na branch `PauloSeze/finalidade-por-codigo`, **NÃO pushado**.

✅ Worktrees de CI da `.232` removidas ao fim (`ci-e2`, `ci-ee2`, `ci-fc`, `ci-fcbase`) — sem sobras.


### [2026-09-09] 🔴 DOIS MÓDULOS DE UNIDADE EM PRODUÇÃO — e o Urban DeVille sem uma linha de base

> Duas perguntas do Paulo. As duas viraram achado. **Nenhuma decisão tomada — as duas dependem
> dele.**

**1. 🔴 `unidades` e `units`: a MESMA feature construída duas vezes, as duas na `producao`.**

| | `unidades` (PR #61) | `units` |
|---|---|---|
| tabelas | `unidades`, `unidade_horarios`, `unidade_excecoes` | `units`, `unit_working_hours`, `unit_exceptions` |
| 1º commit | **17/08** (Paulo Seze) | **26/08** (autor `deploy`) |
| tela | Configurações › **Unidades** | Configurações › **Units** |
| tool de IA | ✅ `buscar_unidades` | ❌ nenhuma |
| coordenada / pin / distância | ✅ | ❌ |
| liga unidade → inbox | ❌ | ✅ `has_many :inboxes` |
| calendário, lembrete por e-mail, recorrência, almoço | ❌ | ✅ |

- **6 tabelas, 2 APIs, 2 telas** para o mesmo conceito — e **as duas entradas aparecem no menu
  lateral**, uma do lado da outra (`SIDEBAR.UNITS` e `SIDEBAR.UNIDADES` no `Sidebar.vue`).
- **Uso real: ZERO nas duas VMs.** A única linha que existe é a unidade da Tozi que eu criei hoje,
  no `unidades`. `Unit.count = 0` na prod da Tozi e na `.232`.
- 🔴 **Como passou:** os commits do `units` também se chamam **`feat(unidades)`**. Duas frentes
  construíram a mesma coisa em paralelo, com nomes em idiomas diferentes, e ninguém cruzou.
- ⏭️ **Recomendação (não executada, aguarda decisão):** consolidar no **`units`** — ele tem a metade
  operacional inteira (inbox, lembrete, calendário) e o que falta nele é uma tool de IA e duas
  colunas de coordenada, que são baratas. O caminho inverso custa muito mais. **Com uso zero nos
  dois, a migração de dados é trivial HOJE** — e fica mais cara a cada cliente que cadastrar.

**2. 🔴 O URBAN DEVILLE NÃO TEM BASE — e a IA preenche o vazio inventando.**

- **A única fonte é o Vista, código 9786** — e o cadastro está vazio: `TituloSite` **em branco**,
  `DescricaoWeb` **em branco**, `Dormitorios` 0, `ValorVenda` 0. A tool devolve só
  *"Deville Urban (código 9786), em construção, entrega 2028-08-30"*.
- **Nenhum documento de knowledge sobre ele.** A conta 6 tem **24 documentos** (Acqua, Ares,
  Carvalho, Cedros, Duottori, Elleva, Etna, Gaia, Genebra, Guanabara, Hamoa, Loris Domus, Pacaembu
  ×2, Parque Sinop, Reserve BH, Zurique…) e **nenhum do Urban DeVille**. Bate com a decisão de
  28/07, que o deixou como pendência de catálogo ("não tem muita procura para esses") — e **depois
  disso a Tozi disparou 2.752 mensagens sobre ele**.
- 🔴 **A invenção, medida (conv 32983):** *"apartamentos de 2 quartos, vaga privativa e sol da
  manhã. A entrada é parcelada em 36x fixas de **R$ 1.897,16**"*. Nada disso existe no Vista nem em
  documento nenhum — nº de quartos, vaga, orientação solar e uma parcela com centavos. Mesma classe
  do fiador digital (19/08): nome sem fato vira invenção do resto.
- ⚠️ **Dois "Deville" que a IA mistura:** o **Residencial Deville** (bairro real, com casas à venda
  e locação — 2498, 9879, 1021…) e o **Deville Urban** (9786, o lançamento da campanha). Em 60 dias
  a IA citou "Deville" **162 vezes**, incluindo *"o Deville é um condomínio fechado… saída pra
  Cláudia"*, que descreve o BAIRRO, não o lançamento.
- **E quem perguntou nem sempre foi atendido:** a conv **9601** (*"Posso saber mais sobre o Urban
  Deville?"*) é uma das silenciadas por `[IGNORAR]` — sem resposta de IA nem de humano.
- ⏭️ **O conserto é DADO, não conduta:** o fact-sheet do Urban DeVille precisa existir (como os 17
  de 28/07), ou o `DescricaoWeb` do 9786 precisa ser preenchido no Vista. Enquanto não houver, a
  regra anti-invenção não tem em que se apoiar.


### [2026-09-09] 🟢 A JÚLIA ATENDENDO LOCAÇÃO: o conserto saiu do prompt e foi pro retorno da ferramenta (PR #116)

> Fecha a última ponta da conv **36940**. O Paulo decidiu o destino (**Bruna**) e delegou o
> gatilho — que foi escolhido por replay, não por opinião.

- **O que o registro mostrou, e corrige o meu diagnóstico anterior:** a Júlia **fez handoff** — só
  que às **22:33**, e o cliente disse que queria alugar às **21:58**. Não foi ausência de passagem:
  foram **35 minutos** de atendimento de locação feito pela agente de vendas, e é nesse intervalo
  que ela afirmou que Deville e Paris eram em condomínio fechado.
- **A regra já existe no prompt dela** (*"Roteamento de não-venda: locação → transfira para
  Bruna"*) e, medida no turno exato, **é seguida 1 vez em 6**. Nas outras cinco ela reconhece a
  virada corretamente e segue sozinha. Mesma classe de 12/08 (0/8 em três versões de texto).
- ✅ **[PR #116](https://github.com/Dev-Simplex/chatspx/pull/116):** o `buscar_imovel` prefixa o
  retorno com a instrução de transferir quando a busca é da finalidade OPOSTA à do assistente —
  nos dois sentidos, e também quando a busca volta vazia. Opt-in por assistente (`finalidade` +
  `agente_outra_finalidade`); sem as duas chaves, nada muda.
- **O gatilho foi decidido por REPLAY de 60 dias**, não por preferência: das **136** conversas em
  que uma agente de vendas buscou locação, **122 (89,7%) terminaram em locação** e só **5** ficaram
  em vendas. Entre as **83** que fizeram uma ÚNICA busca cruzada, **71** foram para locação.
  Esperar a segunda busca daria ~2 pontos de precisão e deixaria passar **61% dos casos** — que é
  exatamente a espera que custou os 35 minutos.
- **Medido:** **339 exemplos / 0 falhas** (baseline 63/0 no arquivo) · rubocop **18 = 18** no código
  e **0 = 0** no spec · **mutação: 7 de 7 exemplos novos falham contra o código antigo**.
- ⏭️ **Nasce desligado.** Depois de merge + deploy: `finalidade: 'venda'` + `agente_outra_finalidade:
  'Bruna'` na Júlia (e o inverso na Bruna), e **remedir o turno da 36940**.

- 🔵 **Achado do Paulo, confirmado e com número:** o template daquele lead é mesmo o
  `tozi_rmkt_imovel` — mas **não vem de campanha de remarketing**. Quem o configura é o **hook #9
  (`site_leads`)**, que tem `imovel_template_name` no global. Resultado: **169 dos 214 leads de site
  em 30 dias** saem com um template chamado "rmkt". A copy é honesta para os dois casos (*"Vi que
  você se interessou neste imóvel"*), mas quem abrir relatório por template vai contar lead de site
  como remarketing. ⏭️ Renomear ou clonar o template.


### [2026-09-09] 🟢 AS TRÊS CORREÇÕES DO PAULO — endereço vira UNIDADE, e o retorno da ferramenta volta ao contexto (PR #115)

> O Paulo corrigiu o rumo das três frentes de hoje, e nas três ele estava certo. O registro
> anterior (logo abaixo) descreve o diagnóstico; este descreve o que de fato ficou de pé.

**1. ✅ ENDEREÇO: saiu do prompt e virou dado da UNIDADE — como ele propôs.**

- Eu tinha fixado o endereço no system prompt. Ele apontou o caminho certo: **o módulo `unidades`
  já existe no SPX** — e, verificado, **já está em produção na Tozi** (tabelas `unidades`,
  `unidade_horarios`, `unidade_excecoes` + tool `buscar_unidades`), só nunca tinha sido populado.
- ✅ **Unidade #1 cadastrada** (conta 6): Av. das Figueiras, 1646 - Sala 01, Centro, Sinop/MT ·
  (66) 3531-7222 · CRECI J 8583 · **grade partida** (seg–sex 07:30–11:30 e 13:30–17:30, sáb
  09:00–11:30, dom fechada) · coordenada **ROOFTOP** (o Google devolveu "Ed. Tozi" na porta exata).
- ✅ **`buscar_unidades` ligada nas 7 assistentes** (Clara, Júlia, Bruna, Letícia, Marina, Rafa,
  Helena) e **o endereço SAIU dos três prompts** que o tinham fixo — a fonte agora é uma só, que o
  time edita pela tela. Duplicar o dado é como ele diverge (a lição do R$21 em duas FAQs).
- **Medido: 0 invenções em 12 rodadas.** Bruna **5/6** e Júlia **3/3** dizendo Figueiras (antes:
  0/6 certas, 3/6 inventando três ruas diferentes). A **Clara responde mandando o PIN** — que agora
  tem coordenada real. E *"vocês abrem sábado?"* saiu **3/3 correto** (9h–11h30), com a data
  resolvida pela ferramenta, não pelo modelo.
- ✅ **A dívida do HORÁRIO foi paga na mesma sessão:** a grade estava escrita em **5 prompts** e
  saiu de todos; ficou só a regra da chave (16h30 / 10h40 no sábado), que a unidade não tem. Medido
  depois: horário **4/4 certo** e a regra da chave **2/2** preservada.
- 🔴 **ENCURTAR TEVE CUSTO, e isso foi medido:** tentando deixar o prompt mais limpo, troquei
  *"O endereço do escritório e o telefone você não sabe de cabeça: consulte a buscar_unidades e
  responda pelo que ela devolver"* por *"Os três vêm da buscar_unidades"*. **O endereço voltou a ser
  inventado** (de 5/6 certo para 1/4, com ruas novas). A versão curta é anafórica — "esses três"
  em vez de nomear o endereço — e perdeu o imperativo. **Restaurada a redação que media certo.**
  Limpo ≠ curto: limpo é *sem fato duplicado*; a instrução que resta precisa manter a força.
- ⚠️ **Furo meu no caminho, corrigido:** ao tirar a grade de Letícia, Marina e Rafa esqueci de dar
  a elas a seção de consulta — ficaram sem os dois por alguns minutos.
- ✅ **Conflito de fontes desfeito na Bruna e na Júlia:** as duas tinham **três** instruções sobre
  endereço apontando para lugares diferentes — a nova (`buscar_unidades`), uma mandando usar o
  campo `Endereco` do `buscar_imovel`, e outra mandando consultar a base de conhecimento. As duas
  últimas foram desambiguadas (a do imóvel diz que é do IMÓVEL; a da base abre exceção para
  endereço/telefone/horário).
- **Estado medido no fim (Bruna, N=6, instrumentado por chamada de ferramenta):** **2 responderam
  com o endereço certo em texto** (as duas que chamaram `buscar_unidades`), **3 mandaram o PIN** —
  que carrega o endereço no título e é entrega correta —, e **1 inventou**, justamente a rodada em
  que não chamou ferramenta nenhuma. **5 de 6 entregam o endereço certo.**
  - ⚠️ **Meu detector contava o pin como erro** e por isso reportei 1/6 antes de instrumentar. É a
    6ª vez que detector grosseiro dá leitura errada — instrumentar a CHAMADA, não só o texto.
- ⏭️ **Dívida que fica:** a FAQ #234 da Clara ainda repete o endereço. E o **pin não vem da
  unidade**: a `enviar_localizacao` lê `office_coords` (integração `vista`, com fallback para
  constante da Tozi **no código compartilhado** — a descrição da tool diz "escritório da Tozi
  Imóveis"). As duas coordenadas batem hoje (20 m), mas são duas fontes para o mesmo fato, e o nome
  do cliente não deveria estar em código de frota. Vira PR próprio.

**2. ✅ CONDOMÍNIO: o carimbo foi REVERTIDO, e o conserto virou o PR #115.**

- 🔴 **O Paulo vetou a minha conduta, com razão:** eu tinha mandado a IA escrever "avulso/condomínio
  fechado" na própria fala. Isso **engessa o diálogo** — vai contra a REGRA #1. Removido.
- 🟢 **E ele nomeou a causa real:** *"pra mim isso acontecia naturalmente em um agente de IA — tudo
  que acontece em turnos anteriores virava contexto"*. **Não acontece.** Confirmado no código: o
  `collect_previous_messages` remonta o histórico a cada turno **só a partir das `Message`**;
  retorno de ferramenta não é `Message` e **some** depois da rodada. O agente fica com a própria
  fala, que é um resumo do resumo — e afirma de memória o que já tinha consultado.
- ✅ **[PR #115](https://github.com/Dev-Simplex/chatspx/pull/115)** — `ToolContextNote`: o que as
  ferramentas devolveram neste atendimento volta como preâmbulo do histórico, ao lado das notas que
  já existiam. **Devolve só FATO** (chamada, argumentos, retorno); o que fazer com o dado continua
  sendo conduta no prompt. Opt-in por conta, recorte no episódio, teto de 6 chamadas × 700 chars,
  chamada com erro fora, best-effort.
  - ⚠️ **Um gate que teria matado a feature em silêncio:** o `TraceRecorder` só gravava com
    `eval_enabled`. Ligar o contexto numa conta sem eval não gravaria nada e a nota nasceria sempre
    vazia. Virou `Captain::ToolCall.gravar_para?` (eval **ou** contexto).
  - **Medido na `.232`: 103 exemplos / 0 falhas** · rubocop **0 nos arquivos novos** (os
    pré-existentes seguem em 21).
- ⏭️ **Nasce desligado.** Para valer na Tozi: merge → deploy → ligar `captain_tool_context` na conta
  6 → **remedir a conv 36940**, que é o critério de sucesso.

**3. ✅ SAUDAÇÃO: mantida a correção de conduta** (saudação não é fecho social), já descrita abaixo.

- ⏭️ **Segue aberto, e é o defeito de fundo da 36940:** a **Júlia (VENDAS) atendeu locação inteira**
  sem transferir pra Bruna. Mesma classe medida em 12/08 (0/8 em três versões de conduta).


### [2026-09-09] 🔴 TRÊS CONVERSAS, TRÊS DEFEITOS — endereço da Tozi INVENTADO, condomínio ao contrário, e um "Bom dia" no vácuo

> O Paulo trouxe as convs **36913**, **36937** e **36940**. As três têm causas diferentes, e as
> três foram corrigidas no banco da conta 6 (sem deploy). O cadastro do Vista **não** tinha culpa
> em nenhuma delas.

**1. 🔴 A IA INVENTA O ENDEREÇO DO PRÓPRIO ESCRITÓRIO (conv 36937) — e cada vez inventa um.**

- A Bruna mandou a cliente para *"Rua das Avencas, 1280, Jardim Botânico"*. O endereço real é
  **Av. das Figueiras, 1646 - Sala 01, Centro, Sinop/MT** (CEP 78550-150, CRECI J 8583) — o Adrian
  teve que corrigir no dia seguinte.
- 🔴 **A causa é lacuna de dado, não descuido: das 9 assistentes, só a CLARA tem o endereço** (no
  prompt e na FAQ #234). **Júlia e Bruna citam "passa no escritório" na conduta de visita — a que
  eu mesmo escrevi em 02/09 — e não tinham o endereço em lugar nenhum.**
- **Medido antes de corrigir (N=6, Bruna): 0/6 acertaram e 3/6 inventaram — com TRÊS ruas
  diferentes** (*Avenida das Embaúbas 881*, *Av. dos Tarumãs 1007*, *Av. dos Jacarandás 1105 N*).
  A contradição entre elas É a prova de invenção. Em 30 dias a IA já tinha dito "Avencas" **2 vezes,
  com números e bairros distintos** (28/08 Júlia, 08/09 Bruna).
- ⚠️ **O estrago passava do texto:** as duas têm a ferramenta `enviar_localizacao` (18 usos em 30
  dias) e oferecem *"quer que eu mande a localização no mapa?"* — com endereço inventado, o **pin**
  ia junto.
- ✅ **Corrigido (banco, +462 chars em cada):** seção `# Endereço do escritório (fato — nunca
  deduza)` na Júlia (13) e na Bruna (14). **Medido depois: Bruna 6/6 e Júlia 3/3 dizendo Figueiras,
  0/6 inventando.**

**2. 🔴 CASA AVULSA APRESENTADA COMO CONDOMÍNIO FECHADO (conv 36940) — a IA contradisse a ferramenta.**

- O cliente pediu condomínio fechado **três vezes**. A Júlia ofereceu *Residencial Deville* e
  *Residencial Paris* dizendo que eram em condomínio — e reafirmou: *"são em condomínio fechado
  mesmo"*.
- 🔴 **O `buscar_imovel` tinha devolvido `[AVULSO — fora de condomínio fechado]` nos dois**, e o
  Vista está **certo** (2498 e 10006 = `Condominio: "Nao"`, conferido). É `contradisse_tool` puro.
- **A armadilha é o NOME:** **9 dos bairros de locação se chamam "Residencial alguma coisa" e são
  avulsos** (Iguatemi, Canadá, Bonne Vie, Florença, Deville, Paris, Aquarela…). Só **4 das 32**
  casas de locação são de fato em condomínio (Santorini ×3 e Portal do Servidor).
- 🔴 **A causa: a seção de desambiguação do rótulo existe SÓ na Bruna** (escrita em 28/08, depois
  da conv 4809). A Júlia nunca recebeu. Medido no turno exato da conversa, N=6:
  **Júlia 6/6 ERRADO × Bruna 1/6** — mesma pergunta, mesma busca, a diferença é a seção.
- 🔴 **A CONDUTA NÃO RESOLVEU, e isso é o dado.** Levei a seção para a Júlia, reescrita para
  atacar o nome do bairro, e medi quatro vezes:
  - cenário difícil (as falas anteriores escritas por mim, sem rótulo à vista): **sem a seção 6/6
    errado → com a seção 2/6 → com um reforço "confira antes de afirmar" 8/8 → com a versão final
    8/8**. O 2/6 era variância; nenhuma versão do texto moveu o ponteiro.
  - cenário realista (ela mesma busca, apresenta, e a fala DELA vira o histórico): **sem a seção
    1/6 errado → com a seção 0/6**. N=6 não distingue esses dois — não afirmo ganho.
  - **A comparação que vale é entre agentes, no mesmo cenário e mesmo turno: Júlia 6/6 errado ×
    Bruna 1/6.** A Bruna tem a regra dentro de `# Visita e chave`, acionada pelo contexto; na Júlia
    ela é seção solta, num prompt de 50k chars com 41 seções. Mesma regra, efeito oposto.
  - **Mantive o texto** (não piora, alinha com a Bruna e faz o rótulo sobreviver: em 4 de 6 ela
    passou a escrever "avulso" na própria fala), mas **sem contá-lo como conserto**.
- ⏭️ **O conserto durável é CÓDIGO, e o desenho já existe como precedente:** dar à `buscar_imovel`
  um parâmetro `condominio` — igual ao que o `mobiliado` ganhou no PR #75. A ferramenta filtra por
  `Condominio` e, quando o cliente pede condomínio fechado e não há nenhum no critério, o retorno
  **diz isso com todas as letras** em vez de esperar que o modelo leia 32 colchetes e conclua.
  Tira do modelo a decisão que ele erra quase sempre. Hoje só **6 dos 50** imóveis de locação são
  em condomínio (1 casa, 2 kitnets, 3 apartamentos) — a resposta certa quase sempre é "não temos".
- ⚠️ **Defeito vizinho, NÃO corrigido:** quem atendeu esse pedido de **locação** do começo ao fim
  foi a **Júlia, que é de VENDAS** — ela nunca transferiu para a Bruna. É a mesma classe medida em
  12/08 (*"conduta da Júlia para locação não funciona"*, 0/8 em três versões). Segue aberto.

**3. 🟡 "Bom dia" QUE FICOU 12h30 NO VÁCUO (conv 36913) — a IA calou de propósito, e por variância.**

- Não foi falha de roteamento: o log mostra `mirror_assigned 19:36:14` → `debounce_fire 19:36:33`
  → **`ignored [IGNORAR]` 19:36:34**. A Clara foi atribuída, rodou e **escolheu** não responder.
- **Reproduzido: 1 de 6.** Não é regra que sempre dispara — é o modelo classificando errado uma
  saudação, encaixando-a no *"fecho social (agradecimento, ok, despedida)"* da seção
  `# Cliente que volta depois da conversa encerrada`. Controle: com "Bom dia" + uma frase qualquer,
  responde 3/3.
- **Escala real, medida sobre os 790 `ignored` de 30 dias** (a maioria é silêncio CORRETO): 264
  fecho social · 65 autorresponder de empresa (o disparo do Feirão bateu em comércios) · 10 URA ·
  **51 de cliente real, dos quais ~12 são de fato cliente da Tozi silenciado**. Os que doem:
  *"Que horas podemos ver a casa?"* (24,6h até um humano), *"Olá! Posso saber mais sobre o Urban
  Deville?"* e dois *"Vi sobre as casas com entrada facilitada e quero saber mais"* — **respostas a
  template de campanha, nunca atendidas por ninguém**.
- ✅ **Corrigido (Clara, +313 chars):** a linha do fecho social passou a dizer que **saudação não é
  fecho** — "bom dia"/"oi"/"olá" sozinhos são alguém ABRINDO conversa, mesmo com a anterior
  encerrada e mesmo sem nada escrito em seguida.
- ⏭️ **O conserto durável não é conduta:** `[IGNORAR]` que silencia mensagem de cliente real não
  deixa rastro para ninguém. Uma varredura que reabra conversa com `ignored` + sem resposta há X
  minutos pegaria os ~12/mês sem depender de o modelo acertar a classificação.

- ⚠️ **Achado colateral no cadastro (não corrigido):** o imóvel 2902 tem `Endereco: "Rua Rogerio A.
  Saconi N° 12"` e `Numero: "1"` — o número está dentro do campo de rua e repetido errado. A IA
  disse à cliente *"nº 286, casa 02"*; a rua bate, o número não. Como ela estava **na frente do
  imóvel** e mandou foto, o número pode ter vindo da leitura da placa — não afirmo invenção, mas o
  campo está sujo.
- **Reversão:** `/tmp/assistant_{7,13,14}_ins_{saudacao,cond,cond2,endereco}.bak-20260909*` na VM.


> **Fila de PRs hoje (09/09):** **#110** (chave da OpenAI), **#111** (foto no Instagram), **#115**
> (contexto de ferramentas) e **#116** (finalidade cruzada), os quatro contra a `homologacao`.


### [2026-09-08] 🔴 FOTO DE IMÓVEL PELO INSTAGRAM: 0 de 10 entregues — o álbum nunca funcionou (correção pronta, sem push)

> Queixa do Paulo: *"está tendo bastante erros no envio de fotos pelo instagram"*. Não é
> intermitente: **é total**, e a IA promete a foto antes de o canal confirmar.

- **A medição que fecha o caso** (inbox 101, desde 18/08): mensagem com **3 imagens agrupadas
  falhou 10 de 10 vezes**; mensagem com **1 imagem por requisição chegou 116 de 117** (a única
  falha é um anexo `location`, tipo que o Instagram não aceita).
- **Dois erros, em sequência:** 01/09 ×3 `The parameter message[attachments][1][type] is
  required` (form-urlencoded, corrigido em `34752e813`) e, depois da correção, 04/09 ×6 e
  05/09 ×1 **`100 - Upload failed`** — a Meta aceita o corpo e não consegue baixar a mídia.
- 🔴 **O estrago é o que o time vê (conv 33147):** as 4 mensagens falharam e a IA disse *"Mandei
  as fotos dos dois! 📸"* e depois *"Agora sim, mandei as fotos dos dois imóveis!"*. O cliente
  respondeu **"Mandou ?"**. A tool devolve "Enviei 3 fotos" ANTES do envio — o agente não tem
  como saber que falhou.
- **O que NÃO é a causa, medido:** as 3 URLs exatas que a Meta recusou em 05/09 respondem
  **HTTP 200, image/jpeg, em paralelo, até com `facebookexternalhit`** — não é alcance público.
  `ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT` está **false** — não é a tag. E o formato deixou de
  dar erro de parsing (sonda com destinatário inexistente: os 5 corpos param no mesmo
  `2534014`, nenhum reclama de formato).
- ⚠️ **Duas variáveis estão CONFUNDIDAS no dado e eu não desfaço com o que existe:** o caminho
  agrupado manda array **e** entrega a URL do **CDN do Vista sem baixar**; o caminho de uma foto
  por mensagem manda anexo único **e** baixa, servindo do nosso host. Nenhum envio no Instagram
  jamais combinou "array + URL nossa" ou "único + URL do Vista". Por isso a correção escolhida é
  a que vale **sob as duas hipóteses**, não a que aposta numa.
- ✅ **Correção:** `Channel::Instagram#supports_multi_image_message?` volta a **false** (o padrão
  do `Channelable`, que já diz por escrito que errar para o `true` custa mensagem muda). O
  caminho do álbum continua no código, atrás da capacidade, para quem provar **no canal dele**.
  - **Medido:** `spec/enterprise/lib/captain/tools/` + `spec/services/instagram/` +
    `spec/models/channel/instagram_spec.rb` = **377 exemplos / 0 falhas** contra baseline
    **374 / 0** (`eb5a76e04f` puro) · rubocop **0 em 4 arquivos** · **mutação: 2 dos exemplos
    novos falham contra o código velho**.
- ✅ **[PR #111](https://github.com/Dev-Simplex/chatspx/pull/111)** aberto contra a `homologacao`
  (`PauloSeze/ig-album-fotos`, 1 commit, 4 arquivos, +77/−17, `MERGEABLE`). Só vale na Tozi depois
  de mergear + promover + deployar.
- ⏭️ **Dívida maior que este PR não fecha:** a `enviar_fotos_imovel` responde "Enviei N fotos"
  antes de o canal confirmar. Enquanto for assim, qualquer falha de envio vira promessa falsa —
  é a mesma classe do carrossel mudo (#49) e do envio silencioso (#58).
- ✅ **Carrossel mudo no Instagram: fechado.** De 05/08 a 17/08 saíram 6 mensagens
  `📷 Carrossel: N fotos do imóvel X` com **zero anexo** (o cliente lia a frase e não recebia
  nada; numa delas a IA mandou *"dá uma olhada no WhatsApp"* dentro do Instagram). Parou depois
  do #49. A vitrine de cards (`apresentar_imoveis`) **nunca foi usada** nessa inbox.

### [2026-09-08] 🟢 CONV 7503 / IMÓVEL 5758: a IA não errou a busca — o imóvel entrou no Vista depois

> Paulo: *"Essa conversa tem sim o imóvel 5758 no sistema"*. Tem **hoje**. Em 05/09 não tinha.

- **O 5758 existe e responde ao filtro exato da ferramenta** (`{'Codigo' => '5758'}`): Casa,
  Aluguel, Jardim Itália III, R$ 2.400 — mas com **`DataAtualizacao = 2026-09-08`**, e hoje
  **16 dos 109 imóveis de locação foram atualizados** (os demais são de 04/09 pra trás).
- **Em 05/09 a busca foi feita 3× e voltou vazia**, enquanto no mesmo minuto buscas por bairro e
  por lat/lng respondiam normalmente — o Vista não estava fora.
- **O 5758 nunca voltou de nenhuma busca do SPX**: 3 chamadas em toda a base, as 3 desta conversa,
  as 3 "não achou". E hoje ele é a **única Casa de locação no Jardim Itália**.
- 🔴 **O defeito REAL da conversa é outro, e é de conduta:** o retorno da guarda diz *"NÃO afirme
  ao cliente que o imóvel não existe, não foi encontrado ou já foi alugado, e não invente
  motivo"*. A IA pediu a confirmação do código (certo), o cliente confirmou — e aí ela disse
  *"Esse código não apareceu aqui no sistema. Pode ser que o imóvel já tenha sido alugado ou a
  placa esteja desatualizada"*, que é exatamente o proibido. **A guarda cobre o 1º turno e não
  diz o que fazer depois que o cliente confirma o código.**
- ⏭️ **Fica em aberto a queixa do SITE** (é do site da Tozi, não do SPX): *"as fotos da casa que
  eu digitei o código é igual da casa só que na hora que abre na descrição não é a mesma casa"*.
  Vale conferir com eles — o cadastro tem `Codigo 5758` e `ImoCodigo 5715`, e o site pode estar
  resolvendo por um e mostrando o outro.
- ⚠️ **Rajada na mesma conversa:** entre 13:19 e 13:20 saíram ~14 mensagens da IA, com o mesmo
  "não tenho casa de 3 quartos" reescrito **3 vezes** e 4 `handoff` (3 recusados). Turnos
  concorrentes respondendo a mesma coisa — medido, não corrigido.


### [2026-09-08] 🔴 A JANELA DE 7 DIAS DO INSTAGRAM NÃO É RESTRIÇÃO DO SPX — a Meta recusa, e o app da Tozi também não tem a feature

> Queixa do Paulo a partir da conv **33563** (conta 6, inbox 101): *"no Instagram a janela é de 7
> dias, mas no SPX fica restringido enviar depois de 24h"*. Medido na box da Tozi, read-only.

- **O SPX já contempla os 7 dias, e não hardcoda 24h.** `Conversations::MessageWindowService#instagram_messaging_window`
  devolve **7 dias** quando `ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT` está ligada e 24h quando não —
  a flag está **`nil`** na box da Tozi.
- 🔴 **Mas ligar hoje deixaria o produto PIOR, e isso foi medido, não deduzido.** Teste de
  capacidade contra a Graph com o token real da inbox 101, usando como destinatário o contato do
  **próprio Paulo, cuja janela venceu há 495h** — fora até dos 7 dias, então **nada é entregue** e
  o que a resposta revela é só *qual* limite bate primeiro:
  - sem tag → `403 code=10 subcode=2534022` *"This message is sent outside of allowed window"*
  - com `HUMAN_AGENT` → `403` *"To use 'Human Agent', your use of this endpoint must be reviewed
    and approved by Facebook"*
  - **A tag é recusada ANTES da janela** — é o que distingue "feature não aprovada" de "7 dias
    estourados", e é o teste limpo pra repetir depois da App Review.
- **Os DOIS apps estão sem a feature.** Em 18/08 isso foi medido no `Business MW` (BigStore); hoje
  se confirma no app da Tozi (Instagram App ID `2737838396591484`, app pai *SPX Lead Ads Tozi*).
  Não é particularidade de uma conta.
- **Consequência de produto:** com a flag ligada e a feature ausente, o composer abriria, o
  atendente escreveria, e a mensagem sairia **`failed`**. Trocaria *"não posso enviar"* por
  *"achei que tinha enviado"* — o bloqueio de hoje é o comportamento **honesto**.
- 🔴 **A armadilha para o dia em que for aprovada:** a flag é `InstallationConfig` **global da
  instância** e o `Instagram::SendOnInstagramService#merge_human_agent_tag` carimba
  `tag: HUMAN_AGENT` em **toda** saída, sem distinguir humano de IA. Medido na inbox 101 em 60
  dias: **700 mensagens do `Captain::Assistant` × 103 de `User`** (+191 sem sender) — ~87% do que
  sairia rotulado como *agente humano* seria a **IA**. A Meta reserva a tag a atendimento humano, e
  o app é **um por instância**: é a via curta pra perder o acesso à API.
- **Tamanho da dor (inbox 101, 60 dias):** 138 conversas com fala do cliente · **112 já
  respondidas** · **8** ficaram sem resposta e **só** a janela de 7 dias alcançaria · 18 morreram
  fora até dos 7 dias. No instante da medição há **15 conversas** na faixa 24h–7d (a 33563 entre
  elas, com **67h**). O ganho é real mas modesto — não justifica atalho de risco.
- ⏭️ **Ordem correta, e ela não começa em código:** (1) **Paulo pede a feature Human Agent** em App
  Review para o *SPX Lead Ads Tozi* → (2) **PR desacoplando o que hoje é uma flag só**: janela de 7
  dias no `MessageWindowService` **separada** da tag, tag aplicada **apenas quando
  `sender_type == 'User'`**, e chave **por conta** em vez de global (na `.232`, multi-cliente, uma
  flag global atingiria todo mundo) → (3) só então ligar, repetindo o teste de capacidade acima.
- ⚠️ **Sem a App Review, a única repescagem legítima segue sendo levar a conversa pro WhatsApp
  enquanto a janela de 24h está viva** — no IG não existe HSM. Decisão já registrada em 18/08.
- ⏭️ **PEDIDO DO PAULO (08/09): a IA passar a COLETAR o WhatsApp**, já que no IG não há HSM
  pra reabrir. Medido antes de desenhar — e o dado mostra que **não é só conduta**:
  - 🔴 **A ponte não existe hoje: `0 de 89` contatos do Instagram têm telefone gravado.** E a IA
    menciona whats/número em **5 de 700** mensagens de 60 dias.
  - 🔴 **Coletar SÓ no handoff cobriria ~20%:** apenas **32 das 158** conversas de 60 dias
    chegaram a ter humano atribuído. A janela mata as outras **antes** do handoff — a régua tem
    que incluir o momento em que o lead esquenta, não só a transferência.
  - 🔴 **O agente NÃO SABE que está no Instagram.** Os **7 agentes** (Clara 7, Júlia 13, Bruna 14,
    Letícia 15, Marina 16, Rafa 17, Helena 18) atendem as **mesmas 4 inboxes** (91 WhatsApp, 61/62
    Api, 101 IG). Só `channel_number` chega ao Liquid (`agentable.rb:25`); **`channel_type` não**.
    Conduta sem gate faria a IA pedir WhatsApp **de quem já está no WhatsApp**. E "ausência de
    `channel_number`" não serve de proxy: é nil também nas inboxes 61 e 62.
  - ⚠️ **Tag Liquid escrita no prompt do banco NÃO executa** — `assistant.liquid:13` interpola
    `{{ instructions }}`, e Liquid não re-renderiza o output de uma variável. O gate por canal
    **precisa vir do molde/código**, não dá pra resolver só escrevendo no prompt da conta.
  - 🔴 **Não há onde gravar:** `salvar_info_lead` **não tem parâmetro de telefone** e não toca
    `contact.phone_number`. ⚠️ E gravar direto em `phone_number` é arriscado — o campo tem
    unicidade por conta e o contato do IG colidiria com o do WhatsApp (merge silencioso ou erro de
    validação). Primeiro guardar em atributo próprio + label; mesclagem é decisão separada.
  - ✅ **[PR #107](https://github.com/Dev-Simplex/chatspx/pull/107) ABERTO** contra a `homologacao`
    (branch `PauloSeze/coleta-contato-ig`, 5 commits): `supports_reengagement?` como capacidade de
    canal (**true por padrão**, false só no Instagram) · `MessageWindowService#hours_remaining`
    derivado do MESMO `messaging_window` do `can_reply?` · bloco no `assistant.liquid` gateado por
    **três** condições · conta regressiva no bloco **volátil** (não invalida o cache do prefixo
    estável) · `salvar_info_lead` com `contato_alternativo`.
  - **A régua entregue** (decisão do Paulo: natural, e tentando antes de a janela fechar): pede
    quando há **motivo à vista** e diz qual é — nunca na saudação, onde soa cadastro · garante
    antes de transferir · **uma última tentativa** se a conversa caminha pro fim sem desfecho ·
    recusa não vira insistência · quem já informou não é perguntado de novo.
  - **O contato vai pro CAMPO CANÔNICO, não pra atributo solto** — correção de desenho que o
    Paulo provocou mostrando a tela de editar contato: guardar em `custom_attributes` deixava o
    número **onde ninguém procura**. Grava em `contact.phone_number` (normalizado pelo
    `BrazilPhoneNormalizer` que já existe, porque o callback do Contact reverte em silêncio o que
    não for E.164), com **duas guardas**: nunca sobrescreve telefone existente e nunca toma número
    de outro contato. A colisão é real e foi medida — a conta 6 tem **33.391 contatos com
    telefone** e **17% dos contatos do IG têm homônimo exato já cadastrado com número** — mas
    colisão **não é falha**: quer dizer que a pessoa **já é alcançável** pelo cadastro que existe,
    e unir os dois é decisão humana. Nos dois casos o número fica no atributo como rastro.
  - **Medido na `.232`:** suíte **83 exemplos / 0 falhas** contra baseline (`origin/homologacao`)
    de **43 / 0** — **+40 exemplos novos, todos passando**. Rubocop **23 = 23**, histograma
    idêntico cop a cop. Worktrees de CI e o banco `chatwoot_test_contatoig` removidos ao fim.
  - ⚠️ **ERRO MEU DE MEDIÇÃO, corrigido no PR:** numa primeira rodada apareceram **3 falhas** nos
    specs de `HUMAN_AGENT` e eu as reportei como pré-existentes, com "dívida de cobertura da flag
    de 7 dias". Rodando de novo, **ramo e baseline dão 0**. Eram **flake de ambiente**: o
    `GlobalConfig` lê do InstallationConfig **com cache no Redis**, e a box de CI **compartilha o
    Redis entre worktrees**. Não há dívida de cobertura. Lição: falha em spec que depende de cache
    compartilhado se confirma **rodando de novo** antes de virar afirmação publicada.
  - ⏭️ **Falta, e não está no PR:** ligar a config na conta 6 (`config['coleta_contato_alternativo']`
    nos 7 agentes) e **medir a conduta com N≥6 por cenário** — só depois do merge + deploy, porque
    o gate é código. **Fase 2:** o time/motor de fato USAR o número (HSM no WhatsApp); sem isso o
    dado fica parado.

- 🔵 **Achado colateral, não relacionado à janela:** 11 mensagens `failed` em 60 dias na inbox 101,
  **todas do `Captain::Assistant` e todas de anexo** — `100 - Upload failed` (8x) e
  `100 - The parameter message[attachments][1][type] is required` (3x), concentradas nas convs
  33147, 32979 e **33563 (05/09 13:15)**. A IA tenta mandar mídia no Instagram e falha; o cliente
  fica sem a foto. Frente própria, ainda não investigada.

### [2026-09-08] 🔴 A IA QUASE NUNCA CONFIRMA O NOME — o mecanismo está inteiro, falta a conduta

> Pergunta do Paulo: a IA está confirmando e salvando o nome? **Não.** Medido na conta 6.

- ✅ **A cadeia funciona ponta a ponta:** `salvar_info_lead` tem o parâmetro `nome_cliente`, grava
  em `contact.custom_attributes['nome_confirmado']` (nunca em `contact.name`, que nessa base é
  área de trabalho do time), a `CustomAttributeDefinition` **existe** (“Nome confirmado”) e o
  painel **renderiza**. Quando grava, grava certo — amostra conferida, e `nome_cliente` vazio não
  vira registro.
- 🔴 **Mas quase não acontece:** **410 de 33.526 contatos (1,2%)** têm nome confirmado ·
  **627 de 3.349 chamadas (18,7%)** da tool levam o nome · e numa amostra do WhatsApp com **14
  apresentações explícitas** (“meu nome é…”, “me chamo…”), **11 foram perdidas**.
- 🔴 **A causa: nenhum prompt manda perguntar nem confirmar o nome.** A Clara tem uma linha
  **passiva** (“se a pessoa der informações úteis (nome…), registre”) e o resto não toca no
  assunto. As linhas que o grep acha são sobre outra coisa — o nome DA IA, ou “em nome de quem o
  financiamento sairia”.
- 🟢 **E o dado sugere que conduta explícita resolveria:** as duas únicas agentes que pedem nome
  são as que mais gravam — **Helena 4 de 5 (80%)** e **Marina 17 de 40 (42%)** — contra **Clara
  233 de 1.806 (13%)** e **Bruna 19 de 144 (13%)**. ⚠️ N pequeno na Helena; é indício, não prova.
- 🔴 **A Clara — a TRIAGEM, a que fala primeiro — é a única dos 7 com
  `feature_contact_attributes` = `nil`.** Ela não recebe os atributos do contato, então não
  enxerga nome já confirmado em atendimento anterior e não tem como evitar perguntar de novo.
- 🔵 **No Instagram pesa mais:** **24 de 89** contatos têm emoji ou estilização no nome
  (“Lash Maria 👑”, “𝐾𝑎𝑟𝑜𝑙𝑖𝑛𝑎…”). Lá o `contact.name` não serve nem pra tratar a pessoa, e
  confirmar o nome real vale mais que no WhatsApp.
- ✅ **APLICADO (banco conta 6, sem deploy):** seção `# Nome de quem você está atendendo` nos
  **7 agentes** (+862 chars cada) e `feature_contact_attributes` **LIGADO na Clara** (era `nil` —
  ela era a única dos 7 sem os atributos do contato).
- 🟢 **O GANHO REAL: registrar o nome foi de 0/6 para 6/6.** Medido em transação revertida,
  pelo mesmo caminho do `ResponseBuilderJob`, contando **chamada de ferramenta** (não texto):
  Júlia **0/6 → 6/6** e Clara **0/6 → 6/6** quando a pessoa se apresenta. Bruna 3/6 na
  formulação intermediária.
- ➖ **NENHUM ganho no nome estilizado, e o baseline provou isso.** Com o cadastro em
  "Lash Maria 👑" a Bruna evita tratar a pessoa por ele **6/6** — mas o **prompt ANTIGO também
  dá 6/6**. Já funcionava; **não é ganho desta mudança**. (Medido restaurando o backup dentro da
  transação, com `update_columns`, e conferindo que produção ficou intacta.)
- 🔴 **PERGUNTAR o nome quando não sabe: 0/6, em TRÊS formulações** (“no meio da conversa” →
  “antes de passar pro time”), com cadastro vazio e com cadastro estilizado. **Conduta escrita
  não faz o modelo tomar iniciativa** — mesma lição da cutucada (31/08). O reativo (registrar o
  que a pessoa disse) pega; o proativo não.
  - ⏭️ **Conserto durável proposto é no PONTO DE DECISÃO, não no prompt:** fazer o **retorno da
    ferramenta de handoff** cobrar o nome quando ele faltar. Instrução que chega no instante da
    ação vale mais que parágrafo a 40k chars de distância — é código, pequeno, e ainda não foi
    feito.
- ✅ **NÃO-REGRESSÃO: `spx:conduta:regressao` → 10/10 cenários dentro do piso**, depois da
  mudança. (É a guarda que existe justamente porque em 28/08 uma conduta nova quebrou um
  cenário vizinho sem ninguém ver.)
- ⚠️ **TRÊS erros meus de medição nesta sessão, todos pegos antes de virarem afirmação:** (1) medir
  “pergunta o nome” na **Clara**, que é triagem e transfere no mesmo turno; (2) medir na conversa
  de rascunho **2159, que é do Paulo** — o cadastro tem nome, então a IA não tinha por que
  perguntar (“Perfeito, Paulo!” na resposta denunciou); (3) quase creditar o 6/6 do estilizado à
  mudança sem ter medido o baseline. **Detector e cenário se validam contra a resposta real
  antes de virarem número.**
- **Reversão:** `/tmp/assistant_<id>_ins_nome.bak-20260908112708` (antes de tudo) e
  `_ins_nome2.bak-20260908113304` (antes da troca de gatilho), na VM da Tozi.

### [2026-09-04] 🟢 DISPARO INQUILINOS (350) + o IP da box mudou + a órfã que era fantasma, não roteamento

- **Campanha #19** (Kettlen, base `INQUILINOS`): **344 enviadas / 6 falhas** (todas `131026`), 15:09→15:39 a **12/min**, número **GREEN**. Template `tozi_urban_kettlen_convite` — header de imagem, **zero variáveis**, botões *Quero conhecer* / *Me chama depois*, aprovado em 2 min.
  - **Copy sem variável foi a escolha certa por um motivo do dado:** ~40 registros da base são **empresa** (`123 PLACAS SOLAR LTDA`, `A M TRANSPORTES`). Com `{{1}}` sairia "Oi 123 Placas Solar Ltda".
  - **Cortes:** 3.919 linhas → 3.600 aptas (112 dup, 207 sem DDD descartadas) → **226 já disparados (motor novo) + 1.169 do disparo de JUNHO + 30 recusas + 99 em atendimento**. Sobram ~1.700 elegíveis.
  - 🟢 **A correção do ponto cego (22/08) se pagou de novo, em escala:** **1.169 pessoas** — um terço da base — teriam recebido mensagem repetida se a dedup ainda lesse só `campaign_recipients`.
- 🔴 **O IP da box da Tozi MUDOU: `3.82.215.109` → `3.94.9.51`.** Sintoma que engana: `tozi.chatspx.app` responde **HTTP 200** porque está atrás do **Cloudflare** (104.21.3.41), enquanto **22 e 443 estavam mortas** no IP velho. O helper do **repo principal já estava corrigido**; a cópia da worktree `chatspx-clientes/tozi-prod` — que é a que as sessões usam — estava para trás. **As duas precisam ser atualizadas juntas.** Antes de escrever, confirmei identidade da box (conta 6, inbox 99, campanhas #17/#18).
- 🟢 **A dúvida do disparo do Lucas (25/08) FECHOU: a regra #73 não tem defeito.** Ela atribuiu sozinha durante todo o envio (15:24, 15:27, 15:28, 15:36, 15:37 — "por Sistema de Automação"), e as 8 respostas caíram todas na Kettlen. **Dois disparos seguidos a 12/min, zero evento perdido.** A falha de automação de 25/08 foi a **saturação do Sidekiq a 60/min**, não um bug de pé.
- 🔴 **DEFEITO NOVO — envio que falha deixa conversa FANTASMA na fila do corretor.** O `RecipientDispatchService` **cria a conversa antes** de `send_hsm`; quando o envio estoura, a exceção pula o `close_with_team` e sobra conversa **aberta, vazia, sem dono** no time da campanha. Medido: **6 órfãs = 6 falhas, correlação 6/6 por telefone.** Quase reportei como falha de roteamento — o que distingue é **`messages.count == 0`**. Fechadas à mão (guarda: só toca em conversa com zero mensagem). ⏭️ Conserto durável é no motor: resolver (ou não criar) a conversa quando o envio falha.
  - **As falhas viram dado útil:** 6 inquilinos ativos com telefone que não está no WhatsApp — a Tozi não consegue alcançá-los. Lista no log da sessão.

### [2026-09-02] 🔴 CANAL DE INSTAGRAM DA BIGSTORE MORTO HÁ 3 DIAS — token invalidado, URL de reconexão PRONTA

> O Paulo notou que "as últimas DMs foram há 3 dias". Era isso mesmo, e é incidente de cliente.
> **Ele confirmou que a senha do Instagram provavelmente foi trocada.** Aguardando ele resolver a
> senha para reconectar — a sessão foi encerrada neste ponto, de propósito.

- 🔴 **Causa provada**, testando o token contra a Graph: `code 190` — *"The session has been
  invalidated because the user changed their password or Facebook has changed the session for
  security reasons."*
- **Corte limpo no volume:** 28/08=312 · 29/08=167 · **30/08=135, para às 12:29** · 31/08, 01/09 e
  02/09 = **ZERO**. Na média das semanas, **~900 mensagens de cliente que não chegaram** — e não
  ficam em fila para chegar depois.
- 🔴 **O SPX NÃO SABE.** O banco diz `expires_at = 2026-10-16`. Invalidação de sessão é coisa
  diferente de expirar, e nada no produto observa isso. **`expires_at` não serve como saúde**:
  mede prazo e todo mundo lê como "funciona".
- ✅ **Isolado:** a outra inbox de Instagram da box (Midwest, conta 3, inbox 56) respondeu
  `TOKEN OK` no mesmo teste. Não é a box, não é o app, não é o endpoint.
- 🔴 **A reconexão PELA TELA mintaria um token quebrado:** `INSTAGRAM_SCOPES` está **nil** na box,
  então cai no `REQUIRED_SCOPES` da constante, que traz só `instagram_business_basic` e
  `instagram_business_manage_messages` — **sem `manage_comments`**. Reconectar pela UI mataria a
  captura de comentários (mesma dívida registrada em 18/08; o Bloco 0 do #68 criou a chave de
  config, mas ela nunca foi preenchida).
- ✅ **URL DE RECONEXÃO MONTADA À MÃO, com os 3 escopos** — receita provada em 18/08: o callback do
  próprio SPX faz a troca e grava o token (zero off-git, zero escrita manual no banco):

  ```
  https://api.instagram.com/oauth/authorize?client_id=1147598410038941&redirect_uri=https%3A%2F%2Fchatspx.app%2Finstagram%2Fcallback&scope=instagram_business_basic%2Cinstagram_business_manage_messages%2Cinstagram_business_manage_comments&enable_fb_login=0&force_authentication=1&response_type=code&state=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOjcsImlhdCI6MTc4ODM5Mzk5OH0.QUDuQFxdB__oow8MKjFXgmXJ8RgwHSvw1JX3QuQpXUQ
  ```

  O `state` é JWT com `sub: 7` e **sem `exp`** — não expira. Para gerar outro:
  `Instagram::IntegrationHelper#generate_instagram_token(7)`.
- ⚠️ **A armadilha de 04/08 continua valendo:** OAuth rodado logado na conta errada conecta o
  Instagram **PESSOAL**. Abrir logado como `@bigstoreutilidades`. Conferir depois:
  `Account.find(7).inboxes.pluck(:id)` tem que continuar `[57]`, e o `/me` do token novo tem que
  devolver `bigstoreutilidades`.
- ⏭️ **Duas dívidas que este incidente expôs** (é a 2ª vez que um canal desta conta morre calado):
  **alarme de token morto** (varredura diária batendo na Graph — o canal de aviso já existe, é o do
  digest) e **preencher `INSTAGRAM_SCOPES`** na config de instalação, para a tela parar de mintar
  token incompleto. ⚠️ Essa chave é **global da box** — muda a tela de consentimento de toda conta.

### [2026-09-02] 🟢 UNIDADES: o parser parou de errar data com convicção, e a loja ganhou coordenada, pin e "a mais perto" (PR #88)

> Pedido do Paulo: usar bem a ferramenta de unidades para horário/endereço/telefone, mandar PIN e
> calcular a mais próxima. Mais a pergunta dele sobre expressões de data.

- 🔴 **O defeito que ninguém veria:** *"sem ser nesse, no outro sábado"* devolvia o sábado que a
  pessoa acabara de EXCLUIR — e devolvia marcado como **reconhecido**. O parser via a palavra
  `sabado`, ignorava o resto e respondia com convicção. Não é lacuna de cobertura: é resposta
  errada que nada acusa.
- **Decisão de projeto, contra as duas alternativas que o Paulo levantou:** nem tool separada de
  calcular data (adiciona um salto e um lugar a mais para transcrever errado, e não conserta o
  defeito), nem passar a data de hoje como parâmetro (move a aritmética para o modelo, e **erro do
  modelo é invisível** — quando o Ruby calcula, a data resolvida fica no retorno e no log). O
  desenho já estava certo; o parser é que estava guloso. **Recusar vale mais que adivinhar.**
- **Medido:** 30 expressões reais contra a prod — as 6 perigosas passam a recusar, as 4 de instante
  passam a resolver, e as **18 que já funcionavam saem idênticas**.
- **`daqui meia hora` é INSTANTE, não data** — caminho separado, e atravessa a meia-noite
  devolvendo a data do instante alvo (é o horário DESSE dia que importa).
- **Coordenada é dado ESTÁTICO, não geocoding em atendimento.** Medido: a conta 7 **não tem
  integração google nenhuma**, e o Google não avisa quando erra (na Tozi, 67 de 259 bairros a +3 km,
  um a 518 km). O ponto da PESSOA vem do pin que ela envia — provado, há anexo `location` inbound
  com coordenada real na box. Sem pin, a ferramenta não fala de distância: convida a mandar a
  localização, e só se houver unidade com coordenada.
- **Três decisões que os specs travam,** todas contra mandar a pessoa ao lugar errado: distância
  desconhecida **não vira zero** (unidade sem coordenada vai pro FIM) · coordenada inválida no CSV
  **não vira 0.0** (o ponto (0,0) fica no Golfo da Guiné) · *"existe a loja mas não tem coordenada"*
  é resposta **diferente** de *"não temos loja nessa cidade"*.
- **Medição:** **111 exemplos / 0 falhas** · rubocop **0 em 11 arquivos** (baseline era 0) ·
  `zeitwerk:check` All is good! · fluxo ponta a ponta com Sinop→Sorriso **~79 km** e Sinop→Cuiabá
  **~421 km**, que batem com a realidade.
- ⏭️ **[PR #88](https://github.com/Dev-Simplex/chatspx/pull/88)** aberto contra a `homologacao`,
  6 commits, `MERGEABLE`. **Não migra produção** — a migration rodou só no banco de teste da CI.
- ⏭️ **Item que ficou de fora: o HISTÓRICO datado** (inaugurada / fechada / mudou endereço / mudou
  telefone). O Paulo **respondeu as duas perguntas de formato**: é **evento** ("mudou de X para Y"),
  a **IA pode consultar**, mas serve mais para controle do time. Falta construir — e ele é
  **pré-requisito** para tirar as FAQs #84, #85 e #86 (as #80 e #88 já podem sair, a tool cobre).
  ⚠️ Junto dele: a tool precisa passar a **enxergar unidade inativa** quando a pessoa cita a cidade
  dela; hoje o filtro `.ativas` está na consulta E no `active?`, então a IA não tem como dizer que
  a loja fechou.
- ⚠️ **Sobra na `.232`:** worktree de CI `/tmp/ci-unidgeo`.

### [2026-09-02] 🔴 O CADASTRO DA BIGSTORE ESTAVA QUASE TODO ERRADO — e a página oficial do cliente resolveu

> Sequência de perguntas do Paulo ("Rondonópolis?", "e as demais?", "consegue pegar os números
> aqui?") que virou auditoria completa do dado. Vault: commits `a5867f4` e `f006746`.

- 🔴 **RONDONÓPOLIS ESTÁ FECHADA, e o vault dizia que não.** A `bigstore-lojas.md` a trazia entre
  as ativas, com endereço e telefone — e foi essa linha que quase fez a carga afirmar uma loja que
  não existe. O que decidiu não foi opinião: **o próprio time responde que ela fechou 63 vezes em
  60 dias**, e clientes foram até o endereço (*"fui no local aqui em rondonopolis onde era e nao
  tinha nada la"*). **A FAQ #84, que dizia o contrário do vault, estava certa.**
- **Varredura das 20 cidades no tráfego real:** só as três já conhecidas (Rondonópolis, Primavera
  do Leste, Cláudia) têm sinal de fechamento; as outras 17 têm **zero**. Dois falsos positivos
  derrubados: **Campo Verde** acusou 9 por co-ocorrência (ela é o **destino** no texto oficial,
  *"encerrar as atividades da unidade de Primavera e direcionar a operação para Campo Verde"*) e
  **Vera** deu 0/0 por erro meu de regex.
- 🔴 **15 DOS 19 ENDEREÇOS ESTAVAM ERRADOS**, e não eram erros de digitação — eram **outra rua**:
  Colíder (Marechal Rondon × **Tancredo Neves**), Juína (Nave do Manso × **Nove de Maio**), Alta
  Floresta (outra rua E outro bairro), Socreppa (outro número E outro bairro). Corrigidos pela
  **página oficial** que o Paulo mandou: `https://bigstoreutilidades.my.canva.site/` (texto em
  imagem — lido por screenshot; os telefones saem dos links `wa.me` do DOM).
- ✅ **Os telefones resistiram: 18 dos 19 conferiram**, incluindo os 14 marcados como
  "reconstruídos". Um errado: Nova Bandeirantes, `+5566992472864` → **`+5566997140151`**.
- 🔴 **ERRO MEU, e a lição vale mais que ele:** eu tinha entregue as coordenadas como *conferidas*.
  Elas apontavam para os endereços velhos. **As 9 verificações por distância passaram assim mesmo**,
  porque continuavam sendo pontos na cidade certa — **distância entre cidades não detecta erro
  dentro da cidade**. A verificação estava um nível acima do dado que ela deveria checar.
- ✅ **Regeocodificadas com a chave do Google da conta 6** (autorizado pelo Paulo; a chave não sai
  daquela box), verificação em três camadas: UF do resultado · caixa geográfica do estado · **veto
  por raio de 15 km** entre o endereço e o centro. Qualidade subiu de forma visível: **8 resultados
  `ROOFTOP`** (porta exata) contra 2 antes. 10 conferências por distância real, **zero falha**.
- ⚠️ **A página oficial também está desatualizada, nos dois sentidos:** lista Cláudia, Primavera e
  Rondonópolis (fechadas) e **não tem Ji-Paraná, Pimenta Bueno nem Vilhena**. Nenhuma das duas
  fontes está completa — **o CSV de carga está**, e passa a ser o único lugar com coordenada (a
  tabela do vault não a duplica de propósito: duplicar dado foi como ela ficou errada).
- **CSV final:** 19 ativas + 3 inativas. As três fechadas entram como `ativa=false` em vez de linha
  ausente — a tool ignora inativa (filtro `.ativas`), então a IA não as oferece, mas o time as vê
  marcadas na tela e a memória de que existiram não se perde na próxima recarga da planilha do
  cliente (que ainda as lista normais, porque não tem campo de status). **As 3 inativas não têm
  coordenada**, de propósito: pin de loja fechada não pode ser enviado.
- ⚠️ **Juruena vetada:** o endereço oficial geocodifica a **19,9 km** do centro. Ficou o centro.
- ⏭️ **Carga NÃO foi feita.** `rails 'spx:unidades:carregar[7,unidades-bigstore.csv]'` depende de:
  merge do #88 → deploy da `.232` (a migration das coordenadas) → então carregar.
- ⏭️ **Perguntar ao cliente:** a página oficial vai ser atualizada? Hoje ela manda gente para três
  lojas que fecharam e esconde três que existem.

### [2026-09-01] 🔴→🟢 AS INBOXES SUMIRAM NO chatspx.app — deploy pela metade, e o conserto veio no mesmo dia

- **Nada foi apagado:** 17 inboxes no banco, as 5 contas intactas, e a API respondeu **200 para os
  15 usuários** da conta 3 (admins 9, agentes 3–4 — o correto, por membresia).
- **O que houve:** merge feito **direto no disco da box** às 14:59 (`simplex`, 295 commits de
  `origin/homologacao`), web reiniciado às 17:31 — e **parou aí**. Ficaram **13 migrations
  pendentes** e os assets de **28/08**, com o merge trazendo **39 arquivos de frontend nunca
  compilados**. Ruby novo servindo JavaScript de quatro dias atrás.
- ✅ **Resolvido às 18:16–18:25:** migrate + precompile + restart, na ordem certa. Migrations
  13 → 0. A migration `Features padrao da frota`, que eu tinha sinalizado como a mais arriscada
  (toca todas as contas da box, incluindo 4 de cliente real), rodou e foi **no-op** — contei antes
  e depois: conta 1 = 48, conta 3 = 47, conta 7 = 41, **zero delta**.
- ⚠️ **O problema de fundo voltou e está pior:** a box tem **315 commits que o GitHub não tem**.
  Qualquer `checkout` nela os destrói. O **PR #71 morreu de morte natural** (a reconciliação foi
  feita dentro da box); vale fechá-lo apontando o motivo, senão confunde quem abrir a fila.

### [2026-09-02] 🔴 EU DERRUBEI A BUSCA DE IMÓVEL EM PRODUÇÃO — teto do Vista é 50, pedi 60

> O Paulo trouxe a conv 33031: cliente pediu kitnet até R$ 1.100 e a IA disse que **não havia
> kitnet nenhuma**. Havia **17**. O consultor teve que desmentir por áudio.

- 🔴 **O Vista recusa paginação acima de 50:** `HTTP 400 — "O limite de resultados por página
  deve ser 50"`, e o fetch volta **VAZIO, sem erro visível**. Medido: quantidade 49 e 50 trazem
  os 17 kitnets; **51 e 60 trazem ZERO**.
- **A regressão foi minha, do PR #90:** para consertar o "são todas as opções", fiz o
  `quantidade_para` devolver `TETO_INSPECAO` (60) em TODOS os ramos. Derrubou **toda busca
  comum de imóvel** desde o deploy da manhã.
- 🔴 **E explica um defeito antigo:** o ramo `mobiliado` já usava TETO_INSPECAO=60 desde o
  PR #75 — ou seja, **nunca funcionou**. Era dele o *"Conferi 0 imóvel(is) e NENHUM está
  cadastrado como mobiliado"* que aparecia com o acervo cheio (inclusive na conv 33006, e eu
  li aquilo como "não há mobiliados").
- ✅ **Corrigido no #90:** `TETO_INSPECAO = 50` + spec exigindo que **nenhum ramo** peça mais
  que isso. **269 exemplos / 0 falhas** · rubocop 18 = 18.
- ⚠️ **A lição:** mudei paginação só no código e testei o filtro de suíte ao vivo — a
  paginação, não. O limite de 50 estava registrado desde 15/07 no próprio STATE.

### [2026-09-02] 🟢 VISITA DE LOCAÇÃO: a regra é do time e a conduta a contradizia (conta 6, sem deploy)

> Conv 30442: a Bruna perguntou *"Quer agendar pra conhecer a kitnet?"* — **duas vezes** — e
> depois *"que dia e período ficam melhores"*. A consultora desfez por áudio: *"a visita a
> gente não agenda"*.

- **A REGRA, medida na fonte viva** (resposta pronta que Evellyn e Adrian mandam, ~110x/30d):
  **não se agenda nem se reserva** · o cliente passa no escritório **no horário de
  atendimento** · deixa **documento físico com foto** · retira a chave e visita por conta
  própria · **devolve no mesmo dia**. Ocorrências em 30 dias: "não agendamos/reservamos" 115 ·
  "documento com foto" 116 · "mesmo dia" 108 · "horário de atendimento" 107.
  Em **condomínio fechado** segue agendada e acompanhada (régua do Paulo, 28/08).
- 🔴 **O furo era meu, da conduta de 28/08:** eu escrevi *"quem confirma o acesso é o
  consultor"* e *"o consultor confirma antes"* — isso **sugere que há algo a combinar**, e foi
  por essa brecha que saiu o "que dia e período". O time diz o oposto.
- 🔴 **Não foi falta de dado:** ela chamou `buscar_imovel` **3x** e tinha o rótulo
  `[NÃO fica em condomínio fechado]`. O 9623 é avulso (`Condominio: "Nao"`, conferido no Vista).
- 🔴 **E o harness media 6/6 enquanto a produção falhava:** o cenário existente cobre o cliente
  **PEDINDO** visita; o defeito passou pelo caminho oposto — a IA **OFERECENDO** antes de
  pedirem. Virou o 10º cenário (no PR #85), com os padrões conferidos contra as três frases
  reais da conversa.
- **Medido depois:** cenário real da 30442 **0/6 oferece agendamento · 6/6 explica a chave** ·
  harness de visita 6/6, 6/6, 6/6 (avulso, condomínio, venda).
- ⚠️ **Correção do Paulo ao meu diagnóstico:** a Júlia **não** recebe locação — a conversa
  estava com ela por resíduo de disparo antigo atribuído ao time de vendas, e ela transferiu
  corretamente. Quem agendou foi a Bruna.
- **Reversão:** `/tmp/assistant_14_ins_visita_chave.bak-20260902165602` na VM.

### [2026-09-01] 🟢 FRENTE CAMPANHAS — o módulo fecha (PR #89) · contrato em `docs/contratos/campanhas.md`

> Pedido do Paulo: *"quero campanhas completo"*. O levantamento inverteu a expectativa: o motor
> e a API **já estavam prontos**, e a tela usava parte deles.

- 🔴 **ERRO MEU DE DIAGNÓSTICO, corrigido no meio:** reportei que "a tela não usa nada da API".
  Falso — eu tinha lido só o `WhatsAppCampaignForm` (criação) e não o **`DispatchPanel`**, que
  fica no detalhe e **já fazia** upload de lista, preview de audiência com os 9 motivos de
  descarte, materialização, start, pause e progresso com polling. **Ler o componente que a rota
  monta, não o que o nome sugere.**
- 🔴 **Segunda correção:** minha nota dizia que sem `target_team_id` o motor *"envia e marca
  failed"*. Não é isso — a conversa nasce com **`team_id` nulo**, e o reply do lead cai sem time
  e sem dono. É o mesmo buraco que a regra #73 fechou à mão em 14/08.
- ✅ **Opt-out que GRAVA.** A `contact_flow_suppressions` tinha **ZERO linhas na instância
  inteira**, e não por falta de leitor (o `AudienceBuilderService` já tem `optou_por_sair`).
  Dois furos: o gravador só rodava dentro do `run_flows` (exige `flows_engine_enabled?`, falso
  na conta 6) e o matcher exigia **match exato** contra `parar|sair|stop|cancelar` — que
  capturou **zero** mensagens desde sempre.
  - **Substring seria pior:** *"Nao tenho interesse em compra. **Gostaria de opções de casa para
    locação**"* e *"não tenho interesse... **to com um terreno pra colocar a venda**"* são leads
    quentes. Comprimento também não serve: *"Obrigada, mas não tenho interesse."* tem 34 chars.
  - **Critério = DOMINÂNCIA:** é opt-out quando, tiradas a recusa, as saudações e as cortesias,
    **não sobra pedido**. Medido em 7.145 mensagens: 305 têm frase de recusa, **233 dominadas**
    (232 contatos), 72 mantidas por terem pedido junto.
  - **Escala do dano hoje:** 452 contatos pediram para parar e **12 receberam disparo depois** —
    um pediu em janeiro e recebeu em agosto.
- ✅ **Configuração do motor na tela** (`DispatchSettings`): time, corretor, pacing, janela e
  health gate saíram do console. A tela diz o que não é óbvio — sem time a conversa fica sem
  dono; atribuir pessoa **só vale em caixa sem IA**; a janela é por **hora cheia** (o motor
  compara `Time.current.hour`, então 16:30 não é expressável).
- ✅ **Público pela BASE** (`SegmentService`): etiqueta, time, caixa, campanha anterior (ou quem
  **não** recebeu), recência e "nunca recebeu nada". Devolve as mesmas `rows` do upload e
  desemboca no mesmo `recipient_rows` — **uma higiene só**. "Recebeu campanha" lê os **dois
  motores**, que é o que faltava quando 294 pessoas levaram o mesmo assunto duas vezes.
  Critérios se **somam**; sem critério o botão fica desabilitado (a base inteira não é público).
- ✅ **Modelo de planilha baixável** (com BOM, senão o Excel estraga os acentos) e **XLSX
  recusado com instrução** — antes virava "0 linhas" sem dizer por quê. Não entrou dependência
  nova de front: repo de produção.
- **Medido:** **76 exemplos / 0 falhas** · rubocop **2 = 2** do baseline (pré-existentes no
  `campaign_stats`) · eslint **0 erros** nos 3 arquivos de front (baseline tinha 6) · i18n `en`
  e `pt_BR`.
- ⚠️ **Erro meu recorrente, 2ª vez no dia:** o modificador `/x` no regex ignora espaços
  literais — `não tenho interesse` virou `nãotenhointeresse` e a 1ª medição deu **0 de 305**.
- ⏭️ **Pendente de autorização:** backfill dos **232 contatos** que já pediram para parar. É
  escrita em produção.
- ⏭️ **Tela NÃO verificada visualmente** — só fecha depois de deploy.

### [2026-09-01] 🟢 O FOLLOW-UP AUTOMÁTICO JÁ EXISTIA — e estava desligado por um gate invisível

> O Paulo apontou a conv 32835 (parada 55h sem cutucada). A causa não é o modelo esquecer:
> **o `auto_schedule_followup` é determinístico e roda no próprio turno** (`response_builder_job`),
> mas o `auto_followup_enabled?` tem **opt-in implícito**: *só liga para agente que já TEM a
> ferramenta `programar_followup`*. A Clara não tinha até 31/08.

- **Ao dar a ferramenta a ela em 31/08 eu liguei o auto sem saber.** Antes: **0 de 191**
  conversas com cutucada. Depois: **11 conversas, 9 com cutucada marcada, 8 disparadas** — as 2
  sem marca não precisavam (numa a última fala é do cliente).
- 🔴 **Erro meu de medição, corrigido:** primeiro contei chamadas da **ferramenta** e li "3 de
  15". O auto **não passa pela ferramenta** — grava direto em `followup_token`/`followup_status`.
  O número certo é 8 de 11. **Medir o efeito, não o caminho.**
- ✅ **Os 7 agentes da conta 6 estão com o auto ligado hoje** (todos têm a ferramenta, nenhum tem
  `behavior['followup']['auto'] = false`). Auto-agendamento a cada 120 min por padrão.
- **O estoque parado NÃO é defeito, e a separação importa:**
  - **Clara: 179** paradas sem cutucada — todas anteriores a 31/08, explicadas pelo gate.
    **Só 1 ainda está dentro da janela de 24h**; as outras 178 já não alcançam por texto livre.
  - **Júlia: 72** — todas com **`msgs = 1`**, ou seja **disparos que o cliente nunca respondeu**.
    Sem fala dele não há janela aberta, então cutucada não se aplica por construção. Quem
    alcança esse grupo é template, e **repescagem segue não existindo**.
  - Bruna: 3 paradas, 1 sem cutucada.
- ⚠️ **A armadilha a lembrar:** o gate é silencioso. Agente novo sem `programar_followup` nasce
  **sem follow-up nenhum** e nada avisa — foi assim que a Clara passou meses sem cutucar.
- ⏭️ A conv 32835 não teria como ser cutucada hoje (janela fechada há 2 dias). Ela também **não
  chamou ferramenta nenhuma** no atendimento inteiro — nem `salvar_info_lead`: o lead não foi
  registrado.

### [2026-09-01] 🟢 AS 3 CONVERSAS DO DIGEST VIRARAM CONSERTO (PRs #84 e #85) — e o harness estava morto

> As 3 do digest de 01/09. Uma era cegueira já corrigida do juiz; as outras duas eram defeito
> real, e as duas foram consertadas hoje. **O juiz corrigido (#78) chegou na VM em 31/08 16:13
> e as avaliações são de 11h–12h** — foram julgadas pela versão cega, o que explica o R$ 500.

- 🔴 **COOLDOWN DE FOTOS (conv 32828) — 27,8% dos pedidos eram recusados.** Medido em 30 dias
  sobre `captain_tool_calls`: de **654 chamadas**, **182 recusadas pelo cooldown**, e **163
  delas de um imóvel DIFERENTE** — o cliente tinha pedido outro. Desfecho: de **144 pares
  (conversa, imóvel) em 85 conversas, 99 (68,8%) NUNCA receberam as fotos**, nem da IA nem de
  humano.
  - **A frase da recusa descrevia uma exceção que o código não tinha:** *"só envie de novo se
    ele pedir explicitamente"* com o `return` já executado. A IA lia, via que ele tinha pedido,
    prometia *"vou te mandar já já"* e não tinha como cumprir.
  - ✅ **[PR #84](https://github.com/Dev-Simplex/chatspx/pull/84):** a régua passa a ser o
    **turno** (imóveis distintos desde a última fala do cliente), lida do `property_code` que a
    própria ferramenta já carimba — sem estado novo. Teto de 3 por turno; o **mesmo** imóvel
    nunca conta contra si. Anti-alucinação passou para ANTES (código inventado não ocupa vaga).
    `fotos_ultimo_envio_at` deixa de ser gravado.
  - **Isto substitui a `docs/SPEC-fila-envio-fotos.md`:** o que sobra da fila é só o
    espaçamento de 20s, e ele custa job novo, estado novo e 4 portões de cancelamento.
  - **O motivo do freio encolheu sozinho:** com `fotos_carrossel` ligado (Júlia, Bruna, Sofia),
    um imóvel é **uma mensagem**, não nove fotos soltas.
  - **Medido:** 264 exemplos / 0 falhas · rubocop **11 = 11** do baseline.
- 🔴 **A CLARA INVENTAVA GEOGRAFIA (conv 32833) — 6/6, e se contradizendo.** Ela **não tem
  ferramenta nenhuma** de imóvel, mapa ou localização (só registro e roteamento), e descreveu
  o bairro do anúncio. Medido: **6/6 afirmaram geografia**, três dizendo *"região norte"* e
  três *"região sul"* do MESMO bairro — a contradição É a prova de invenção.
  - ⚠️ **Mudei de recomendação no meio, por dado:** eu ia dar `buscar_localizacao` a ela. O
    achado de 28/08 desaconselha — o geocoding de bairro em Sinop **erra 26%** (67 de 259 caem
    a +3km; um a 518km) e o Google **nunca diz que não achou**. Seria trocar invenção por dado
    errado com cara de certo, e ainda não responderia *"é longe do centro?"*.
  - ✅ **Conduta no banco (conta 6, sem deploy), +805 chars:** pergunta sobre onde fica,
    distância ou perfil de região → **transferir**, porque a especialista tem `buscar_imovel`,
    que calcula distância de verdade. Ação positiva, não proibição.
  - **Medido: geografia 6/6 → 0/6** e `transferir_para_agente` **2/6 → 6/6**.
  - **Reversão:** `/tmp/assistant_7_ins_geografia.bak-20260901133837` na VM.
- 🔴 **O HARNESS DE REGRESSÃO NUNCA RODOU** — a rake chamava `Regressao.new(conversa:)` e o
  serviço espera `conversation:`. `ArgumentError` antes da 1ª rodada. **O "8/8 dentro do piso"
  que registrei em 28/08 foi medido antes dessa divergência e ficou valendo como se fosse
  verdade.** A ferramenta feita para pegar regressão estava, ela mesma, em regressão silenciosa.
  - ✅ **[PR #85](https://github.com/Dev-Simplex/chatspx/pull/85):** o keyword + o incidente da
    32833 como **9º cenário**. Rodado de verdade pela 1ª vez: **8/8 dentro do piso**, e o
    cenário novo **6/6**. O de pergunta aberta subiu de 3/6 para **5/6**.
  - **O cenário novo só tem `proibe`** (a forma de não afirmar varia) e os 4 padrões foram
    conferidos contra as frases reais da conversa — regex que não casa nada passaria 6/6 sem
    medir nada, que é o pior tipo de verde.
- ⚠️ **Erro meu no caminho:** o 1º detector de geografia usava o modificador `/x`, que **ignora
  espaços literais** — `região norte` nunca casaria, e a 1ª medição saiu **0/6 quando era 6/6**.
  É a 5ª vez que detector grosseiro dá leitura errada. **Validar o detector contra a frase real
  antes de confiar no número.**
- ⏭️ **Esperando merge:** #81 (follow-up) · #82 e #83 (cron das 7h) · #84 · #85.
- ⚠️ **Sobras na `.232`:** worktrees de CI `/tmp/ci-fotos-turno` e `/tmp/ci-fotos-base`.

### [2026-08-31] 🟢 FOLLOW-UP: a cutucada para de silenciar à noite e o horário do cliente para de sumir (PR #81)

> Pedido do Paulo: *"e se o cliente chamou a Tozi às 23h? Ele não recebe cutucada? Uma redução na
> cadência seria interessante, não silenciar por completo"*. As três camadas que ele nomeou —
> **cutucada** (sutil), **agendamento** (o cliente diz a hora) e **repescagem** (fora da janela) —
> estavam fundidas num mecanismo só, e as regras da primeira apagavam a segunda.

- 🔴 **Erro meu de medição, corrigido antes de virar desenho:** a 1ª consulta usou
  `AT TIME ZONE 'America/Cuiaba'` numa coluna `timestamp without time zone` que guarda **UTC** —
  o deslocamento dobrou e saiu uma distribuição impossível (2 mensagens às 10h, 4.182 à
  meia-noite). Refeita convertendo pelo Rails. **Ler o tipo da coluna antes de converter fuso.**
- **O dado que derrubou a faixa antiga** (mensagens do CLIENTE por hora, 14 dias, 21.218 no total):
  21h=242 · 22h=156 · 23h=99 · **0h–5h≈114 no total** · 6h=157 · **7h=667**. Às 7h há mais
  movimento que às 18h (428). O silêncio de **21h→8h cobria duas pontas com gente conversando**;
  a faixa real de descanso é 0h–6h. Passou a **22h→7h**.
- **Dentro da faixa a cutucada desacelera, não se cala.** A régua é a **última fala do cliente**:
  quem escreveu na última hora recebe, com espaçamento de 45 min contados da fala dele; quem já
  sumiu espera a manhã. **Não precisou de contador novo** — se ele não responde à cutucada da
  noite, a seguinte já o encontra fora da janela de "acordado" e cai pro dia seguinte: no máximo
  uma por noite, por construção.
- 🔴 **A armadilha que quase furou a faixa inteira:** o `compromisso?` do job lê `followup_motivo`,
  e `motivo` é **obrigatório** na ferramenta — ou seja, ele significa "programado pelo agente",
  **não** "o cliente marcou hora". Usá-lo como critério de isenção liberaria **toda** cutucada.
  Quem marca hora é a `janela`, e é ela que isenta. Os dois conceitos agora são predicados
  separados, com o `compromisso?` intacto onde ele já valia (a despedida educada não desmarca o
  combinado — conv 20320).
- **A janela é consumida ao ser cumprida** (vira `followup_janela_cumprida`, preservando o rastro):
  senão a isenção da faixa vazaria pras cutucadas preventivas seguintes da mesma conversa. É a
  mesma armadilha que o consumo do `motivo` já tratava.
- **Teto separado:** cutucada segue em 2 dias, horário pedido pelo cliente vale **7**. Com um teto
  só, *"quinta de manhã"* era encurtado calado pra **quarta 20h** e *"sábado à tarde"* também — a
  cutucada chegava **antes** da hora e ninguém ficava sabendo.
- 🔴 **Dois buracos no parser que o próprio teste expôs**, os dois terminando em `minutos_ate = nil`
  e no palpite do modelo prevalecendo: **`"me chama as 21h30"` não casava** (o padrão terminava em
  `\b` e entre o `h` e o `3` não há fronteira de palavra — a forma mais comum de dizer hora
  quebrada em português era a única que falhava, enquanto `21h` e `21:30` funcionavam); e
  **`"semana que vem"` não era data nenhuma** (o cliente pedia uma semana e a cutucada saía
  minutos depois).
- **Medido:** spec do job **24 exemplos / 0 falhas** (6 novos) · rubocop **4 no ramo × 4 no
  baseline** nos mesmos arquivos · parser exercitado em **14 formas reais** na `.232`, com
  controle (`"quando der"`, `"assim que puder"`, `"sem pressa"` seguem nil — não inventa janela).
  **Harness de conduta não foi rodado de propósito:** a mudança é toda de código de agendamento,
  nenhum prompt nem descrição de ferramenta foi tocado.
- ⏭️ **[PR #81](https://github.com/Dev-Simplex/chatspx/pull/81)** aberto contra a `homologacao`
  (3 commits, 3 arquivos). Só vale na Tozi depois de mergear + promover + deployar.
- ⏭️ **Repescagem segue não existindo** — decisão mantida. Fora da janela de 24h a cutucada morre
  definitivo; quem bate na porta lá fora é template, e essa forma não foi construída.
- ⚠️ **Bordas declaradas no PR:** `"hoje às 18h"` dito às 20h30 agenda pra amanhã (o `momento_de`
  empurra janela vencida, e cutucar no passado não é opção) · o `business_hours` do assistente
  segue ignorado pelo job, dívida já registrada no `docs/contratos/eixo-followup.md`.
- ⚠️ **Sobra na `.232`:** worktrees de CI `/tmp/ci-followup` e `/tmp/ci-fu-base`.

### [2026-08-31] 🔴 CONV 32808 — mais DUAS cegueiras do juiz, e a nota 4 quase toda indevida

> O Paulo leu o atendimento, achou a condução boa e questionou a nota 4 com 5 categorias.
> Conferi finding a finding: **a maioria não procedia**, e por duas causas novas.

- 🔴 **ÁUDIO virava `[audio]` no transcript.** O cliente perguntou **por áudio** *"essas
  casinhas aonde mesmo? que cidade que é?"*; a IA respondeu *"É aqui em Sinop mesmo, MT"* — a
  resposta EXATA — e levou **`nao_respondeu_pergunta` ALTA**, porque pro juiz ela falou de
  Sinop do nada. O agente recebe a transcrição; o juiz recebia o rótulo do anexo.
- 🔴 **O `SPEC_CHAR_LIMIT` de 14k cortava a norma no meio.** **7 dos 8 agentes truncados** —
  Júlia perde **71%**, Bruna 64%, Sofia 56%, Clara 47%. O estrago: a regra *"quando há
  restrição no nome existem produtos da casa que atendem"* mora no **char 15.825** do prompt
  da Júlia. Ela cumpriu à risca e levou **`info_incorreta` ALTA em cima da própria norma**.
- **Os outros findings:** `handoff_ausente` **e** `handoff_tardio` na MESMA conversa
  (incoerentes entre si; o handoff saiu em **7 minutos**) · o juiz reclamou de ela seguir
  respondendo depois do handoff, mas o retorno da ferramenta manda *"CONTINUE atendendo até o
  atendente assumir"* · `repeticao` contada **3x pro mesmo trecho**, inflando a nota pra baixo.
  **Procedia só o `quebrou_regra`** (a Clara qualificando renda contra a norma dela).
- ✅ **No mesmo [PR #78]:** transcrição de áudio via `content_for_llm` (método que o próprio
  `Message` já expõe) + **`SPEC_CHAR_LIMIT` 14k → 60k**. Custo medido: **+8,4k tokens/avaliação
  × 254/dia ≈ US$ 26/mês** no gpt-4.1-mini, e menos com prompt caching (o `spec_context` é
  idêntico entre avaliações do mesmo agente). **11 exemplos / 0 falhas · rubocop 11 = 11.**
- 🟢 **O defeito que o Paulo viu e o juiz não tem categoria: PERGUNTA FECHADA.** O cliente
  respondeu **"Sim" 4 vezes seguidas**, e a IA teve que voltar e perguntar *"você mora de
  aluguel, é isso?"* pra desfazer a ambiguidade que ela criou. Virou **cenário do harness**
  (`pergunta aberta, não interrogatório`) — mediu **3/6 e 5/6**, piso no **pior**, porque
  vermelho intermitente por variância ensina a ignorar o vermelho.
- **Conjunto de regressão: 8/8 dentro do piso** depois de tudo.
- ⚠️ **Erro meu no caminho:** escrevi `\b` em string Python não-raw e gravei **4 bytes 0x08**
  no YAML do harness — `Psych` recusou o arquivo inteiro. Segunda vez no dia que escape de
  string me morde (a 1ª foi `\m` em heredoc de SQL).

### [2026-08-31] 🔴 O JUIZ JULGAVA CEGO — e o Paulo pegou lendo as conversas (PR #78)

> O digest começou a chegar no grupo e o Paulo leu as 5 primeiras de duas rodadas. Discordou:
> *"pra mim o único defeito foi falta de follow-up"* e *"nenhuma estava apta a fazer handoff"*.
> **Ele tinha razão, e eu tinha confirmado o contrário.**

- 🔴 **O "R$ 500/mês" NÃO era alucinação — é o texto do anúncio.** As conversas trazem
  `meta_anuncio: "Saia do aluguel — a partir de R$ 500/mês"` nos `custom_attributes`, e o
  **agente RECEBE isso no state** (conferido: `'500' presente = true`). A Clara repetiu o
  criativo, que é o comportamento certo.
- 🔴 **ERRO MEU DE MÉTODO:** eu "confirmei" a alucinação procurando o valor no prompt e nas
  FAQs. Não olhei nos atributos da conversa, que era onde estava. Cheguei a escrever que era
  "invenção pura" com 128 ocorrências.
- **A causa no código:** `conversation_eval_service.rb` **não menciona `custom_attributes` em
  lugar nenhum**. O juiz recebe prompt do agente (truncado em 14k), transcrição e tool calls —
  e **nada da origem**. Vê a IA citar o valor sem fonte visível e marca `alucinacao` alta.
- **Escala:** **61 dos 275** findings de alucinação em 30 dias vêm de conversa com
  `meta_anuncio` carimbado. A amostra confirma (conv 6066 acusada por dizer exatamente a frase
  do próprio anúncio dela).
- ✅ **[PR #78](https://github.com/Dev-Simplex/chatspx/pull/78):** bloco `ORIGEM DA CONVERSA`
  no prompt do juiz (anúncio, campanha, origem, tipo, jornada — os mesmos campos do agente),
  dizendo que a origem é **fonte legítima**; `handoff_ausente` passa a exigir **gatilho
  concreto** e diz que *resolver sozinha é o esperado* (pedido do Paulo: "nem toda conversa
  precisa ser transferida para humano"); e **`transferencia_ausente` nasce separada** de
  `handoff_ausente` — IA→IA e IA→humano eram o mesmo balde.
  **8 exemplos / 0 falhas · rubocop 11 = 11 do baseline.**
- 🟡 **A CUTUCADA DA CLARA — conduta NÃO resolveu, e isso é o dado.** Decisão do Paulo
  ("cutucada"). Diagnóstico: ela era a **única dos 8 agentes sem `programar_followup`** e o
  prompt dela **não citava follow-up em nenhuma linha**. Escala: **208 conversas dela abertas
  sem humano em 30 dias, 159 paradas há +48h, 205 sem cutucada**.
  - **Aplicado:** ferramenta habilitada + seção de conduta copiada quase byte a byte da Júlia
    (que usa 92x/30d, então é texto provado). Backups
    `/tmp/assistant_7_{ins,tools}_followup.bak-20260831102906` e `_ins_fu2.bak-20260831103054`.
  - 🔴 **Medido, e não funcionou: cutucada 0/6 → 0/6 → 1/6** (a 3ª medição já com a seção
    movida pro FIM do prompt, testando a hipótese de posição). **Conduta escrita não segura
    isso** — é a mesma lição do dia inteiro.
  - 🟢 **Efeito colateral que resolve o problema por outra via: a transferência pra Júlia foi
    de 0/6 → 3/6 → 5/6.** E aí não cutucar está CERTO: a Júlia assume, e ela tem e usa
    cutucada. O lead deixa de morrer porque passa pra quem sabe cuidar dele. ⚠️ Não isolei a
    causa (N=6, sem controle) — não afirmo causalidade, só registro o antes e o depois.
  - ⏭️ **O conserto durável é determinístico, não conduta:** um job que varre conversa de IA
    parada há X horas sem humano e dispara a cutucada. Não depende de o modelo lembrar.
- ✅ **O harness (PR #77) fez o trabalho dele:** rodado depois de mexer na Clara, acusou
  "taxa de condomínio" em 4/6. **Era falso negativo do MEU detector** — as respostas diziam
  *"nenhuma das duas fica em condomínio"* e o regex só aceitava *"não ficam"*. Corrigido →
  **7/7 dentro do piso**. É a 3ª vez que detector grosseiro acusa falha onde não houve.
- ⚠️ **O que o juiz NÃO pega e o Paulo viu:** as 4 conversas estão paradas há **88–95h**, sem
  humano, sem follow-up. O juiz mede aderência à norma; não mede lead que morre.
- ✅ **A Clara transfere sim** — 661 `transferir_para_agente` em 30 dias, 49 dos 94 leads de
  anúncio. Nas 4 que ele leu, não transferiu.
- **Digest: teto removido a pedido dele** (`nota_maxima` fora, `limite: 50`, e o nó do n8n
  sem `TETO`). Motivo medido: o corte em 2 na rodada de 30/08 deixou passar **1 de 6**, e
  entre as 5 silenciadas estava a **conv 4809** — a que gerou toda a investigação de sexta.
- ⚠️ **Bug meu no nó do n8n:** o Webhook entrega o corpo em `.body`, não na raiz — o fluxo
  concluía "dia sem falha grave" com 13 conversas no payload. Corrigido.
- 🔴→✅ **O DIGEST CHEGAVA ÀS 11h, NÃO ÀS 7h — erro meu, corrigido em 31/08.** O sidekiq-cron
  agenda no **`Time.zone` da aplicação** (`America/Manaus`, UTC-4), **não em UTC**. Meu
  comentário no `schedule.yml` dizia *"11h UTC = 7h em America/Cuiaba"* e estava errado nos
  dois sentidos: `0 11` disparava às **11h da manhã do próprio cliente**. Ele recebeu assim
  **três dias** antes de notar.
  - 🔴 **CORREÇÃO (01/09): isto NÃO estava consertado, e o digest voltou às 11h.** Duas falhas
    minhas empilhadas, as duas medidas hoje:
    1. **O commit do `schedule.yml` ficou órfão.** Eu o fiz em 31/08 na branch do PR #77 — que
       **já tinha sido mergeado em 29/08 19:49**. Branch de PR fechado não entra em lugar
       nenhum: `a021b99f57` não está nem na `homologacao` nem na `producao`, as duas seguem
       com `0 11`. Eu registrei aqui como "corrigido no PR #77" sem conferir.
    2. **O remendo ao vivo não sobrevive, por construção.** O `apt-daily-upgrade.timer` roda
       **todo dia às 06:05 UTC (02:05 em Sinop)** e reinicia o worker — hoje ele subiu 36s
       depois do timer. Todo boot recarrega o `schedule.yml` do disco e sobrescreve o Redis.
       Enquanto o arquivo disser `0 11`, o horário volta toda madrugada, **antes** das 7h.
       Refazer ao vivo seria inútil.
  - ⏭️ **[PR #82](https://github.com/Dev-Simplex/chatspx/pull/82)** (contra a `producao`, que é
    onde a Tozi sente) e **[PR #83](https://github.com/Dev-Simplex/chatspx/pull/83)** (contra a
    `homologacao`, pra próxima promoção não desfazer). Mesmo commit, 1 arquivo, sem migration
    nem asset. Depois do merge basta o código no disco: o boot das 02:05 recarrega sozinho.
  - ⚠️ **A lição, agora com as duas metades:** cron de agendador não é UTC por padrão — e
    **commit em branch de PR já mergeado não chega a lugar nenhum**. Conferir na branch de
    integração (`git show origin/<branch>:<arquivo>`), não na worktree.

### [2026-08-28] 🔴 O EVAL JÁ TINHA PEGADO — ninguém consome · e a SOFIA foi aposentada

> Duas perguntas do Paulo depois da conv 4809: por que o Eval não pegou, e por que a Sofia,
> que devia ter morrido em 28/07, ainda atende alguém.

**1. O Eval pegou. O sinal não chega a ninguém.**

- Das 5 conversas que ele mandou de manhã, a **4236 já estava avaliada às 14:07 com nota 5** e
  findings de severidade ALTA: `contradisse_tool` ×4, `alucinacao` ×2, `promessa_indevida` ×2,
  `info_incorreta`. **Antes de ele me mandar.** Um dos findings é literalmente *"o endereço que
  mandei é o que está registrado no sistema"*.
- **Volume de 30 dias na conta 6:** `contradisse_tool` **583** · `promessa_indevida` **376** ·
  `alucinacao` **311** · `quebrou_regra` 554 · `usou_tool_errada` 121. **380 conversas com finding
  grave da IA, nota média 5,2.**
- **A lista já existia.** Passei o dia descobrindo lendo conversa o que o eval tinha catalogado.
- **Rastro de uso:** a anotação `#eval` (única ação que deixa marca) tem **8 registros desde
  sempre, os últimos de 29/07**. O time usou dois dias em julho e parou.
- 🔴 **Lacuna estrutural A — episódio ABERTO nunca é avaliado.** O juiz tem
  `return if episode.ended_at.blank?`. Na Tozi conversa não fecha, então uma fatia do tráfego é
  invisível ao eval por construção. Das 5 conversas, **3 não tinham avaliação** exatamente por
  isso (4809, 32730, 32755) — todas com episódio aberto.
- 🔴 **Lacuna estrutural B — nada empurra o achado.** É painel que alguém precisa abrir. Sem
  alerta, sem digest, sem fila priorizada.
- ✅ **O juiz NÃO é o problema:** ele recebe as tool calls intercaladas no transcript
  (`[TOOL nome args=... => resultado]`, `conversation_eval_service.rb:179`) e tem as categorias
  certas — `contradisse_tool` diz *"a ferramenta confirmou um dado e a IA afirmou outro"*.
- ✅ **[PR #76](https://github.com/Dev-Simplex/chatspx/pull/76) — DIGEST DIÁRIO CONSTRUÍDO.**
  `Spx::EvalDigestJob` + scheduler + mailer + view + cron (11h UTC = 7h Cuiabá). Agrupa por
  conversa as avaliações com finding **grave da IA**, ordena pela pior nota, manda por e-mail com
  link direto. **Opt-in por conta** (`custom_attributes['eval_digest']`) e **destinatário é lista
  explícita, nunca "todos os admins"** — a conta 6 tem **25 administradores**, e e-mail que chega
  pra 25 pessoas não é de ninguém (é exatamente por essa via que a notificação nativa já é
  ignorada).
  - **Dois silêncios deliberados:** dia sem falha grave **não** gera e-mail (digest que chega
    sempre vira filtro de caixa de entrada); mas o eval não ter avaliado **nada** gera alerta,
    porque aí a notícia é que o cron parou.
  - **Medido:** 12 exemplos / 0 falhas · rubocop **0** nos 5 arquivos · prévia contra a prod
    (317 avaliados em 24h → **13 conversas** com falha grave).
  - 🔴 **A primeira prévia já achou um padrão que ninguém tinha visto:** as **4 piores notas do
    dia (2, 2, 3, 3) são o MESMO defeito** — a Clara qualificando renda a fundo e afirmando valor
    de parcela em lead de MCMV, em vez de transferir pra Júlia. `handoff_ausente` + `alucinacao` +
    `quebrou_regra` nas quatro.
  - ✅ **WEBHOOK também**, porque e-mail é onde o digest morreria: medido antes de escolher —
    a conta 6 **não tem inbox WAHA** (grupo não existe em Cloud API), a inbox interna "Notas"
    (#93) está **parada desde abril** (12 msgs, zero membros), a **janela de 24h está fechada**
    e os **41 templates aprovados são todos de campanha**. WhatsApp exigiria aprovar um HSM só
    pra aviso interno. Do webhook o Paulo pluga no n8n e manda pra onde quiser.
  - **Um payload, dois usos:** vai o dado estruturado **e** um campo `texto` já formatado — quem
    só encaminha usa o texto, quem monta a mensagem usa o resto. Sem opção extra pra errar.
    Os dois destinos coexistem (só e-mail, só webhook, ou ambos).
  - **Medição final:** **17 exemplos / 0 falhas** · rubocop **0** nos 5 arquivos.
  - ✅ **LIGADO NA CONTA 6 e provado ao vivo:** webhook do n8n do Paulo respondeu **HTTP 200
    "Workflow was started"** com o payload real. Config: `enabled`, `webhook_url`,
    `nota_maxima: 2`, janela 24h, limite 15.
  - ✅ **Os PRs #75 e #76 JÁ ESTÃO EM PRODUÇÃO** (HEAD `6293c29b0`) — alguém mergeou e deployou
    no mesmo dia. Conferido no **processo vivo**, não só no disco: rótulos
    `[NÃO fica em condomínio fechado]` e `(taxa de condomínio R$ 300)` carregados em memória,
    cron do digest registrado no Sidekiq (22 jobs), zero migrations pendentes.
  - 🔴 **A MEDIÇÃO QUE MUDA A EXPECTATIVA: o eval leva 24h.** Mediana de **1.442 minutos**
    (p90 1.491) entre o fim do atendimento e o veredito. **Não é latência do digest** — é do
    ciclo do avaliador, que só julga episódio FECHADO, e episódio fecha por inatividade.
    **Alerta "no instante do erro" NÃO sai do eval.** Aviso em tempo real teria que vir de
    guarda determinística no turno (como as do #75), não do juiz.
  - ✅ **[PR #77](https://github.com/Dev-Simplex/chatspx/pull/77) — corte por nota**, pedido do
    Paulo ("deveria acontecer por erro, não por rotina"). Sem corte são ~13/dia = relatório =
    paisagem. Medido em 14 dias: **nota ≤ 2 → 2,5/dia (pico 6)** · ≤ 3 → 4,1 (pico 9) · ≤ 4 →
    5,1 (pico 14). **Decidido: corte em 2** — é o único que cabe num grupo e deixa dias em
    silêncio. Avaliação SEM nota fica de fora (nota nula não é evidência de falha).
    **21 exemplos / 0 falhas**, rubocop 0. ⏭️ Até o deploy do #77 o digest manda 13 (mas o nó
    do n8n corta em 5 e mostra "+N no painel").
  - ⚠️ **Bug meu no nó do n8n, corrigido:** o Webhook do n8n entrega o corpo em **`.body`**, não
    na raiz. Eu lia da raiz → tudo `undefined` → o fluxo concluía "dia sem falha grave" com 13
    conversas no payload. O nó corrigido está no scratchpad da sessão.
  - **Guardas anti-poluição ficam no nó do n8n**, não no canal: **1 item de saída sempre** (o
    erro clássico é `Split Out` no array e o grupo receber 13 mensagens), teto de 5 na mensagem
    com "+N no painel", e `enviar: false` cortado por um IF.
  - ⏭️ **Decidi NÃO abrir a frente de alerta em tempo real agora:** o #75 já pôs guarda
    determinística onde importava (o dado não chega ao modelo, então não pode vazar), e
    prevenir vale mais que avisar sobre erro já enviado ao cliente.
- ⏭️ **O conserto caro segue aberto:** avaliar também episódio ABERTO parado há X horas.

**2. SOFIA #19 APOSENTADA** (banco, sem deploy).

- **Diagnóstico:** 260 conversas, **todas abertas**, todas inbox 91 · **0 com humano atribuído** ·
  **196 (75%) o cliente NUNCA falou** · **apenas 2 com cliente ativo em 30 dias** · **zero leads
  novos há mais de 30 dias** (o hook #8 manda tudo pra Júlia). Ela vivia só da cauda do Pacaembu
  de junho/julho que reabre.
- **A premissa do plano de 28/07 nunca se cumpriria:** *"desligar quando as abertas resolverem"* —
  a Tozi não resolve conversa.
- **A Júlia assume sem perder nada:** 47.691 chars × 31.610 · 19 docs × 3 · 45 FAQs × 6 · e
  **5 ferramentas a mais**. A Sofia não tinha ferramenta exclusiva nenhuma.
- 🔴 **A única perda real era o doc #28 "Fronteira: casas MCMV x apartamentos"** (5 chunks) — a
  guarda que diz que casa Pacaembu **não é condomínio fechado, não tem portaria, não tem taxa de
  condomínio e é sempre 2 quartos**, com FAQs. Copiado pra Júlia como **doc #29** antes de migrar.
  O doc #7 (catálogo monolítico, 114 chunks) ficou de fora de propósito: foi substituído em 28/07
  pelos 17 fact-sheets por empreendimento.
- ⚠️ **Armadilha na cópia:** o `external_link` desses docs é identificador FALSO
  (`https://tozi.local/...`), e o `after_create_commit :enqueue_crawl_job` deixou o doc novo preso
  em `in_progress` com 0 chunks, com o `CrawlJob` em retry pra sempre. Resolvido forçando o
  `ChunkBuilderJob` e marcando `available`. **Provado:** a Júlia recupera o chunk certo (antes caía
  no Playbook genérico).
- **Decisão do time de handoff (delegada a mim): 26 "vendas"**, não 67 "leads meta" — 2 pessoas
  contra 1, 76 abertas contra 444, e "leads meta" é resíduo do modelo por ORIGEM que o Paulo
  substituiu por ESPECIALIDADE em 28/07. **O `team_id` das 260 não foi tocado:** o `resolve_team`
  move a conversa sozinha quando houver handoff real.
- **Estado final:** Sofia `inboxes=[]`, 0 conversas · Júlia com 453 · assistente, prompt e
  knowledge **intactos** (só parou de responder).
- **Reversão:** `/tmp/sofia_aposenta.bak-20260828174200.json` na VM + recriar o `CaptainInbox`.

### [2026-08-28] 🟢 PROMPTS DA TOZI — 37 falas prontas removidas e a contradição da visita desfeita (banco conta 6, sem deploy)

> Queixas de comportamento do time. Pesquisa de prompting (08/2026) + anatomia medida dos 8 prompts
> antes de mexer. **Nada de código, nada de deploy** — só `config['instructions']` da conta 6.

- **A anatomia que motivou:** Júlia **47.649 chars, 207 linhas, 40 seções, 103 linhas-regra (72%)**;
  Bruna 37.820/34 seções; Clara 25.133/27. A regra de visita mora a **44-45% do prompt** — o miolo,
  onde a recuperação é pior. **31 linhas estão duplicadas em 3+ agentes**, 6 nos oito.
- **O que a pesquisa diz e explica as falhas:** adesão cai com a **contagem de restrições
  condicionais**, não com o comprimento (103 regras a 98% cada ≈ 12% de acertar todas); proibição
  negativa é a forma mais fraca; exemplo de fala vira cópia literal.
- 🔴 **O inventário derrubou metade da minha própria proposta.** Eu ia remover ~77 trechos entre
  aspas. Medido: **a maioria é fala do CLIENTE usada como gatilho** (`"perto de X"`, `"tá caro"`,
  `"onde fica?"`) — removê-las quebraria as regras. Só **37 eram fala da IA**, e essas saíram.
- **15 substituições aplicadas em 7 agentes** (Helena não tinha nenhuma): fecho de serviço (6
  agentes, byte-idêntico) · `"vai te chamar"`/`"vai passar pro consultor"` · `"deixei sua mensagem
  registrada, o time retorna amanhã"` · `"o time já vai te retornar"` · `"não temos no bairro X"` ·
  `"não temos nessa faixa"` · `"te esperamos"`/`"qualquer coisa estou por aqui"` · `"fico no
  aguardo"` · e a pior de todas, **`"temos de 2 e 3 quartos"`** — a afirmação FALSA sobre o Pacaembu
  escrita por extenso no prompt da Júlia.
- **🔴 A CONTRADIÇÃO QUE O TIME SENTIU:** a seção `# Visita e chave` da Bruna proibia cravar horário
  **e, três linhas depois, mandava perguntar dia e período**. Nos 89% de imóveis avulsos não existe
  agenda a combinar (a chave se retira na loja), então perguntar É a promessa. Medido antes:
  **3/3 perguntavam dia e período** tanto no avulso quanto no condomínio — a IA **não distinguia**.
- **Regra nova ancorada em DADO, não em prosa:** o `buscar_imovel` já devolve
  `[em condomínio fechado]` / `[imóvel avulso, sem condomínio]`, e o `Condominio` do Vista está
  preenchido em **106/106** da locação. A seção passou a abrir pelo rótulo. Se ele não estiver à
  vista, a conduta manda **chamar `buscar_imovel` pelo código** antes de conduzir.
- **Medido em 6 rodadas por cenário, `generate_response` em transação revertida:** avulso
  **0/3 → 6/6** explicando a retirada da chave · condomínio **6/6** dizendo *"a visita é agendada e
  acompanhada"* · Pacaembu 6/6 negando sem a frase proibida · controle `[IGNORAR]` intacto.
- 🔴 **ERRO DE MÉTODO MEU, corrigido no meio:** com **N=3** li "0/3, consertado" e com **N=2** li
  "voltou a falhar" — as duas leituras erradas, por amostra pequena. **N≥6 por cenário** é o piso
  para conduta. E a 1ª versão do parágrafo do avulso usava *"NÃO pergunte dia nem período"* —
  proibição negativa, a forma que a própria pesquisa condena. Trocada por ação positiva
  (*"EXPLIQUE como funciona: a chave se retira no escritório"*): foi o que levou de 5/6 a 6/6.
- ⚠️ **Achado colateral:** numa das 12 rodadas a Bruna **inventou o endereço** — disse "Rua das
  Margaridas" para o imóvel 9887, cujo cadastro é "Rua Projetada 01, 1212". Classe conhecida
  (Catatau, 11/08), não causada por esta mudança, mas segue aberta.
- **Reversão:** `/tmp/assistant_{7,13,14,15,16,17,19}_ins_aspas.bak-20260828132125`,
  `/tmp/assistant_14_ins_visita2.bak-20260828133000` e
  `/tmp/assistant_14_ins_condominio.bak-20260828161723` na VM.

- 🔴 **REGRESSÃO QUE EU CAUSEI E CORRIGI NO MESMO DIA (conv 4809, 15:20 — depois do meu deploy
  de conduta das 13:30).** O Paulo trouxe a conversa; a primeira coisa que checkei foi se o
  problema era meu. Era, em parte.
  - **O dano:** a seção nova mandava *"leia a marca [em condomínio fechado] / [imóvel avulso]"*,
    mas o retorno do `buscar_imovel` usa a palavra **"condomínio" com dois sentidos na mesma
    linha** — `(condomínio R$ 300)` é a **taxa** (`ValorCondominio`) e `[imóvel avulso, sem
    condomínio]` é o **fato** (`Condominio`). Eu elevei a saliência da palavra sem desambiguar,
    e o modelo passou a usar a taxa como evidência.
  - **Medido no cenário real, N=6 de cada lado:** backup de antes **4/6 certas** → depois da
    minha mudança **2/6**, com 3 respostas afirmando categoricamente *"as duas são em condomínio
    fechado"*. Uma delas emendava *"a visita é agendada e o consultor acompanha"* — **a regra de
    visita amplificou o erro de leitura**.
  - **Corrigido** com bloco de desambiguação na própria seção (taxa ≠ estar em condomínio; a
    única evidência é o colchete; sem o colchete à vista, buscar pelo código): **5/6 certas**, e
    as certas explicam a distinção. Não-regressão conferida: visita **6/6 no avulso e 6/6 no
    condomínio**.
  - ⏭️ **O conserto durável é no tool, não na conduta:** renomear para `taxa de condomínio R$ X`
    e `[fica em condomínio fechado]` / `[não fica em condomínio fechado]`. Enquanto a linha for
    ambígua, a conduta só compensa.
  - **Os outros 4 defeitos da 4809 NÃO são meus** — conferido: invenção de imóvel deu **0/6** no
    turno exato que a gerou (é evento raro, não induzido), e distância/insistência/mobiliado são
    áreas que a mudança não tocou.

### [2026-08-28] 🔴 CONV 4809 — cinco defeitos numa conversa só, e a IA inventou um imóvel inteiro

> Queixa do gerente: *"falou sobre imóvel que não temos mais, ficou insistindo em dois imóveis
> deslocados"*. O consultor (Adrian) teve que pedir desculpas. Lead de site parado desde fevereiro,
> reaberto em 28/08 15:20. Júlia → Bruna transferiu certo; o resto quebrou.

- 🔴 **NÃO era "imóvel que não temos mais" — ela INVENTOU um que nunca existiu.** Ofereceu *"Casa no
  Residencial Jardim Itália - 3 quartos, R$ 1.400/mês, 2 vagas"*. Não estava na busca daquele turno;
  no acervo, "Jardim Itália" tem **6 kitnets de 1 quarto e 1 apartamento de 2 — zero casas**; e o
  código que ela usou (3210) **não existe** no Vista. **A cliente escolheu justamente esse.** Quem
  segurou foi a trava do `enviar_fotos_imovel` (*"o código 3210 não apareceu na busca"*) — a IA teve
  que voltar atrás 20s depois. **A trava protege a FOTO, não a FALA.**
- 🔴 **Contradição sobre condomínio** — ver a regressão acima. Causa dupla: linha ambígua do tool +
  minha mudança de conduta.
- 🔴 **"Essas ficam próximas ao Centro" é falso:** Bella Morada II a **5,89 km**, Jardim Aurora a
  **8,96 km**. O próprio retorno da busca mandava *"deixar claro que não são do bairro solicitado"*.
  O tool **calcula distância** quando recebe lat/lng — ela não passou. Com a chave do Google agora
  validada, isso vira número em vez de opinião.
- **Insistência:** as mesmas 2 casas em 4 blocos (15:25 · 15:27 · 15:29 · 15:32). A cliente fechou
  com *"Por enquanto nem uma me agradou"*. O acervo só tem **2 casas** naquela faixa — não havia
  terceira, e a IA repetiu em vez de reconhecer o esgotamento.
- 🔴 **Prometeu buscar mobiliada e não buscou — nem conseguiria.** *"Vou buscar pra ver se tem
  alguma casa mobiliada"* e **zero tool call depois**. O Vista **não permite filtrar por mobiliado
  na listagem** (HTTP 400; o campo só existe em `/imoveis/detalhes`, um por vez). Medido no acervo
  inteiro: **4 de 106 imóveis de locação são mobiliados**. O Adrian mandou 3 deles na mão — e o
  quarto é **uma CASA (cód 8849, Jardim Celeste, R$ 2.600)**, exatamente o que a cliente pediu, que
  **ninguém ofereceu**.
- Ruído: **handoff chamado 5x** (4 recusados) e abertura com anúncio vazio (*"Vi seu interesse no
  anúncio ''"*).
- ✅ **[PR #75](https://github.com/Dev-Simplex/chatspx/pull/75) ABERTO** (`PauloSeze/busca-imovel`,
  3 commits, 7 arquivos, +754/−35) com os cinco consertos em CÓDIGO, mais a régua de endereço em
  venda e a **regressão de conduta**:
  - `taxa de condomínio R$ X` × `[FICA em condomínio fechado]` / `[NÃO fica em condomínio fechado]`
  - lista **numerada** com o total explícito e a instrução de não completá-la de memória
  - geocoding da referência pedida → a distância vai na linha de cada alternativa, com **veto pelo
    raio urbano** (o Google devolve homônimo em vez de dizer que não achou)
  - `mobiliado` vira parâmetro filtrado pelos detalhes (agora **cacheados**, 6h), com estado
    explícito quando nada bate
  - **pin do BAIRRO em venda** (coordenada do Google, acervo só como verificador) + logradouro e
    número mascarados na descrição
  - 🔴 **o spec pegou um bug meu:** o regex do endereço exigia o "nº" literal, então
    *"Rua das Palmeiras, 1234"* saía com a rua mascarada e **o número na frase** — metade do
    vazamento passando.
  - **Medido:** `spec/enterprise/lib/captain/tools/` **259 exemplos / 0 falhas** · rubocop **19
    ofensas contra 23 no baseline** (abaixo; os 3 arquivos novos não somam nenhuma) · regressão de
    conduta **7/7 cenários dentro do piso** contra a prod.
- ✅ **CHAVE DO GOOGLE LIGADA na conta 6** (`AccountIntegration` provider `google` +
  `geo_city: Sinop MT`). O `buscar_localizacao`, que falhava **12/12 em 7 dias**, voltou a
  responder. Sem deploy — é config.
- ✅ **Conduta:** a **Sofia #19 não tinha regra nenhuma de visita** (só a Júlia tinha) — ganhou a
  seção, com a régua que o Paulo fechou em 28/08: **qualquer visita de venda é acompanhada por
  corretor, sem exceção de categoria**. E a Bruna parou de citar o **texto literal** do rótulo de
  condomínio, que o PR renomeia — conduta presa a literal quebraria em silêncio no dia do deploy.
- 🟢 **NOVO: `spx:conduta:regressao`** (`lib/tasks/spx_conduta.rake` +
  `Spx::Conduta::Regressao` + `docs/clientes/tozi/conduta-regressao.yml`). Roda cenários
  congelados contra os prompts do banco, N≥6 por cenário, pelo mesmo caminho do
  `ResponseBuilderJob`, em transação revertida. **Piso honesto** (5/6 onde o comportamento
  oscila) para acusar piora real em vez de variância. Os 7 casos são incidentes reais.
  ⚠️ **Ele já pegou dois problemas na estreia** — inclusive um cenário MEU mal construído, que
  media 0/6 sem haver defeito nenhum (pedido de visita sem imóvel na mesa não é pedido de visita).
- ⏭️ **Sobra na `.232`:** worktree de CI `/tmp/ci-buscaimovel`.

### [2026-08-28] 🟢 ENDEREÇO EM VENDA: o vazamento é o PIN, não o texto · e a chave do Maps funciona

> Régua do Paulo: **locação pode endereço completo; venda só bairro.** Medido na prod, 30 dias.

- **Texto quase não vaza:** 105 mensagens da IA com logradouro+número — **44 são locação**
  (permitido), **54 são eco do cliente**, e dos 4 "só venda" um é holerite casando o regex e outro
  é o endereço do próprio escritório. **Sobram 2 vazamentos reais.**
- **🔴 O PIN é o vazamento:** 33 envios de `enviar_localizacao_imovel`, sendo **7 de imóveis à
  VENDA** — coordenada exata de 2 terrenos no Flamboyants, casa no Bonne Vie, kitnets no Vitória
  Régia, casa no Novo Horizonte, empreendimento no Sonhalto e casa no Parque Amazonas.
- **O canal do texto é a DESCRIÇÃO do Vista**, não o campo `Endereco` (que o `buscar_imovel` nem
  pede): **6 de 50** descrições de venda trazem logradouro, e a Júlia fez **239 buscas por código**
  em 30 dias — é o ramo `detalhado: true`.
- **🟢 CHAVE DO GOOGLE VALIDADA** (Paulo enviou em 28/08): geocoding OK, e a Aquarela das Artes bate
  na coordenada exata do link dele. **259/259 bairros do acervo "resolvem"** — mas o Google **nunca
  diz que não achou**: cruzando com os imóveis reais, **67 (26%) caem a mais de 3 km**, sendo
  *Jardim Belo Horizonte* (16 imóveis) a **518 km** e *Jardim Curitiba* (20 imóveis) a 28,9 km.
  `components=locality:Sinop` quase não ajudou (70 → 67).
- **Desenho decidido:** pin do **bairro** em venda (título = nome do bairro), pin do imóvel em
  locação, e **o acervo como VERIFICADOR, nunca como fonte** — num bairro com 1 imóvel o "centro do
  acervo" É a porta dele, e 116 dos 241 bairros de venda têm um único imóvel.
- ⏭️ **Vira PR:** trava do pin + máscara da descrição em venda + linha 119 da Júlia / 58 da Bruna
  invertidas. As duas primeiras são código — o modelo não recebe o dado, então não pode vazar.
- ⏭️ **Régua de visita em VENDA segue pendente do Paulo:** terreno (corretor não acompanha na maior
  parte), lançamento (não faz sentido visita) e o resto. O `Categoria` do Vista já separa os três.
- ⏭️ **Controle de chave ADIADO por decisão do Paulo.** Registrado o desenho que ele quer (chave
  fora da loja, devolução, prazo vencido, gatilho ao devolver) e a medição: o Vista **não expõe
  empréstimo de chave** (`/chaves/*` = 404, campo `Chave` vazio em 106/106 da locação); a
  `/agenda/listar` existe com 25.295 registros mas caiu de **3.515 (2024) → 1.003 (2025) → 584
  (2026)** e só 3 de 30 têm imóvel vinculado. **Se for construir, nasce no SPX** — o gatilho só é
  barato se o evento for nosso.

### [2026-08-25/26] 🟢 A IA RESPONDEU COMENTÁRIO DE VERDADE — provado ao vivo na conta da BigStore

> **CLIENTE BigStore · CONTA 7 · VM `.232`.** Piloto restrito a `@pauloseze`. Tudo abaixo rodou
> contra a conta e o token REAIS, num banco descartável — **sem deploy nenhum**.

- **🟢 A PROVA:** o Paulo comentou *"Qual valor Coca Cola?"* no post da Liquida. A IA leu as **20
  imagens do carrossel**, achou o item e respondeu *"@pauloseze Oi! O bowl Coca está de R$ 10,00
  por R$ 5,00 na promoção. Corre que é só até dia 31! 🧡"* — **entregue no direct dele**, com
  `message_id` da Meta. Antes da leitura de imagem, a mesma pergunta virava *"consulte no direct"*.
- **E ela cala quando é para calar:** no comentário *"Top"* devolveu `[IGNORAR]` explícito.
- 🔴 **NADA DISSO ESTÁ DEPLOYADO.** A box está **26 commits atrás** e a tabela `social_comentarios`
  **não existe** em produção. A configuração da conta 7 está gravada e correta, mas não há código
  na box que a leia. O piloto nasce vivo no instante do deploy — e só para o Paulo.

**Quatro achados que só a execução ao vivo produziu:**

- 🔴 **A URL do CDN da Meta serve para nós e NÃO serve para o modelo.** Nossa box baixa a imagem
  com HTTP 200; a OpenAI, na mesma URL, leva **403** (`invalid_image_url / Upstream status code:
  403`). Os bytes têm que descer aqui e subir em base64. "Público" é propriedade de quem pede, não
  da URL — e isso não está em documentação nenhuma.
- 🔴 **`thumbnail_url` era `string(255)` e a URL do CDN é maior.** O `update!` estourava no meio da
  captura, fora do rescue, e **matava o gatilho da IA**: comentário gravado, ninguém respondendo.
  Colunas viraram `text` e a gravação entrou no rescue que o serviço prometia e não cumpria.
- 🔴 **O runner devolve Hash de chaves STRING e o código lia com símbolo** — a IA gerava a resposta
  certa e nada saía. **Passou pelo motivo errado no primeiro teste:** o comentário era "Top", que
  dá `[IGNORAR]`, e os dois caminhos devolviam nil e se mascararam. E **o spec estava verde e
  mentindo**, porque o dublê devolvia String e nunca exercitava o ramo de Hash.
- 🔴 **A 2ª resposta privada ao mesmo comentário devolve `HTTP 500 code=1` genérico.** A Meta não
  diz "já respondido". Quem tratar esse 500 como falha transitória insiste para sempre — a guarda
  de idempotência é o que impede. Observado, não documentado.

- **Sondagem inicial de capacidade (nada publicado):** a **privada** devolveu `400 / 2534014` —
  erro de OBJETO, não de permissão. Depois **confirmada por envio real**. A **pública** devolveu
  `500 code=1` e **segue DESCONHECIDA** — por isso está desligada. ⚠️ Contradiz a nota de 04/08 no
  vault que dizia que a privada exigiria `graph.facebook.com` + Page Token: ela respondeu no
  `graph.instagram.com`.
- **Construído (PR #68):** os dois caminhos de envio com **chave separada por conta** · portão de
  piloto · registro da tentativa · botão de resposta manual na tela · a IA respondendo **pelo mesmo
  portão** do clique humano · e a **leitura das imagens da publicação**.
- **Leitura de mídia:** uma leitura por item do carrossel (teto 20, com log se houver mais —
  encarte truncado em silêncio responde errado com cara de completo). **Vídeo dentro de carrossel
  é caso real** e desce pro temporário virando quadros no `Captain::VideoFrameExtractor`, que
  ganhou entrada por CAMINHO para não existir um segundo ffmpeg no produto. Opt-in por conta
  (`ler_midia`), uma vez por publicação, ~1 min e centavos por post. A leitura entra no contexto
  **rotulada como leitura de imagem**, não como fato da casa.
- **Medição:** 67 exemplos / 0 falhas nos specs da frente · rubocop **0** em 16 arquivos ·
  `enterprise/services/captain` deu **38 falhas no ramo e 38 no baseline** (pré-existentes na box).
- 🔴 **Allowlist vazia = NINGUÉM, nunca "todo mundo".** Sair do piloto é ato explícito
  (`todos: true`). Tem spec para cada porta.
- ⚠️ **A privada é UMA por comentário, com janela, sem segunda chance.** Grava-se a *tentativa*
  (quando, id, erro), não um booleano. Falha fica sem `external_id` e o comentário segue pendente.
- **Configurado na conta 7:** `social_reply = {privada: true, publica: false, allowlist:
  ["pauloseze"], todos: false, ia: {ativa: true, assistant_id: 19, forma: "privada"}}`.
- **Assistente #19 "Bia — comentários" criado** (989 chars), **sem inbox nenhuma** — não toca o DM.
  A **Bia #18 segue com a inbox 57**, conferido depois. Persona derivada da que o próprio n8n do
  cliente usava, **menos a linha de responder comentário negativo com ironia** — escolha de imagem,
  não inventei sozinho.
- ✅ **PARTE JÁ ESTÁ NA `homologacao`:** durante esta sessão alguém mergeou o #68
  (`68debee18e merge(release): PR #68`) — captura, tela, portão de piloto e resposta manual estão
  lá. **Segue aberto no #68** o que veio depois: a IA respondendo, os dois consertos e a leitura
  de mídia. ⚠️ O merge tornou o PR CONFLITANTE (só `db/schema.rb`, disputa da linha de versão);
  **resolvido nesta sessão** ficando com a migration mais recente, e a suíte rodou **122 exemplos
  / 0 falhas** sobre o resultado, em banco novo carregado do schema resolvido.
- ⏭️ **Para virar produto:** merge do resto do #68 → deploy na `.232`, que está **142 commits
  atrás com 2 migrations pendentes**. ⚠️ Deploy dessa box **se mede na box** — o Almirante já
  mentiu sobre ela (15/08).
- ⚠️ **`ler_midia` NÃO foi ligada na conta 7 de produção** — só no ambiente de prova. Ligar é uma
  chave, mas é custo de visão por publicação e a decisão é do Paulo.
- 🔵 **Dívida de conduta que a própria prova criou:** o prompt do assistente #19 diz que ele *"não
  tem nenhuma fonte de dados de loja conectada"*. Isso segue verdade para endereço e horário, mas
  **deixou de ser para preço** quando o preço está no post. Se não ajustar antes de abrir para
  cliente real, ele pode recusar responder algo que está lendo na frente dele.
- **Reversão:** `a = Account.find(7); s = a.settings; s.delete('social_reply'); a.update!(settings: s)`
  · `Captain::Assistant.find(19).destroy!`.
- ⏭️ **Recomendação:** abrir pela privada — provada por envio real, e erro dela só o Paulo lê. A
  pública segue com capacidade desconhecida e o primeiro envio dela é público.

### [2026-08-25] 🟢 RODÍZIO v2 — **PR #67 pronto pra revisão** (8 commits): o motor sai do console e ganha relógio

> Frente `PauloSeze/rodizio-v2`. Contrato: **`docs/SPEC-DISTRIBUICAO-V2.md`**. Cruzamento das
> listas de operadores da Tozi × SPX no vault (`clientes/tozi-conversation-log.md`).

- **O diagnóstico que motivou:** o motor da v1 está inteiro em produção e **nunca rodou** — as 4
  tabelas com 0 linhas. Três causas: (1) `DistribuirService` tem **UM único ponto de chamada**,
  dentro do `HumanHandoffService` — distribuição só existe onde a IA atende; (2) não havia como
  configurar sem console; (3) a tela `RodizioPage.vue` está no ar desde 31/07 e **não tem entrada
  de menu nenhuma**.
- **Cruzamento das listas (medido):** dos **14 corretores** da tabela do Guilherme (vendas),
  **8 existem no SPX e 6 não** (Alisson, Carlos, Marcos, Rosivane, Vander, Vinicius) — e
  **nenhum dos 8 é membro do time de vendas**, que tem só Maria Vitoria e Cibele. Como o
  `build_pool` intersecta com membros, ligar vendas hoje dá **pool vazio e `sem_pool` em
  silêncio**. A planilha do Léo (locação) lista 2 consultores; hoje são **4 atendendo** —
  Evellyn e Camila não estão nela.
- **Entregue (4 fatias):** suspensão com prazo no pool (`suspenso_ate`, volta sozinha) · API
  `GET/PATCH /teams/:id/distribuicao` (admin **ou gerente do time**) · passo **③ Distribuição** no
  wizard de `/settings/teams/:teamId/edit` · tool **`registrar_preferencia_atendente`** · **repasse
  por SLA** com relógio de expediente.
- **🔴 O SLA quer dizer coisas DIFERENTES por modo de posse** — e tratá-los como um só faria o job
  nunca agir em locação: em `designacao` mede *não assumiu* (a linha aberta expira); em `assignee`
  a pessoa já é dona no instante da escolha, então mede *não respondeu*.
- **O expediente é do time, na política.** Medido: a inbox 91 (onde a locação atende) está com
  `working_hours_enabled=false` e os **defaults de fábrica** (9h-17h seg-sex); o horário real
  (07:30-11:30 · 13:30-17:30 · sáb até 11:30) só existe no `behavior` do agente de IA. Resolução:
  `policy.horario` → `inbox.working_hours` (se habilitado) → **não expira** (fail-closed, e o
  passo ③ avisa).
- **Verificação:** suspensão 11/11 · relógio 7/7 com o expediente real · fail-closed provado (job
  roda e não cria linha) · tool provada contra conversa real com rollback · rota e classes num boot
  real · ESLint limpo e **SFC compilado** (o `vite build` completo não roda na CI por um import
  pré-existente do `portal.js`) · rubocop abaixo do baseline no `policy.rb`.
- ⚠️ **Achado operacional:** o `chatwoot_test` da `.232` é **compartilhado entre worktrees de CI**.
  Regenerar `schema.rb` lá traz tabelas de outras frentes (peguei `social_comentarios`). O schema
  deste PR foi editado à mão. **Vale isolar o banco por worktree.**
- ⏭️ **Fora do PR, por decisão:** gatilhos além do handoff da IA e o modo `sugestao` (sombra).
- ⏭️ **Ordem invertida de propósito:** a v1 mandava começar por vendas; vendas é o time que **não
  pode** ser ligado hoje. **Locação primeiro** — pool proposto Adrian #63, Gelson #72, Evellyn #137,
  Camila #110, com Maria Vitoria fora (1,7 msg/conversa em 744 = ela despacha).
- ⏭️ **Sobras:** worktrees de CI `/tmp/ci-rodizio` e `/tmp/ci-leads-site` na `.232` + o banco
  isolado `chatwoot_rodizio_v2` que criei pra validar o schema.

### [2026-08-25] 🟢 UNIDADES GANHOU TELA — as 4 questões da §9 decididas, Fase 2 no PR #61

> O Paulo perguntou onde estavam a tela de lojas e a de Rede Social. **Nenhuma das duas existia** —
> zero arquivo de frontend nos dois PRs. A de lojas estava travada em 4 decisões dele; ele
> respondeu e a tela foi construída.

- **Decisões (§9 de `docs/contratos/unidades.md`, agora status DECIDIDO):** fases → *"Decida"*
  (delegado) · quem edita → **perfis admin** · aprovação → **não** · IA pode dizer o motivo → **sim**.
- **Contexto que ele deu junto e que muda a leitura da §7: a conta 7 ainda é DE TESTE, ninguém da
  BigStore usa o SPX.** Então a tela não nasce sem usuário por defeito — ela nasce **antes** de o
  cliente entrar, que é a ordem certa. O primeiro usuário é o time da SimplexIA.
- **Minha decisão na #1: a Fase 2 é a tela com a aba Exceções completa e a aba Unidades em
  LEITURA.** CRUD de unidade fica para a Fase 3. A aba de leitura **não é escopo extra** — é
  pré-requisito: sem a lista não há de onde escolher o alvo da exceção nem como conferir a carga.
- **🔵 Gate da sidebar é por DADO, não por feature flag** — some quando a conta não tem unidade
  (§7). Carregar as unidades liga a tela; não há segundo interruptor para esquecer. E evita
  encostar na máquina de feature flags que **quebrou a criação de conta na instância inteira em
  04/08** (as 4 features órfãs). Precedente literal: o item "Campanhas", no mesmo menu.
- **Entregue** (2 commits em `PauloSeze/unidades`): `GET /unidades` (lista + etiquetas + grade da
  semana na ordem de leitura, distinguindo dia **não cadastrado** de **fechado**) ·
  `GET/POST/DELETE /unidade_excecoes` · tela `Configurações › Unidades` com as duas abas · i18n
  `en` e `pt_BR`. **Sem `update` de exceção**, de propósito: corrigir é apagar e criar outra.
- **Medido:** 18 request specs / 0 falhas · rubocop **0** em 5 arquivos · eslint **exit 0** em 7 ·
  zero vite vazado (specs de API JSON não disparam build — a armadilha é só de spec que renderiza
  view). ⚠️ **Tela NÃO verificada visualmente** — só fecha depois de deploy.
- **[PR #61](https://github.com/Dev-Simplex/chatspx/pull/61)** virou Fases 1+2: 9 commits, 34
  arquivos. **Os 7 primeiros commits são a Fase 1 e podem ser mergeados sozinhos** — é onde está o
  ganho maior (a IA respondendo sobre unidade), e está dito no corpo do PR.
- ✅ **A tela de Rede Social também foi construída**, no mesmo dia, dentro do PR #68 — ver a entrada
  abaixo. ⚠️ **Os dois documentos de desenho só existem na `conciliacao/higiene-11ago`** — não
  estão na `homologacao` nem na `producao`.

### [2026-08-25] 🟢 PÁGINA REDE SOCIAL — o comentário capturado deixa de ser invisível (no PR #68)

> Fase 1 da `docs/SPEC-instagram-social.md` §6: abas ① Comentários e ② Publicações. Sem ela o
> PR #68 capturava comentário que ninguém via.

- **Item de topo na sidebar**, ao lado de Conversas e Kanban — **não em Configurações**, porque é
  operação diária (a SPEC pede assim na §5). Mesmo **gate por dado** da tela de unidades: só
  aparece para conta que tem comentário capturado. Admin-only.
- **Aba Comentários:** quem comentou, o quê, quando, em que publicação (miniatura + link), e se já
  foi respondido. Filtros por publicação, "só os sem resposta" e incluir as respostas do time.
- **Aba Publicações:** legenda, tipo, link, curtidas, e **quantos comentários NÓS capturamos**
  separando cliente de resposta do time — ao lado do total que a Meta reporta. A diferença entre
  os dois é o que a assinatura não trouxe (comentário anterior a 18/08, ou publicação em colab).
- 🔵 **O "respondido" é INFERÊNCIA, e a tela diz isso.** O webhook **não traz `parent_id`** — a
  resposta da conta chega como comentário comum na mesma publicação. O que liga uma à outra é a
  convenção do `@usuario` no começo, observada em **todas** as respostas medidas em 24/08.
  `Spx::Social::Respondidos` casa **só menção no começo** (no meio é citação, não endereçamento) e
  **não atravessa publicação**. Erra para o lado de sobrar trabalho na tela, nunca para o de
  esconder cliente sem resposta. ⏭️ **Conserto durável: buscar `parent_id` na Graph ao gravar.**
- **Medido:** **111 exemplos / 0 falhas** · rubocop **0** em 8 arquivos · eslint **exit 0** em 7 ·
  rotas conferidas com `rails routes` · zero vite vazado. ⚠️ **Tela NÃO verificada visualmente.**
- **[PR #68](https://github.com/Dev-Simplex/chatspx/pull/68)** agora tem 7 commits e 38 arquivos.
- ⏭️ **Fora desta fatia:** responder comentário · as outras 4 abas da §5 (campanhas "comente X",
  marcações/UGC, agenda, painel) · **se a pessoa segue a conta** — o dado existe na Graph
  (`is_user_follow_business`, provado em 18/08) mas não é capturado ao gravar.

### [2026-08-24] 🔴 A BIGSTORE NÃO TEM BOT NENHUM — e os comentários chegavam e eram jogados fora (branch `PauloSeze/instagram-comentarios`)

> Sessão de retomada do módulo de Instagram com foco na BigStore. Tudo medido read-only na `.232`
> (conta 7, inbox 57). Detalhe no vault: `spx-os/clientes/bigstore.md`.

- **🔴 O achado que inverte a premissa: não há automação atendendo a BigStore.** Desde que o SPX
  enxerga o canal (03/08) **nunca houve resposta automática**. Mediana de resposta por semana:
  **48min · 19min · 80min · 20min**; p90 de **5h45**; respostas em menos de 30s ficam entre 3,5% e
  8,7%. As saídas existem **só das 08h às 18h** e a saudação varia o emoji na mão (`Oie, bom dia 😃`
  44x, `🌞` 36x, `☀️` 35x). É **uma pessoa** respondendo ~1.300 mensagens por semana.
- **A Bia (#18) está desligada de fato:** prompt de 5.520 chars, `config['tools']` **nil**, 0
  documentos, 10 FAQs, elegível na inbox 57 — e **1 conversa de 1.577 com o espelho atribuído**.
  Falou **9 vezes em 60 dias, todas na conversa 2675 (a do Paulo)**, a última em 15/08.
- **O trabalho da pessoa é triagem geográfica, e é quase todo automatizável.** Frases mais repetidas
  em 7 dias: `Entre em contato com a loja pelo WhatsApp` 55x · `Qual das lojas?` 26x · o telefone de
  Cacoal **26x** · `Qual cidade seria?` 22x. É exatamente o que a `buscar_unidades` (PR #61) devolve.
- 🔴 **As 10 FAQs no ar dizem o CONTRÁRIO do que o humano faz.** A #88 afirma que *"a lista de
  cidades, o endereço e o telefone não são consultáveis pelo direct"*. Com a tool, isso vira mentira
  sobre a própria capacidade.
- 🔴 **Na BigStore handoff não tem para onde ir:** a conta 7 tem **0 automation rules, 0 times e 2
  usuários — Paulo (#51) e Simplex (#1)**. Ninguém do cliente tem conta no SPX. Ou a IA resolve, ou
  a mensagem morre. É o oposto da Tozi, e muda a conduta inteira.
- **O canal é de mídia:** 30 dias = 3.667 entradas, **1.691 com anexo (46%)** — **1.126 `ig_story`**,
  455 vídeo, 73 imagem. Justifica o `media_pipeline` que já está ligado.

- **🟢 COMENTÁRIOS: a precondição está provada ao vivo, e o defeito era nosso.** Payload real
  capturado em 24/08 (`field: comments`, com `from.id`/`username`, `media.id`, texto). Em 7 dias:
  **51 entregas, 39 comentários distintos, 16 publicações — todos descartados** pelo
  `test_event?`, que classifica qualquer `changes` como evento de teste do painel da Meta.
- **Fase 1 implementada** (6 commits, worktree `orca/workspaces/chatspx/instagram-comentarios`):
  discriminador de teste vira `entry.id == "0"` (o que a doc no rodapé do próprio arquivo sempre
  disse) + roteamento por `field` + tabelas `social_comentarios`/`social_publicacoes` + cache de
  publicação pela Graph. **Nada é enviado; esta fatia só captura.**
- **Três decisões vieram da medição, não da documentação:** (a) 51 entregas para 39 comentários — a
  Meta **reentrega**, então idempotência por índice único é o caso normal, não zelo; (b) **22 das 51
  eram da própria `@bigstoreutilidades`** — o webhook devolve o que a conta comenta, e sem a marca
  `proprio` um agente responderia a si mesmo; (c) comentário não tem destinatário, então o canal se
  acha por `entry.id`.
- **Bloco 0 junto (dívida do STATE de 18/08):** `INSTAGRAM_SCOPES` e `INSTAGRAM_SUBSCRIBED_FIELDS`
  viram config de instalação, que **acrescenta e nunca remove** o núcleo. E o `subscribe` para de
  mentir: `HTTParty.post` **não** levanta exceção em 400, então o `rescue StandardError` só pegava
  falha de rede e recusa da Meta passava por sucesso; agora a resposta é conferida e, se o lote
  completo for recusado, recua-se pro núcleo em vez de deixar o canal sem assinatura nenhuma.
- **Medido:** suíte de Instagram **135 exemplos / 0 falhas** · rubocop **0** nos 14 arquivos ·
  `zeitwerk:check` "All is good!" · `schema.rb` (escrito à mão) carrega em banco novo criando as
  duas tabelas · `installation_config.yml` parseia com 97 entradas e zero chave duplicada ·
  `global_config_service` 2/0 e `global_config` 3/0. ⚠️ **O dump automático do schema é armadilha:**
  o `chatwoot_test` da box é compartilhado e o dump saiu com **405 inserções**, arrastando 17
  tabelas de outras frentes.
- ⚠️ **`installation_configs_controller_spec.rb` NÃO foi rodado, de propósito** — ver o incidente
  abaixo. Conferido por leitura: ele cria o próprio `TESTCONFIG` por factory e só checa HTTP 200;
  não conta entradas nem lê o `installation_config.yml`, e as duas chaves novas (`locked: false`)
  só aumentam o conjunto `InstallationConfig.editable`.
- 🔴 **INCIDENTE QUE EU CAUSEI NA `.232`, contido:** spec de super_admin que renderiza view dispara
  um `vite build --mode test` por exemplo, e **eles não terminam**. Cinco execuções daquele arquivo
  deixaram **94 builds presos**, levando o Postgres a **104 conexões com `max_connections=100`** —
  93 no `chatwoot_test`, sobrando **5 para o `chatwoot_production`** da box, que atende contas
  reais. A partir daí todo rspec morria em `PG::ConnectionBad`, inclusive produzindo "3 falhas"
  falsas que não eram do código. **Resolvido com autorização do Paulo:** matar os builds devolveu
  as conexões sozinho (104 → **9**, `chatwoot_test` em zero), sem tocar no banco; app em HTTP 200,
  web e worker ativos. Receita e diagnóstico na memória `reference-ci-232-chatspx`.
- ✅ **[PR #68](https://github.com/Dev-Simplex/chatspx/pull/68)** aberto contra a `homologacao`
  (6 commits, 16 arquivos, +795/−17). ⏭️ **Falta:** a tela (abas Comentários e Publicações) e a
  resposta pública — as duas fatias seguintes.
- ⏭️ **Duas perguntas de fato para o cliente, agora com gente esperando nos comentários:**
  **Rondonópolis está aberta?** (FAQ #84 diz que foi transferida; `bigstore-lojas.md`, corrigido
  pelo Paulo em 17/08, lista como ativa — e **duas pessoas perguntaram sobre ela em 24/08**) e
  **domingo** (FAQ #80 diz "não abre"; 5 das 20 abrem 08h–13h).
- ⚠️ **Deixado na box:** worktree de CI `/tmp/ci-igcom` e o banco descartável `chatwoot_schemacheck`.
- ⚠️ **Limitação a declarar antes de prometer cobertura:** post em colab **não entrega comentário**
  para o app da conta, e a BigStore usa colab em lançamento.

### [2026-08-24] 🟢 VOCABULÁRIO POR ESPECIALIDADE — vendas fala CORRETOR, locação fala CONSULTOR (banco conta 6)

> Queixa do time. Medido por agente antes de mexer; só prompt, sem deploy, sem tocar FAQ.

- **O defeito não era a palavra errada, era as DUAS palavras.** A **Júlia #13 (vendas)** tinha
  **16 "consultor" e 39 "corretor" no mesmo prompt** — o cliente ouvia os dois nomes da mesma
  pessoa. As 16 foram conferidas uma a uma (todas do fluxo de venda) e viraram "corretor".
- **Quem já estava certo não foi tocado:** Sofia #19 (vendas) 42× "corretor" e zero "consultor";
  Bruna #14 e Letícia #15 (locação) o inverso.
- **Clara #7 (triagem) não tem palavra certa** — ela roteia pros dois lados. As frases genéricas
  viraram neutras ("o time"); a linha sobre **garantia de locação** manteve "consultor". As **31
  FAQs dela com "corretor" são todas de venda** (MCMV, FGTS, planta) — falso positivo, nada a fazer.
- **Marina #16:** só a frase genérica. *"consultora de captação"* é o **título** dela — preservado.
- **Provado:** Júlia 3/3 "corretor" · Bruna 3/3 "consultor" (transação revertida, nada enviado).
- ⚠️ **Dívida:** a frase da pausa do almoço está **copiada idêntica em 5 prompts** e a palavra certa
  difere em cada um. Mesma classe do R$21 em duas FAQs — **texto duplicado diverge**.
- Backups: `/tmp/assistant_{7,13,16,17}_ins_vocab.bak-20260824165419.restore.rb`.

### [2026-08-19] 🔴→🟢 A IA DE LOCAÇÃO INVENTAVA PREÇO — 3 valores em 5 rodadas (banco conta 6, sem deploy)

> Entrou como "atualizar dois fatos que o Léo passou" e a medição virou o assunto. Tudo em FAQ +
> prompt da **Bruna #14** (a agente de locação), prod Tozi. Detalhe no vault:
> `spx-os/clientes/tozi.md` e `aprendizados/prompt-nome-sem-fato-vira-invencao.md`.

- **Fatos novos aplicados:** taxa de assinatura do contrato **R$ 21 → R$ 49** (estava em **duas**
  FAQs, #284 e #288 — mexer numa só faria a IA dar valores diferentes conforme a pergunta) e o
  **fiador digital** como **4ª garantia** (a Loft entra como fiadora, **12,5% do valor anual**,
  conforme análise, até 12x, sem imóvel/caução/terceiros). FAQ **#307** nova entra pela dor
  ("sem fiador e sem caução"), que é como o cliente pergunta. Re-embed automático conferido.
- **`seguro fiança` deixou de ser beco sem saída:** a FAQ #291 segue dizendo que a Tozi não trabalha
  com isso, mas agora oferece o fiador digital — que é exatamente o que quem pergunta procura.
  ⚠️ Fiador digital **não é** seguro fiança; a proibição do prompt continua valendo.
- **🔴 O ACHADO:** rodando a pergunta da taxa **5x** (transação revertida, nada enviado), a IA
  **só consultava a base em 2/5**. Nas outras três **inventou preço: R$ 500, R$ 400 e "um aluguel"**.
  O R$21 antigo **nunca aparecia** — ela não lia a FAQ nem antes. **Trocar o número sozinho
  consertaria só 40% dos casos.**
- **Causa:** o prompt tem regra anti-invenção para imóvel, link, localização, pet, horário e fotos —
  e **nenhuma** para taxa/valor de contrato/percentual/garantia. Seção nova fecha a classe:
  consulte ANTES de responder mesmo achando que sabe + valor que não veio da base não sai.
  **Depois: 5/5 consultam e acertam.**
- **🔴 Erro meu, medido e desfeito:** eu tinha posto *"fiador digital"* na **enumeração dentro do
  prompt**. Medido: **3/5 diziam o nome e inventavam a descrição** ("análise feita online"), **0/5**
  citavam Loft ou os 12,5%. **Nome no prompt + fatos só na base = recita o nome e inventa o resto** —
  é a REGRA #1 valendo para **substantivo**, não só para frase de exemplo. Enumeração removida →
  **5/5 citam Loft e 12,5%**.
- ⚠️ **Armadilha de sonda (2ª vez nesta sessão):** `run_raw` devolve `output` **vazio** quando há
  handoff — 5 respostas boas apareceram como 5 vazias e eu quase reportei regressão. Medir com o
  fallback que o `ResponseBuilderJob` aplica.
- **Reversão:** `/tmp/tozi_garantias.bak-20260819110810.restore.rb` e
  `/tmp/assistant_14_ins_valores.bak-20260819112131.restore.rb` na VM.
- ⏭️ **Pergunta ao Léo:** o fiador digital vale para todo contrato ou tem restrição por
  imóvel/proprietário? Hoje a resposta diz "conforme análise" e manda confirmar com o consultor.

### [2026-08-19] 🟢 CONVERSA SEM DONO: a máquina já existia, vetada por UMA flag (PR #66) · e a fila presa (PR #65)

> Queixa do time: conversa "some". Medido na prod Tozi (conta 6), read-only. Dois PRs, dois
> defeitos diferentes — um de entrada na fila, outro de saída dela.

- **🔴 A flag `reply_assignment_gate` faz DUAS coisas de sinais opostos.** Ela obriga o humano a
  estar atribuído para responder (**a favor** de todo mundo ter dono) e proíbe a IA de reassumir
  órfã (**contra**), porque no modelo FILA a conversa devia esperar alguém puxar. Quem abandonou a
  fila quer a primeira metade e não a segunda — e não conseguia: era tudo ou nada.
- **A reentrada JÁ ESTÁ CONSTRUÍDA e diz exatamente o modelo do Paulo.** Comentário no próprio
  código do `orphan_captain_reentry?`: *"Reaberta volta pra TRIAGEM, com o time LIMPO: ela lê o
  histórico + a mensagem nova e decide se continua o assunto anterior ou abre um novo, e roteia."*
  O `OrphanRetriageJob` também já re-executa as regras a cada 15 min. **Os dois estavam vetados
  pela mesma flag.**
- **✅ [PR #66](https://github.com/Dev-Simplex/chatspx/pull/66)** (`PauloSeze/toda-conversa-com-dono`):
  chave `ia_reentra_orfa` por conta separa as duas. **Sem a chave nada muda** — deriva do
  `reply_assignment_gate` como antes, e os specs existentes que cobrem os dois lados continuam
  valendo sem alteração (é a prova de que o default não mudou). Rubocop 0 nos 7 arquivos.
  ⚠️ **Specs NÃO rodados** (6 exemplos novos) — a box de CI é LAN e a sessão estava fora dela.
- **Medição (28 órfãs agora):** inbox 91=12 · 101=6 · **99=6** · 61=2 · 62=2. A Clara (#7) é a
  triagem e está elegível em 91/61/62/101 → **22 das 28 ganham dono ligando a chave**. As 6 da
  **99 não têm IA nenhuma** (inbox de disparo) — são de gente, tratamento à parte.
- **Isso NÃO come a fila de espera:** conversa aguardando humano depois de handoff **não é órfã**
  (o `HumanHandoffService` não solta o espelho de propósito), e `still_orphan?` exige assignee nil
  **e** sem espelho. O receio registrado no F1.4 não se aplica.
- **✅ [PR #65](https://github.com/Dev-Simplex/chatspx/pull/65)** (`PauloSeze/aguardando-preso`) — o
  outro lado: conversa com dono humano ficava **presa para sempre** em "Aguardando atendimento".
  `aguardando_humano_desde` é limpo por **mudança** (assignee muda, espelho solto, resolve); com
  humano já dono no instante em que o marcador nasce, não sobra mudança a observar. Corrida de
  ordem — alguém puxa a conversa no meio do turno em que a IA produz o handoff. Medido na conv
  4854: atribuída 09:33, marcada 09:34, fila mentindo enquanto a consultora respondia. 4 specs.

### [2026-08-19] 🟡 CONV 4285 — a IA mandou o carrossel SEM UMA PALAVRA. É a corrida do takeover, 1 em 217

> A cliente mandou **6 mensagens em 33s** (incluindo "Boa tarde", uma foto e "Este imóvel está
> disponível?"); a IA respondeu **só com o carrossel**. Um humano assumiu e saudou 5 min depois.

- **Aquele `📷 Carrossel: 9 fotos do imóvel 6767` é o texto da PRÓPRIA TOOL, não fala da IA.**
- **O log do turno conta tudo:** `09:39:45 debounce_fire` → `09:39:50 human_takeover` →
  `09:39:56 carrossel` → `09:39:57 handoff`. Alguém assumiu **no meio do turno**.
- **Causa estrutural:** `captain_can_respond?` (`response_builder_job.rb:51`) relê o espelho fresco
  do banco **depois** da rodada do modelo e cala a fala. Mas a tool de fotos **escreve a mensagem
  ela mesma, dentro da rodada**, sem passar por esse portão — o mesmo vale para o `HumanHandoffService`
  (a nota privada saiu). **O portão protege as palavras, não os atos.**
- **Escala medida (60 dias): 217 carrosséis, 1 mudo (0,5%) — é esta.** Não é comportamento
  sistêmico nem falha de conduta; é corrida rara. Vale fechar porque é barato e o sintoma para o
  cliente é feio, mas **não é urgência**. ⏭️ Conserto: checar o portão imediatamente antes de a
  tool escrever (fecha ~a janela inteira: o takeover foi 6s antes da escrita).

### [2026-08-19] 🔵 CARROSSEL INVISÍVEL NO PAINEL — e não é só o carrossel: **NENHUMA** mensagem rica é desenhada

> Queixa do time: não conseguem ver pelo SPX as imagens enviadas em carrossel.

- **`rg interactive_payload app/javascript` = ZERO.** O front não sabe que essa chave existe.
  Toda mensagem rica que o SPX manda — carrossel, botão de CTA, pedido de localização, Flow —
  chega ao time como **uma linha de texto seca**. O carrossel é só o caso que dói mais.
- **O dado já está todo lá, e é público.** Cada card do payload traz
  `header.image.link` (CDN da Vista), `body.text` e `action.parameters.url`. A mensagem é gravada
  com **`attachments` vazio** de propósito (o carrossel é passthrough da Meta).
- **Logo NÃO precisa baixar nem armazenar nada** — a alternativa de anexar as imagens custaria
  storage, dobraria o download e ainda **mentiria** sobre o que foi enviado (o cliente recebeu
  cards com botão, não fotos soltas). ⏭️ O conserto é **1 componente de bolha** que lê
  `content_attributes.interactive_payload` e desenha os cards; mesmo componente serve os 4 tipos.

### [2026-08-18] 🔴→🟢 A JANELA DE 24h DO INSTAGRAM: não há atalho, e o loop da BigStore estava quebrado

> Fechado com medição, depois de duas correções minhas. Contratos:
> `docs/contratos/human-agent-instagram.md` e `docs/contratos/ponte-whatsapp.md`.

- **O mapa, todo testado ao vivo** (destinatário `1737491620526400`, janela fechada há 78h):
  dentro de 24h funciona · **`HUMAN_AGENT` = 7 dias, existe nesta API e falta App Review** ·
  Marketing Messages exige opt-in do usuário e parece ser do sabor Página · resposta privada a
  comentário tem janela própria de 7 dias · **as outras 4 tags do Messenger a Meta ignora** ·
  **abertura a frio não existe** (sem interação não há nem IGSID para endereçar).
- **O erro distingue tudo:** sem tag → `403 subcode 2534022` ("fora do período permitido"); com
  `HUMAN_AGENT` → `403` reclamando da **feature não aprovada**, citando "this endpoint". A API
  conhece a tag. Testadas 4 grafias/formatos — mesmo erro nos quatro.
- ⚠️ **O painel MENTE:** `Human Agent` aparece como `Standard access`, "pronto para usar", "nenhuma
  análise solicitada" — e o endpoint recusa. Mesmo padrão dos comentários (permissão no app ≠
  permissão no token). **Ler o painel não substitui testar por capacidade.**
- **🔴 TESTE CRUZADO n8n × SPX — o achado do dia.** O Paulo lembrava que no n8n funcionava fora da
  janela, e o fluxo `Zap` de fato **envia** fora dela (o gatilho é o **lojista respondendo no
  WhatsApp**, não o cliente). Rodado lado a lado, mesmo destinatário e mesmo corpo: **os dois
  levaram `403 subcode 2534022`**. O n8n nunca teve capacidade a mais — o nó tinha
  `onError: continueErrorOutput`, então a falha virava aviso no WhatsApp **da loja** e nunca chegava
  ao Paulo.
  > **O loop lojista→cliente da BigStore estava quebrado toda vez que a loja demorava mais de 24h.**
  > O cliente perguntava, a loja respondia, a resposta não chegava. Não é regressão da migração — é
  > defeito que a migração revelou.
- ⏭️ **A saída que não depende da Meta (ideia do Paulo):** usar as 24h que existem para **levar a
  conversa ao WhatsApp**, que tem template. Duas formas — Tozi (tem WABA, conversa segue no SPX) e
  BigStore (não tem WABA; o telefone vai para a loja falar do próprio número). Contrato escrito.
- ⏭️ **Pedir a feature Human Agent** no `Business MW` (`478777497423728`) segue valendo, para quem
  não quer dar o telefone. Agora com argumento melhor: é conserto de defeito, não melhoria.
- ⚠️ Não dá para repetir o teste do app antigo: a BigStore foi desvinculada dele. E ainda que ele
  tivesse algo a mais, a box tem **um** `INSTAGRAM_APP_ID` — trocá-lo atingiria toda conta dela.

### [2026-08-18] 🟢 REAGIR / DIGITANDO / VISTO no Instagram — funcionam hoje, e o SPX não usa nenhum

- Testado na inbox 56 (Midwest, conta do Paulo): `sender_action: react` com **`love` → 200 OK**,
  `unreact` → OK, **`typing_on` → 200**, **`mark_seen` → 200**.
- **`love` é a ÚNICA reação aceita** — testadas 15 (`wow`, `haha`, `like`, `thumbs_up`, `fire`…),
  todas recusadas com "Reação inválida".
- É o `reagir` que o n8n tinha e o SPX não tem: **nenhuma das quatro capacidades existe no código**.
  Não depende de escopo, de aprovação nem de janela nova — é a lacuna mais barata da lista.
- Bônus: o indicador "digitando" hoje só existe no WhatsApp Cloud; no Instagram responde 200.

### [2026-08-18] 🟢 CARROSSEL NO INSTAGRAM: dois formatos provados ao vivo (frente `instagram-midia`)

- Enviados de verdade pela inbox 56 (Midwest → @pauloseze), os dois com **HTTP 200**:
  **generic template** (carrossel de cards com foto, título, subtítulo e botão) e **`attachments[]`**
  (até 30 fotos numa mensagem só).
- **No celular os dois renderizam bem** (confirmado pelo Paulo). No **Instagram Web** o generic
  template mostra *"Mensagem não aceita — use o app do celular"*; o `attachments[]` renderiza.
- ⚠️ A Meta **não devolve eco** do generic template (6 ocorrências de `attachments` no journal,
  zero de `template_type`). Isso **não** é objeção para o produto — quando o SPX envia, ele cria a
  `Message` local antes; o eco só importa para mensagem mandada por fora.
- **Decisão do Paulo:** fazer os dois. `attachments[]` para as fotos de um imóvel; generic template
  para a vitrine de 3 imóveis com botão. O clique volta por **`postback`** (`web_url` não volta).
- Frente aberta: worktree `instagram-midia`, branch `PauloSeze/instagram-midia`.
- ⏭️ **WhatsApp fica como está** (decisão do Paulo). Lá não existe álbum: o `WhatsappCloudService`
  manda `attachments.first` — uma mídia por mensagem —, então o carrossel é o único agrupamento.

### [2026-08-17] 🔴→🟢 LEAD DE LOCAÇÃO NASCIA NA AGENTE DE VENDAS (conv 28230) — **PR #57 aberto** · rodízio mapeado · supervisor de locação criado

> Sessão de queixa de cliente. Tudo medido na VM da prod Tozi (conta 6), read-only. Log completo do
> caso no vault: `spx-os/clientes/tozi-conversation-log.md` (3 blocos de 17/08).

- **O caso:** lead do site com `jornada` começando em *"Interesse em locação"* foi atendido pela
  **Júlia (vendas)** e encaminhado ao time **vendas**; a Maria Vitoria corrigiu na mão 12 min depois.
- **Três defeitos empilhados:**
  1. **Origem:** o `SiteLeadJob` monta o lead **sem `campaign_id`**, e `hook_setting` só resolve
     override **por campanha** → **todo** lead de site cai no global do hook #8 (bot 17 = Júlia).
     Não existia caminho de configuração para o site.
  2. **🔴 `handoff_team_id` da conta é IGNORADO.** A chave (=60, recepção) só desliga a enumeração de
     times no `HandoffTool`; o `HumanHandoffService#resolve_team` **nunca a lê** e cai no
     `assistant.config['team_id']`. Medido: **641 handoffs/60d, só 81 pra recepção — e os 81 são da
     Clara**, cujo padrão já é 60. Era paliativo até o rodízio ficar pronto e **nunca funcionou** —
     e ainda tirou da Júlia a capacidade de rotear. Comentário corrigido no PR #57 (`f862aa5e`).
  3. Conduta manda transferir locação pra Bruna (usa 93x/60d), mas o gatilho positivo do `handoff`
     vence quando o cliente pede fotos/visita.
- **Escala:** 40 conversas/60d com busca de locação + handoff pra vendas. **28 corrigidas por humano**
  (mediana **78 min**; 15 casos >1h, pior **17h30**), 11 pela própria IA (mediana 3 min), 1 nunca.
- **✅ [PR #57](https://github.com/Dev-Simplex/chatspx/pull/57)** (branch `PauloSeze/leads-site-fotos`,
  4 commits, **81 specs / 0 falhas**, rubocop 35=35 contra baseline):
  - **`intent_overrides` no hook** (opt-in, genérico): `[{match, assign_agent_bot_id, assign_team_id}]`
    casado por substring contra a `jornada`, sem acento/caixa. Precedência **campanha > intenção >
    global**. Provado por **replay das 100 jornadas reais**: sem a chave = idêntico a hoje; com ela,
    57 mudam e **43 desses 57 o time humano de fato levou pra locação** (91,5% dos decididos).
  - **Carrossel deixa de virar fala do agente:** mensagem com `interactive_payload` entra no histórico
    como `[carrossel de fotos do imóvel X enviado]`. Causa medida: o modelo **copiou** o texto do
    rótulo e mandou uma linha sem foto 7s depois do carrossel real. Alcance: 149/56.870 msgs em 30d.
  - **`docs/SPEC-fila-envio-fotos.md`** — o `COOLDOWN=90` recusou os outros 2 imóveis que o cliente
    pediu (9ms e 3ms, e as 3 chamadas gravaram `status=ok`). Spec de enfileirar em vez de recusar.
    **Não implementada** — decisão do Paulo: estudar e criar.
  - ⏭️ Só vale na Tozi **depois** de mergear + promover + deployar. Ligar a chave no hook #8 é config.
- **🟢 RODÍZIO: motor 100% construído, 0% configurado.** As 4 tabelas (`distribuicao_policies/states/
  logs/produtos`) estão **vazias** — nunca rodou. Tem pool ordenado, preferência do cliente por nome,
  teto, continuidade 30d, SLA 30min, espelho Vista e `modo_posse=designacao` pro corretor que não vive
  no SPX. **O código já está na prod** — ligar é config, não deploy.
  - **Locação (#27) pronta:** os 5 membros formais são os 5 atendentes reais; **96%** das conversas
    atribuídas tiveram fala do dono → `modo_posse: assignee`. Pool proposto: **Adrian #63, Gelson #72,
    Evellyn #137, Camila #110**. **Maria Vitoria #66 fora** — 1,6 msg/conversa em 1.080 conversas, ela
    despacha, não atende. ⏳ aguarda aval dos nomes.
  - **Vendas (#26) NÃO dá pra ligar:** o time tem **2 membros e nenhum corretor** (eles vivem no
    Vista). O `build_pool` **intersecta com os membros do time** → pool vazio → `sem_pool` em silêncio.
  - ⚠️ Cap: começar **sem**. Evellyn tem **185 conversas abertas** contra 35/15/7 — parece acúmulo, não
    carga; com cap ela seria excluída por um número que não significa o que parece. (Olhar em separado.)
- **🟢 SUPERVISOR DE LOCAÇÃO CRIADO — usuário #141 Leonardo Rimoli**
  (`supervisor.locacao@toziimoveis.com.br`). Identificado por prova: cartão compartilhado pela Angela
  em 13/07 — *"Leonardo Gerente Comercial De Locacao"*, +55 66 99243-3029, LID `157784347828264@lid`.
  Ele **não tinha conta** e operava só por 3 grupos de WhatsApp que caem na inbox.
  - **Config canônica:** `role=agent` + linha em `team_supervisors` (time 27).
    `permissions=["agent","team_supervisor"]`. Enxerga **7.998 conversas, todas de locação, zero fora**.
  - ⚠️ **A frente "Supervisor de Time" JÁ EXISTIA** (`task/supervisor-de-time.md`, F1–F5 entregues, já
    em produção). **"Supervisor" é rótulo de UI, não role do backend** (D1/D6). Um custom role que eu
    havia criado foi **revertido e apagado** por duplicar o conceito.
  - ⏳ **`agent` não vê relatório** (`ReportPolicy#view?` exige admin) e *"relatórios escopados por
    supervisão"* está em **Fora de escopo (deferido)** no doc deles. **Paulo levantou com o Walisson
    em 17/08; resposta esperada 18/08.**
- ⏭️ **Sobras:** worktree de CI em `/tmp/ci-leads-site` na `.232` · as **31 conversas** poluídas pelo
  incidente de menção do Instagram seguem abertas · a `producao` local deste notebook está **297
  commits atrás** (sair sempre de `origin/producao`).

### [2026-08-18] 🟢 COMENTÁRIOS DO INSTAGRAM DESTRAVADOS — eram DUAS coisas nossas, nenhuma da Meta

> Inverte o diagnóstico de 11/08 (`docs/SPEC-instagram-comentarios.md`), que dava o escopo como
> bloqueio com prazo de App Review. **Não havia App Review nenhuma.** Faltavam duas coisas, ambas
> do lado do SPX: a assinatura de conta e o escopo no token. As duas resolvidas hoje, sem deploy.

**O caminho do diagnóstico, porque ele erra duas vezes antes de acertar:**
1. Achei que era só a assinatura de conta → liguei `comments` → **webhook continuou sem disparar**.
2. Achei então que o escopo gateava a entrega e que teria App Review → **o painel mostrou
   `Standard access`, ativo, sem análise pendente**.
3. O teste que fechou foi **por capacidade, não por declaração**: pedir
   `fields=username,from{id,username}` num comentário devolvia **HTTP 200 com os campos
   simplesmente ausentes**. A Meta não erra quando falta permissão — ela **omite em silêncio**.
   Mesma família das outras falhas caladas da semana.

**✅ Resolvido (18/08, sem tocar em código):** reconexão da inbox 57 por uma URL de consentimento
montada à mão com o escopo a mais, usando o `redirect_uri` e o `state` do próprio SPX — o callback
dele fez a troca e gravou o token. Zero off-git, zero escrita manual no banco.

Conferido depois: conta 7 segue com **uma** inbox (`[57]`, nenhuma fantasma — o risco real era
autorizar na conta errada, que foi o incidente de 04/08); token novo com 60 dias; a assinatura de
`comments` **sobreviveu** (o `subscribe` é `after_create_commit`, não roda em update); e o autor
dos comentários **passou a aparecer** (`@pauloseze`, `@mayarabalbino6`…) onde antes vinha vazio.

⏭️ **Falta a prova do webhook** — o comentário de teste foi feito antes da reconexão.

⏭️ **A dívida de código que fica:** `Instagram::IntegrationHelper::REQUIRED_SCOPES` é constante
global. A reconexão pela TELA continua mintando só dois escopos, então este token é melhor que o
que a UI produz. Acrescentar o escopo ali muda a tela de consentimento de **toda conta em toda
box**, e onde o app não tiver a permissão o OAuth passa a falhar por escopo inválido — a Tozi usa
outro app (`SPX Lead Ads Tozi`). Tem que virar configurável, não constante. Mesmo padrão da
armadilha do `subscribed_fields`.

> **Registro antigo, mantido porque explica os números:**

- **O app do SPX na `.232` é o `Business MW` (`478777497423728`)** — confirmado pelo print do painel:
  callback `https://chatspx.app/webhooks/instagram`, conta `bigstoreutilidades`
  (`17841468839878751`) com assinatura ativada, e o campo **`comments` já Assinado no nível do app**.
  ⚠️ O `INSTAGRAM_APP_ID` gravado na box é `1147598410038941` — é o *ID do app do Instagram* do
  produto, não o id do app pai; não confundir com o WABA TOZI (`1147301410628990`).
- **São DUAS camadas de assinatura**, e quem manda é a de **conta**: `GET /{ig}/subscribed_apps`
  devolvia `["messages","message_reactions","messaging_seen"]`. Essa lista é escrita pelo **próprio
  SPX**, no array fixo do `Channel::Instagram#subscribe`, e é sobrescrita a cada conexão de inbox.
- **Provado nos dois lados antes de mexer:** 7 dias de journal = **4.418** eventos de webhook do
  Instagram e **zero** evento de `changes` (nenhum `TestEventService`). Os únicos `changes` no log
  são do WhatsApp, que é outro produto.
- ✅ **`comments` LIGADO para a BigStore em 18/08**, por chamada de API, **sem deploy**, com snapshot
  e reversão automática embutida. Estado final:
  `["comments","message_reactions","messages","messaging_seen"]`.
  **Reverter:** `POST /17841468839878751/subscribed_apps?subscribed_fields=message_reactions,messages,messaging_seen`
  (script em `/tmp/liga_comments.rb` na box).
- **Por que foi seguro:** o SPX **não consegue responder** comentário (sem código e sem escopo), então
  ligar o recebimento **não** cria resposta dobrada com o n8n — aquele risco é só da resposta. O
  comentário chega, o job classifica como evento de teste e descarta. Nada muda para o cliente.
- ⏭️ **Falta provar com comentário real.** O rastro será a linha de `Parameters:` do
  `Webhooks::InstagramController` com `"field" => "comments"` no journal.
- 🔴 **A armadilha da frente, para quando ela abrir:** aquele array de `subscribed_fields` é
  **compartilhado por toda inbox de Instagram de toda conta em toda box** — inclui a Tozi, com a
  Clara viva na inbox 101. E o `subscribe` manda a lista inteira numa chamada só, com
  `rescue StandardError; true`: numa box cujo app não tenha o campo, a chamada falha, o erro é
  engolido e **o canal pode ficar sem assinatura nenhuma, matando o DM em silêncio**. Tem que ser
  condicional por canal e com a falha visível.
- ⏭️ **Responder** comentário continua dependendo de `instagram_business_manage_comments` no token →
  reconectar a inbox por OAuth. Aí sim é decisão + janela de manutenção.
- ⏭️ **Decisão de modelagem tomada pelo Paulo:** comentário **não vira conversa**. Vira superfície
  própria — uma página de rede social com o comentário, a publicação, e o que a IA respondeu (ou não,
  e por quê). O cache de publicações que essa tela precisa é **o mesmo dado** que a IA precisa para
  responder, então tela e cérebro são a mesma obra.

### [2026-08-18] 🔵 FRENTE ABERTA: `unidades` — onde moram as lojas do cliente (Fase 1)

> Worktree `orca/workspaces/chatspx/unidades`, branch **`PauloSeze/unidades`**, agente Claude
> rodando. Contrato: **`docs/contratos/unidades.md`** (está na branch de docs / PR #42, ainda não
> na `homologacao` — o worker lê por `git show origin/conciliacao/higiene-11ago:...`).

- **Por que existe:** o SPX **não tem lugar nenhum** para as unidades físicas de um cliente —
  verificado no código. `WorkingHour` é por *inbox* (quando o SPX atende, não quando a loja abre) e
  **não existe conceito de exceção/feriado em lugar nenhum do repositório**; `Captain::CustomTool`
  exige `endpoint_url`, então consulta mas não guarda; knowledge responde por similaridade, que é
  ruim em listagem e incapaz de fazer conta de data. Resultado medido na BigStore: o prompt da Bia
  diz *"você não tem nenhuma fonte de dados conectada"* e **toda** pergunta de horário, endereço,
  telefone ou preço vira handoff — no n8n a mesma IA respondia, porque tinha uma Data Table.
- **O princípio:** regra padrão e exceção são coisas diferentes, e **a exceção tem data e morre
  sozinha**. A dor do n8n não era guardar, era que exceção virava regra (`abre_domingo: true`) e
  alguém tinha que lembrar de desfazer. Exceção vale para um **conjunto** (etiqueta), senão
  "editar 20 linhas" só vira "criar 20 exceções".
- **Escopo da Fase 1:** 3 tabelas + models com a regra de resolução + tool `buscar_unidades` +
  rake de carga + specs. **Sem UI** — a tela é Fase 2 e depende das 4 questões da §9.
- **A prioridade da UI é invertida de propósito:** endereço muda uma vez por ano e a gente carrega;
  **exceção muda toda semana e precisa ser do cliente**, senão reconstruímos o n8n com mais passos.
- **Ganho de projeto sobre o n8n:** lá a instrução era o **modelo** converter "abre amanhã?" em data
  absoluta antes de consultar. Aqui a data se resolve **em Ruby**, no fuso da unidade. E expressão
  não resolvível tem que dizer isso — não pode virar "hoje" por omissão.
- ⚠️ **Armadilha evitada na criação:** a `homologacao` **local** deste notebook está **156 commits
  atrás** da origin. Worktree criada com `--base-branch origin/homologacao` explícito (`ce3adb2be9`).
  É a mesma pegadinha que em 15/08 fez um cherry-pick nascer sobre base velha.
- **Sem Run de orquestração**, de propósito: é **uma** frente, e a fila de mensagens do Run polui a
  conversa do Paulo. Supervisão por leitura do terminal.

### [2026-08-17] 🟡 FLOWS: o menu de opções sumia em canal que não desenha menu (PR #60) — armadilha latente, exposição ZERO hoje

> O `send_interactive` é o **mais antigo** dos cinco nós de canal e o **único sem guarda**. As quatro
> ações ricas (`send_cta_url`, `send_location_request`, `send_whatsapp_flow`, `send_template`) já
> levantam `StepSkip('inbox_not_whatsapp')`; ele confiava que o canal saberia desenhar.

- **Mesma classe do carrossel (#49) e do envio por exceção (#58):** canal que não implementa
  `input_select`+`items` **não recusa** — manda só o `content` e as opções somem. A pessoa recebe
  uma pergunta sem como responder, e nada registra falha.
- **Não dá pra reusar o `whatsapp_cloud_inbox?`** — menu não é exclusividade do WhatsApp. Desenham
  hoje: WhatsApp (cloud **e** 360dialog, pelo `create_payload_based_on_items`), Telegram
  (`inline_keyboard`), Facebook (`quick_replies`), LINE, widget (nativo no front) e **Api** (WAHA
  REST desenha; sem sessão WAHA o `WebhookListener` entrega os items ao consumidor). **Não** desenham:
  Instagram, e-mail, SMS/Twilio, TikTok. Virou capacidade de canal:
  `Channelable#supports_interactive_items?`, irmã da `supports_interactive_payload?` do #49,
  **falsa por padrão**.
- **Exposição medida antes de escrever código: zero.** Tozi prod tem **27 flows (25 ativos) e
  nenhum** usa ação de canal; a `.232` tem 1 flow demo com `send_interactive` na conta 3; as **4**
  mensagens `input_select` de 90 dias saíram todas em WhatsApp, todas `read`. Está declarado no PR —
  é trava preventiva, não incidente. Vale porque o motor de Flow está em construção, o gatilho
  **manual** roda qualquer flow sobre qualquer conversa, e a Tozi já tem inbox de Instagram viva.
- **Medição:** ramo **311 exemplos / 0 falhas** × baseline **307 / 0**. **Mutação** (spec novo contra
  código velho): **3 falhas**, exatamente as da guarda. O 4º exemplo novo — Telegram continua
  entregando — passa dos dois lados **de propósito**: é a contraprova de que a guarda não virou
  "só WhatsApp Cloud". Rubocop 0 nos 10 arquivos.

### [2026-08-17] ✅ CORREÇÃO DE REGISTRO: os PRs #32–#39 foram MERGEADOS em 12/08

> O STATE os listava como "fila do Walisson". Não estão mais. Entre eles o **#37**, que tirou a
> **cidade fixa "Sinop MT"** das buscas do Google (`buscar_lugar`/`buscar_localizacao`) — o bug
> compartilhado que atingia Fábrica e Tozi está **fechado**, não pendente. Fila real hoje:
> **#40, #41, #42, #43, #44, #46, #53, #57, #58, #59, #60** + os zumbis #1–#7.

### [2026-08-17] 🟢 CTWA — 93% das conversas de anúncio chegavam sem dizer de onde vieram (PR #59) · e o #56 virou #58+#59

> Lead de **formulário** já era carimbado desde julho; quem clica no anúncio e escreve primeiro
> entra por **outra porta** (pipeline de mensagem recebida) e ficava invisível. Medido na Tozi
> (conta 6, inbox 91), 45 dias: **167 conversas vindas de anúncio, 155 sem nenhum atributo de
> campanha (93%)**, de **17 criativos distintos**.

- **O dado sempre esteve lá** — no `referral` que a Meta manda junto da primeira mensagem. Ninguém
  o lia. Traz `source_id` (id do **anúncio**, não da campanha), `source_type`, `source_url`,
  `headline`, `body`, `media_type`, `image_url`, `ctwa_clid`. **Não vem nome de campanha nem de
  conjunto** — isso exigiria consultar a Graph. Mas vem o `headline`, legível, então a visibilidade
  não depende de chamada externa nenhuma.
- **PR #59 (fase 1, só visibilidade):** `Whatsapp::ReferralVisibilityService` +
  `Spx::CtwaVisibilityListener` no `AsyncDispatcher`. Carimba **as mesmas chaves** do fluxo de
  formulário (`meta_anuncio`, `meta_anuncio_id`, `meta_origem`, `meta_tipo`) de propósito — o
  marketing não pode ter duas taxonomias pra mesma pergunta. **Primeiro clique manda** (a conversa é
  única por contato; reescrever apagaria a origem em silêncio). **Uma label só** (`anuncio`), senão
  17 criativos viram 17 labels. Sem opt-in por conta: só age quando há `referral`, e o que grava é
  fato, não comportamento.
- **Medido na `.232`, banco dedicado, contra baseline (o próprio ramo com o commit revertido):**
  ramo **296 exemplos / 11 falhas** × baseline **289 / 11**, **lista de falhas idêntica** (as 11 são
  pré-existentes na box). +7 exemplos novos passando, zero regressão. Rubocop 0 nos 4 arquivos
  (a 1ª medição pegou `CyclomaticComplexity 8/7` no listener — era a navegação segura do log, não a
  regra; extraída em commit separado).
- ⏭️ **Fase 2 (rotear por `source_id`) NÃO foi feita** e depende de ler o **PR #44** antes, pra não
  duplicar `campaign_overrides`. É a fase que muda comportamento — decisão do Paulo.
- ⚠️ **Erro meu, corrigido:** commitei o CTWA em cima da branch do **#56** (conserto do envio
  silencioso no Instagram), misturando dois assuntos num PR só. Separado **sem force-push**: duas
  branches novas a partir da `homologacao`, **#58** (Instagram) e **#59** (CTWA), e o #56 fechado
  apontando pros dois.

### [2026-08-15 04:20] ✅ DEPLOY DA `.232` EXECUTADO — e o off-git dela virou código de verdade (PR #51 mergeado)

> O deploy estava **suspenso** desde 13/08 porque a box tinha trabalho vivo fora do git. Saiu hoje,
> depois de o trabalho ser resgatado, conciliado e mergeado. Box em `e14d711bc0`, 10 migrations
> aplicadas, assets recompilados, web+worker reiniciados, **zero erro no log**.

- **O que a box escondia:** 328 commits atrás, 2 à frente, 70 entradas sujas — e não era resíduo:
  **streaming SSE do Copilot**, painel de IA, **grupos de WhatsApp com autor por mensagem** e o
  **gate de sessão + backoff do LID** (`Waha::SessionStatusCache`). Um deploy direto apagava os 27
  arquivos rastreados em silêncio.
- **Resgate sem tocar na box** (havia 3+ sessões de agente rodando nela): commit montado com
  `GIT_INDEX_FILE` temporário, sem mexer em HEAD, working tree ou índice → branch
  **`backup/232-offgit-20260814`** (`b55d1045ee`, 66 arquivos, 11.184 inserções). Conferido depois:
  HEAD e as 70 entradas intactos.
- **PR #51 (mergeado):** as **16 colisões** (não 7 — a contagem inicial ignorou que os 2 commits da
  box também colidiam) resolvidas por um critério só: *isto já chegou à `homologacao` por outro
  caminho?* Chegou em parte. Ficou a homologação onde houve implementação em paralelo
  (`acceptable_webhook_urls`, `create_conversation_service`, `orphan_retriage`); ficou a box no que
  não existia lá (participantes de grupo, `SessionStatusCache`, rescue por episódio); ficaram **os
  dois** em `routes.rb`, no `router_service` (`skip_labeled?` **e** default tri-estado de grupo) e no
  i18n (fusão **por chave**, porque a fronteira do conflito cortava o meio de um objeto e concatenar
  gerava JSON inválido).
- **🔴 O que a suíte pegou e o merge textual não pegaria:** ficar com a versão da homologação do
  `orphan_retriage_job.rb` trazia de volta um bug que a box já tinha consertado — `notify_admins`
  roda **antes** do `update!` do marcador; com conversa inválida o alerta sai, o update estoura, o
  dedupe nunca existe e **todos os admins levam push/e-mail a cada tick do cron, para sempre**.
  Corrigido em `c7fbfc8836`. Conflito **semântico**: só apareceu rodando os testes do lado perdedor.
- **⚠️ O Almirante MENTE sobre esta VM.** `dry_run homologacao` disse *"ee87f5e799 → aaf5f8354
  (1 commits atras)"* e *"🟢 migrations em dia, nada pendente"*. O real: **328 commits** e
  **10 migrations**. Ele mede **antes** do checkout. Quem apertar o botão dele nessa VM acreditando
  no verde leva 328 commits e 10 migrations sem saber. **Deploy dessa box: medir na box.**
- **Receita que funcionou (sem `reset --hard`):** depois do #51 mergeado a box ficou *332 atrás e
  **0 à frente*** → `git stash push` nos 27 modificados + mover para `/tmp/pre-deploy-untracked/` os
  **39 não rastreados que passaram a existir na homologação** (senão o checkout recusa por colisão)
  → `git merge --ff-only` → `db:migrate` → precompile → restart. Nada destrutivo.
- **Gotcha do precompile:** `NODE_OPTIONS=--max-old-space-size=4096` **estoura o heap** nesta box
  (`Build with Vite failed!`, rastro de node sem mensagem clara). Com **8192** passa. A box tem 31 GB
  livres — o limite era o do Node, não o do SO.
- **Provado no processo vivo, não só no disco:** `SessionStatusCache`, `CopilotStreamsController`,
  `Conversation#group?` e `RouterService#skip_labeled?` todos carregados; **as 2 rotas de SSE
  existem** (era o motivo de mergear o #51 *antes* de deployar); 5 contas de pé (BigStore com 865
  conversas). `db:migrate:status` = 0 pendentes.
- ⚠️ **Lacuna declarada:** `MessageList.spec.js` — a homologação tem 4 testes de isolamento por
  agente e a box tinha 8 de agrupamento em grupo, com bancadas de store incompatíveis no mesmo
  arquivo. **O código de grupo veio; os 8 testes dele não.** Estão em `backup/232-offgit-20260814`.
- ⚠️ **Ainda no `/tmp` da box:** `pre-deploy-untracked/` (39 arquivos), `resgate232/` e as worktrees
  de CI `ci-fotos`/`ci-video`/`ci-conc`. Só apagar depois de alguém confirmar que não quer nada de lá.

### [2026-08-15 05:40] ✅ SEGUNDO DEPLOY DA `.232` — vídeo virou contexto e a BigStore está LENDO os stories

> Mergeados **#45, #50, #52, #49** e deployado: box em `59aba4a89f`. Sem migration nova, sem mudança
> de dependência, e o vite pulou o build corretamente (**0 arquivo de front** nos 11 commits).
> Receita já conhecida: ff-merge → migrate → precompile (heap **8192**) → restart. HTTP 200 nos dois.

- **Eram QUATRO portas, não uma** — e é por isso que "está pronto" não significava "está vendo":
  #45 não mergeado (`MediaDescriptionService` ausente) · #50 não mergeado (`VideoFrameExtractor`
  ausente) · o deploy anterior parava antes dos dois · e a chave `media_pipeline` da conta.
- **Ligado na BigStore** (conta 7, assistente 18): `media_pipeline = {video_description: true,
  video_transcription: true}`. Antes era `nil`.
- **🟢 PROVADO em vídeo real do story deles** (anexo 8322, 60s, 8,4 MB), e o caso resume tudo: o
  cliente escreveu só **"Tem em Sorriso?"**. Os **quadros** trouxeram o produto (caixa térmica
  vermelha de 5 litros, loja em Peixoto de Azevedo); a **transcrição** trouxe o que a imagem não
  tinha: *"garrafa térmica, dois litros e meio… pelo valor de trinta reais essa semana"*. **O preço
  só existe na fala** — é a justificativa medida para as duas chaves serem independentes.
- **Volume que justifica:** inbox 57 em 30 dias = **2.010 entradas, 915 com anexo (45%), 751
  `video/mp4`, 866 story replies**. Na Tozi vídeo era borda (9 chamadas em 60d); na BigStore é o
  meio do fluxo. Custo estimado: poucos dólares/mês (visão no modelo pequeno, 3 quadros a 768px).
- ✅ **Crédito da Anthropic da `.232` comprado pelo Paulo** — `claude-sonnet-4-5 → OK`. As chaves das
  duas boxes são **diferentes** (digest `ab7b103c…` × `c5778e20…`) e não compartilham balanço; a da
  OpenAI é a mesma. Isso destrava as contas **1, 3 e 7**.
- 🔴 **A IA da `.232` esteve MUDA e ninguém viu**, porque falha e silêncio deliberado tinham o mesmo
  rastro: `ignored {raw: ""}`. Foi o que motivou o segundo commit do #52.

### [2026-08-15 22:20] ✅ A TRAVA DA MENÇÃO ESTÁ NO AR NA PRODUÇÃO DA TOZI (PR #54 → #55), sem carregar mais nada

> Pedido: subir só o #54, sem prejuízo à Tozi nem ao que aguarda o Walisson. Feito por
> **cherry-pick cirúrgico**: a `producao` recebeu **1 commit, 2 arquivos, 53 inserções** — os 21
> commits da promoção continuam parados, esperando ele.

- **Caminho:** #54 mergeado na `homologacao` (para não se perder na promoção futura) → cherry-pick
  numa branch a partir de `origin/producao` → **PR #55** → merge → VM.
- ⚠️ **Armadilha que quase me pegou:** o Orca criou a worktree com `--base-branch producao` e pegou a
  branch **LOCAL**, que está **297 commits atrás** de `origin/producao`. O cherry-pick foi parar em
  cima de base velha. Refeito a partir de `origin/producao`. **A `producao` local deste notebook
  está podre — e a worktree `chatspx-clientes/tozi-prod` está nela.**
- **Transporte por `git bundle`**, porque a VM **não tem credencial git** (`could not read Username
  for github.com` — dívida antiga confirmada de novo). O bundle mantém o git da VM consistente, ao
  contrário do scp de arquivo solto que já criou o off-git de junho. A VM saiu de **detached HEAD**
  e ficou na branch `producao`, em `142564790`.
- **Sem migration (0 pendentes, conferido antes do restart), sem mudança de dependência e sem
  arquivo de front** — mudança só de Ruby, então nada de precompile. Restart do **worker primeiro**
  (não derruba requisição) e depois do web. HTTP 200 local e público, zero erro no log.
- **Provado no processo vivo, com as mensagens REAIS do incidente:** constante e método presentes ·
  a menção que gerou a ligação (msg **1652245**) → `should_respond? = false` · a resposta a story da
  **mesma conversa** (msg **1652242**) → `true` · texto comum do WhatsApp (inbox 91) → `true`.
- Medição antes de subir, contra o código da **produção** (que difere da homologação):
  **17 exemplos / 1 falha no ramo × 12 / 1 na base** — a falha é o spec obsoleto de `skip_labels`,
  pré-existente lá e já corrigido no #52, que está só na homologação.

### [2026-08-15 21:48] 🔴→🟢 INCIDENTE TOZI IG: a Clara respondia MENÇÃO de story — inclusive dos próprios corretores

> Cliente ligou. Tozi PROD, conta 6, inbox 101. **Contido por conduta no banco** (sem deploy),
> com prova na conversa real. Backup: `/tmp/assistant_7_ins_mencao.bak-20260815214805`.

- **O que acontecia:** quem **recompartilha** um story da Tozi gera um `story_mention`, e quem
  responde a story manda `ig_story_reply` — muitos sem texto. A regra **#68** (`conversation_created`
  → `assign_ai_agent` Clara) atribui a Clara, que responde qualquer coisa.
- **Escala medida (60 dias):** **53 mensagens de menção, 33 conversas, a IA falou em 31 — 48
  mensagens**, todas da **Clara #7** (nenhum outro agente). Frases mais repetidas: *"Vi que você
  enviou um arquivo. Como posso te ajudar?"* (12x) e variações.
- 🔴 **Quem estava sendo abordado:** `viniciustiago.ocorretortozi`, `lucassouza.ocorretor`,
  `adrianomachado01`, `rosivanecorretora_tozi` — **os próprios corretores da casa divulgando**. A IA
  perguntava a eles se queriam alugar ou comprar.
- **Caso que gerou a ligação (conv 49383 / display 28174, 13h26–13h30):** a pessoa respondeu a três
  stories e recompartilhou um; levou **5 mensagens em 4 minutos**, uma delas em resposta a *"Eles
  arrasam!!!"*.
- **Causa de fundo:** o prompt da Clara tem **24 mil chars e ZERO menção** a Instagram, story,
  menção, imagem ou vídeo. Ela foi escrita para WhatsApp e herdou a inbox do Instagram — é a
  cegueira de canal já mapeada. Some-se a isso que a prod **não tem a camada de mídia** (#45/#50 só
  na homologação), então ela é de fato cega a vídeo lá.
- **Conduta aplicada** (+1.099 chars): menção não é atendimento → `[IGNORAR]`; resposta a story sem
  pergunta nem pedido → `[IGNORAR]`; e **nunca dizer que não conseguiu ver** — se a mídia não chegou,
  o problema é nosso, não da pessoa.
- **Provado sem enviar:** o histórico real da 49383 → `[IGNORAR]` **3/3**; a mesma conversa com uma
  pergunta de locação → atende e transfere para a Bruna **2/2**.
- ⏭️ **Conserto durável é código, não conduta:** `story_mention` não deveria nem acordar a IA — o
  router precisa ignorar por tipo, como o n8n da BigStore já faz num ramo dedicado. Conduta é
  mitigação: ela ainda roda o modelo para depois calar.
- ⏭️ As 31 conversas já poluídas seguem abertas com as mensagens da IA; ninguém as tocou.

### [2026-08-15 02:50] 🟢 BIA LENDO VÍDEO DE STORY — provado ponta a ponta, e a conduta ajustada no banco

> Conta 7 · inbox 57 · assistente 18 · VM `.232`. Nada enviado ao cliente: prova por
> `generate_response`, que não cria mensagem.

- **Funciona:** a camada leu o story do Paulo (fruteira com tampa, **R$ 20 à vista, R$ 22 em 3x**,
  tirado dos quadros) e o contexto do agente passou a conter a leitura rotulada.
- ⚠️ **Duas conclusões minhas que a medição derrubou** — as duas por sonda mal feita, não por
  defeito do sistema:
  1. *"A Bia ignora o contexto"* — falso. Minha sonda montava o histórico como **texto puro**,
     enquanto o `ResponseBuilderJob` monta com `prepare_multimodal_message_content`. A leitura
     nunca chegava ao modelo no teste. **Lição: replicar o caminho do job, não improvisar histórico.**
  2. *"A conduta velha impedia o uso do vídeo"* — falso. Mesmo dizendo `você não enxerga nada`, o
     modelo **seguiu a evidência do contexto** e usou a leitura. A instrução obsoleta não bloqueou.
- **Conduta ajustada assim mesmo**, porque prompt que mente sobre a capacidade é frágil (hoje o
  modelo ignora, amanhã obedece e alucina "não vi"). Backups em `/tmp/assistant_18_ins_video*.bak-*`
  com linha de RESTORE.
- **A/B com o texto real das três versões** (mesma mensagem, mesmo contexto):
  - velha → dá o preço **como fato próprio** (`À vista R$20…`)
  - minha 1ª versão → **empobreceu**: sumiu o preço e sumiu o município que ela puxara do histórico
  - **final** → `O story mostrava R$20 à vista … Pra confirmar se ainda tem na unidade de Sinop,
    uma pessoa do time vai responder` — dá o preço **atribuindo à origem** e deixa disponibilidade
    com o humano. Story expira em 24h, então o preço lido é de no máximo ontem.
- **Pronto para teste ao vivo:** fila `low` (a do job de mídia) está sendo consumida, hook devolve
  `true` para a conta 7, e o espelho segue atribuído só na conversa do Paulo.
- ⏭️ **PR #53 (cache por story) ainda não deployado:** enquanto não for, duas pessoas respondendo
  ao mesmo story fazem o vídeo ser lido duas vezes.

### [2026-08-15] ✅ QUATRO SPECS PARADOS NO TEMPO — **PR #52 mergeado**, homologação sai de 4 falhas para 0

> Medido nos dois lados: `origin/homologacao` (`e14d711bc0`) = **38 exemplos, 4 falhas**; o ramo do
> #52 = **40 exemplos, 0 falhas**. Rubocop 4 × 4. Nenhuma mudança de comportamento — a única linha
> fora de spec extrai o rótulo do áudio para a constante `AUDIO_TRANSCRIPTION_LABEL`, que é o que
> impede a divergência de voltar (era string literal solta, e por isso o spec pôde derivar em
> silêncio). Conferido que nenhum outro ponto do código ou do front usa o literal.

> Não é bug de código: em todos, o código mudou por decisão deliberada e o teste ficou afirmando o
> contrário. Medido nos dois lados (o mesmo spec falha num ramo sem as mudanças).

- `open_ai_message_builder_service_spec.rb:78`, `:145`, `:275` — esperam a transcrição de áudio
  **crua**; o código a entrega **rotulada**, e o rótulo é de 25/07, do fix do falso positivo que
  silenciou um cliente por 16h.
- `router_service_spec.rb` (`:71` na homologação, `:114` depois do #51) — afirma que `skip_labels` é
  *guard morto*; ele foi **ressuscitado em 23/07** para o interlocutor-robô (label `bot-externo`) e
  está vivo no `should_respond?`.
- ⚠️ O handoff de 14/08 atribuía a vermelhidão ao **PR #41**. Não é: o fix funcional e o spec do #41
  já estavam na `homologacao` (`aaf5f8354b`). A confusão veio de comparar com `git diff A...B` (três
  pontos), que mede contra a **base de merge**, não contra o topo. **#41 é refactor, não urgência.**

### [2026-08-14] 🔴→✅ FOTOS DA IA NO INSTAGRAM: o carrossel saía como TEXTO (PR #49) · vídeo vira contexto (PR #50)

- **A tool era chamada e não entregava imagem, sem registrar falha.** O carrossel monta
  `content_attributes['interactive_payload']`, lido **só** pelo `WhatsappCloudService#send_message`;
  em qualquer outro canal a mensagem sai como o `content` — o cliente recebia a frase
  `📷 Carrossel: 9 fotos do imóvel X` e nada mais. Medido na Tozi (conta 6, inbox 101), 60 dias:
  **9 chamadas, 2 conversas, 0 imagem, 0 falha**; no WhatsApp, 931 chamadas entregando. Os clientes
  responderam *"Não apareceu"*, *"Só a mensagem"*, *"Fotos não carrega"* — e a IA insistiu que tinha
  mandado, porque a tool devolve "enviei".
- **PR #49:** `Channelable#supports_interactive_payload?` (false por padrão; true só em
  `Channel::Whatsapp` com provider `whatsapp_cloud`) + a trava anti-alucinação passando a ler
  **`urls_imoveis` além de `codigos_buscados`** — o primeiro guarda Codigo **e** ImoCodigo e corta em
  60, o segundo só o Codigo e corta em 40, então a IA citando o ImoCodigo levava "não" silencioso
  (aconteceu na conv 48182 com 3 códigos seguidos). ⚠️ Os **Flows** têm o mesmo buraco e não foram
  tocados.
- **PR #50 (empilhado no #45):** vídeo → contexto, **duas chaves independentes por conta**.
  Medido no story real da conv 48193 antes de escrever código: 3 quadros a 768px com `gpt-4.1-mini`
  leram **o código do imóvel (9718)**, preço, metragem e telefone — e o Whisper, no mesmo arquivo,
  devolveu `🎵Music Plays🎵` e setenta emojis de fogo. Por isso `video_description` e
  `video_transcription` são separadas: na Tozi o dado está **escrito**, na BigStore é **narrado**.
  **`ffmpeg` 6.1.1 já estava na frota** (o ActiveStorage o usa) — a objeção de infra não existia.
  Story de **foto** já funcionava; o buraco era só vídeo, que é **61 dos 83 anexos** daquela inbox.

### [2026-08-14] 🟡 BIGSTORE: a Bia NÃO está desconectada — está elegível e muda

> Corrige o handoff de 14/08, que a dava por desconectada. Muda o risco: ligar virou **uma automation
> de distância**, não um trabalho.

- `CaptainInbox #15` existe desde **12/08 16:42**, `active_bot? = true` na inbox 57 (conta 7).
- Ela falou **4 vezes, todas em 12/08, numa conversa só** — a **2675, do contato #2206 "Paulo Seze"**.
  Em 7 dias: **1.252 mensagens de clientes, 1.432 respostas do time pelo app do Instagram**
  (`external_echo: true`) e **4 da IA**.
- **O que segura é o gate por atribuição:** só a 2675 tem o espelho atribuído; as outras 844 estão
  com `bot=nil` e **não há automation nenhuma na conta 7**. Ou seja, o "piloto restrito ao contato do
  Paulo" que ele pediu **já é o estado de fato** — não há o que configurar.
- ⚠️ **A whitelist antiga não existe mais:** o `RouterService` declara em comentário que
  `only_contact_phones`, `skip_labels` e `skip_after_human_response` morreram com o gate por
  atribuição. Pedido de "ligar só para o meu contato" hoje se resolve **atribuindo o espelho**.
- Buraco real do canal, medido: conv 2676 — cliente pergunta **21h12**, resposta **08h21** do dia
  seguinte.

### [2026-08-14] 🟢 DISPARO URBAN DEVILLE (Tozi c6, inbox 99) concluído + regra #73 fecha o buraco de roteamento dos disparos

> Campanha #7 pelo motor nativo (`Campaigns::Whatsapp`), não pelo `DisparoLeadJob`. Base
> `LEADS_PRODUTO_VERTICAL2026_SEM_DUPLICADOS.xlsx`: 2.759 linhas → 2.756 aptas → **2.649 elegíveis**
> após cortar 79 já-disparados, 15 recusas explícitas e 17 com conversa aberta. Enviados os 130 primeiros.

- **Resultado: 128 enviadas / 2 falhas** (`131026` número sem WhatsApp — não é cobrado). Ritmo 3/min (`pacing_seconds: 20`), `target_team_id: 62`, `quiet_hours 18h–8h`, header de imagem em `public/urban-ago26.jpg`.
- **Template `tozi_urban_lancamento`** (id `925689729922756`, APPROVED) — header IMAGE via resumable upload (`POST /{APP_ID}/uploads` → `POST /{upload_id}` com `Authorization: OAuth` + `file_offset: 0` → handle), 1 variável, 2 quick replies. Corpo começa com texto porque a Meta rejeita variável na abertura (`2388299`).
- 🔴 **GOTCHA que custou 6 pessoas:** `CampaignRecipient#template_params` é **`{'1' => valor}`** (documentado em `send_template_service.rb:23`), não `{'body' => [valor]}`. Com o formato errado o HSM sai **sem erro e sem o nome** ("Oi , sou a Kettlen..."). Peguei no 6º **lendo o texto enviado**, não o status — status só diz que a Meta aceitou. Era o primeiro template com variável nesta conta, não havia precedente para copiar. Corrigidos os 124 pendentes antes de retomar.
- **🟢 Buraco de roteamento fechado — regra #73** `Disparo inbox 99 — time Kettlen → Kettlen` (`conversation_opened` + `inbox_id=99` + `team_id=62` → `assign_agent=126`), criada por `dup` da #72 para não inventar formato. **O time 62 tem `allow_auto_assign=false`** e não tinha regra: o lead respondia, a conversa reabria no time e ficava **sem dono** até alguém abrir o painel. Medido: João e Cibele estavam atribuindo à Kettlen **na mão**, uma a uma, com até 13 min de espera. A regra automatiza o que já era a prática. As campanhas anteriores já tinham as #70/#71/#72 (Francielli 68→138, Henrique 69→140, Weigler 70→139).
- ⚠️ **`conversation_opened` só dispara na transição resolvida→aberta.** Conversa que já está aberta e recebe nova mensagem **não** passa pela regra — por isso a #73 não age nas que reabriram antes dela existir (essas seguem na mão).
- **Levas seguintes:** **#8** (sáb 15/08, 8h–12h) → **998 enviadas / 2 falhas**, **6,6% de resposta (66 leads)** — a projeção feita a partir da #7 dizia 63. **#9** (ter 18/08, 8h–9h) → **300 enviadas / 0 falhas, 9% de resposta**. Número seguiu **GREEN** depois de 1.426 disparos.
- **[19/08] Três campanhas configuradas de uma vez, dedup em cascata (0 telefone repetido entre elas):** **#10** Kettlen 500 · **#11** Leandro 200 · **#12** Leandro 300 (qui 20/08). Fecharam **500 + 200 + 298, 2 falhas**.
- **🟢 [21/08] TETO DE VELOCIDADE MEDIDO — `pacing_seconds: 1` = 60/min, e passa liso.** Campanha **#13** (Kettlen, 200): **200 enviadas em 4 minutos** (17:52:50 → 17:56:50), **zero falha**, zero throttle, número **GREEN** imediatamente depois. É **5× o ritmo mais rápido já provado** (12/min do `DisparoLeadJob` antigo). O limite do motor é `batch_size = 60 / pacing_seconds` com `MAX_BATCH = 200` por tick de 1 min — então 60/min é o máximo prático, não uma escolha conservadora.
- **Urban DeVille encerrado: 2.624 enviadas, 6 falhas** (todas `131026`, número sem WhatsApp) + **#14** com os **25 últimos** agendada para sáb 22/08 8h → total **2.649**. ⚠️ Fila da Kettlen em **148 abertas** ao fim.
- 🔴 **A base acabou, e o gargalo seguinte é COPY, não lista.** Existem **4.825** pessoas que receberam disparo anterior (Casas Pacaembu 4.863 · Motoristas de app 603) e nunca receberam o Urban. **Não dá para mandar o template atual para elas:** a copy afirma *"há um tempo você procurava **apartamento** para comprar"*, e esse público veio de campanha de **casa MCMV** — a frase é falsa sobre a pessoa, que é a classe de erro da REGRA #1 e o caminho mais curto para bloqueio/queda de qualidade. Retomar volume exige **template novo com copy honesta** (casa → apartamento), não uma lista nova. Decisão do Paulo em 21/08: por ora, só os 25.
- ⚠️ **O pool encolhe sozinho:** os "livres" caíram de 47 para 25 em um dia porque o corte *conversa aberta* subiu de 90 para 210. Contagem de elegíveis vale para o instante da medição — recontar sempre na hora de montar a campanha.
- **[22/08] Lista de indicações da Maria Alice (`Untitled spreadsheet (1).xlsx`, 112 contatos): campanha #16, 103 enviadas / 0 falhas**, 11:02→11:22 a 5/min, número GREEN depois. Cortes: 9 já disparados, 1 em conversa aberta, 0 recusas, 0 duplicados. DDDs de 18 a 96 — **não é lista de Sinop**. **Total do Urban: 2.752.**
  - ⚠️ **Decisão do Paulo contra recomendação registrada:** eu propus `tozi_convite_whatsapp` (aprovado, `{{2}}` livre, permitiria dizer a verdade sobre a origem do contato); ele escolheu o `tozi_urban_lancamento`. Então 103 pessoas que **nunca falaram com a Tozi** receberam *"há um tempo você procurava apartamento para comprar"*. Se a qualidade do número cair, é o primeiro lugar a olhar; o `health_gate` pausa sozinho.
- 🔴 **[22/08] A DEDUP TINHA UM PONTO CEGO — os disparos de junho eram invisíveis.** As campanhas **1 e 2** (motor antigo `DisparoLeadJob`, ~6.100 pessoas) carimbam `campaign_id` **na conversa** e **não criam `campaign_recipients`**; todos os meus cortes liam só a tabela nova. **294 pessoas receberam disparo em junho e o Urban agora.** Correção: o conjunto de exclusão precisa unir `CampaignRecipient` **e** `Conversation.where.not(campaign_id: nil)`.
- **Inventário real de audiência (22/08, dois motores somados):** 30.292 contatos com telefone · **13.980 já receberam algum disparo** · 361 recusaram · **15.276 nunca receberam nada**. ⚠️ Os 15.276 **não são uma base**: é todo mundo que já falou com a Tozi por qualquer canal, sem produto, segmento nem recência. Prontas para virar volume: **4.823** (Pacaembu/motoristas, nunca receberam Urban) + **~5.800** (junho, nunca receberam Urban) — as duas travadas na mesma coisa, a copy.
- 🟢 **A guarda de janela pegou um erro meu de verdade (22/08):** eu montei a campanha achando que era sexta 19h e o script abortou com *"enviaria AGORA (11h)"* — era **sábado 11h**. Transação revertida, nada criado. **Nunca deduzir a hora do fio da conversa: ler o relógio da VM.**
- ⚠️ **A janela é por HORA CHEIA** — `quiet_hours?` compara `Time.current.hour`, então **16:30 não é expressável**. O pedido original da #11 era 16h30; virou 16h por decisão do Paulo, para não depender de alguém dar `dispatch_running!` na hora.
- **Leandro Silva (#142, `ljscorretor@gmail.com`) já existia** com time **#71** (`auto_assign=true`) e a regra **#74** (inbox 99 + time 71 → `assign_agent=142`), montada no mesmo padrão da #73. Nada a criar.
- **`quiet_hours` é a janela de SILÊNCIO, não a de envio** (`dispatch_scheduler_job.rb:63`): `{start: 12, end: 8}` cala das 12h às 8h, ou seja envia 08:00–11:59. Campanha criada já em `dispatch_running` fora da janela fica muda e acorda sozinha — não precisa de ninguém apertando botão na hora. Os scripts de criação **abortam** se, com a config escolhida, a campanha fosse enviar no instante da escrita.
- **Receita que fechou o buraco do nome:** em vez de escrever o `template_params`, o script **lê um destinatário que já renderizou certo** na campanha anterior e aborta se a chave não for `'1'`. Também aborta com template não aprovado, imagem do header fora do ar, nome vazio na seleção ou elegíveis insuficientes.
- **A inbox 99 não tem IA nenhuma.** A regra que mandaria pra Clara (#63) está escopada na **inbox 91**. As 583 abertas da 99 são todas de humano (Francielli 310, Weigler 192, Henrique 81). ⚠️ Não confundir com a queixa da equipe sobre "a Clara pega tudo" — aquela é da **91**. São duas filas com desenhos opostos.

### [2026-08-12] 🔴→🟡 FÁBRICA: vazamento de marca contido no SPX (causa raiz segue no MTM) · Tozi: override do Pacaembu · BigStore: agente criado desconectado

> Sessão orquestradora geral. Tudo medido na VM, não deduzido. Relatórios completos em `Temp/` das
> worktrees `chatspx-clientes/fabrica`, `chatspx-clientes/tozi-prod` e `orca/workspaces/chatspx/instagram-comentarios`.

- **🔴 FÁBRICA — as IAs mandavam cliente para loja do Atacadão.** Os 4 prompts dizem "óticas Fábrica dos Óculos" e a `mtm_loja_mais_proxima` envia `departamento=fabrica`, mas **o MTM ignora o filtro**: 3 de 3 chamadas voltaram `departamento=atacadao` (Várzea Grande `shop_id=3`, Cuiabá `shop_id=5`, Pedra 90 `shop_id=8`), com endereço que a IA passava ao cliente e `shop_id` que ela usava para agendar. **Contido no response_template** (guarda por departamento) — 3/3 agora devolvem `NAO_ACHOU_LOJA`, sem regressão (Sinop empate/referência e Sorriso intactos). ⚠️ **A causa raiz continua no MTM** e Cuiabá/VG passam a ficar sem loja pela IA da Fábrica até a conta 2 existir.
- **🟡 A guarda criou beco sem saída:** `NAO_ACHOU_LOJA` não existe no prompt da Bia — ela ignora e segue qualificando (gênero, presente, CPF) até o cliente descobrir no fim que não há loja. A Elen acerta por **não** ter o fluxo de loja. Correção de conduta em andamento no bloco `# Cidade e loja` (byte-idêntico em Bia/Carol/Sofia).
- **Aplicado na conta 1** (config, prompts byte a byte intactos, backup em scratchpad + `RESTORE`): calendário expõe `agora.*`; `mtm_criar_proposta` manda hora XOR período (**enum confirmado por sonda com data no passado + controle negativo**: `manha`/`tarde`/`sem_preferencia` — e `morning`/`afternoon` também passam); Sofia ganhou `mtm_calendario`; Elen perdeu `buscar_lugar`/`buscar_localizacao`. **Vale sem restart** (provado: uptime 21h anterior à escrita, toolset remontado no processo quente, sem memoização).
- **⚠️ Almirante é CEGO para a VM da Fábrica** (`ai_get_agent` → `sem aiconfig_url`, `ai_history` → null, enquanto tozi devolve 1,9M chars). Não há rollback governado ali: backup manual é a única rede.
- **Código off-git do box resgatado e pushado:** `backup/fabrica-box-offgit-20260812` (`b6000bcc113b`, pai `2d2d2eaef`). São 5 arquivos + `SessionResetService` novo, com a feature **ATIVA** na conta 1 — deploy por cima apaga em silêncio. 34/34 hashes conferidos. Prompts ficaram **fora** do git (conduta de cliente não vai para repo compartilhado; vão para o vault).
- **🔴 Bug compartilhado (atinge a Tozi também):** `buscar_lugar_tool.rb:57` monta `textQuery: "#{query} Sinop MT"` e `buscar_localizacao_tool.rb:18` faz `geocode('#{local} Sinop MT')` — **cidade fixa na consulta ao Google**. Referência em Sorriso é geocodificada como Sinop. Vira issue.
- **TOZI — override do Pacaembu aplicado** (Hook #8, `campaign_overrides`), provado sem enviar mensagem: Pacaembu passa a usar `tozi_lead_pacaembu_abertura` (APPROVED, 1 variável, `body_fields` casando — sem rota de `#132000`) e as outras 7 campanhas seguem idênticas. **CASAS 300-900K ficou sem override**: nenhum dos 34 aprovados serve.
- **Mapa das campanhas (90d, 1.270 leads):** Pacaembu 668 · RMKT 2026 398 · Site 102 · ETNA 21 · CASAS 20 · RMKT 4 · ACQUA 0. **`assign_agent_bot_id` e `assign_team_id` são honrados POR CAMPANHA** (`create_conversation_service.rb:112-119`) — hoje todos nil, então tudo cai no bot 17 (Júlia).
- **Locação — premissa corrigida:** das 126 conversas no time 27, **58% (73) foram movidas pela própria IA** (Júlia 57, Sofia 15, Marina 1), não à mão. A Júlia já tem `transferir_para_agente` e a conduta já manda transferir para a Bruna. O sinal (`jornada` = "Interesse em locação") **já chega ao modelo a cada turno** e é determinístico no Site (46 de 83); ela só não é instruída a agir. Perda concreta hoje: **7 leads**. Override no hook #9 é **impossível** (resolve por `campaign_id`, lead de site não tem).
- **`{nome_anuncio}` do CASAS é nome interno** — "IMÓVEL 9817 - TELHADO APARENTE", "9817" (16/16 sem catálogo, `meta_imovel_codigo` = 0). Mas **o código do imóvel está no nome do anúncio**, e o SPX já sabe resolver código → descrição + foto (é o `tozi_rmkt_imovel`, **65,5% de resposta contra 35,0%** do só-texto). Frente `PauloSeze/meta-leads` aberta para derivar o código do nome do anúncio + corrigir a **abertura duplicada** (`initial_message_already_sent?` usa `content_attributes @>` em campo com dupla serialização → sempre falso → **26 leads receberam o HSM duas vezes em 90d**).
- **BIGSTORE — o DM não é canal de venda, é mesa de triagem geográfica.** Censo de 1.389 entradas e 1.611 respostas humanas: mediana de resposta **17 caracteres**, 27,8% encaminham para o WhatsApp da loja, 13,7% são só um telefone, a pergunta mais repetida é "qual cidade?", preço aparece em 0,4%. **Assistant #18 criado na conta 7, DESCONECTADO e sem triagem** (provado: `CaptainInbox` vazio dos dois lados, `active_bot?` false). ⚠️ **Não ligar**: a única saída dele é handoff, e o time trabalha **99,9% pelo app do Instagram** (1 mensagem com sender User em 1.611) — ninguém leria. 518 das 626 conversas estão fora da janela de 24h e o Instagram **não tem HSM**.
- **PRs abertos hoje (fila do Walisson):** **#36** imóvel pelo nome do anúncio (opt-in por campanha, extração ancorada provada em 7 valores reais + 9 negativos) + abertura duplicada (bug provado ao vivo: sem o fix o redelivery gera 2 aberturas) · **#37** dupla serialização do NPS nos 3 pontos + cidade das buscas do Google saindo de config por conta (⚠️ **o NPS muda comportamento ao vivo**: o filtro casa com 0 linhas hoje e passaria a casar com 8.194 de 12.844; 581 pesquisas ativas mudam se o cliente responder depois do deploy — **decisão do Paulo**, e os 2 commits são revertíveis em separado) · **#38** tela de campanhas fatia 1 (só leitura: template configurado × o que de fato saiu, override × padrão, quem atende).
- **🔵 DOIS "NÃO" QUE VALEM MAIS QUE UM SIM** — as duas frentes mediram e **se recusaram a aplicar**:
  1. **Conduta da Júlia para locação NÃO funciona** (3 versões, 8 rodadas cada, ~200 execuções, nada escrito). No formato dominante do dado real (`"...último imóvel visto NNNN (Casa)"`) a transferência **nunca dispara** — 0/8 no baseline e 0/8 nas três versões. Causa isolada: o que decide é o **verbo** da jornada, não a declaração — "Pediu agendamento de visita" dá 5-6/8; "último imóvel visto" dá 0-1/8 **mesmo começando com "Interesse em locação"**. Ser mais explícito **piorou** (7/8 → 3/8). Regressões novas observadas: Júlia transferindo **para si mesma** (suja `ia_transferencias` e conta no trilho anti-ping-pong) e um `[IGNORAR]` = lead real silenciado.
  2. **Regra de string sobre a jornada também não serve:** 89,7% de precisão com **4 FP, 2 deles terminando em vendas**. FP **irredutível**, provado: 3 conversas com jornada **byte a byte idêntica** foram para financeiro, locação e vendas. A informação que decide o destino **não está no campo**.
  - **Escopo que limita tudo:** `jornada` existe em **83/83 leads de Site e 0 de 1.169 de campanha Meta** — 6,6% dos leads. Os 88 de locação vindos de campanha não têm sinal estruturado.
  - **Conserto durável = na origem:** o site sabe a intenção no clique e manda como prosa num campo narrativo. Um campo de intenção com valor fechado faria o hook discriminar no ponto mais cedo. É código (site + `PERMITTED` do `site_leads_controller.rb:12`) — **decisão do Paulo**. Ganho sem risco hoje: fila/alerta para os **7 leads** com jornada de locação parados no time de entrada.
- **Vazamento de marca no nível de TIME (Fábrica): medido, não houve.** Das 15 chamadas de handoff no histórico (31/07–11/08), 8 passaram `team_id` e **as 8 foram para time da Fábrica**; 7 não passaram time. ⚠️ Limite honesto: janela curta, tráfego quase todo de teste, nenhum cliente real de Cuiabá/VG chegou ao handoff. A IA **oferecia** verbalmente "a equipe de Cuiabá"; a execução nunca ocorreu. Corrigir a **descrição** dos times é inócuo (a HandoffTool publica só `id: nome`). Em andamento: renomear os 3 times do Atacadão para carregarem a marca. **Buraco vizinho:** em 7 dos 15 handoffs a IA não passou time e a conversa fica **sem fila**.
- **PR #39 — allowlist de times por conta** (fecha a 2ª camada do vazamento de marca). `Account#handoff_teams` lê `custom_attributes['handoff_allowed_team_ids']` e é ligada em **dois** pontos: a enumeração do `handoff_tool` (advisory) **e** o `resolve_team` do `human_handoff_service` — este é o que fecha, porque o modelo pode passar id que ninguém enumerou. Time recusado se comporta como id inválido e **não derruba o handoff**: cai no time padrão do agente e, se esse também estiver fora, segue sem time (caminho que já existe). ⚠️ **Consequência declarada: a allowlist precisa incluir os times padrão dos agentes.** Opt-in: conta sem a chave não muda. Suíte: 300/26 no ramo × 293/26 no baseline, **lista de falhas idêntica** (as 26 são pré-existentes na box) → +7 exemplos novos passando, zero regressão.
  - 🔴 **Buraco maior registrado no PR, não relacionado:** `copilot/assign_conversation_service.rb:27` seta `team_id` **sem nenhuma validação de conta**.
  - **Por que o renome não bastou** (medido): a IA lê "atacadão" no nome do time e roteia assim mesmo, **3/3**, inclusive reconhecendo na mesma resposta que não há loja na cidade. Renome aplicado e mantido só por deixar a marca visível ao humano no painel — **não conta como conserto**. Reversão no relatório.
  - **Remover os times não é opção:** `destroy` falha com FK de funnels (todo time ganha funil no `after_create`, sem `dependent:`), não existe conceito de desativar na tabela, e duas usuárias ficariam sem time. Mover para a conta 2 deixa 6 registros órfãos entre contas. **A conta 2 já tem os 3 times equivalentes** (#11/#12/#13) — os da conta 1 são resíduo de cadastro.
- **Prática de orquestração documentada:** `docs/ORQUESTRACAO-ORCA.md`. A causa da poluição de hoje foi usar `dispatch --inject` de baixo nível, que **não tem ciclo de vida** — `worker-release` só enxerga dispatch de `worker-start`, então worker que termina fica pendurado emitindo batimento rejeitado. A receita do handoff de 11/08 está marcada como superada.
- **INSTAGRAM/comentários:** `docs/SPEC-instagram-comentarios.md` (na `homologacao`) mapeou o código. Gargalo único: **`instagram_business_manage_comments`**, que o SPX não pede (`integration_helper.rb:2`) e destrava as 4 capacidades de uma vez; `private_replies` usa o **mesmo** `POST /{ig_id}/messages`, trocando `recipient {id}` por `{comment_id}` (7 dias, 1 por comentário, 750/h). `HUMAN_AGENT` = **false nos 3 boxes**; decisão do Paulo: **não mexer**. Brief para o painel da Meta em `instagram-comentarios/Temp/BRIEF-META-escopo-comentarios.md`.

### [2026-08-11] 🟢 ALUCINAÇÃO DE LOCALIZAÇÃO CORRIGIDA na raiz — o exemplo do prompt ERA a invenção (banco conta 6, agentes 13 e 14)

> Caso Catatau, conv **2159** (prod Tozi). Cliente pediu casa perto de um comércio; a Bruna citou **duas avenidas que não existem** pra aquela rede, e depois costurou o endereço real dentro da invenção. Diagnóstico com prova, correção no banco, medição antes/depois.

- **Causa provada (não deduzida):** o prompt trazia `ex.: cliente diz "trabalho na Ronta" → "Tem mais de uma Ronta, você trabalha na da Tarumãs ou na da Perimetral?"`. Pelo `journalctl -u chatwoot-worker.1` filtrado por `session_id` `6_2159`, no turno que errou o `RunResult` tinha **`role: :tool` = 0** (nenhuma ferramenta executada) e zero ocorrência do endereço real no contexto; no turno seguinte, 4 turnos de tool e o dado certo. **Ela respondeu de cabeça e preencheu o molde com os nomes do exemplo.** Violação da REGRA #1 do Paulo dentro do próprio prompt.
- **Dado real** (Google Places, estável em toda variante de query): as 2 unidades são **R. das Caviúnas, 763** (Setor Comercial) e **R. João Pedro Moreira de Carvalho, 205** (Setor Industrial). Nenhuma em avenida nenhuma das citadas.
- **Dois erros irmãos no mesmo atendimento:** (a) **distância inventada** — disse "menos de 1 km"/"1 km"; real 3,48 km e 2,39 km (a `buscar_imovel` já devolve a distância calculada, ela não usou); (b) **código trocado** — descreveu o imóvel de R$ 1.950/2 quartos (5195/5196) mas mandou carrossel e link do **5194**, que é R$ 3.200/3 quartos. O card final cravou "Cód. 5194 | R$ 1.950 | 2 quartos".
- **Aplicado no BANCO (sem deploy, prompt é lido vivo), agentes 13 (Júlia) e 14 (Bruna):** exemplo removido e substituído por comportamento sem nome de lugar + ordem explícita (antes do retorno da ferramenta não cita logradouro, não afirma que há mais de uma unidade, não pede escolha); bullet de reconciliação com **teste operacional** ("a rua aparece no retorno? se não, não é dado"); + bullets de distância-só-da-ferramenta e código-coerente-entre-fala-foto-link. Júlia 45.611→47.665 chars, Bruna 34.923→36.977. Backups: `/tmp/assistant_{13,14}_ins_proximidade.bak-20260811194049` e `..._ins_reconcilia_v2.bak-20260811194336`. **`assistant.liquid` intocado.**
- **Medido com `run_raw` em transação com ROLLBACK (nada enviado):** gatilho original **corrigido** (Bruna 4/4, Júlia 2/2 consultam e só citam rua real). ⚠️ **Recuperação segue instável**: quando a falsidade já está no histórico e o cliente a confirma, em 6 amostras 3 saem limpas (uma diz que aquela unidade não apareceu na busca), 2 ecoam a premissa em pergunta e **1 derivou** pro bairro homônimo e ofereceu imóveis de lá. A 1ª versão do bullet (genérica, "corrija-se") **não pegou** — só a versão com teste operacional moveu o ponteiro.
- ⏳ **Não validados ainda** (aplicados, sem prova): os bullets de **distância** e de **código coerente** — pedem roteiro mais longo (busca → apresentação → fotos). ⏳ **Sofia (#19)** tem `buscar_imovel`+`enviar_fotos_imovel` mas não tem a seção "Regras de busca de imóvel" — ficou **fora** desta correção. ⏳ Trava estrutural sugerida (não feita): o retorno da `buscar_lugar` instruir a descartar referência que não está na lista — seria em `enterprise/lib` (código compartilhado, agnóstico) e exige PR + deploy.
- Detalhe no vault: `aprendizados/spx-exemplo-no-prompt-vira-resposta.md`. Higiene da 2159 (limpeza + fechamento pra reabrir na triagem): `aprendizados/spx-limpar-conversa-de-teste.md`.

### [2026-08-11] ✅ PRs #29 e #30 MERGEADOS e no ar · suíte de tools verde pela primeira vez · vazamento de senha fechado

> Sessão integradora. O Bloco 1 do `docs/PLANO-2026-08-11.md` já estava feito quando a sessão abriu: os dois PRs foram mergeados às 11:58 UTC e consolidados — `producao` == `homologacao` == `19ad487573`.

- **Deploy confirmado NA VM** (não só pelo Almirante, que já mentiu sobre isso): Tozi prod roda `19ad48757`. `PRODUCAO`, `CATATAU` e `SENTINELA` idem. Fora: **FABRICA** (`2d2d2eaef`) e a **`.232`** (`ee87f5e799`).
- **Gate do plano 1.1 verificado retroativamente** (o código já tinha descido): o bloco `{% if channel_number %}` no molde compartilhado é agnóstico — não nomeia cliente nem vertical — e só renderiza em inbox WhatsApp, porque `channel_number` vem de `inbox.channel.try(:phone_number)` e canal Instagram não responde a isso. Sem risco de dizer "WhatsApp" numa DM.
- **🔴 Imagem do disparo Pacaembu resgatada pro git** (`e8b05d0298`). A `public/pacaembu-ago26.jpg` (230KB, 07/08) vivia **só no disco da VM**, e era a única imagem em `public/` — nenhuma rastreada. É o header do template do disparo, e a Meta busca a URL **no momento do envio**. É o risco #7 do apanhado com o precedente já consumado: o `inq-mapa.jpeg`, ainda hardcoded em `INQ_IMAGE_URL` (`disparo_lead_job.rb:54`), está **404 desde 08/06**.
- **🔴 Vazamento da senha do Cortex fechado** (`ef8e46c97e`) — Bloco 0.4 do plano, que estava listado como tarefa do Paulo. A causa não era descuido: o `tozi-hml.sh` montava `echo '$PASS' | sudo -S ...` **na mesma string do comando do usuário**, então qualquer aspa desbalanceada quebrava o parsing e o shell remoto devolvia a linha inteira — com a senha — no erro. Agora a senha vai pelo **stdin** e o comando viaja em **base64**, o que mata a classe de erro. Provado ao vivo: o mesmo comando que quebrava falha sem imprimir a senha. **Rotacionar sem isto só trocaria qual senha vaza.**
- **Bloco duplicado removido** (`c861ecd8d9`): o merge `f542675b77` (WIP da VM de volta pro git) duplicou as 4 constantes do trilho anti-ping-pong no `transferir_para_agente_tool.rb`. Inócuo hoje, armadilha amanhã — quem calibrar `MAX_TRANSFERS_IN_WINDOW` no 1º bloco é sobrescrito pelo 2º.
- **🟢 Suíte de tools: 138 exemplos / 18 falhas → 143 / 0** (`84a04f42f4`), rubocop limpo nos 9 arquivos. **As 18 falhas eram da `homologacao`, que é a `producao`** — não eram defasagem da `fricoes`, como o plano supunha. Nenhuma era bug: eram specs paradas em comportamentos que decisões posteriores substituíram (tool de transferência redesenhada pra receber **nome** e não id; descrição do handoff trocada de propósito; Modelo A não solta o espelho; `ActivityMessageJob` recebe ID e não o registro). Antes de "consertar" o teste do espelho, foi confirmado que o `HumanHandoffService` — fonte única dos 6 call sites — **não tem ramo por `reply_assignment_gate`**, então não havia regressão sendo mascarada. **O trilho anti-ping-pong ganhou cobertura: estava em produção sem nenhum teste**, apesar de ter nascido da conv 17770.
- **Frentes destravadas:** `eval`, `campanhas`, `followup` e `rodizio` estavam **0 commits à frente** da `homologacao` (o trabalho delas já entrara) — fast-forward puro. A `fricoes` mergeou **sem conflito** (a `homologacao` não tocou no `handoff_tool.rb`) e foi **pushada**: o `ee9e234b59` não vive mais só neste notebook. Backup em `backup/fricoes-pre-merge-20260811`.
- ⏭️ **`producao` está 4 commits atrás da `homologacao`** — os 4 acima. Promover + `propose_deploy_vm` é o próximo passo; enquanto não for, a imagem do Pacaembu segue sem rede de proteção na VM.

### [2026-08-07] 🟡 CONDUTA "atendimento anterior encerrado é passado" — nos 8 agentes da conta 6 (banco, prod Tozi); espera o recorte por episódio

> Lado do agente para o contexto por episódio que a frente `spx/eval` está entregando (`SPEC-contexto-episodio.md`). Só conduta, nada de código.

- **Origem:** conv **20215** (display 4083, Camila) — 3 episódios (16/02 · 05/03 · **07/08 09:40**). A Clara colou o desabafo de fevereiro (bairro sem energia, portão elétrico travado) na busca de casa com edícula de agosto, prometeu acionar o time com urgência, e a cliente respondeu *"Faz tempo isso, já resolveu / Kkkkkkk"*.
- **Aplicado no BANCO da conta 6** (sem deploy, sem restart — prompt é lido vivo): seção `# Atendimento anterior encerrado é passado` inserida logo após `# Cliente que volta depois da conversa encerrada` nos 8 agentes (Clara 7, Júlia 13, Bruna 14, Letícia 15, Marina 16, Rafa 17, Helena 18, Sofia 19), +1.456 chars cada. O molde compartilhado `assistant.liquid` ficou **intocado**. Backups na VM: `/tmp/assistant_<id>_ins_episodio.bak-20260807123048`. Confirmado via `ai_get_agent` (Clara) + varredura dos 8.
- **O que a conduta diz** (comportamento puro, zero exemplo de fala): atendimento encerrado é passado — não retoma por iniciativa própria, não vai atrás do desfecho, e **nada vindo da nota vira urgência, alerta ou handoff**; a nota diz quantos/quando/como terminaram, **não sobre o que eram** (proibido deduzir ligação com o assunto de hoje); assunto novo é novo; **se a própria pessoa trouxer o antigo de volta, aí é do momento** e ela assume com o que a nota deu; quanto maior o intervalo, mais o contato se parece com alguém chegando novo.
- **Prova antes/depois em transação com ROLLBACK** (`run_raw`, conta 6, 6 cenários — caso real da 20215, cliente trazendo o assunto de volta, nota recente de 3 dias, nota antiga de 155 dias, nota com resumo urgente do episódio anterior, e conversa sem nota): **antes == depois em todos**. Com a nota sendo fato puro e os turnos antigos fora do contexto, o modelo já não morde a isca — nem com resumo urgente — e continua pegando o assunto quando o cliente o traz (handoff + resumo). Zero regressão sem nota. **A conduta é apólice contra drift, não o conserto: quem conserta é o recorte.**
- ✅ **DESATUALIZADO em 11/08 — o recorte DESCEU.** O PR #30 foi mergeado e o código está na VM da Tozi (`19ad48757`). Mas ele **nasce desligado**: só age em conta com `custom_attributes['captain_episode_window']` ligado, e a conta 6 ainda não tem. Enquanto não ligar, a seção segue **inerte** e o comportamento é o de antes. **Ao ligar: repetir a medição na 20215** (critério de sucesso da spec) — e antes disso resolver a colisão das duas notas de sistema (risco #5 do apanhado: a `HumanHistoryNote` existe pra devolver o caso ao dono e abre com o mesmo `[Contexto do sistema: ...]`, enquanto esta conduta manda não acionar ninguém; nunca foi probado com o texto real).

### [2026-08-05] ✅ ÁUDIO DA IA CONSERTADO E NO AR — PR #28 mergeado (21:04) e deployado na Tozi (21:05)

> Descoberto por teste do Paulo na conv 2159 (prod Tozi c6). A resposta em voz **nunca funcionou** num número Cloud API desde que foi construída (jul/2026) — não tinha sido testada ponta a ponta. **Dois bugs em série.**

- **Bug 1 — não chegava** (`131053: Media upload error`): a tool declara `content_type: 'audio/ogg'`, o ActiveStorage re-detecta pelo conteúdo (Marcel) e sobrescreve por **`audio/opus`**, que a Meta não aceita. Como a mídia vai **por link**, ela busca a URL, lê esse content-type e rejeita. Fix: `identify: false` no `attachments.build`.
- **Bug 2 — chegava como ARQUIVO, não nota de voz**: PTT só sai com **upload em `/media` + `voice: true`** no objeto `audio`. **Não é o mime** — testado com `audio/ogg` e `audio/ogg; codecs=opus` (header confirmado por `curl -I` chegando intacto na Meta) e os dois vieram como arquivo. Fix: `voice_note_content` + `upload_media` no `whatsapp_cloud_service.rb`, só pra OGG/Opus; todo o resto de mídia segue pelo link.
- **Bug 3 — falha de áudio virava SILÊNCIO TOTAL**: a tool manda o agente encerrar com `[IGNORAR]` assim que **anexa**, mas o envio é assíncrono (`send_reply` atrasa 2s por causa do anexo) — falhou, o agente já se calou e o cliente não recebe nada. Fix: overlay Enterprise em `handle_error` (ponto único de falha, roda 1x — um listener em `MESSAGE_UPDATED` perderia o change tracking no dispatch async) entrega o **transcript** (que já está no `content`) como texto. Provado nos 3 cenários: nota de voz da IA falhada gera · texto da IA falhado não gera · áudio de humano não gera.
- **PR [#28](https://github.com/Dev-Simplex/chatspx/pull/28) MERGEADO** 05/08 21:04 UTC (merge `18a6a9f05`, junto do #27), **e já deployado**: código no disco da VM Tozi 21:05:38, restart do web 21:05:40 e do worker 21:05:43 (depois do código, então pegou o novo), 4 puma / 3 sidekiq, HTTP 200 local e público. `identify: false` e `voice_note_content`/`upload_media`/`voice: true` conferidos no arquivo em disco. **Confirmado ao vivo pelo Paulo**: nota de voz nativa.
- **Gotchas** (detalhados em `Obsidian/aprendizados/spx-resposta-em-audio-elevenlabs.md`, que **afirmava o oposto** e foi corrigido): HTTParty não monta o multipart do `/media` (`#100 parameter file is required`) → `Net::HTTP#set_form`; **v13.0 serve** (não precisa bumpar); transação com rollback **não testa anexo** (upload roda no `after_commit` → `FileNotFoundError`) — reusar anexo já commitado.
- ✅ **Frente `spx/fricoes` corrigida na origem** (`ca69bd765`, pushado): ela reescreveu o `responder_em_audio_tool.rb` e carregava o bug 1; corrigir lá evitou que a resolução do conflito no merge o reintroduzisse — **e funcionou**: o `identify: false` sobreviveu à integração (PR #29 abaixo). ✅ Conv 2159 limpa.

### [2026-08-05] 🟡 INTEGRAÇÃO das duas frentes órfãs — PR [#29](https://github.com/Dev-Simplex/chatspx/pull/29) ABERTO, aguardando merge + deploy

> `spx/fricoes` (04/08) e `spx/contact-invite` (29/07) estavam prontas, pushadas e **fora de qualquer PR**. As duas conflitavam com a `producao` e o conflito só piorava. Branch `integra/audio-conteudo-contato`, a partir de `18a6a9f05`.

- **Descoberta que mudou o merge:** as duas frentes resolveram o MESMO problema em paralelo. A `producao` já tinha trocado o gatilho "chame SOMENTE quando o cliente pedir" por julgamento em **`9587f4c6a` (02/08)** — não era escolher um lado, era sintetizar. Base = `producao` (que tem `a_pedido_do_cliente` + `ProdutoApresentacao` resolvendo produto de verdade), absorvendo da frente: `resumo_texto` + linha de registro, freio de recusa e reciprocidade.
- **Reciprocidade virou TERCEIRA PORTA que libera o proativo, não muro.** Na frente ela bloqueava tudo, inclusive o áudio PEDIDO pelo cliente — quem pedisse por escrito sem nunca ter mandado áudio era recusado, o que **regride** o que está em produção. Agora: `voice_proativo` OU produto OU cliente-já-mandou-áudio liberam a iniciativa; a pedido dele sempre passa.
- **Portão de produto da frente era INERTE:** lia `defined?(Produto)`, constante que não existe (a real é `Spx::Distribuicao::Produto`) — nunca bloqueou nada. Descartado em favor do da `producao`.
- **Recusa vence até o `a_pedido_do_cliente`** (decisão desta integração): o modelo pode marcar a flag por engano; o custo do falso positivo é uma resposta em texto, falha benigna.
- **Verificado na VM em `/tmp`, sem tocar no código que roda:** `ruby -c` OK nos 7 arquivos · RuboCop com a árvore e config do projeto, baseline contra os mesmos arquivos em prod: **26 → 24 offenses** (o `attachment_parts` ficou mais simples), arquivo do áudio com **0** · **17 cenários** dos portões em transação com rollback na conta 6, todos passando (inclusive `NÃO MANDA ÁUDIO` maiúsculo acentuado, o bug do `/[ãa]/i`) · vCard exercitado com **cartões reais** (161 na conta 6) e **diferencial** contra a versão de prod: o mesmo anexo saía `User has shared an attachment` e passa a sair com nome e telefone, enquanto um `ig_story` (video/mp4) sai **idêntico** — sem regressão no ramo do Instagram.
- ⚠️ **`chamar_contato` nasce desligado** (`settings['contact_invite']`, `return :desligado unless enabled`): nenhuma conta muda de comportamento pelo merge. Pra ligar na Tozi é preciso definir os templates.
- ⚠️ O bloco `{% if channel_number %}` entra no **molde compartilhado** — agnóstico e condicional, mas vale pra todos os clientes assim que deployar.

### [2026-08-05] ✅ RESÍDUO OFF-GIT DA VM TOZI RESGATADO pro GitHub

> Auditoria pedida pelo Paulo. **Nada de código vivo estava fora do git** — working tree limpo (só `public/version.json`) e HEAD == `origin/producao`. O que existia eram snapshots históricos que só moravam naquele disco.

- **9 branches novas no origin:** `backup/tozi-vm-stash-0..7` (os 8 stashes da VM) + `backup/tozi-vm-pre-switch-20260611` (branch local `d759c7d8e`, que não existia em lugar nenhum — 99 arquivos ausentes do HEAD, UI de captain/agents de junho). Transporte por `git bundle` + scp, porque **a VM Tozi não tem credencial git** (dívida antiga, ainda aberta).
- Triagem: `stash@{0}` é pré-superset (o HEAD tem mais); `{1}`/`{3}` só `version.json`; `{4}`–`{7}` são de maio e o HEAD já tem muito mais; `{2}` (304 arquivos, 21/06) é o único que não cravei como redundante. Agora todos estão no GitHub — a VM pode ser limpa sem medo.
- **`1464f7750`** (runbook do Instagram), que só existia neste notebook, foi pra `docs/runbook-instagram` no origin.
- ⚠️ **Almirante mentiu duas vezes nesta sessão:** `drift_check` não listou a TOZI como defasada (e compara SHA de 10 chars com 9, dizendo "1 commit atrás" do mesmo commit) e `service_status` reportou "0 puma / 0 sidekiq" numa VM com 4 e 3 rodando. Quando a resposta importar, **bater na VM**.

### [2026-08-04] 🟢 INSTAGRAM — Tozi PROD LIVE com Clara respondendo DM + BigStore conectada na .232
- **Tozi (conta 6, VM .109):** produto Instagram adicionado ao app **SPX Lead Ads Tozi** (`1658426868710322`, BM da Tozi — modelo **1 app Meta por VM**, o webhook do produto tem UMA URL por app; Instagram App ID do produto `2737838396591484`, configs no super_admin). **Inbox 101 @toziimoveis.com.br** + kit: auto_assign OFF, Clara #7 (espelho **16**) + Júlia/Bruna/Letícia/Marina/Rafa/Helena elegíveis, rules **#68** (created→Clara) / **#69** (opened→Clara, guarda de humano nativa). **Clara respondeu DM real** ("Boa noite! 😊 / Em que posso te ajudar?") — Captain é channel-agnóstico, mesma equipe do WhatsApp. Credenciais: vault `credenciais/infraestrutura.md`.
- **BigStore (.232):** conectada após fix do tester — estava no app ERRADO (cliente tinha app próprio de n8n "BigStore-IG"); tester tem que ser no app que o SPX usa (Business MW na .232).
- **Pegadinhas novas (pro runbook `docs/RUNBOOK-INSTAGRAM-SPX.md`, commit `1464f7750` — ✅ pushado em 05/08 na branch `docs/runbook-instagram`):** (1) OAuth logado na conta errada conecta o IG PESSOAL — admin do app passa SEM tester (inbox 100 nasceu com @pauloseze e foi excluída; conferir `/me` do token pós-conexão); (2) autorização VELHA ativa mascara convite de tester novo (remover em Apps e sites antes de reconvidar); (3) corrida regra×1ª conversa (conversa criada segundos antes do wire fica com humano — fix manual: assignee nil + espelho da Clara).
- **Fast-follows Tozi IG:** conduta window-aware + disclosure de IA (prompt NÃO vê o canal — `channel_type` só chega no state/tools; 1 linha de código expõe no contexto — **coordenar com a frente Orca `spx-tozi-ig`**); localização e follow-up fora da janela falham em silêncio no IG; teto 1.000 chars (humanizer 280 da conta 6 já respeita).

### [2026-07-28] 🟢 CONSOLIDAÇÃO Sofia → Júlia + knowledge ancorada por empreendimento (EXECUTADO em prod)

> **Decisão do Paulo:** agente se separa por **especialidade** (vendas/locação/…), nunca por **origem** (Meta, site, direct). Origem vira contexto, não identidade. A Sofia tinha nascido por origem e já estava divergindo da Júlia.

- **Diagnóstico que motivou:** Sofia (#19) e Júlia (#13) faziam a mesma coisa com cérebros diferentes — Júlia 41 FAQs × Sofia 6 (e **a Júlia sabia mais MCMV que a Sofia**: faixas 2026, FGTS, docs, taxa de obra); Sofia tinha remarketing/holerite/tabela ETNA que a Júlia não tinha; **Catálogo duplicado** (doc#7 = doc#8, byte-a-byte); **tabela ETNA só na Sofia** → lead orgânico do Etna caía na Júlia e não simulava. Conversa 41613 provou a fronteira vazando (lead Meta com a Júlia).
- **Knowledge:** catálogo monolítico (114 chunks, **93 órfãos sem citar empreendimento**) → **17 documentos, 1 por empreendimento** (docs #10–#26, 118 chunks, todos embeddados). Fonte agora ancora 100% (`0 sem fonte, 0 genérica`). Tabela ETNA copiada pra Júlia (doc#27). doc#8 removido após 5 verificações. **Pacaembu:** docs renomeados pra `Pacaembu Tívoli — casas MCMV` e `Pacaembu Rhodivi Morada do Bosque — casas MCMV` (Rhodivi = Morada do Bosque; mesmo produto, localidades diferentes — Paulo confirmou) + metadata dos chunks re-etiquetada.
- **Prompt da Júlia:** 28.373 → **38.460 chars** (37 seções, nada removido; backups em `/tmp/julia_prompt_backup_*`). Absorveu da Sofia: origem/remarketing, holerite (conferência sem reprovar), pedido-de-falar-depois, campanhas de aquisição SPL (levantamento + ramo com/sem tabela + documentação + preferência de visita). Dos briefings: escada de produtos, permuta (quitado é crítico), renda por último, frustração ≠ saída, não presumir aluguel, condomínio incluso, 2 perguntas de benefício (filho menor / 3 anos de carteira). Novo: **maioridade sem interrogatório** (inferência passiva → pergunta de processo → nunca gate, nunca data de nascimento na abertura). Tudo como instrução, zero exemplo (regra #1).
- **FAQs:** 41 → **45** (planta única Pacaembu, alternativa a quem não financia, prazo Pacaembu, + nova de score/CPF). 45/45 com embedding.
- **Roteamento virado:** o mecanismo real é o **hook** (`assign_agent_bot_id`), não a rule — hook#8 `23 (Sofia) → 17 (Júlia)` + rule #66 (reabertura time 67) `Sofia → Júlia`. **Time 67 "leads meta" mantido** (preserva segmentação e fila). Smoke test: prompt renderiza (48.807 chars, 2 blocos, cache_control ok), 16 tools, knowledge responde ancorada.
- **⚠️ Sofia INTOCADA de propósito** (decisão do Paulo): segue elegível na inbox 91 atendendo as **414 conversas já abertas** com ela; doc#7 (catálogo monolítico) mantido como knowledge dela + backup. Desligar de vez só quando as abertas resolverem.
- **Pendências — resolvidas em 31/07 (decisões do Paulo):**
  - (1) **Rhodivi: FALSO ALARME, nada a corrigir.** O material do doc#22 diz *"Casa térrea não geminada, **modelo único** identificado como BT_2D8_4385 (B = Linha Básica; T = Cobertura Telhado Aparente; 2D8 = 2 dormitórios…)"*. "Linha básica" e "cobertura" **não são duas tipologias** — são a decodificação das letras do código do modelo **único**. A FAQ #303 (Júlia) e o material sempre concordaram. Paulo confirmou: **Rhodivi é MCMV planta única**.
  - (2) **Catálogo de Blend, Méditerranée, De Ville Urban e Elleva Studios: fica como pendência mesmo** — Paulo: "não tem muita procura para esses". Não é prioridade do marketing.
  - (3) **Simulação de financiamento: vai pro backlog**, sem data. Segue dependendo de definir banco parceiro; as taxas do briefing são média de mercado e superestimam a parcela.
  - (4) **Loft = Vista** (mesmo sistema) — a redação antiga tratava como duas coisas. Corrigido em 30/07.
  - (5) **Piso de renda de ~R$ 2.500 é SÓ do Pacaembu**, não é régua universal (Paulo, 31/07). ⚠️ Verificado em 31/07: **esse número não está no prompt de nenhum agente** (Júlia #13 e Sofia #19 não mencionam 2.500, piso nem renda mínima) — é orientação interna pra pivotar de produto, nunca régua anunciada ao cliente. Registrado no vault `clientes/tozi.md`.
- **🚨 PREEXISTENTE, não relacionado:** Sidekiq da Tozi com **9.999 jobs no DeadSet**. Não foi tocado; investigar em separado.

### [2026-07-23] 🟢 VISTA — criar card no pipeline (PROVADO ao vivo, aguardando regras de rodízio)

> Próximo grande passo pós-meta-leads: o SPX criar o card no funil do Vista/Loft quando a Sofia marca lead QUENTE. Hoje todo handoff vai pra Cibele que cadastra + faz rodízio manual; corretores NÃO usam SPX (só Vista).

- **✅ Fase 2 (escrita) do Vista LIBERADA** (era 401 em abril, agora 400 "informe os dados"). **Testado E2E ao vivo** (chave inbox 91): cria cliente + card. **RECEITA:** cliente = `POST /clientes/detalhes` body JSON `{fields:{...}}`, obrigatórios Nome/Celular/FonePrincipal/VeiculoCaptacao/Interesse; **Vista dedupa por telefone automático**; criar cliente dispara integrações RD Station/Exact Sales. Card = `POST /negocios/detalhes` param **`cadastro`** = JSON string de `{fields:{...}}`, obrigatórios NomeNegocio/VeiculoCaptacao/CodigoCliente/**CorretorNegocio**/CodigoPipe/EtapaAtual. **Pipe 3 = vendas** (PROSPECTO 67 / CONTATO 73 / QUALIFICAR); nome padrão `"C - <imóvel>"`. Corretores via `/corretores/listar` (44; bucket "Tozi Imóveis Lead" #20). **⚠️ DELETE BLOQUEADO (401)** → build idempotente + dedup de card. Detalhe completo: vault `clientes/tozi-vista-capacidades.md` (§2026-07-21).
- **Processo real da Cibele** (confirmado por print do card 84871): ela escreve a nota **"INFORMAÇÕES" (resuminho)** + **encaminha pro corretor (rodízio)** — **NÃO cria nem move o card**. Quem **cria o negócio e move no funil é o CORRETOR**. Nossos forms (Pacaembu/RMKT) NÃO entram no Vista sozinhos (só via Cibele); outros forms (ex.: Loris Domus) entram pela **integração nativa "Loft/CRM - Facebook Lead Ads"**.
- **Decisões (Paulo):** **só quentes** vão pro Vista (frio fica no pool de reabordagem SPX); dedup por telefone (Vista faz) + de card (checar negócio ativo); **rodízio manual dentro do Vista** (o SPX escolhe o corretor e seta `CorretorNegocio` na criação); **o SPX cria o card COMPLETO** (cliente + resuminho da Sofia + card PROSPECTO + corretor) — mais rico que o manual da Cibele e na hora; **Cibele vira supervisora**.
- **⏳ BLOQUEIO:** regras do **rodízio em discussão no time** (Paulo vai passar) → destrava o `Spx::Tozi::VistaCardService` (handoff quente → dedup → cria cliente+resuminho → cria card `C - <imóvel>` Pipe 3/PROSPECTO com corretor → grava CodigoNegocio na conversa). **Registros de teste a remover na mão** (DELETE bloqueado): cliente **65205**, negócios **85015/85016/85017**.

### [2026-07-23] 🟢 ETNA & ACQUA (aquisição apto SPL) — conduta + knowledge na Sofia (opener/roteamento pendente)

> Briefings de 2 campanhas novas (apto SPL, aquisição/FRIO): `Downloads/2026-07-23_briefing-ia-aquisicao-{etna,acqua}.md`. **Decisão: uma Sofia só** (não IA separada); ela puxa respostas de **Vista (buscar_empreendimento) + knowledge**, nada hardcoded.

- **✅ Conduta "# Aquisição de apartamento SPL"** no prompt da Sofia (frio, apresenta a Tozi, levantamento 1-por-vez, coleta preferência de visita, passa pro corretor mesmo com timing longo). **Design elegante: TEM tabela na knowledge → simula (Etna); NÃO tem → coleta documentação (Acqua)** — sem hardcodar qual é qual. Docs do Acqua reusam a leitura de PDF já construída.
- **✅ Tabela de preços do Etna na knowledge** (Captain::Document **9**, 4 chunks embeddados, retrieval testado: "quanto custa Etna 2 quartos" → traz a tabela, dist 0.35). Guardrails: "a partir de", nunca inventa, NÃO simula térreo/garden, fora-da-tabela → corretor. Vista já dá a entrega (Etna 2029, Acqua 2026 = base da "prova de entrega" do Acqua).
- **✅ Opener frio de apto SPL LIGADO no Etna** (commit `00a68dff0`): template **`tozi_lead_apto_spl`** (id 2031782617545212, APPROVED) — *"Oi {{1}}! Aqui é da Tozi Imóveis, a maior imobiliária de Sinop 👋 Vi que você se interessou no {{2}}..."* + botões Quero saber/Me chama depois. Mecânica: `template_render_context` ganhou `empreendimento` (via `hook_setting`); override do `FORMS-ETNA` (campaign_id `120247064869780544`): `whatsapp_template_name=tozi_lead_apto_spl`, `whatsapp_template_body_fields='first_name,empreendimento'`, `empreendimento='ETNA BY SPL'`, `lead_tipo='aquisicao'`. Render verificado: {{1}}=nome, {{2}}="ETNA BY SPL". **Nota:** o lead do Etna ANTES recebia o `tozi_lead_meta_abertura` genérico ("num dos nossos anúncios") — não "casas" (isso era só o preview interno desatualizado). **O mesmo template serve o Acqua.**
- **✅ Override do Acqua LIGADO** (campaign_id `120242129957770544` = "[FORMS] - ACQUA", confirmado na Graph API, ACTIVE): mesmo `tozi_lead_apto_spl`, `empreendimento='ACQUA BY SPL'`, `lead_tipo='aquisicao'`. Render verificado ({{2}}="ACQUA BY SPL"). Acqua tem 0 leads no SPX ainda, mas já está pronto. Como o Acqua **não tem tabela na knowledge**, a conduta cai no ramo "coleta documentação" (correto — briefing Acqua não simula).
- **✅ Simulação do Etna VALIDADA** (teste controlado via `generate_response`, sem enviar): Sofia recitou os números certos da tabela (2Q a partir R$567.420, sinal R$28.371, 30/70 R$3.546, 50/50 R$6.383, 36x R$14.974) + puxou a entrega jun/2029 do Vista. Arredonda centavos (readability, não erro). **Etna 100% pronto** (opener + conduta + knowledge + simulação).
- **⏳ Pendente (opcional):** fact-sheet de amenidades do Acqua na knowledge; ajuste de centavos exatos na simulação Etna (se o Paulo quiser).
### [2026-07-25] 🟢 CASO 20058 RESOLVIDO: falso positivo do anti-bot silenciou cliente real por 16h (transcrição de áudio)

> Diagnóstico com evidência de log: triagem OK (Clara atribuída 17:42, run executou), mas o áudio do cliente foi transcrito errado ("tudo joia" → palavra estranha tipo nome de empresa) e a Clara classificou como spam/sistema → `[IGNORAR]` — e o protocolo anti-bot manda seguir ignorando o padrão ("Bom dia"/"Olá" seguintes também silenciados) até humano assumir 09:33 do dia seguinte. Invisível no painel: run que termina em `[IGNORAR]` não gerava mensagem nem log.

- **Fix estrutural (commit `5e9d09d91`, deployado + restart):** (1) transcrição de áudio chega ao agente MARCADA — `[áudio transcrito automaticamente — pode conter erros de transcrição]: <texto>` (`OpenAiMessageBuilderService#transcription_or_placeholder`) — sem o rótulo, transcrição errada é indistinguível de texto digitado e vira "evidência" de robô; (2) `[IGNORAR]` agora grava `AssistantLog event_type='ignored'` com o raw (`ResponseBuilderJob#log_ignored` + event type novo) — silêncio deliberado auditável no painel/diagnóstico.
- **Fix de conduta (banco, 8 agentes + molde, commit `ee3284a39`):** `[IGNORAR]` de sistema/spam exige evidência POSITIVA (menu/oferta/link/repetição); primeira mensagem ambígua = pessoa; a exceção anti-URA do molde ganhou a mesma salvaguarda agnóstica. Backups `/tmp/assistant_*_ins_antibot3.bak-*` + `/tmp/assistant.liquid.bak-fp` na VM.
- **Provado nos 2 lados (probe 2159):** transcrição marcada com palavra estranha → responde normal ✓ · URA com menu → `[IGNORAR]` mantido ✓. Obs: só a conduta NÃO bastou (probes intermediários) — o marcador estrutural foi o que virou o jogo.
- **Bug paralelo descoberto (não tratado):** `Conversations::OrphanRetriageJob` da conta 6 explodindo em loop com `RecordInvalid: Contact can't be blank` (alguma conversa órfã com contato deletado) — o job morre e órfãs não são re-triadas nem notificadas. Investigar/blindar.

### [2026-07-23] 🟢 CONDUTAS DA IA (prod Tozi, banco conta 6) + POLÍTICA DE TEMPLATES (código deployado)

> Sessão de correções dirigidas por casos reais que o Paulo trouxe. Tudo probado na conversa de teste 2159 (probes via `run_raw`, traces deletados após).

- **Handoff SILENCIOSO (caso 14363 + ajuste):** o GATILHO SENSÍVEL (Bruna #14/Júlia #13) agora aciona sem narrar — removida a permissão "situacional" de avisar; seção "Visita e chave" da Bruna reescrita (aciona handoff + colhe preferência de dia/período em vez de "já estou passando pro consultor"). Probe: handoff acionado + resposta "Que dia e período ficam melhores pra você conhecer?" (zero narração). Backups `/tmp/assistant_{13,14}_ins_silencio.bak-*` na VM.
- **Orçamento é faixa, não parede (caso 19857):** a IA propagava `valor_max` do cliente em toda busca e afirmou "não tenho nenhuma no Vindilina" com casa existente acima do teto (o Gelson ofereceu à mão 19h depois). Bullet duro em "Regras de busca" (Bruna+Júlia): busca com teto vazia num bairro → refaz SEM teto antes de responder; opção acima do valor é oferecida com o preço real. Probe: rebuscou sozinha, ofereceu a casa acima do teto + 3 na faixa em outros bairros.
- **Política de templates (commit `f9663a956` local, DEPLOYADO em prod via hotfix):** `Spx::TemplateReplyRouterListener` (novo, registrado no AsyncDispatcher) — resposta do cliente a template HSM roteia pra quem o template define: template MANUAL (sender User) → conversa vai pro humano remetente; template de DISPARO com label `rmkt*` → vai pra IA (`settings['template_reply_routing']`, conta 6: enabled, prefix `rmkt`, assistant 13=Júlia). Desarma sozinho se alguém já respondeu depois do template. Fecha o buraco da conv 8917 (aberta com humano = nenhuma automation dispara; "Quero ver" ficou 13h no vácuo). Testado transacional (3 casos ✓) + restart web+worker + HTTP 200. Obs: 8917 em si não foi reatribuída (listener só roteia respostas novas). `account.rb` (schema+accessor) só no commit — prod aceita a chave sem ele; chega no próximo deploy governado. **Temporário assumido:** o ideal futuro (IA atende reply de template manual em "handoff aguardando" com contexto do humano) fica pra próxima obra.
- **✅ F4.2 EVAL HUMANO IMPLEMENTADA (23/07, commit `51dc330c3`, DEPLOYADA em prod via hotfix + restart):** gestor escreve **nota privada com `#eval`** na conversa → CaptainListener captura → re-julga o episódio correspondente (force, mesmo já avaliado) com a anotação no prompt do juiz em PESO MÁXIMO + escalação automática pro modelo forte + `veredito_raw['human_annotated']=true`. Episódio aberto: a anotação entra quando fechar (via `ConversationEpisode#human_annotations`, janela started_at..início do episódio seguinte). Zero UI nova (nota privada nativa, funciona no app do celular). **Provado E2E na 2159**: nota async real → juiz incorporou os apontamentos no resumo/findings → human_annotated=true. Falta (fase 2): filtro "anotadas pela gestão" no painel. **Treinar os gerentes: `#eval <observação>` em nota privada.**
- **✅ Item "tracking/ImoCodigo HML→prod" JÁ RESOLVIDO** pela reconciliação do Paulo (23/07): `origin/producao` == box nas tools (trava anti-alucinação do enviar_fotos + track_urls + VistaImovelUrl/ImoCodigo + cooldown de fotos). Nada a promover; o cenário 19863 está bloqueado na raiz.
- **✅ Reconciliação git CONFIRMADA (23/07):** `origin/producao` (`2bd596be8`) é superset da sessão do eval (até `253042d71`) + WIP vista (`bkp/tozi-wip-vista-*`) + 70 commits do Nicolas. Faltam no remoto só os 2 commits de hoje: `f9663a956` (template router) e `51dc330c3` (F4.2) — pacote preparado, aguardando ok de push.
- Anteriores da mesma sessão (já em prod): anti-bot v2 + exceção agnóstica no molde (19861 AEGEA, label `bot-externo` 95 + rule #67 + `skip_labels` revivido no RouterService) · gate `phantom_photo_findings` (19863 Iguatemi×N.S.Aparecida) · Eval 2.0 completo (episódios/tool-traces/juiz 2 camadas/painel) · migração knowledge (31 Q&A, 6 prompts) com baseline congelado pra comparar ~05/08.
- **✅ Painel do Eval consertado + evoluído (23/07 noite, deployado com precompile):** (a) commit `87e9b0ca1` — barras não renderizavam porque usavam classes Tailwind INEXISTENTES (`bg-{g,b,y,r}-500/600`); trocadas por tokens reais (`bg-n-teal-9/blue-9/amber-9/ruby-9`) + segmentos IA×Humano com largura proporcional; (b) commit `ab87d14a5` — barras de "Onde estão as falhas" divididas por **IA (azul) × Humano (vermelho)**, clique no segmento filtra categoria+autor (`findings_stats` agrega `ia`/`humano` por categoria). Dados reais: "não respondeu pergunta" é 75% HUMANO (497×170), "quebrou regra" 66% humano, "alucinação" 97% IA — argumento pro Eixo C; (c) commit `1c76f7462` — **observação por mensagem específica**: item "Observação pro Eval (#eval)" no menu ⋮ da mensagem (só admins) abre nota privada pré-preenchida com `#eval “<trecho>” — `; a citação ancora o finding na resposta exata via o pipeline F4.2. ⚠️ ReplyBox.vue e conversation.json divergem repo×box (sessões de UI) — os patches no box foram cirúrgicos por âncora; backups `/tmp/evalnote_backup.tgz` e `/tmp/evalpanel_backup.tgz` na VM.
- **✅ UX final do Eval humano (23/07 noite, decisão do Paulo): "Avaliar atendimento" no menu ⋯ do header, POR EPISÓDIO.** O atalho por-mensagem foi REVERTIDO (`0ec5d8ef8` — Paulo não gostou de nota solta). No lugar (commits `103c027b6` + fix `8599acb16`, deployados com precompile): item no menu ⋯ da conversa (junto de transcrição/bloquear, só admins) → modal lista os EPISÓDIOS da conversa perpétua (período, msgs, nota, badge "Em andamento", resumo) → gestor escolhe QUAL atendimento avalia e escreve. Vira nota privada `#eval` com âncora EXPLÍCITA `content_attributes.eval_episode_id` (permite avaliar episódio antigo; sem heurística temporal). Backend: rotas+actions `conversation_episodes`/`annotate` no eval_dashboard, `human_annotations` com OR explícito+temporal, listener honra a âncora. **Gotcha achado:** `Message#content_attributes` é `store coder: JSON` sobre jsonb = DUPLA serialização (banco guarda STRING JSON) → SQL usa `(content_attributes #>> '{}')::jsonb ->>`. **Provado E2E em prod:** anotação ancorada no ep 7015 (antigo, fora da janela) re-julgou nota 9→2 com `human_annotated=true` e findings ecoando a gestão; teste limpo depois (nota deletada + re-julgado).
- **✅ "Avaliar esta resposta" no menu ⋮ da mensagem (24/07, commit `0cc05b70a`, deployado com precompile):** segundo ponto de entrada do Eval humano, INTEGRADO à UX por episódio (sem nota solta): abre o MESMO modal "Avaliar atendimento" com o episódio QUE CONTÉM a mensagem pré-selecionado (payload ganhou `first/last_message_id`; matching no front) e o trecho já citado (`“<trecho>” — `) — a citação ancora o finding do juiz na resposta exata. Bus event `OPEN_EVAL_MODAL` (MessageContextMenu → MoreActions monta o modal com `anchor`). Header = atendimento geral · mensagem = resposta específica; uma UX só.
- **⚠️ Observação:** a conversa de teste 2159 foi RE-SEGMENTADA (fechamento manual do ep 9474 + deleção das notas de teste invalidaram fronteiras) — episódios dela zeraram e voltam no próximo ciclo. Produção intacta (9.920 episódios, cron vivo). Lição: não fechar episódio na mão em teste; usar conversa com fronteira real.
- **Pendências:** push dos commits `0cc05b70a` (+STATE) pra `producao` — os anteriores (`0ec5d8ef8`+`103c027b6`+`8599acb16`) JÁ pushados (`22fa7049e..ddc905ffc`) · fase 2 do F4.2 (filtro "anotadas pela gestão" no painel) · rotação de keys DESCARTADA pelo Paulo (23/07).

### [2026-07-22] 🟢 UI conversa — 7 ajustes de UX (front compartilhado, commitado na homologacao)

- Resumo da IA (banner `ReplyBoxBanner.vue` + card lateral `ConversationSummary.vue`) **colapsável** (clamp 3 linhas + "ler mais/menos", nasce colapsado, não persiste — composable `useCollapsibleText.js`) e **só renderiza em conta com IA** (`FEATURE_FLAGS.CAPTAIN_V2`); janela 24h expirada **sem lista de templates rápidos**; **bug do "Resumo do humano" corrigido** (método `updateCustomAttributes` faltava no API client + `try/catch` engolia o erro) e "Resumo da IA" agora **somente leitura**; checkbox do checklist com **borda visível** nos 2 temas + "Assuntos / Tarefas"→"Assuntos e Tarefas"; ações da conversa com **toggle Atribuir↔Devolver** por dono. ⚠️ **A `.232` precisa de precompile + restart do web pra exibir** (não é automático). Eslint 0 erros.

### [2026-07-16] 🟢 META LEADS — higiene de dados + visibilidade no painel + RMKT separado (tudo LIVE na prod Tozi)

> Sessão de refinamento pós-go-live. Tudo em `homologacao` + cherry-pick `producao`, hotfix no box (conta 6), worker reiniciado. Serviço central: `app/services/meta/lead_ads/`.

- **✅ Nome sujo do form corrigido** (`fetch_lead_service.rb`, commit `f54f98de3`): a Meta às vezes cola o **CTA do anúncio no valor cru do campo nome** (`"Quero saber mais   Tiago"`) → a IA chamava o lead de "Quero". `sanitize_name` quebra por 2+ espaços e descarta segmentos que são frase de CTA conhecida (lista `CTA_PHRASES`), preservando o nome real; nome normal passa intacto. Só 1 lead afetado em 81 (Tiago, conv 19356) — corrigido o contato existente. Origem = dado sujo da Meta, não bug de mapeamento (`qual_seu_nome_` casou certo).
- **✅ Origem do lead visível no painel** (`create_conversation_service.rb#stamp_campaign_visibility`, commit `2efb4d1b8`): o time NÃO vê `additional_attributes` na UI (Chatwoot só renderiza `custom_attributes` **definidos**). Agora todo lead carimba na conversa: **Campanha / Anúncio / Público(adset) / Origem(fb→Facebook,ig→Instagram) / Tipo do lead** (5 `CustomAttributeDefinition` conversation-level, ids 75-79) + **label da campanha** (slug: `pacaembu`, `rmkt-vendas-2026`, `rmkt-vendas`) → filtrável. Backfill de 85 leads. ⚠️ pra ver na tela: **Ctrl+Shift+R** (front cacheia as defs).
- **✅ RMKT separado do frio** (commit `23ad92cb2`): `hook_setting(key)` resolve config do hook honrando **override POR CAMPANHA** (`settings.campaign_overrides[campaign_id]`) — opener/locale/body_fields/team/agent_bot distintos por campanha **sem multiplicar hooks** (o `HookFinder` é 1-por-página). **Decisão: uma Sofia só** (não IA separada — mesmo job/knowledge/gates; IA nova = manutenção dobrada + drift). Diferença frio×morno em 2 pontos: (1) **opener caloroso RMKT** `tozi_rmkt_abertura` (id 1945385199505080, APPROVED) ligado nos 3 RMKT campaign_ids (`120250094031260544`, `120249984750560544`, `120243017498040544`); default (Pacaembu+outros) = `tozi_lead_meta_abertura`; (2) **`meta_tipo`** (Remarketing×Lead novo, derivado do override `lead_tipo`) alimenta a conduta da Sofia — prompt expandido (12418→13104 ch, seção "frio×morno": remarketing=retomada calorosa de quem já conhece a Tozi, sem re-apresentar; frio=apresentação+qualificação do zero). **41 dos 85 leads = RMKT.**
- **✅ Coleta + LEITURA de holerite no MCMV** (prompt Sofia #19, DB conta 6 — não é git): (a) estava **opcional** e a seção de handoff mandava passar cedo → quase nunca pedia; virou **diretiva-mas-sensível** ("# Holerite no fluxo MCMV", `PEÇA` após interesse real + financiamento, enquadra pelo benefício, sem holerite → renda alternativa/terreno, não bloqueia handoff) + reforço no pré-atendimento. (b) **Análise da imagem** ligada: a foto **já chega como visão direta** ao Claude (`OpenAiMessageBuilderService#image_part` → `RubyLLM::Content`; `image_description` é ~no-op, o `MediaPipelineService` só transcreve áudio) — só faltava o prompt deixar; agora ela confere **legibilidade / titularidade (vs nome do contato) / mês de referência** (recência pela data no contexto), registra via `registrar_observacao`, **sem ler valor e sem reprovar** (no máximo pede versão melhor). Prompt →14900 ch. (c) **✅ PDF agora É lido** (commit `15802a1ef`, código compartilhado): `OpenAiMessageBuilderService` passou a emitir `file_part` (`type:'file_url'`) pra anexo PDF; `extract_text_and_attachments` junta com as imagens → `RubyLLM::Content` manda como bloco `document` (Claude lê PDF nativo). **Testado sem deployar** (load): msg real com PDF → RubyLLM type `:pdf`; imagem segue `image_url` (0 regressão). Vale pra TODOS os assistentes captain (genérico). Demais anexos (docx/xlsx) seguem como nota de texto. Prompt da Sofia ajustado (foto **ou** PDF, fallback removido). **Verificação behavioral do LLM lendo o conteúdo pendente** (lead MCMV real, ou teste controlado).
- **✅ Humanização + triagem de renda (feedback de teste do Paulo + gerente, 16-17/07):** (a) conduta ficou verbosa/robótica → portada a humanidade da Júlia: "# Jeito de conversar" (menos texto, uma ideia por vez, não recapitular, não despejar, calor genuíno) + travado info-dump na base de conhecimento. (b) **Modelo QUENTE × FRIO (não descarte — um lead pode servir a outro produto)** — evoluído do pedido do gerente (via corretora Rosivane). Regras de renda MCMV: renda de **INSS não enquadra** na Caixa (auxílio temporário por afastamento **E aposentadoria** — o gerente corrigiu: aposentado tbm não); aceita renda formal/comprovável (holerite/carteira/autônomo); piso **~R$2.500** (orientação, não régua anunciada); caminho natural = **renda composta/co-comprador**. **Sofia não decide enquadramento** (o corretor confirma) — usa isso só pra **pivotar de produto**: casa não fecha → oferece **terreno** (à vista/parcelado direto, sem Caixa) ou outro empreendimento. Classifica: **QUENTE** (tem venda agora: casa OU outro produto viável → handoff, `salvar_info_lead status:'qualificado'`); **FRIO** (sem fit imediato mas pessoa real → pool de reabordagem, `status:'esfriado'` + follow-up, NÃO vai pro corretor como quente, NÃO descartada); **`nao_qualificado`** só pro raro sem-perfil-pra-nada (tool commit `bdfddb518`: cancela cadência + label `nao-qualificado`, sem re-abordar). Insight do Paulo (quente/frio) **elimina o risco de hardcodar renda errado** — mis-gauge cai no pool frio, não some. **PDF do holerite validado ao vivo.** ⚠️ R$2.500 universal ou por unidade → briefing SPL.
- **✅ Correção Pacaembu (17/07) — RESOLVIDA:** casas MCMV = **Construtora Pacaembú**, lançamentos **EM CONSTRUÇÃO**. Prompt corrigido (removido nome fixo; Sofia pega o nome/status/entrega vivos pela `buscar_empreendimento`). **Conflito de nome fechado:** o Paulo **atualizou o Vista hoje** — minha 1ª query pegou estado pré-edição (por isso vi "Tivoli e Morada do Bosque" sem Rhodovi/data). Estado atual do Vista (verificado ao vivo): **9810 "Pacaembú Tivoli"** (bairro Tivoli, entrega 2028-04-30) + **9912 "Pacaembú Rhodivi Morada do Bosque"** (novo, entrega 2027-08-31) — o "Rhodovi" do Paulo é o **9912 (grafado "Rhodivi")**. A tool devolve os 2 certos, em construção, com descrição oficial → Sofia alinhada sem mais mudança. **Knowledge doc (#7)** tem fact-sheet antigo (pré-9912) — refresh opcional (a tool já cobre nome/status/entrega ao vivo).
- **🟢 DESCOBERTA (17/07) — RMKT é catálogo dinâmico e o imóvel POR LEAD chega no webhook:** o pessoal da Tozi pediu opener de RMKT com foto/info do imóvel específico ("template ficou brando"). Verificado ao vivo: a campanha RMKT VENDAS 2026 é **dynamic ads de catálogo**, e a Graph API do leadgen devolve **`retailer_item_id` = código do imóvel no Vista** (varia por lead: 9873, 7686, 6658, 8500…), que resolve pra imóvel real com fotos (`cdn.vistahost.com.br`). **O `FetchLeadService` NÃO pede esse campo hoje.** **✅ CONSTRUÍDO (17/07):** **Fase 1 LIVE** — `FetchLeadService` pede `retailer_item_id` (commit `6aa525e78`, homolog+prod); `CreateConversationService` busca o imóvel no Vista (`fetch_imovel`: código→descrição+foto, memoizado, no-op sem Vista/retailer) e carimba `meta_imovel_codigo`+`meta_imovel` na conversa (defs 80/81); **backfill 181/183** leads (26 imóveis distintos — confirma catálogo). Sofia ganhou tools `buscar_imovel`+`enviar_fotos_imovel` + seção "# Imóvel do anúncio" (abre direto no imóvel do anúncio). **Fase 2 (opener com foto):** `create_imovel_opener` pronto (HSM header de imagem = foto do imóvel + `{{1}}`nome `{{2}}`descrição), **gated por `hook_setting('imovel_template_name')`** (inativo até wire). Template **`tozi_rmkt_imovel`** (id 1753724852539889) **APROVADO + LIGADO** (17/07): `imovel_template_name` apontado nos 3 overrides RMKT. **Verificado E2E:** envio pro nº do Paulo (conv 2159, imóvel 7686) → **status `delivered`** com wamid, header renderizou a foto do imóvel. **RMKT catalog lead agora recebe opener com a foto do SEU imóvel** (`create_imovel_opener`); fallback = opener warm de texto pros ~2 sem imóvel/foto (gate `imovel_opener_ready?` trata foto nil). Copy do template: header foto + "Oi {{1}}! ...Vi que você se interessou neste imóvel: {{2}}. Quer que eu te mande as fotos e os detalhes?" + botões Quero ver/Me chama depois. **FEATURE COMPLETA.**
- **Opener por campanha = por override** (não por hook): nova campanha com opener/IA/time próprio → adicionar entry em `campaign_overrides[campaign_id]`. `lead_tipo:'remarketing'` marca warm.
- **⚠️ 130472 (número em experimento Meta) segue sem workaround**: opener de lead é forçado MARKETING pela Meta (UTILITY re-categorizado). Mitigação = listener `entrega-segurada` → Cibele liga (número válido).

### [2026-07-14] 🟢 META LEADS (Caminho B, formulário) — GO-LIVE EXECUTADO na prod Tozi (Sofia pré-qualifica); validando com lead de teste

> **Contexto:** campanha Meta `120243133255210544` (forms Pacaembu/Tívoli MCMV). Estado ao vivo verificado read-only na prod Tozi (conta 6): **0 hooks meta_lead_ads, 0 conversas `source=meta_lead_ads`, 0 CTWA em 180d** — nenhum lead de anúncio chega ao SPX hoje. Decisão do Paulo: fazer funcionar por **formulário com webhook** (não CTWA). Modelo de IA vigente = "IA como agente atribuível" (7 agentes: Clara #7 triagem, Júlia #13, Bruna #14, Letícia #15, Marina #16, Rafa #17, Helena #18 RH).

- **✅ Gap do webhook corrigido** (`app/services/meta/lead_ads/create_conversation_service.rb`, commit `0e6f37820` em **homologacao**): (1) `source_id` em Cloud API via `PhoneNumberNormalizationService` (fim do reply órfão/duplicata); (2) `find_or_create_conversation` honra `lock_to_single` + idempotência contra redelivery/retry; (3) guard anti-1ª-msg-duplicada. Espelha o `DisparoLeadJob`. Syntax OK. **Falta chegar na `producao`** (governado) antes de ligar o webhook.
- **✅ IA Sofia #19 criada** na prod conta 6 (runner clonando comportamento da Júlia + prompt novo script-free, 9461 ch): pré-qualificação de leads Meta com **gates sensíveis** (trava não é parede — nome sujo → previsão de quitação/Tuiuiú; sem holerite → renda alternativa/terreno; sempre busca caminho e passa pro corretor), herda o *feeling* de venda da Júlia (encantar sem "namorar"). Mirror AgentBot #23. **DESCONECTADA** (0 CaptainInbox = não responde nada). `image_description` ON (foto do holerite → sinaliza, não reprova). Tools: salvar_info_lead, programar_followup, transferir_para_agente, atualizar_resumo, registrar_observacao, registrar_assunto.
- **✅ Time "Leads Meta" #67** criado (conta 6), único membro **Cibely (user #67)** — ela distribui manual entre corretores. `Sofia.config.team_id=67`.
- **Credenciais do webhook** (vault `credenciais/tozi.md`): app `1658426868710322`, page `539594042748152`, verify/secret/system-user-token OK. **Callback ainda em PAULAO** (`paulo.chatspx.app`) — migrar pra `tozi.chatspx.app/webhooks/meta_lead_ads`.
- **🟢 GO-LIVE EXECUTADO (14/07):** fluxo Meta Leads → Sofia LIVE na prod Tozi. (a) template `tozi_lead_pacaembu_abertura` (id 4534320560147675) APPROVED + sincronizado na inbox 91; (b) 3 commits meta na `producao` (`603ba9bbb`) — **deploy governado via Almirante travou** (mirror git dele defasado + VM Tozi sem credencial git), feito **hotfix cirúrgico** no box (só o `create_conversation_service.rb`, sem migration, migrate:status limpo, restart web+worker, HTTP 200); (c) **Hook #8** criado na conta 6 (page 539594042748152, inbox 91, template, `assign_agent_bot_id=23`=Sofia); (d) **callback do app Meta migrado** de PAULAO → `tozi.chatspx.app/webhooks/meta_lead_ads` (subscription active, leadgen; page confirmada subscrita ao app); (e) roteamento por hook (não por automação) — cada campanha/hook → seu agente; (f) Sofia elegível na inbox 91 (CaptainInbox), **piloto = acompanhar os 1os leads + kill-switch** (desabilitar Hook #8 ou desplugar Sofia). Futuras campanhas: novo hook por `form_id`/campanha → agente/knowledge próprio.
- **⚠️ Dívidas de infra descobertas (não bloqueiam o go-live, mas organizar):** (1) mirror git do Almirante desatualiza — não fez fetch de `0d9d08238`/`603ba9bbb`; (2) VM Tozi **sem credencial git** (`could not read Username for github.com`) → deploy governado não consegue `pull`; (3) commit `0d9d08238` (fix captain track_imoveis de outro dev) está na `producao` mas **não deployado** na frota (que roda `c97ce3b8e`). O hotfix da Tozi levou só o arquivo meta, não o `0d9d08238`.
- **✅ VALIDADO AO VIVO (15/07):** leads reais chegaram (5 Pacaembu + 3 RMKT VENDAS). Descobertos e corrigidos 2 problemas: (1) **triagem #55 sobrescrevia a Sofia** → leads iam pra Clara/Júlia; (2) **sem filtro de campanha** → RMKT entrava junto. **Fix (commits `036605655`+`896439e18` em homologacao+producao, deploy via hotfix no box):** (a) **filtro dinâmico** `allowed_campaign_ids` no hook (editável por operador; hoje `[120243133255210544]`) — RMKT e futuras campanhas são ignoradas; (b) lead criado **já com `team_id=67`** + Sofia atribuída na criação; a triagem geral **#55 foi gateada** (`team_id is_not_present`) → só triaga conversa sem time, então a Sofia **gruda**; (c) regra **#66** (reabertura time 67 → Sofia) + **#63** exclui 67; (d) opener corrigido (`initial_message_template` no hook = corpo real → o agente lê o contexto Pacaembu). **Testado:** Pacaembu→Sofia gruda, RMKT→filtrado, opener certo. Leads Pacaembu já-entrados reatribuídos à Sofia (19232/19236/19237); os com humano e os RMKT deixados como estavam.
- **Roteamento por campanha = por hook**: cada campanha/funil → seu hook (ou allowlist) → seu time+IA. Novas campanhas: criar hook próprio OU adicionar campaign_id ao allowlist + apontar o agente.

### [2026-07-15] 🟢 SOFIA VIRA ESPECIALISTA DE ATIVAÇÃO META (todos os produtos) — conhecimento dos empreendimentos + todas as campanhas liberadas

> **Decisão do Paulo:** Meta-leads são chamadas ativas → todos vão pra **Sofia** (independe do produto; podem migrar de interesse). **Júlia** = orgânico/inbound (terceiros + empreendimentos). Sofia deixa de ser só-Pacaembu e vira **especialista em ativar lead Meta de qualquer empreendimento**, com qualificação adaptativa.

- **✅ Tool `buscar_empreendimento`** (`enterprise/lib/captain/tools/buscar_empreendimento_tool.rb` + entry no `config/agents/tools.yml`, deploy hotfix): consulta o Vista (`/imoveis/listar` filtro `Categoria=Empreendimento`, `/imoveis/detalhes`) e calcula **pronto vs planta** pela `DataEntrega`. Gotcha: header `Accept: application/json` obrigatório + `quantidade` limitada a **50**. Habilitada na Sofia (#19) e Júlia (#13). Testada.
- **✅ Knowledge dos 17 books ingerida** (dual-source: Vista=dados vivos, books=diferenciais). 17 fact-sheets destilados por subagentes (salvos em `Downloads/Tozi Imoveis/_factsheets/`), viraram 1 `Captain::Document` "Catálogo de Empreendimentos" por assistente → doc #7 Sofia (57 chunks embeddados) + doc #8 Júlia (58). Modo hybrid → busca via `search_knowledge`. **Decisões do Paulo:** todos os books = produto Tozi; Etna=cód 9851; Tívoli+Morada=Pacaembu; Guanabara entrega 31/05/2026 (pronto).
- **✅ Prompt da Sofia expandido** (via Almirante `ai_update_prompt`, change_set 18, passou test-gate): todos os produtos, qualificação **adaptativa** (casas MCMV com gates sensíveis · aptos pelo eixo planta×tempo · terrenos por investimento), usa a tool + knowledge, herda o *feeling* da Júlia. **Lógica SPL fina (planta × tempo de espera → produto) PENDENTE do briefing do Paulo.**
- **✅ Todas as campanhas liberadas** → Hook #8 `allowed_campaign_ids=[]` (vazio = todas → Sofia). **✅ opener genérico `tozi_lead_meta_abertura` (id 912482414494964) APROVADO + já trocado no Hook #8** (produto-neutro, serve pra casa/apto/terreno). O `tozi_lead_pacaembu_abertura` fica de reserva.
- **✅ Família de erros Meta tratada** (listener): 131026/131030 (sem WhatsApp) → label `sem-whatsapp` + Cibele · 131049 (Meta segurou entrega) → `entrega-segurada` + Cibele · 131031/131042/131048 (conta) → log crítico. Time "Leads Meta" #67 corrigido: membro é **Cibele Heloisa (#107)**, não Cibely.
- **⚠️ Pré-validação de número via Meta é IMPOSSÍVEL** na Cloud API (endpoint `/contacts` foi desligado — testado, HTTP 400). Só dá pra reagir ao 131026 (feito).
- **PENDENTE:** briefing SPL do Paulo (lógica de produto) → refina o prompt da Sofia.

### [2026-06-11] ✅ DECISÃO 2.7 EXECUTADA em prod Tozi — higiene das abertas só-HSM (4.013 resolvidas, 0 falhas)

- **Critério estrito do Paulo:** conversa com APENAS template(s) outgoing, zero resposta do lead, zero texto humano, atribuída. Universo: 4.606 (nenhum corretor tinha escrito nada). Resolvidas as paradas 3d+: **4.013 em 369s, 0 falhas** (lotes de 50 + pacing; teams setados nas sem-team via MAP corretor→time de disparo; Gelson/Adrian via skip flag). Dry-run prévio: CSAT/NPS OFF (zero pesquisa pro lead), 0 webhooks de conta, resolve+rollback de teste OK.
- **Resultado: inbox 91 caiu de 6.508 → 2.487 abertas** (resolved 11.077). Residual: 593 (<3 dias — ficam com os corretores). Cards dos funis moveram pra "Resolvidos" via callback. Reply futuro reabre zerada (#53) → triagem por intenção (decisão 3.5, batida hoje: labels `intencao:*` + automation `assign_team`). Detalhes: `docs/DECISOES-CLARA.md` §2.7 e §3.5 · script `Temp/executa_27.rb` · log `/tmp/resolve27.log` na AWS.

### [2026-06-11] 🚨 DESCOBERTA DE INFRA: 192.168.8.232 = chatspx.app (SaaS COM CLIENTES), não só "hmlchat"

- `FRONTEND_URL` da VM 232 é `https://chatspx.app`; contas: 1 SimplexIA · 3 Simplex Tecnologia · 4 Colégio Alternativo · 5 Realizare Imobiliária. **Tratar como produção** (o restart/migrations de hoje passaram sem incidente, mas o risco era maior que o assumido). Auto-pull da homologacao SEM migrate vira risco crítico — corrigir urgente. Vault atualizado (`credenciais/infraestrutura.md`).

### [2026-06-11] 🟢 CLARA LIVE NO NÚMERO SIMPLEXIA OFICIAL (chatspx.app, conta 3, inbox 44)

- **Número Cloud API oficial funcionando: +55 66 2018-0686** (inbox 44 "SimplexIA", conta 3 Simplex Tecnologia). Equipe clonada da conta 1 → conta 3: **Clara #3 (CONECTADA à inbox 44)** · Júlia #10 · Bruna #11 · Letícia #12 · Marina #13 · Rafa #14. Modelo da conta 3: `claude-sonnet-4.5` (era gpt-4.1, sem uso). Custom tools clonadas (geocoding ON). Cota 99.965/100k. `audio_transcriptions=true` na conta 3. `pending_status_enabled=false` na inbox 44 (sem limbo). Sem whitelist — a Clara responde QUALQUER mensagem no número (é o teste).
- **Para testar:** mandar WhatsApp pro +55 66 2018-0686 (texto/áudio). Trocar o agente conectado = `CaptainInbox.find_by(inbox_id: 44).destroy` + `create!(inbox_id: 44, captain_assistant_id: <id>)`.
- Limitações conhecidas do teste: transferência IA→IA = handoff com destino no motivo (tool real = Fase C6) · busca de imóvel usa o Vista da TOZI (chave no .env — ok pra teste).
- **Knowledge da AWS importada (11/06):** Playbook de Vendas (doc, 19 chunks com embedding, available) → Júlia #10 · 40 Q&A divididas conforme a spec: 4 institucionais → Clara #3, 36 vendas/objeções → Júlia #10, todas com embedding. Bruna/Letícia/Marina/Rafa seguem sem knowledge (curadoria §12 do EQUIPE doc — a base de prod não tem conteúdo de locação/suporte/captação/prestadores). `knowledge_mode=hybrid` (retrieval ON; `feature_faq=false` só desliga a GERAÇÃO automática de FAQ no resolve, não a consulta).
- **🔄 AJUSTE pós-teste do Paulo (11/06 tarde): Clara #3 virou ORQUESTRADORA** (padrão validado da Tozi prod, já que o runtime atual só permite 1 assistant por inbox). Os 5 especialistas viraram CENÁRIOS dela (Vendas #13 c/ buscar_imovel+geocoding+fotos · Locação #14 idem · Suporte #15 · Captação #16 · Prestadores #17), com frases de transferência ajustadas pro mecanismo de cenários (devolver à assistente principal). Cenário recepcionista standalone desabilitado (volta no modelo IA-como-agente). Knowledge CONSOLIDADA na #3: 40/40 Q&A + Playbook (19/19 chunks) com embeddings. Motivo do teste falho: a Clara recepcionista não tinha buscar_imovel por design e não tinha pra quem transferir. Os assistants #10–14 ficam como fonte pro modelo novo (não conectados).

### [2026-06-11] 🟢 EQUIPE DE AGENTES CRIADA NA SANDBOX (chatspx.app, conta 1 SimplexIA)

> Spec completa: [`docs/EQUIPE-AGENTES-IA.md`](../docs/EQUIPE-AGENTES-IA.md). Setup idempotente: `Temp/hml_setup_sandbox.rb` (local, não versionado).

- **6 agentes criados** (assistant ids 4–9): Clara (recepção/triagem por intenção) · Júlia (vendas, prompt = prod) · Bruna (locação, = prod) · Letícia (suporte, = prod) · Marina (captação, NOVO) · Rafa (prestadores de serviço, NOVO). Cada um: 1 cenário "Comportamento" com o prompt, config baseline (guardrails+guidelines da Clara prod + anti-senha; memory/faq OFF), behavior baseline (debounce 15s, humanizer 280, business_hours Sinop, sem whitelist), modelo `claude-sonnet-4.5`.
- **Infra da sandbox**: chaves LLM (InstallationConfig) copiadas da AWS · custom tools geocoding (enabled) + vista (disabled, como prod) na conta 1 · `TOZI_VISTA_API_KEY` no .env · web+worker reiniciados (migrate 0 down) · HTTP 200. **Nenhum agente conectado a inbox** — não respondem nada até plugar (seguro).
- **Critério de agente por setor** (DECISÕES §13 do EQUIPE doc): jurídico SEM agente (handoff humano); prestação de contas do proprietário → Letícia até Onda 5. Transferência IA→IA por enquanto = handoff com destino no motivo (tool real é Fase C6 da arquitetura).
- **Próximo:** Paulo valida os agentes na UI (hmlchat → conta SimplexIA → Agentes IA) · plugar inbox de teste OU aguardar número SimplexIA Cloud API pro teste E2E · curadoria de knowledge (institucional/locação/suporte/captação/prestadores).

### [2026-06-11 noite] 🟢 ORQUESTRAÇÃO IA FUNCIONANDO E2E no chatspx.app (conta 3, inbox 44)

> **Fluxo provado em teste sintético:** conversa órfã → triagem automática atribui Clara (automation `assign_ai_agent`, rule #31) → Clara identifica intenção e **transfere via tool `transferir_para_agente`** → Bruna assume com contexto e atende. Transferência invisível, sem eco.

- **Implementado por mim (commits na homologacao até `5fb885a2e`):** tool `transferir_para_agente` (C6, lookup direto do espelho) · action `assign_ai_agent` (C4) · entry tools.yml · B3 `configured_agent_tools` · B1 instructions no v2 · fix image-blocks no histórico (foto da IA quebrava turnos seguintes) · fixes de fotos (transação/reenvio/sem oferta) · gates aceitam `captain_integration_v2` (gotcha "não habilitado" morto na raiz, useCaptain+CSAT+áudio).
- **Equipe conta 3:** Clara #3 recepcionista (transfere) · Júlia #10 · Bruna #11 · Letícia #12 · Marina #13 · Rafa #14 — agentes únicos standalone (cenários OFF, B1+B3), todos ELEGÍVEIS na inbox 44 (CaptainInbox; a Fase C endureceu: espelho não-elegível é recusado).
- **Frente paralela (.41):** 2 sessões Claude Code NO SERVIDOR (loop autônomo `plano/ia-consolidado.md`; F0+A aceitas — commitei tudo em `2bee0f724`; Fase C/UI em andamento). ⚠️ Precompile SEGURADO até a Fase C fechar (SCSS em progresso quebra build + não servir UI parcial pros clientes do SaaS). Bugs da noite (todos mortos): multi-agente da gem (eco), worker dessincronizado, image-blocks, elegibilidade sem dados.
- **Próximo:** teste do Paulo via WhatsApp (conversa 515 com a Clara) · Fase C fechar → precompile (UI de agentes + fix da tela) · curadoria de knowledge dos especialistas · espelhar a receita pro go-live Tozi.

### [2026-06-11] 📐 ARQUITETURA "IA COMO AGENTE ATRIBUÍVEL" — planejada de manhã; Fases A (loop .41) + B1/B3/C4/C6 (eu) JÁ IMPLEMENTADAS — ver entrada acima

> **Plano completo: [`docs/ARQUITETURA-IA-COMO-AGENTE.md`](../docs/ARQUITETURA-IA-COMO-AGENTE.md)** (fases A–D, ~2 semanas, aceites e roteiro E2E novo de 14 testes).

- **Decisão do Paulo:** fim da "Clara com cenários". Cada IA = um agente independente, atribuível como atendente; **a IA só responde conversa atribuída a ela** (sem router/whitelist/labels). Cenário sobrevive só como SUBPROMPT de comportamento. Conversa da IA fica com composer BLOQUEADO pro humano — botão "Assumir conversa" rouba a atribuição explicitamente.
- **Viabilidade verificada no código (6 agentes, 11/06): ~70% do trilho já existe** — `conversations.assignee_agent_bot_id` + AssignmentService com assignee_type + endpoint + callback `reset_agent_bot_when_assignee_present` (atribuir humano limpa o bot = "transferiu → cala" de graça). Trilho escolhido: **AgentBot-espelho por Captain::Assistant** (`bot_type :captain`). O gate atual é 100% por inbox (`inbox.captain_assistant`) — vira por conversa.
- **Implicações:** whitelist/label atendimento/skip-pós-humano/pending-limbo MORREM; regra #53 TEM que morrer na virada; go-live da Clara deve acontecer JÁ neste modelo (não religar no modelo velho); substitui parte da Onda 2 do roadmap.

### [2026-06-11] ✅ RECONCILIAÇÃO DE BRANCHES EXECUTADA — `producao` é a canônica única

> **O problema "cada redeploy re-dropa patches off-git" está MORTO.** Estado final dos ambientes:

- **`producao` (29a32046f)** = canônica, superset de TODAS as linhas: paulao (22 commits, PR #21) + producao consolidada de 08/06 + único commit exclusivo da rollout (FK cascade, PR #22). Merge teve 1 conflito (disparo_lead_job add/add → versão paulao) + 18 .rb validados com ruby -c. Migration landmine agora é a versão SAFE em todas as branches.
- **`paulao`** = sincronizada com producao. **`homologacao`** = producao + 10 PRs do redesign workspace-v2 (merge sem conflito) — **branch de trabalho do Paulo daqui pra frente**.
- **AWS Tozi** = checkout LIMPO da `producao` (era rollout/release-20260605 + sujeira off-git). Bundle incremental via scp (VM sem credencial git), backup da sujeira em branch local `backup/pre-switch-20260611`, migration 20260609120000 aplicada via `db:migrate:up` específico, 0 down, precompile + restart → HTTP 200, tráfego real ok.
- **hmlchat (192.168.8.232)** = homologacao completa: 6 migrations aplicadas, zeitwerk OK, HTTP 200. Credencial descoberta e salva no vault (`credenciais/infraestrutura.md` § HMLCHAT). ⚠️ Tem **auto-pull da homologacao que NÃO migra/precompila/restarta** — bomba-latente a cada push; corrigir o mecanismo.
- **TODOs operacionais:** deploy key git na AWS (fetch falha; bundle foi o workaround) · git ident do user chatwoot na AWS · runbook oficial de deploy (decisão 1.3) · consertar auto-pull da hmlchat.

### [2026-06-11] 🟡 GO-LIVE REORGANIZADO — Bloco 1+2 executados em prod; switch da Clara aguarda sandbox + decisões

- **Executado em prod Tozi (11/06):** T1 áudio (gate código + `audio_transcriptions=true`) · T2 fix 403 (+ commit `e74b935b1`) · T3 anti-duplicata do disparo · T4 restart validado · T5 notificações dos 4 corretores (3 flags push + 3 email; falta cada corretor ACEITAR a permissão no navegador — Ederson) · T6 memberships Marcus/Bruno + 442 conversas re-sincronizadas (0 dessincronizadas no final) · T8 lista do mutirão (408 conversas em `Downloads/mutirao-tozi-12h.csv`; inclui Paloma 11, Gelson 4, Ivanete 1 além dos 4 corretores).
- **Decisões batidas (11/06):** D1 SIM com sub-definições (ver doc) · D2 24/7 · D3 desligar memory/faq · homologacao = branch de trabalho · sandbox = número SimplexIA na Cloud API oficial.
- **PENDENTE:** T7 (config Clara) · T9 (switch CaptainInbox) · T10 (roteiro 13 testes) · T12 (piloto leads reais) — aguardam Etapa 2 (sandbox SimplexIA) + sessão de decisões dos Grupos 2–8 de **[`docs/DECISOES-CLARA.md`](../docs/DECISOES-CLARA.md)** (~35 decisões consolidadas com recomendação cada).
- **Ordem macro decidida:** Etapa 1 reconciliação ✅ → Etapa 2 sandbox SimplexIA Cloud API + quick wins (Langfuse/playground/golden set) → Etapa 3 go-live Clara organizado → Etapa 4 Ondas 1+2+4.1 em paralelo → Etapa 5 Onda 5 antecipada (Vista fundo; MA Financeiro 🔴 ~1 mês de atraso contratual).

### [2026-06-10] 🚀 PLANO DE GO-LIVE DA IA — 11/06 (Paulo + dev sênior + Ederson), abertura 12/06

> **Plano executável: [`docs/PLANO-GOLIVE-IA-2026-06-11.md`](../docs/PLANO-GOLIVE-IA-2026-06-11.md)** — tarefas T1–T12 com comandos prontos, papéis, roteiro E2E de 13 testes, critérios go/no-go e rollback.

- **Verificação final de prod (10/06):** kit Clara quase completo — 13 tools ✅, fallback handoff (02bcbac0f) ✅, typing ✅, followup_job ✅. **Pending limbo NÃO recorre em prod**: a rollout tem guarda dupla no `reopen_resolved_conversation` (`active_bot? && pending_status_enabled?`) + `pending_status_enabled=false` na inbox 91 → conversa resolvida reabre OPEN. ⚠️ A `paulao` local NÃO tem essa guarda (tem o f96ae7740 no lugar) — na reconciliação levar AMBOS (complementares). ⚠️ NUNCA ligar "status pendente" da inbox 91.
- **Gaps reais achados (entram no plano de amanhã):** (T1) transcrição de áudio MORTA em prod — commit `1671b9017` ausente + `account.audio_transcriptions=false` (2 gates); (T2) fix 403 = 1 linha no `authorize_team_access` (assignee sempre abre a própria conversa); (T3) patch cirúrgico do `11b913531`; (T5) notificações dos corretores OFF de fábrica; (T7) `feature_memory=true` e `feature_faq=true` na Clara — religar dispara LLM por resolve (recomendado desligar no go-live); (T6) Marcus/Bruno sem membership de time + re-sync team das conversas de disparo.
- **Decisões D1–D3 pro Paulo bater amanhã cedo:** Clara atende replies de disparo ao abrir geral? (recomendo sim; script de label bulk pronto como alternativa) · responder fora do horário? (recomendo manter) · desligar memory/faq? (recomendo sim).

### [2026-06-10] 🔴 BUG ATIVO: corretor vê conversa atribuída a ele mas recebe 403 ao abrir ("Você não tem permissão")

> Reportado pelo Paulo com prints (lista do Lucas + modal de permissão). **Diagnóstico cravado com dados de prod (read-only).**

- **Causa:** gate de time do fork — `authorize_team_access` (`app/controllers/api/v1/accounts/conversations_controller.rb:231-243`): não-admin recebe 403 ao abrir conversa cujo `team_id` é de um time do qual ele NÃO é membro. As conversas problemáticas estão **atribuídas ao corretor X mas com team do corretor Y** — dessincronização causada pelas **reatribuições em massa via `update_columns`** (04/06 jobs→Kettlen; 09/06 Kettlen→4 corretores) que não rodam o `sync_team_from_assignee`. Confirmado nos contatos dos prints: "Harla Proprietaria" (conv 11986) e "Lourival spadacio" (conv 12324) = assignee Lucas + team 62 "kettlen - disparo" → 403.
- **Números (prod 10/06):** ~700 conversas abertas com assignee ∉ team — Lucas 114 + Bruno 113 + Marcus 113 no team da Kettlen; Bruno 49/Marcus 42/Kettlen 42 no team do Lucas; + dezenas em times funcionais (locação/financeiro/recepção). **Agravante:** Marcus (#128) e Bruno (#131) **não são membros de NENHUM team** (nem dos próprios "marcus/bruno - disparo", que só têm Guilherme+Maria Vitoria). O corretor VÊ a conversa na lista porque o push do ActionCable filtra client-side só por assignee (`applyRoleFilter` não checa team), mas o GET unitário toma 403.
- **Fix proposto (aguardando aval — mexe em prod):** (1) DADOS: re-sincronizar `team_id` das abertas dos 4 corretores — times de disparo (61-65) → team do próprio assignee; criar membership de Marcus→64 e Bruno→65; times funcionais decidir caso a caso (adicionar membro ou reatribuir). (2) CÓDIGO: 1 linha no `authorize_team_access` — `return if @conversation.assignee_id == Current.user.id` (assignee sempre pode abrir a própria conversa; atribuição implica acesso).

### [2026-06-10] 🗺️ MAPEAMENTO COMPLETO — IA orquestradora de conversas (doc-mestre + plano em fases)

> **Doc-mestre: [`docs/MAPEAMENTO-SPX-ORQUESTRACAO-IA-2026-06-10.md`](../docs/MAPEAMENTO-SPX-ORQUESTRACAO-IA-2026-06-10.md)** + 20 relatórios por subsistema em `docs/mapeamento-2026-06-10/` (21 agentes sobre o código + auditoria read-only de prod). Pedido do Paulo: estado atual do SPX + o que a IA pode orquestrar (triagem, atribuição, follow-up, campanhas, kanban) coexistindo com humanos.

- **Achados de prod (10/06, read-only):** inbox 91 com **6.508 open** (≈6.100 de disparo) / 7.009 resolved; **432 abertas com lead esperando resposta >12h** (Bruno 151, Kettlen 149, Marcus 61, Lucas 59); 1.618 resolved com assignee; **143 contatos ainda com >1 ficha + 115 com >1 conversa** (resíduo HISTÓRICO jan–mai, fora do escopo da consolidação dos 275; sem re-duplicação ativa). Rule #53 ativa (única); teams espelham funis; 26/30 usuários são admin (só os 4 corretores têm role restrita). Fix `11b913531` confirmado FORA de prod (diff real: prod sem fix e sem lógica inq — rollout 08/06 regrediu o job). `inq-mapa.jpeg` 404 confirmado. 0 migrations pendentes. Sidekiq sem jobs spx agendados.
- **Diagnóstico-chave do "ninguém viu":** não é permissão (secretárias são admin) — é **notificação default OFF** (`assigned_conversation_new_message` sem push/email de fábrica; só `conversation_assignment` vem ligado — `account_user.rb:46-51`) + fila "Abertas" afogada em conversas de disparo + reply em conversa open não dispara `conversation_opened` (#53 não devolve pra triagem).
- **Correções ao STATE antigo:** (1) o limbo pending está 80% resolvido NO CÓDIGO — `mark_pending_conversation_as_open_for_human_response` NÃO está mais stubbado (override `enterprise/app/models/enterprise/message.rb` ativo via prepend) + `f96ae7740` abre quando a IA assume; residual = `router_skip` (whitelist) segue pending invisível. (2) SLA Enterprise EXISTE e roda no cron (gatilho temporal nativo "lead esperando há X" com notificação) — caveats: AppliedSla terminal pós-resolve (ruim c/ conversa única; usar snooze), business hours ignorado. (3) Já existe embrião de **Evals**: copilot tool `get_conversation_analysis` espera serviço LLM-judge externo em `TOZI_EVAL_API_URL` (127.0.0.1:8910) — serviço NÃO existe ainda (porta vazia na VM). (4) Copilot do painel já tem 32 tools (assign/status/send_template/workload) — gatilho `#copilot` semifuncional (sem user → tools inativas; resposta descartada) e `send_template` com bug (template_params em additional_attributes, MessageBuilder lê top-level).
- **Decisão recomendada no doc:** orquestração DENTRO do Captain (listener `Spx::Orchestrator` + tools de atribuição com team_id + triagem por labels `nicho:*` → automation `assign_team` + SLA nrt como despertador) — NÃO via AgentBot externo. Rule #53 é substituída pela triagem orquestrada no médio prazo (são mutuamente exclusivas: ela zera QUALQUER atribuição em `conversation_opened`, inclusive auto-open da Clara). Conversa única (lock_to_single) MANTIDA — organização por funis (FunnelItem é por conversa×funil, multi-card) + labels + custom_attributes, não por múltiplas conversas.
- **Plano em fases (doc §10):** F0 higiene (reconciliar branches; patch fix disparo; **ligar notificações dos corretores — quick win nº1**; mutirão das 432; política de status p/ conversas de disparo; consolidar 143 históricas + reconciliador incoming) → F1 triagem+go-live Clara (HandoffTool c/ team_id, labels nicho, matar #53, Lead Ads HSM+source_id) → F2 cadência completa (disparo entra no funil, cancel-on-reply genérico, SLA nrt) → F3 campanhas como módulo (entidade persistida + UI + stats por template + gate de saúde) → F4 Evals (worker 8910) + Copilot consertado → F5 multi-cliente.
- **15 bugs/riscos novos catalogados** (doc §11): webhooks at-most-once (retry inerte — fix 1 linha), backfill do Kanban poluindo o funil Tozi (origem dos 868 "Novo Lead"), Kanban ignora custom role + filtro de label quebrado, Lead Ads source_id com `+` (futura fábrica de duplicatas), `skip_agent_bot` NoMethodError latente, PII integral nos traces OTel, etc.

### [2026-06-08] 🟢 CONVERSA ÚNICA POR CONTATO — duplicatas de disparo CONSOLIDADAS (reply órfão resolvido)

> **Reclamação:** leads que receberam disparo dias atrás e respondiam hoje apareciam **"Não atribuída", sem corretor e sem histórico**.

- **Causa-raiz (diagnóstico com dados):** o `DisparoLeadJob` criava ficha (`ContactInbox`) com `source_id` no NOSSO formato (`BrazilPhoneNormalizer`, +9º dígito) e conversa nova via `Conversation.create!`. Pros números antigos, o **wa_id que o Meta entrega é a outra variante** (12d sem o 9). Aí o reply caía numa **ficha/conversa diferente** da do disparo → órfão; e a `AutomationRule #53 'iniciar zerado'` (event `conversation_opened`, inboxes 61/62/91, zera assignee+team) **desatribuía ao reabrir**. O `Whatsapp::PhoneNumberNormalizationService` (variantes 12d/13d) existe e é certo — o disparo é que **não o usava**. **275 contatos** ficaram com >1 conversa (203 com 2 fichas + 72 com 2 convs na mesma ficha).
- **Decisão (com Paulo):** o SPX da Tozi exige **1 conversa por contato** (`lock_to_single`). Logo, **não** remendar roteamento (deixaria 2 convs) — **consolidar** (eliminar a duplicata) + **consertar a origem**. NÃO desativar a #53 (é consequência, não causa).
- **🟢 FRENTE 2 — consolidação APLICADA + verificada (prod):** script `scripts/spx/tozi/consolida_conversas_duplicadas.rb`. Por contato: funde tudo na conversa com mais incoming (empate→mais recente), move msgs (`update_all`), atribui ao **corretor do disparo**, deixa **aberta**, migra `campaign_id`/`source`/`template`, apaga convs vazias + fichas duplicadas (`delete`/`update_columns`, sem callbacks/async, transação por contato). Validado com rollback em 1, depois rodado: **275 ok, 0 falhas, 810 msgs movidas, 298 convs + 203 fichas apagadas.** Pós-verificação: **0 contatos com >1 conversa/ficha**. SILMAR (exemplo): 1 ficha (`556699776106`) + 1 conversa aberta atribuída ao Bruno, 22 msgs (atendimento+HSM+follow-up+reply juntos). **Bônus:** o corretor agora **vê o histórico inteiro** (resolve o "sem histórico" da reclamação). **Bleeding parado** — replies agora roteiam certo sozinhos.
- **🟡 FRENTE 1 — job consertado, COMMITADO LOCAL (`11b913531`), NÃO deployado.** `disparo_lead_job.rb`: `resolved_source_id` (usa `PhoneNumberNormalizationService` → reusa a ficha que o WhatsApp já usa) + `find_or_create_conversation` (reusa a conversa única, reabre+atribui; cria só se nunca existiu). **Impede o próximo disparo de re-duplicar.**
  - ⚠️ **BLOQUEIO de deploy — DIVERGÊNCIA prod↔repo:** o job em prod (AWS, **124 linhas**) está **ATRÁS do repo** — **não tem** a lógica de inquilinos (`NO_BODY_VAR`/`INQ_IMAGE_URL`/`no_var_params` + chaves `tozi_inq_*`). Resíduo das múltiplas sessões. **NÃO transportar o arquivo inteiro** (clobberaria). Deploy de frente 1 = **patch cirúrgico in-place** (3 pontos: source_id + find_or_create + 2 helpers, baseline confere) + restart `chatwoot-worker.1`. Backup do job feito na AWS (`.bak.*`). `migrate:status` = **0 down** (restart seguro; ⚠️ contradiz o STATE que dizia a landmine `20260330120000` down — investigar se foi aplicada).
  - **PENDENTE:** aval do Paulo pro patch cirúrgico + restart do worker. Não urgente (bleeding já parado; frente 1 só previne disparo futuro).
  - 🔴 **O deploy das 01:48 (rollout) também dropou ASSETS off-git:** `public/inq-mapa.jpeg` → **404** (imagem do header dos templates `tozi_inq_*`). Templates existem APPROVED no canal, mas **envio de imagem falharia** (Meta busca a URL no envio). Some também do repo/local. Recuperável: anexo `mapa-localizacao.jpeg` da resposta rápida `/interesse` (att 411283, em prod) — *se for o mesmo mapa*. Reforça que a reconciliação tem que trazer **código + assets** da paulao/off-git pra rollout.

### [2026-06-08] ⏸️ Follow-up 2ª leva (600 locação) — EM ESPERA (Paulo: "segura")

> Pool de follow-up por segmento (não-respondentes sem re-bate): **Locação 669 · Venda 2.206 · Inquilinos 1.015 = 3.890**. Disparos novos faltando: **Inquilinos 2.470** (locação/venda esgotadas, ~35 resíduo).

- Paulo pediu armar **600 da locação** (17:30 Sinop = 21:30 UTC, round-robin Lucas#127/Bruno#131/Kettlen#126, 200 cada, 5s) com **template de imagem**. **Travado** porque a imagem morreu (ver acima) → exigiria recuperar imagem + dar suporte a header de imagem no `FollowupHsmJob` (hoje só texto) + deploy/restart em prod. Paulo mandou **segurar**.
- ✅ Confirmado: follow-up é **seguro pós-consolidação** — `FollowupHsmJob` manda na conversa única existente (não duplica; o bug era só do `DisparoLeadJob`). Alternativa zero-deploy quando retomar: texto `tozi_followup_lanc` (copy encaixa nos não-respondentes), sem mexer em prod.
- **🟢 DISPAROU (09/06 ~22:20 UTC):** 670 não-respondentes locação, 4 corretores **Marcus#128/Kettlen#126/Bruno#131/Lucas#127** (~167 cada, round-robin, reatribuídos via `update_columns`), 5s, `tozi_followup_lanc` (1 var). Script `Downloads`/tmp `fu_schedule.rb`. Termina ~23:16 UTC.
  - 🔴 **GOTCHA grave:** o `followup_hsm_job.rb` tinha **SUMIDO de prod** (`uninitialized constant Spx::Tozi::FollowupHsmJob`) — dropado no deploy 01:48 junto com TODO o código off-git da paulao. **Restaurei** via scp do repo local → prod + **restart `chatwoot-worker.1`** (migrate:status 0 down). Agora prod tem o job de novo (mas é remendo; a reconciliação real continua pendente).
  - Falhas iniciais ~40% = **131026 número morto** (esperado nos não-respondentes; não cobrado) + 1× 130472 pacing. **Não é bug** — envio saudável (entregues OK).
  - ⚠️ Cada vez que prod for redeployado da `rollout`, esse job (e a imagem, e a lógica inq) **somem de novo**. Reconciliar a `rollout` com a paulao é o conserto definitivo.

### [2026-06-05] 🔁 FOLLOW-UP re-engajamento (capacidade nova: HSM na conversa EXISTENTE)

> Re-bater nos NÃO-RESPONDENTES da campanha 1 (lançamento/locação). Paulo: 600 total, corretores Lucas+Bruno.

- **Audiência:** campanha 1, alcançados (delivered/read) SEM incoming, atribuídos a Lucas(127)/Bruno(131) = 691 → cap **600** (interleave: Lucas 330 + Bruno 270, ambos cobertos). Script `Downloads/followup_schedule.rb`.
- **🆕 `Spx::Tozi::FollowupHsmJob`** (`app/jobs/spx/tozi/followup_hsm_job.rb`, no repo + prod): envia o HSM **DENTRO da conversa que já existe** (não cria nova — diferente do DisparoLeadJob), `conv.open!` se resolvida, mantém o assignee. 1 variável ({{1}}=nome). Pausar: deletar `FollowupHsmJob` do ScheduledSet.
- **Template `tozi_followup_lanc`** (id 2265413040930153, MARKETING/pt_BR, PENDING): "Oi {{1}}, mandei uma mensagem essa semana e ainda não tive retorno seu..." + botões `Tenho interesse`/`Me chama depois`. ⚠️ "Oi" adicionado antes de {{1}} (Meta não deixa corpo começar com variável).
- **Monitor** espera DisparoLeadJob (inquilinos) zerar + template aprovar → sync → amostra do follow-up na conversa do Paulo → se OK, dispara 600, 5s ~50min.
- **🟢 DISPAROU (05/06):** monitor disparou auto quando inquilinos zerou. Paulo mandou "não disparar inquilinos hoje" mas inquilinos **já tinha terminado** (1.178 enviados, 975 ok). Follow-up foi pausado no 44º, Paulo confirmou **"follow-up sim, inquilinos não"** → retomado com exclusão dos 44 já-enviados (`already_fu` no `followup_schedule.rb`), +556 → **600 total** (Lucas 330 / Bruno 270). 5s.
- **🟢 FOLLOW-UP VENDA +400 (05/06):** Paulo pediu "mais 400" → base de VENDA. Mesmo template/job, alvo = não-respondentes da **campanha 2** no fio existente. Primeiro rodou K/L/B (134/133/133), mas Paulo corrigiu **"só Bruno e Lucas"** → pausei (375 deletados, incl. Kettlen) e re-disparei **400 = Lucas 200 + Bruno 200** (exclui já-enviados via `already_fu`). Script `Downloads/followup_venda_schedule.rb` (BROKERS=[127,131]). ⚠️ Número **YELLOW** (Paulo ciente; follow-up warm). Monitorar.

### [2026-06-05] 🖼️ INQUILINOS — disparo com TEMPLATE DE IMAGEM (capacidade nova) + auto-armado

> Lista nova `INQUILINOS.xlsx` (3.919). Guilherme vetou gatilho "sair do aluguel" (lista tem inativos, alguns já compraram). Copy refeita: ângulo oportunidade/investir/relacionamento, **sem nome** (nomes estranhos), **sem presumir status**.

- **Ingestão `Downloads/ingestao_inquilinos.py`** — dedup 4 camadas: corretores + já-enviados + **CONVERSA ABERTA na inbox 91** (não-resolvida, p/ não misturar assunto) + dup. Recuperação: 9-díg→DDD 66, 8-díg→66+9, trunk-0→tira 0 mantém DDD. **3.654 net-new** (`tozi_inquilinos_limpa.csv`).
- **🆕 TEMPLATE COM IMAGEM (1ª vez):** 3 criados `tozi_inq_lancamento`/`tozi_inq_invest` (header IMAGE = mapa localização, represamento) + `tozi_inq_cliente` (texto). Imagem subida via **resumable upload** (`POST /APP_ID/uploads` → handle; APP_ID=1147301410628990) em `Downloads/create_inq_templates.rb`. Hospedada pública p/ envio: `https://tozi.chatspx.app/inq-mapa.jpeg` (em `public/inq-mapa.jpeg`).
- **🆕 JOB ESTENDIDO** (`disparo_lead_job.rb`): branch `NO_BODY_VAR` (templates inq = corpo SEM variável) + `no_var_params` monta `processed_params: {header: {media_url: URL, media_type: 'image'}}`. Formato descoberto em `Whatsapp::TemplateProcessorService#build_header_params` (espera `media_url`+`media_type`). Caminho de 2 variáveis intacto (A/B não quebra).
- **Disparo:** `Downloads/disparo_inq.rb` — 1.200, 3 corretores **Bruno #131/Kettlen #126/Lucas #127** (400 cada), 3 templates decorrelacionados, 5s, ~1h40. CSV em `/home/chatwoot/tozi_inquilinos_limpa.csv`.
- **Monitor background** espera A/B 227 zerar + 3 aprovarem → sync → **amostra com imagem pro Paulo** → se entregar (= Meta buscou a imagem) → solta os 1.200. Gotcha: "delivered" num template de imagem prova que a imagem foi buscada/entregue OK.

### [2026-06-04] 🧪 A/B QUALIFICADO DISPAROU 20:41 (auto via monitor) — base de venda ESGOTADA

> A/B `tozi_venda_oportunidade` (137) vs `tozi_venda_lembrei` (136) disparou automático às 20:41 (monitor esperou o 1.000 zerar → sync → amostra delivered pro Paulo → soltou). **273 leads, só Kettlen** (Bruno/Marcus/Lucas removidos a pedido), split 50/50 perfeito (fórmula `j % TEMPLATES.size`), 5s, ~23min. **Base de venda zerada após** (3.398 elegíveis todos disparados ao longo dos lotes). **PENDENTE:** medir a **taxa de resposta QUALIFICADA** de cada template (cliques `Quero saber` + interesse real / enviados) quando o lote terminar (~21:04) — esse é o payoff do teste. Motor `Downloads/disparo_ab.rb`.

### [2026-06-03] 🟢 DISPARO VENDA Tozi (proprietários de venda, copy nova, 5s, SEM cap)

> Segundo disparo. Público = **PROPRIETÁRIOS DE VENDA** (vendedores), segmento NOVO (lista de locação já tinha sido toda disparada — ver entrada de 02/06). Paulo quer **contínuo a 5s, sem cap, ele manda parar** (ver [[feedback-disparo-continuo-sem-cap]]).

- **Audiência:** `PROPRIETARIOS VENDA - removidos ativos...xlsx` (3.505) → ingestão `Downloads/ingestao_tozi_v4.py` (canonical DDD+8, dedup tríplice: blacklist corretores 1.177 + já-enviados DB + dup interno + filtro fake `(\d)\1{6,}`) → **3.394 elegíveis** (`Downloads/tozi_venda_limpa.csv`). Só 5 overlap com locação (segmento limpo).
- **Templates (APPROVED + sincronizados):** `tozi_venda_prioridade` (1507152557728445), `tozi_venda_investidor` (1473243537915273), `tozi_venda_condicoes` (1911525192852443). MARKETING/pt_BR, {{1}}=lead {{2}}=corretor, 2 botões quick-reply: **"Tenho interesse" / "Quero, mas outro horário"**. Criados via `Downloads/create_venda_templates.rb` (Net::HTTP→Graph API, rodado na AWS p/ não corromper acento).
- **Motor:** `Downloads/disparo_venda.rb` (rodado na AWS via `rails runner`, `DRY=1` simula / `DRY=0` enfileira). Decorrelacionado (cada corretor manda os 3 templates), round-robin **Kettlen #126 / Bruno #131 / Lucas #127 / Marcus #128** (~849 cada), 5s, `campaign_id=2`.
- **Campaign âncora #2** "Disparo Venda Tozi" (one_off/completed — nunca auto-dispara). Stats via tela de campanha por `campaign_id=2`.
- **PAUSAR:** deletar `DisparoLeadJob` do `Sidekiq::ScheduledSet` (script igual aos de `Temp/`). Início: 3.379 na fila após enfileirar.
- **🔴→✅ SUSTO "mensagens estranhas" (resolvido):** Paulo viu no painel a bolha cortada **"Oi Adriana!"** e mandou pausar. Diagnóstico: o `DisparoLeadJob` tem hash `PREVIEWS` (o `content` que o time vê na transcrição) e os `tozi_venda_*` **não estavam lá** → caía no fallback `'Oi %<n>s!'`. **Era só o rótulo interno** — o LEAD sempre recebeu o template completo (confirmado: corpo aprovado na Meta idêntico, params {{1}}/{{2}} certos, 0 duplicatas, 3 testes pro WhatsApp do Paulo chegaram perfeitos). **Fix:** adicionados os 3 `tozi_venda_*` ao `PREVIEWS` com corpo completo (`app/jobs/spx/tozi/disparo_lead_job.rb`, deploy + **restart worker** com disparo pausado) → painel agora mostra a mensagem inteira. Repo sincronizado com prod.
- **Retomado 03/06:** re-enfileirado com dedup (`skip ja_enviado:51, fake:4`) → **3.343** a 5s. ⚠️ `prioridade` diz "aqui é **o** {{2}}" — fica "o Kettlen" (mulher), gramática torta só nesse template c/ corretora mulher.
- **🔄 TROCA p/ template CURTO (03/06):** Paulo dispensou os 3 longos e pediu um **curto com botões**. Criado `tozi_venda_abertura` (id 1737345930628257, MARKETING/pt_BR, **APPROVED**): *"Oi {{1}}, tudo bem? Aqui é {{2}}, da Tozi Imóveis. Tá podendo falar agora?"* + botões **`Sim, pode falar` / `Agendar horário`**. Gênero-neutro ("Aqui é {{2}}"). Adicionado ao `PREVIEWS` do job (deploy + worker restart). **Kettlen #126 removida** da rotação → só **Bruno #131 / Lucas #127 / Marcus #128**. Motor: `Downloads/disparo_venda_curto.rb` (template único + 3 corretores). **314 já tinham recebido os 3 longos** (51 1ª leva + 263 na retomada); os **3.082 restantes** recebem o curto. Re-enfileirado 03/06 (`skip ja_enviado:312, fake:4`), 5s, ~4,3h.
- **⚠️ Falhas esperadas:** lista de vendedores tem muito 131026 (sem WhatsApp) + 130472/131049 (pacing). Não-cobradas.
- **🟢 FASE 2 (04/06):** 3 templates NOVOS APPROVED (`tozi_venda_condicao` 1391763976151966 / `tozi_venda_invest` 874042698421860 / `tozi_venda_suites` 996870739390338, copy refinada, **gênero-neutro "aqui é {{2}}"** + botões `Tenho interesse`/`Quero, mas outro horário`). Disparo **1.200** (Paulo deu cap explícito desta vez — exceção ao [[feedback-disparo-continuo-sem-cap]]) — 4 corretores Kettlen #126/Marcus #128/Lucas #127/Bruno #131 (300 cada), 3 templates (400 cada), 5s, ~1h40. Número GREEN, primeiros sends 0 falha. Motor `Downloads/disparo_venda2.rb` (cap `LIMIT=1200`) + `create_venda2_templates.rb`. Sobram ~1.273 na base após.
- **🟢 LOTE 3 (04/06):** mais **1.000** com o template CURTO `tozi_venda_abertura` (4 corretores Kettlen/Marcus/Lucas/Bruno, 250 cada, cap 1.000, 5s, ~1h23). Motor `Downloads/disparo_curto_lote2.rb` (`LIMIT=1000`, 4 brokers). Dedup excluiu 2.121 já enviados → 1.000 de 1.273 disponíveis; **sobram ~273** após. Número GREEN.
- **🧪 A/B QUALIFICADO (04/06) — auto-disparo armado:** insight do Paulo: curto "Tá podendo falar?" enche de volume DESQUALIFICADO (clientes acham que é sobre o imóvel deles); longo qualifica mas pouco volume. Solução = **curiosidade ancorada no benefício**. 2 templates novos APPROVED-pending p/ A/B: `tozi_venda_oportunidade` (3096853437186543, "Separei uma oportunidade boa pra você... valoriza rápido e dá pra alugar. Quer que eu te conte?") + `tozi_venda_lembrei` (1298701482390341, "Apareceu uma oportunidade que combina com cliente da casa e lembrei de você... valoriza e gera renda. Vale 2 min?"). Botões iguais (isola copy): `Quero saber`/`Me chama depois`. **Esgota os ~273 restantes**, split 50/50 por lead (`template = j % TEMPLATES.size` — fórmula trocada porque a antiga `(j + j/N)%2` quebrava com N=1 e mandava só 1 template). **SÓ Kettlen #126 — Bruno #131, Marcus #128 e Lucas #127 removidos a pedido 04/06** (jobs pendentes deles no lote de 1.000 reatribuídos pra Kettlen via `reassign_{bruno,marcus,lucas}.rb`, horários preservados: 66+59+75). ⚠️ Tudo concentrado na Kettlen (~423 convs: 150 do 1.000 + 273 A/B). Motor `Downloads/disparo_ab.rb` (LIMIT=0). **Monitor background** espera 1.000 zerar + aprovação → sync → amostra pro Paulo → se OK dispara. Previews dos 2 já no job. ⚠️ Gotcha de relógio: server loga UTC (≠ Sinop UTC-4) — "00:40 UTC" = 20:40 Sinop. Métrica do teste = **taxa de resposta QUALIFICADA** (não volume bruto).
- **🟢 SAÚDE recuperou pra GREEN (04/06):** número estava YELLOW, voltou pra **GREEN** após pausa + engajamento alto (433 respostas, 24,5% no curto). WABA APPROVED/verified, `health_status.can_send_message=AVAILABLE` (WABA+Business+App), throughput STANDARD, inbound vivo (250/12h). **Seguro retomar.** Lição: blast de pitch longo em base fria derruba reputação; template curto que gera resposta a PROTEGE (Meta premia engajamento). Custo real acumulado (2 disparos, via pricing_analytics): **US$135,12 ≈ R$701** (2.162 marketing entregues; 2.954 service grátis). Relatório PDF: `Downloads/Relatorio-Disparos-Tozi.pdf` (1 pág, gerador `report_gen.py` + `report_data.rb`).
- ⚠️ **Qualidade do número = YELLOW** (degradou no 1º disparo). Falhas iniciais: **131026 sem-WhatsApp** (lista de vendedores tem mais nº morto) + **131049/130472 pacing** (Meta já throttla marketing cedo no YELLOW). Risco real de RED se mandar tudo (3.394 = 4,7h, ~R$1.065). Paulo controla o stop.
- **Job hardcoda** `source='disparo_lancamento'` → venda entra no mesmo dedup futuro (ok). `tozi_venda_limpa.csv` na AWS em `/home/chatwoot/`.

### [2026-06-02 noite] 🟢 DEPLOY CONCLUÍDO (tela campanha + anexo resposta-rápida) — disparo FINALIZOU

> Disparo copy-nova **terminou** (Paulo confirmou "os envios terminaram"). Com a fila zerada, as 2 features foram deployadas num **precompile único + restart só do `chatwoot-web.1`** (worker intocado — nenhuma das 2 usa job). Guard `migrate:status` = `down==1` (só a landmine). HTTP local+público 200. **Números finais do disparo (campaign_stats #1): total 1529, alcançados 1337, entregues 457, lidas 824, falhas 178 (131026=119 sem-WhatsApp, pacing 58, outro 1), respostas 180.** Distribuição Lucas 583 / Kettlen 583 / Bruno 363.

**Disparo "Lançamento Tozi" — copy NOVA (Guilherme refinou), rodando:**
- Templates novos **APROVADOS + sincronizados** no WABA: `tozi_lanc_prioridade` (id 874854259000986), `tozi_lanc_portfolio` (2773640852999289), `tozi_lanc_investidor` (869549619532683). MARKETING/pt_BR, **{{1}}=lead + {{2}}=corretor**, 2 botões ("Tenho interesse"/"Quero saber mais"). (Os `tozi_aquarela_*` com Guilherme fixo foram **apagados** no WhatsApp Manager — nome trava ~4 semanas.)
- `app/jobs/spx/tozi/disparo_lead_job.rb` **DEPLOYADO**: `agent_first_name(assignee_id)` preenche `{{2}}`, PREVIEWS novos, grava `campaign_id=1`. Worker reiniciado.
- **GOTCHA resolvido:** template novo dava `#132000 number of parameters` até `Inbox.find(91).channel.sync_templates` (o SendOnWhatsappService usa os templates SINCRONIZADOS, não só processed_params). Depois precisou **restart do worker** pra limpar cache de templates.
- **Resume:** corretores **Kettlen #126 / Lucas #127 / Bruno #131**, **5s**, dedup. ~412 já enviados + **420 restantes DECORRELACIONADOS** (`template=(j + j/3)%3` — cada corretor manda os 3; o `i%3` original casava corretor↔template = cada um mandava só 1). Os ~412 da 1ª parte ficaram correlacionados (irreversível). 1ª leva (695) usou copy ANTIGA `tozi_lancamento_*`.
- Scripts em `Temp/`: `resume_lanc.rb`, `fix_decorrelate.rb`, `monitor_lanc.rb`, `create_lanc_templates.rb`.

**Respostas rápidas criadas** (Account 6, com `{{contact.name}}`): `/interesse` (loc+lista prioridade) + `/preco` (deflete preço + qualifica investir/uso).

**🟢 DEPLOYADO (02/06 noite)** — precompile único (`✓ built in 2m20s`, manifest 23:35) + restart `chatwoot-web.1`:
1. **Fix tela campanha** — `app/javascript/dashboard/api/campaigns.js`: **axios GLOBAL** (`/* global axios */`) em vez de `import axios` (era 401 → "Não foi possível carregar estatísticas"). ✅ no ar.
2. **Anexo em respostas rápidas** (9 arquivos): Back — `canned_response.rb` (`has_many_attached :attachments`) + `canned_responses_controller.rb` (permit `attachments: []` + serialize `file_url: url_for(att)` + purge no update). Front — `api/cannedResponse.js` (FormData c/ anexo), `AddCanned.vue`+`EditCanned.vue` (input file), `CannedResponseModal.vue` (emite `attachments` no select), `ReplyBox.vue` (`onCannedResponseSelect`→`attachCannedResponseFiles`: fetch `file_url`→File→`onFileUpload`), `cannedMgmt.json` en+pt_BR (`FORM.ATTACHMENT.LABEL`). ✅ no ar.

**Verificação pós-deploy (backend, server-side ✅):** `campaign_stats(#1)` retorna hash completo (números acima); `CannedResponse#attachments` carrega (`has_many_attached`); **mapa anexado na resposta #77 `/interesse`** (att id=411283, `mapa-localizacao.jpeg`, 290KB) e `rails_blob_url` serve com `302 → disco` (fetch do ReplyBox segue o redirect). Endpoint `GET /canned_responses` (HTTP 200) já traz `attachments:[{id,filename,file_type,file_url}]` por item.

**🔴→✅ BUG do anexo inline (achado quando Paulo testou "não vi mapa no /interesse") — corrigido + deployado (02/06 ~00:12):** havia **2 caminhos** de resposta rápida e só o **modal** estava ligado ao anexo. O **`/` inline** (o que o time usa) é renderizado pelo editor ProseMirror (`Editor.vue` → `CannedResponse.vue` via `MentionBox`), que inseria **só o texto** (`@replace`) e descartava `attachments`. Fix aditivo em 3 arquivos: `CannedResponse.vue` emite `@attach` com `selected.attachments` (match por `short_code===item.key`); `Editor.vue` encaminha via emit `attachCannedFiles`; `ReplyBox.vue` liga **os 2 editores** (compositor padrão 2291 + wa-composer-bar 2530) ao `attachCannedResponseFiles` já existente. **Zero regressão** (canned sem anexo nunca dispara `@attach`). Revisão adversarial OK: MentionBox repassa item completo (`item.key` sobrevive); `onFileUpload({name,type,size,file})` = mesmo shape do drag-drop (ReplyBox:1103). **Falta só Paulo testar** (hard-refresh Ctrl+Shift+R p/ pegar o bundle novo): (a) 📊 no card da campanha carrega; (b) digitar `/interesse` inline → texto + mapa juntos.

**Deploy B (tela de campanha) JÁ no ar:** endpoint `GET /api/v1/accounts/:id/campaigns/:id/stats` (`campaigns_controller#stats` + `campaign_stats`, agrega por `campaign_id`) + policy `stats?` + rota detalhe `campaigns_whatsapp_detail` (`whatsapp/:campaignId`) + `WhatsAppCampaignDetail.vue` + card 📊. Faltava só o fix do axios (item 1).

### [2026-06-02] 🟢 PLANO DE GO-LIVE DA IA (prioridade — resolver o quanto antes)

> **🟢 RE-VERIFICADO AO VIVO 2026-06-10 (read-only, prod AWS Account 6).** Cérebro + infra **100% prontos e intactos** (o deploy 08/06 que dropou código off-git NÃO mexeu na config da Clara — ela vive no DB). Estado seguro: Clara **desconectada** (`CaptainInbox(91)=nil`, `active_bot?=false`, `agent_bot=nil`). Confirmado: `captain_integration_v2=true`; `captain_auto_resolve_mode='disabled'`; modelo `claude-sonnet-4.5`; cota captain 99.841/100k; knowledge `hybrid` (1 doc Playbook *available* + **40 Q&A com embedding**); Scenarios Vendas#5=6274 / Locação#6=3719 / Suporte#7=2796; chaves LLM SET no InstallationConfig (que é de onde o `ai_agents.rb` lê — `after_initialize`); `TOZI_VISTA_API_KEY` SET no env do worker; canal `whatsapp_cloud` com `api_key`; código SPX/Tozi presente (`disparo_lead_job`, `followup_hsm_job` restaurado 09/06, `funnel_placement_service`, `reactivation_cadence_service`).
>
> **⚠️ CORREÇÃO do bloqueio #1 (pending limbo):** o item 1 abaixo está **superdimensionado**. `Inbox(91).pending_status_enabled?` = **`false`** (coluna real no DB, default false, **independente do bot** — NÃO deriva de `active_bot?`). Em `reopen_resolved_conversation` a guarda é `active_bot? && pending_status_enabled?` → com pending desligado, conversa resolvida que recebe msg do cliente cai no `else → conversation.open!` (**reabre, não vira pending**). Logo o stub `captain_pending_conversation?=false` é **inofensivo hoje** (o caminho `pending!` nunca roda). **O incidente NÃO recorre por essa via.** ⚠️ **Único cuidado:** NÃO ligar "status pendente" da inbox 91 na UI (`pending_status_enabled`) — se ligar, o limbo volta (o stub continua lá).
>
> **Resta só DECISÃO, não trabalho:** (a) recriar `CaptainInbox(91,7)` e (b) abrir a whitelist `only_contact_phones` (hoje só `+5566996350491`). Recomendado: **piloto controlado** (reconectar + N números reais + monitorar 1 dia → remover whitelist).

A Clara está **DESCONECTADA da inbox 91** (test-mode encerrado por causa do incidente abaixo). Pra religar pra valer, resolver ANTES (senão o incidente volta):

1. **Pré-req reabertura:** com a Clara religada `active_bot?` volta a `true` → resposta de cliente em conversa resolvida vira **pending limbo** de novo (`Message#reopen_resolved_conversation`: inbox com bot → `pending!` em vez de `open!`). **🟢 NEUTRALIZADO 10/06:** só dispara se `pending_status_enabled?=true`, e na inbox 91 está **false** → reabre como `open!`. Resolver com UMA das opções: (a) Clara atende de verdade (tira whitelist) e abre a conversa, **ou** (b) corrigir o código — `mark_pending_conversation_as_open_for_human_response` está **stubbado `false`** em `app/models/message.rb` (`captain_pending_conversation?` retorna false), então nem resposta humana abre a pending.
2. **Whitelist:** sair de `behavior.router.only_contact_phones=["+5566996350491"]` de forma controlada (piloto com N leads → geral).
3. **Auto-resolve:** manter `captain_auto_resolve_mode='disabled'` OU reconfigurar com cuidado (mensagem PT decente, gateado, sem loop pending→resolve).
4. **Reconectar:** recriar `CaptainInbox(inbox_id=91, captain_assistant_id=7)` só depois dos 3 acima. Testar E2E: cliente que volta é atendido (não fica pending).
5. **Cérebro (já validado/staged):** prompt Júlia (Scenario Vendas #5, 6274 chars) + knowledge (1 doc Playbook 19 chunks + 40 Q&A nativas, modo hybrid) + tools (`buscar_imovel` via `TOZI_VISTA_API_KEY`, geocoding com chave embutida).

### [2026-06-02] 🔴→✅ INCIDENTE: IA fechando conversas / "mensagens sumindo" — RESOLVIDO

**Sintoma:** equipe achou que o número parou de receber mensagens + conversas fechando com *"Resolvendo a conversa dado que está inativa..."*. Suspeita: IA.

**Diagnóstico (com dados):** número 100% saudável na Meta (`CONNECTED/GREEN/STANDARD`); inbound nunca parou (241 msgs/dia, última há 1 min). A causa era a combinação:
- Inbox 91 com Clara conectada → `active_bot?=true`. Em `Message#reopen_resolved_conversation`, inbox com bot → conversa resolvida que recebe msg do cliente vira **`pending!`** (não `open!`), esperando o bot atender.
- Clara com **whitelist** (`only_contact_phones`, só o nº do Paulo) → **não atende o lead** → conversa **presa em pending** (invisível na aba "Abertas").
- **Auto-resolve do Captain** (`Enterprise::Account::ConversationsResolutionSchedulerJob` → `Captain::InboxPendingConversationsResolutionJob`) fechava as pending inativas >1h com a mensagem PT (pública) + nota EN "Auto-resolved:" (privada). **57 PT + 55 EN, ~17 convs, inboxes 61/62/91**, ondas 23/05 (47) + 01/06 (10), **última 01/06 15:34**.

**Fixes aplicados (prod):**
- **Auto-resolve:** `Account.find(6).captain_auto_resolve_mode='disabled'` (já estava, desde 01/06). Trava DUPLA no código (scheduler linha 15 + job linha 8: `return if captain_auto_resolve_disabled?`). **Zero auto-resolve desde 01/06 15:34** (confirmado: 0 hoje).
- **Reabertura:** **Clara DESCONECTADA da inbox 91** — `CaptainInbox(91,7)` destruído → `active_bot?=false` → cliente que volta cai no `else → conversation.open!` (reabre como **Aberta**). Clara (assistant #7, config/knowledge/cenários) **intacta**, reconecta no go-live.
- **Recuperação:** **76 conversas presas reabertas** (74 inbox 91 + 1+1 em 61/62) + 5 pending limbo zeradas.

**Bug residual conhecido (não corrigido):** `reopen_resolved_conversation` manda pra `pending!` em inbox com bot — ok SE o bot atende; vira limbo se o bot está calado (whitelist). Tratar no go-live (item 1 do plano acima).

### [2026-06-02] 🟡 Disparo "Lançamento Tozi" EXECUTADO (parcial, PAUSADO) + Campaign âncora + view "Não lidas"

**Disparo (motor próprio, NÃO o nativo):**
- **695 enviados de 1.526** (601 entregues, 335 lidas, **87 falhas**: 56 sem-WhatsApp `131026` + 31 pacing Meta `130472`/`131049`). **832 segurados** (pausados; jobs cancelados do Sidekiq).
- Motor: `app/jobs/spx/tozi/disparo_lead_job.rb` (cria contato+conversa+atribui+HSM, grava `campaign_id`) + rake `spx:tozi:disparo[csv,limit,dry_run,spread_min,template]` + `spx:tozi:disparo_teste`. Pacing ~4,8s, round-robin, rotação 3 templates `tozi_lancamento_{interagir,qualifica,curiosidade}` (aprovados, 2 botões positivos + Agendar). CSV audiência: `Downloads/tozi_audiencia_limpa.csv` (1.526) na AWS em `/home/chatwoot/`.
- **Distribuição final:** Kettlen #126 **305**, Lucas #127 **304**, Bruno #131 **86** (Marcus #128 e Guilherme #125 tirados e redistribuídos). Corretores isolados por custom role "Corretor".
- ⚠️ **Adrian #63 e Gelson #72 mandaram ~11 HSM na mão** (fora do orquestrador, sem `campaign_id`) — equipe continuou disparo manual.
- Pausar/retomar/redistribuir/dedup = scripts console (canonical = DDD+8). Pra retomar: re-enqueue com dedup pelos já-enviados.
- **Relatório PDF:** `Downloads/Relatorio-Disparo-Tozi.pdf` (89 respostas → **63 positivas / 21 negativas / 5 neutras**; gerado via Python→HTML→Edge headless).

**Campaign nativa como âncora (Campanhas › WhatsApp) — Deploy A no ar:**
- **Campaign #1** "Disparo Lançamento Tozi" criada `completed` (NUNCA dispara o blaster nativo: scheduler ignora não-active + `trigger!` retorna `if completed?`). 695 conversas linkadas via FK `campaign_id`.
- **Blaster WhatsApp nativo DESATIVADO** (`Campaign#execute_campaign` só loga — `Whatsapp::OneoffCampaignService` não tem pacing/atribuição/rotação, atropelaria o WABA) + **botão "Nova campanha WhatsApp" REMOVIDO** (`WhatsAppCampaignsPage.vue` vira viewer; `CampaignLayout.vue` botão `v-if="buttonLabel"`). Quebra 1 spec nativo (esperado).
- ⚠️ **FALTA Deploy B:** tela de **detalhe** da campanha (dashboard agregado por `campaign_id`: progresso/entrega/distribuição/conversas + Pausar/Retomar). Conceito = "Painel de Disparos" (workflow). Card hoje só lista/exclui.

**View "Não lidas" deployada (12 arquivos, no ar):** scope `Conversation.unread` (incoming após `agent_last_seen_at`) + finder `conversation_type=unread` + rotas `conversation_unread` + item sidebar (abaixo de "Mencionadas") + i18n en/pt_BR. Espelha o "Não respondidas". Validado E2E.

### [2026-06-01] 🟡 Clara ATIVADA em MODO TESTE em prod (só +5566996350491)

> ⚠️ **SUPERADO em 02/06:** a Clara foi DESCONECTADA da inbox 91 (ver incidente acima). O conteúdo abaixo é histórico do estado em 01/06.

**Mudança de estado crítica:** a Clara (#7) saiu de DESLIGADA para **LIGADA em modo teste** na inbox 91 (Account 6).
- `CaptainInbox(inbox_id=91, captain_assistant_id=7)` criado → `inbox91.captain_assistant=Clara`.
- `behavior.router.only_contact_phones` trocado de 4 números antigos para **`["+5566996350491"]`** (número do Paulo). Só ele recebe resposta; todos os outros (386 conversas abertas + leads reais) → router skip → Clara calada.
- `captain_active?=true` (cota captain.responses: 99.856 disponíveis de 100k) → **sem risco de `perform_handoff`** (que mandaria "Transferring to another agent" em inglês nas pending se a cota estivesse zerada). `skip_after_human_response=true` e `skip_groups=true` preservados.
- Chaves LLM (InstallationConfig global OpenAI+Anthropic) setadas.
- **[2026-06-01] Modelo trocado pra Claude:** `account.captain_models['assistant']` = **`claude-sonnet-4.5`** (era `gpt-4.1`). O modelo do runner v2 vem de `account.captain_assistant_model` (= dropdown "Assistente" da tela LLM Settings), lido a cada request. Chave: o `ai_agents.rb` configura o gem `agents` no boot com a Anthropic **GLOBAL** (`CAPTAIN_ANTHROPIC_API_KEY`) — a chave per-conta da UI NÃO alimenta o v2. **Chave global testada ao vivo: chamada a `claude-sonnet-4-5` respondeu "OK".**
- **⚠️ Worker precisa reiniciar** pra carregar a chave Anthropic global no runtime (`Agents.configure` roda no boot). Modelo muda sem restart; chave não. Reiniciar `chatwoot-worker.1` antes do teste E2E.

**Sessão de teste 01/06 — achados e fixes (todos em prod):**
- ✅ **Modelo trocado pra Claude Sonnet 4.5** (`captain_models['assistant']`). Chave Anthropic global validada ao vivo. Teste direto do agente: Júlia respondeu natural em PT-BR, roteou pra cenário Locação. **Cérebro OK.**
- 🔴→✅ **Auto-resolve estava ligando junto com a Clara e mandando "inicie uma nova conversa" + resolvendo conversas de CLIENTES REAIS** (10 msgs/6h, NÃO gateado pela whitelist). Kill-switch: `account.captain_auto_resolve_mode` (`store_accessor :settings`, default 'evaluated'). **Setado `'disabled'`** via `Account.find(6).update!(captain_auto_resolve_mode: 'disabled')`. Scheduler `Enterprise::Account::ConversationsResolutionSchedulerJob` roda p/ TODA `CaptainInbox` exceto `captain_auto_resolve_disabled?`.
- 🐛→✅ **Bug do handoff v2:** quando o agente faz handoff, `result.output` volta vazio → `ResponseBuilderJob` tratava como `[IGNORAR]` → **fala de transferência sumia no WhatsApp**. Fix em `AgentRunnerService#process_agent_result` (fallback `last_assistant_message_text`). Commit `02bcbac0f`, transportado + worker restart.
- ✅ **n8n desligado da inbox 91:** o `AgentBot "Clara" #7` (webhook n8n, 19.614 msgs) ainda estava plugado mesmo após Paulo remover workflow/webhook. **`AgentBotInbox(inbox_id=91)` destruído** → `inbox91.agent_bot=nil`. Captain Clara intacta. Migração n8n→SPX concluída na inbox 91.
- ⚠️ **Whitelist FUNCIONA** (dezenas de `router_skip` p/ clientes reais; só o nº do Paulo engaja). Mas a inbox 91 é **produção viva** (atendentes reais + clientes o tempo todo) — cuidado com efeitos colaterais ao mexer.
- ⚠️ **Conv 2159 = thread de teste podre** (centenas de msgs, multi-dia) → histórico polui o agente. Limpa: 2132 deletada, 2159 esvaziada (557 msgs+38 anexos). **inbox 91 tem `lock_to_single_conversation=true`** → não cria conversa nova por contato; reusa/reabre a última.
- 🟢 **E2E APROVADO (01/06 16:07):** Clara (Captain v2, **Claude Sonnet 4.5**) respondeu "Oi, Paulo! Tudo bem? 😊" / "Como posso te ajudar hoje?" — outgoing público, humanizer quebrou em 2, enviado no WhatsApp. 2.9s. Sender=Captain::Assistant (não AgentBot). Pipeline completo OK.
- 🟢 **Indicador "digitando" + espaçamento (commits `0b3307830`, `71629abe1`):** typing via Cloud API (`status:read`+`typing_indicator`, **v21.0** — v13.0 do endpoint padrão NÃO suporta). `Whatsapp::Providers::WhatsappCloudService#send_typing_indicator(source_id, show_typing=true)` (show_typing=false = só read/tique azul) + no-op no base + delegate no `Channel::Whatsapp`. **Comportamento final (após feedback do Paulo):** tique azul (read) imediato no hook **sem** typing contínuo; "digitando" só em **rajada curta antes de CADA pedaço** do humanizer, proporcional ao tamanho (`delay_per_char_ms` 45, piso 1,5s / teto 7s). Corrige "typing contínuo da chegada até a resposta" (robótico) + mensagens fora de ordem. Best-effort (rescue), só WhatsApp Cloud.
- 🔴→✅ **Busca de imóvel NÃO achava nada — `TOZI_VISTA_API_KEY` faltava no `.env` de prod** (o n8n tinha; migração esqueceu). `Captain::Tools::BuscarImovelTool` lê `ENV['TOZI_VISTA_API_KEY']` (+ `TOZI_VISTA_BASE_URL` default `toz19328-rest.vistahost.com.br`, correto). Chave no vault `credenciais/tozi.md` como `VISTA_API_KEY` (nome diferente!). **Adicionada `TOZI_VISTA_API_KEY` no `.env`** + restart. Testado: acha apto cód 9532 (Aquarela). ⚠️ gotcha: o tool usa `TOZI_VISTA_*`, o vault/n8n usavam `VISTA_*`.
- ✅ **Geocoding (busca por localização) OK** — custom tool #4 "Buscar localização (geocoding)" tem a **chave do Google Maps EMBUTIDA na endpoint_url** (não env var). Testado ao vivo: `google_status=OK`, coordenadas certas. Proximidade ~3km alimenta o `buscar_imovel` (lat/lng bbox).
- ✅ **`buscar_imovel` confirmado E2E:** ferramenta built-in (`enterprise/lib/captain/tools/buscar_imovel_tool.rb`) consulta Vista, filtra Cidade/Status/Categoria/Bairro(like)/Dormitorios/Valor/lat-lng, retorna até 5 com URL `toziimoveis.com.br`. Clara também tem `enviar_fotos_imovel`, `salvar_info_lead`, `programar_followup`. Custom tool #3 "Buscar imóveis no Vista" está `enabled=false` (a built-in substitui).
- ⚠️ **Reopen-on-incoming:** ao esvaziar+force-resolve a 2159 via `update_columns`, a conversa NÃO reabriu sozinha no incoming (hook não dispara em `resolved`). Disparei `ResponseBuilderJob.perform_now` manual + abri a conversa. Provável artefato do force-resolve; conferir se em prod normal (resolve via flow) o incoming reabre + Captain responde a cliente que retorna.

**Go-live (quando validar):** remover a whitelist `only_contact_phones`. Antes disso, decidir as **57 conversas open+pending SEM resposta humana** (as 329 com resposta humana já são protegidas por `skip_after_human_response`): travar as 57 com `atendimento_humano=true` (script) OU deixar a Clara resgatá-las. 0 conversas com trava manual hoje.

### [2026-06-01] 🟢 Knowledge da Clara reorganizada em prod (FAQ→Q&A nativa, modo hybrid)

**Contexto:** Paulo apontou que o FAQ devia ser Q&A nativa (não doc) e o Playbook "parecia duplicado". Auditoria + verificação adversarial (workflow 3 frentes) confirmou: prod (Account 6, Clara #7) estava `knowledge_mode=chunks` com **0 Q&A nativas**; FAQ vivia como documento chunkado (13 chunks) duplicando ~factualmente o Playbook (19 chunks). O "playbook duplicado" é na **PAULAO** (2 docs "Playbook de Vendas Tozi" na aba Documents) — em prod só há 1 cópia. PAULAO tem as Q&A nativas corretas (aba FAQs, Approved) = `FAQ-TOZI.md` verbatim; nunca foram migradas pra prod.

**Feito em prod (Account 6):**
- ✅ **40 Q&A nativas criadas** (`Captain::AssistantResponse`, standalone `documentable=nil`, status approved, **40/40 com embedding**) — extraídas do `FAQ-TOZI.md` (16 institucional + 17 observada + 7 objeções; dropado 1 dup de FGTS). Script: `aws_create_faq.rb`.
- ✅ **knowledge_mode `chunks`→`hybrid`** (liga faq_lookup + mantém search_knowledge). Retrieval testado com 6 perguntas reais → todas casaram na Q&A certa (dist 0.24–0.47).
- ✅ **Documento FAQ (doc#2) DELETADO** (13 chunks foram em cascata; 0 responses atreladas — as 40 Q&A são standalone, intactas). Backup: `clara_knowledge_report.txt` (local) + `/tmp/faq_doc_backup_2.md` (AWS).
- **Estado final:** 1 doc (Playbook, 19 chunks) + 40 Q&A. Zero duplicação de fatos.
- **Playbook prod = fonte canônica** `PLAYBOOK-VENDAS-TOZI.md` (28/05/2026) verbatim — atualizado.

**UI deployada em prod (commit `444e6afa4`, restart web):** aba Knowledge→FAQs agora tem **editar** (inline) + **excluir** (confirmação inline) nas Q&A — backend já tinha o CRUD (`resources :assistant_responses`); faltava só o front (botões + override do `update` no `api/captain/response.js` p/ envolver no wrapper `assistant_response`). Mesmo restart serviu o fix do scroll do Settings.vue. (PAULAO só vê quando recompilar na rede da empresa.)

**Pendente:** limpeza PAULAO (Paulo, via UI: apagar 1 Playbook dup + doc FAQ). Opcional não-bloqueante: enxugar seções factuais 1/3/4 do Playbook prod.

### [2026-06-01] Disparo em massa Tozi — audiência + templates de lançamento

- **Fase A (ingestão) FEITA:** `PROPRIETARIOS DE LOCAÇÃO TOZI.xlsx` (1.614 donos, Nome+Tel sem DDI) cruzado com lista negra `TODOS CORRETORES DE SINOP.csv` (1.177, com DDI). Normalização canônica = **DDD + últimos 8 dígitos** (colapsa DDI + 9º dígito). Resultado v2 (recuperação aplicada): **1.526 leads limpos** (`Downloads/tozi_audiencia_limpa.csv`), 22 corretores cortados, **+12 recuperados** (trunk-0 e mobile 9-díg sem DDD → +66), 24 pra revisão manual (`tozi_revisao_manual.csv` — quase todos "9 duplicado/dígito a mais"), 43 dups. Script `Temp/ingestao_tozi_v2.py`. Verificado: 0 corretor vazou, 0 dup, encoding ok, recuperados presentes.
- **Fase B FEITA:** Custom role **"Corretor" #1** (`conversation_participating_manage`) criada. Configurados na Account 6 + membros da inbox 91: Marcus #128, Kettlen #126 (rebaixado admin→agent), Lucas #127 (rebaixado admin→agent), Bruno #131 — todos **agent + role Corretor** (veem só o atribuído). Guilherme #125 = **administrator** (vê tudo + recebe lead na fila). **Isolamento verificado ao vivo:** corretor vê 0 (só o seu), Guilherme vê 11.216 (tudo). Mecanismo: `Enterprise::Conversations::PermissionFilterService` (participating → `accessible_conversations.assigned_to(user)`; admin bypassa). Senhas recebidas no chat NÃO salvas (contas já existiam).
- **Fase C (orquestrador) A FAZER** — bloqueada por: templates `tozi_lancamento_*` aprovados (PENDING Meta) + tier WABA (~1.600/dia). Build `Spx::Tozi::DisparoEmMassa`: round-robin pros 5 + ScheduledMessages c/ HSM personalizado espalhado em 2h. Testar lote 5-10 antes do real.
- **Templates de disparo recriados com nomes NOVOS `tozi_lancamento_{interagir,qualifica,curiosidade}`** (MARKETING, pt_BR, **2 botões positivos** + "Agendar horário", texto do Guilherme = lançamento apto 3 suítes). **PENDING** na Meta. Audiência = os proprietários (donos/investidores).
- ⚠️ **2 gotchas Meta HSM:** (1) ao DELETAR um template, o **nome+idioma fica travado ~4 semanas** (`error_subcode 2388023`) → recriar exige nome diferente (por isso `tozi_disparo_*` virou `tozi_lancamento_*`). (2) **corpo NÃO pode começar/terminar com variável** (`2388299`) → precisa texto antes do `{{1}}` (usar "Oi {{1}}, ...").
- **Plano disparo (Fase B/C):** Custom Role "Corretor" (`conversation_participating` = só vê o que é atribuído a ele) — **NÃO precisa de 5 times**, basta 5 contas + role + atribuição round-robin. Orquestrador `Spx::Tozi::DisparoEmMassa` sobre `ScheduledMessages` (cria conversa + atribui round-robin + HSM personalizado espalhado em 2h). Pré-req: 5 contas de corretor (Paulo cria), tier WABA p/ ~1.600/dia, recuperação dos 10 tels.

### [2026-06-01] ⚠️ Gotcha: token da WABA Tozi cria templates mas NÃO deleta

`Whatsapp::TemplateManagementService#delete` (e o botão excluir da nova UI de templates) falham com `#100 Need permission on either WhatsApp Business Account or owner/shared business`. O `api_key` do provider_config da inbox 91 cria/envia mas não tem management/delete. **Pra deletar HSM:** WhatsApp Manager (Paulo, admin). Impacto: os 3 `tozi_disparo_*` já estão **APPROVED com 2 botões**; pra trocar p/ botão único (regra: só positivo), Paulo apaga no Manager → eu recrio com 1 botão.

### [2026-05-29] 🟢 Bloco 3+4 + branch paulao DEPLOYADO em produção AWS (Account 6)

**Status:** Branch paulao (19 commits) MERGEADO em `producao` (PR #19, merge `cc4536209`) e DEPLOYADO na VM Tozi AWS (`3.82.215.109`, Account 6). App **live e saudável** (HTTP 200 local+público, web/worker/target active, bundle novo `BaY3jm5l` servido). `zeitwerk:check` "All is good!" na AWS e na PAULAO.

**Implementado nesta sessão (Bloco 3+4):**
- **Bloco 3 — state machine do funil:** `Spx::Tozi::FunnelAutomationListener` (Wisper/AsyncDispatcher, rescue-wrapped, no-op p/ contas sem o funil) + `FunnelPlacementService.move/current_type/prevenda_funnel`. Transições: incoming→em_conversa (+cancel cadência); handoff humano→qualificado; programar_followup→em_silencio; followup MAX→frio; salvar_info_lead status→qualificado/frio. Hooks em `enterprise/lib/captain/tools/{programar_followup,salvar_info_lead}_tool.rb` + `followup_job.rb`.
- **Bloco 4 — cadência HSM fora-da-janela 24h:** `ScheduledMessages` aceita `template_params` (coluna jsonb + create/send service; o `MessageBuilder` já fazia a ponte→`SendOnWhatsappService`). `Spx::Tozi::ReactivationCadenceService` agenda HSM (1d/3d/7d), só Cloud API, idempotente, cancel-on-reply. **Dentro da janela = follow-up do agente (já existia); fora = HSM determinístico.** Estágio do funil arbitra.
- **Fixes:** CGI.escape no template service; migration de chunks `disable_ddl_transaction!`+`if_not_exists`; rake `create_templates` idempotente (list-then-skip) + nomes v2.
- Review adversarial (4 reviewers) + 6 fixes (HIGH: handoff não cancelava cadência; MEDIUM: listener sem rescue derrubava event chain global).

**Deploy AWS — GOTCHAS (críticos pra próxima vez):**
- **🔴 LANDMINE migration:** `20260330120000_add_foreign_key_constraints` é **DESTRUTIVA** (`DELETE` de órfãos em conversations/messages/scheduled_messages/etc.) e está `down` há 6+ dias **DE PROPÓSITO**. **NUNCA rodar `db:migrate` puro na AWS** — dispararia ela = perda de dados. Aplicar SEMPRE alvo: `db:migrate:up VERSION=<ts>`.
- **Transporte (não-git):** tar-pipe de `git archive origin/producao` → AWS. **`tar` extrai como ROOT** (`--owner` é opção de criação, ignorada na extração; sem `--no-same-owner` usa uid do archive=0) → `EACCES` no boot (`public/version.json`). **Fix: `sudo chown -R chatwoot:chatwoot` exceto storage/node_modules.** Alternativa melhor: extrair via `sudo -u chatwoot tar`. Também `git archive` do Windows traz CRLF (Ruby tolera; limpei `bin/*`).
- pgvector **0.8.2** → HNSW direto (fix H1 é só rede de segurança). Precompile com `NODE_OPTIONS=--max-old-space-size=4096`.
- `rake spx:tozi:setup_funnel[6,91]` → **funil "Pré-Venda Tozi" id=41** (stages 127-133). Backfill: 0 leads (hook Meta nunca rodou em prod).

**Re-apply em prod (FEITO 29/05):**
- ✅ **Prompt da Júlia** aplicado no Scenario Vendas **#5** (Clara #7): 4458→6274 chars (da proposta `julia-vendas-PROPOSTA.md`). Backup do antigo em `/tmp/julia_vendas_5_backup.txt` na AWS.
- ✅ **Knowledge** anexada à Clara #7 (knowledge_mode `faq`→`chunks`): doc#1 Playbook (19 chunks) + doc#2 FAQ (13 chunks) = **32 chunks, todos com embedding**. RAG funcionando.

**Estado de ativação (VERIFICADO em prod 31/05 — read-only):**
- 🟢 **Clara DESLIGADA (seguro): não conectada a nenhuma inbox.** `inbox91.captain_assistant=nil`, `clara.inboxes=[]`, `inbox91.captain_active?=false`. Não responde nada. Inbox 91 é tocada por **humanos** (469 msgs/3d, sender=User). Prompt+knowledge estão staged numa assistant não-plugada. **O interruptor real de ativação = conectar a Clara à inbox 91** (na UI: Agents → Inboxes, ou via API). ⚠️ Inbox 91 é a linha humana ao vivo — configurar router (whitelist/skip)/trava-humana/horário ANTES de conectar, senão a Clara atropela os atendentes.
- ✅ **Backend já pronto:** `captain_integration_v2=true`; chaves LLM setadas (InstallationConfig global `CAPTAIN_OPEN_AI_API_KEY`+`CAPTAIN_ANTHROPIC_API_KEY` + hook per-conta `openai` #4); Clara config (prompt Vendas #5=6274 + 32 chunks); **4 templates HSM APROVADOS** no WABA (abertura/followup/reativacao/horario_combinado); inbox 91 Cloud API com `api_key` SET.
- ⚠️ A UI "Agentes IA não habilitado" é enganosa (gotcha "chave em 2 lugares": UI checa hook per-conta, runner v2 usa InstallationConfig global). `CAPTAIN_OPEN_AI_MODEL` vazio→usa default. Diag sugeriu Agents SDK não-configurado no runtime → **restart garante** ao ativar (initializer `ai_agents.rb` lê chaves no boot).

**Falta (próxima sessão) — depois de ativar o agente:**
- 🔴 **Hook Meta Lead Ads em prod BLOQUEADO por gap de código.** `create_initial_message` (`app/services/meta/lead_ads/create_conversation_service.rb:129`) manda **texto livre**. Na inbox 91 (Cloud API), a 1ª msg a um lead de formulário (sem sessão WhatsApp aberta) é **bloqueada pela Meta** — fora da janela 24h só HSM passa. **Construir: 1ª-mensagem-como-HSM (`tozi_lead_abertura` via `template_params`) quando inbox.whatsapp?**. Sem isso, ativar o hook = leads entram no funil mas não recebem abertura (morrem). Em WAHA (PAULAO) funciona porque texto livre passa.
  - Meta-side (Paulo): switch do callback do app Meta pra `https://tozi.chatspx.app/webhooks/meta_lead_ads` (hoje aponta pra PAULAO) + confirmar aprovação do template `tozi_lead_abertura` no WABA.
- **Teste E2E** em prod (depende do hook OU teste manual da state machine/Júlia numa conversa controlada).
- Reconciliar corpos exatos dos templates v2 com o WABA (rake tem corpos-fonte; conferir via `svc.list`).
- Tuning de produto: cadência até 4 cutucadas in-window + 3 HSM; `agendado`/`aguardando_1a` sem trigger automático.

**Acesso AWS:** `ssh -i Downloads/handoff-tozi/simplex.linux.pem ubuntu@3.82.215.109` · RVM · `sudo -u chatwoot bash -lc "cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec ..."`.

### [2026-05-29] Vendas Tozi — Júlia repaginada + templates HSM + knowledge

**Base:** análise de 400+ áudios de atendimentos reais (corretor Henrique, alta conversão) em `C:/Users/paulo/Workspaces/tozi/analise-atendimentos/` (ANALISE-COMPORTAMENTAL.md, PLAYBOOK-VENDAS-TOZI.md, FAQ-TOZI.md, julia-vendas-PROPOSTA.md). Método: consultivo, tom "de Sinop", descobre a pessoa antes dos números (direção do gerente Guilherme: "não quero SDR que pergunta 'qual sua renda bruta'").

**Feito (PAULAO + WABA prod):**
1. ✅ **Prompt da Júlia (Scenario Vendas #1, account 1)** atualizado da proposta: 4458→6273 chars, agora com consciência de nicho (5 nichos), qualificação humanizada, represamento de lançamentos, handoff por nicho, consulta à knowledge. Backup: `/tmp/julia_backup_1780092115.txt` na VM PAULAO. **A proposta NÃO estava aplicada antes — só era documento.**
2. ✅ **Knowledge anexada à Clara** (assistant 1, knowledge_mode=chunks): doc#3 Playbook (19 chunks) + doc#4 FAQ (13 chunks), embeddings OK. Júlia consulta via search_documentation (RAG).
3. ✅ **4 templates HSM submetidos** no WABA Tozi (905788818829319) — PENDING aprovação Meta. IDs em `Obsidian/credenciais/tozi.md`.

**Acesso produção descoberto:** VM AWS `3.82.215.109` (tozi.chatspx.app), chave `Downloads/handoff-tozi/simplex.linux.pem`, Account 6. **Não é git** (deploy via script). Detalhes em `credenciais/tozi.md`.

**Falta:**
- Aplicar o mesmo (prompt Júlia + knowledge) em **produção AWS Account 6** quando subir — lá o Scenario Vendas é #5, assistant Clara #7, ainda com prompt antigo (4458).
- Aprovar/ajustar templates com o time (Paulo confirmando).
- Subir o código da branch paulao pra AWS (processo não-git a definir).
- Bloco 3+4 da cadência (state machine + ScheduledMessages) — ainda pendente.


### [2026-05-27] Meta Lead Ads → Clara (Tozi) — 🟢 EM PRODUÇÃO, aguardando lead orgânico

**Status:** Pipeline completo funcionando E2E. App em modo Live no Meta. Subscription ativa. Hook configurado. Testado via Lead Ads Testing Tool — webhook real chegou no SPX, conversa criada (id=146). Aguarda primeiro lead orgânico real (de campanha rodando) pra fechar ciclo com WAHA+Clara.

**Configuração final (27/05):**
- App Meta: **SPX Lead Ads Tozi** id=`1658426868710322`, criado dentro do BM Tozi, modo **Ao Vivo**
- Page Tozi: `539594042748152`, subscribed em field `leadgen` ✅
- Lead Access Manager: SPX Lead Ads Tozi listado como CRM ✅
- SU Token: nunca expira, salvo em `Obsidian/credenciais/tozi.md` seção "Meta Lead Ads"
- App Secret: `4c27cd1eb604a196f6ed1d74c05abacf` (vault)
- Verify Token: `228d3c9f0065ab7fa859255dce9b24795a60ff0bbd9988f2` (vault)
- Hook no SPX (Account 1): id=3, `skip_initial_message=true` (modo teste — não dispara 1ª msg ao lead até validar com lead real)
- Inbox alvo: 1 (WAHA Tozi, paulo.chatspx.app)
- Último commit: `005661347` (fix substring match + dummy filter na extração de campos)

**Validação E2E (27/05):**
- ✅ GET challenge respondido (Meta verificou webhook)
- ✅ POST de Meta IP real (`2a03:2880:2ff:4d::`) chegou em 13:23
- ✅ Job processou em 611ms, criou Conversation 146 (sem phone — form de teste tinha dummy data)
- ✅ Conversations criadas: 144, 145, 146 (todas testes, podem ser deletadas)

**Bugs identificados e corrigidos hoje:**
1. `Lead has no phone_number` raise → agora aceita lead sem phone (cria conv mesmo assim, não envia 1ª msg) — commit `09958905a`
2. Form com nomes custom PT-BR (`qual_seu_telefone?`) não casavam com lista exata de chaves → substring match + normalização de acentos/caracteres especiais — commit `005661347`
3. Test Tool injeta `<test lead: dummy data>` como valor → agora filtra via TEST_DUMMY_REGEX

**Bloqueios resolvidos hoje:**
- "App is not installed by any of the admins" → resolvido adicionando app ao Lead Access Manager
- "App em desenvolvimento, leads reais não disparam webhook" → resolvido ativando modo Live (URL política privacidade + categoria já configurados)
- Webhook ficava Pending no Tool → resolvido com DELETE+POST subscribed_apps (reset)

**Pesquisa-base:** [`Obsidian/pesquisas/meta-lead-ads-webhook-api.md`](C:/Users/paulo/Workspaces/Obsidian/pesquisas/meta-lead-ads-webhook-api.md)

**Antes do primeiro lead orgânico responder:**
- ⚠ Remover/ampliar whitelist `only_contact_phones` da Clara (hoje só responde +5566996247866)
- ⚠ Quando confiante, desligar flag `skip_initial_message` no hook (Settings → Integrations → Meta Lead Ads → Editar)

### [2026-05-27] Templates HSM WhatsApp via API do SPX — 🟢 mecanismo pronto, falta criar os templates Tozi

**Objetivo:** criar/submeter message templates (HSM) pra aprovação Meta sem abrir WhatsApp Manager — tudo via API do SPX. Base pra cadência em produção (Cloud API).

**Implementado (commits `de4014dd2` + `2991b61e7`):**
- `Whatsapp::TemplateManagementService` — generaliza `CsatTemplateService`. create/list/status/delete via Graph API v22.0. Aceita MARKETING/UTILITY/AUTHENTICATION + components livres. Usa `provider_config` business_account_id + api_key. Normaliza nome (lowercase+underscore).
- `Api::V1::Accounts::InboxMessageTemplatesController` — index/create/destroy scoped por inbox. Valida Cloud API (WAHA rejeitado). Rota: `resources :message_templates` dentro de inboxes.
- `rake spx:tozi:create_templates[account_id,inbox_id]` — cria os 4 templates da cadência: tozi_lead_inicial (MKT), tozi_lead_followup_dia (MKT), tozi_lead_reativacao (MKT), tozi_followup_horario_combinado (UTILITY).

**Status sync de aprovação:** já existe `Channel::Whatsapp#sync_templates` + `templates_sync_job`.

**Falta:** rodar `create_templates` numa inbox Cloud API. PAULAO é WAHA (sem WABA). Prod inbox 91 (número fixo Tozi Cloud API) serve. Precisa WABA id + api_key do provider_config da inbox 91, OU rodar a rake em prod.

### [2026-05-27] Kanban de Pré-Venda Tozi + Cadência de Follow-up — 🟡 EM CONSTRUÇÃO

**Descoberta chave:** o fork chatspx JÁ TEM sistema Kanban completo e robusto — não precisa construir. Componentes existentes a reusar:
- `Funnel` / `FunnelStage` / `FunnelItem` (models) — Kanban com colunas/cards/drag-and-drop
- `KanbanBoard.vue` + `ListView` + `CalendarView` (3 visualizações prontas em `routes/dashboard/kanban/`)
- `FunnelStage.automation_type` — move card automático (hoje só open/resolved)
- **`ScheduledMessage` + `ScheduledMessages::SendJob`/`CreateService`** — base PRONTA da cadência de follow-up (envio agendado, status pending/sent/failed/cancelled)
- `Kanban::FunnelItemsBackfillService`, `MoveConversationToAutomatedStageService`

**Diagramas de design (v3):** `docs/tozi-followup-{kanban,flow}.excalidraw` + `.png`. Renderer offline: `docs/render_excalidraw_offline.py` (PIL, sem CDN — porque esm.sh está bloqueado no ambiente). Cadência definida: A (frio, 2h/24h/3d, Marketing), B (silêncio, trigger=pergunta pendente, 15min/1h/6h/24h, Service→Marketing), AGENDADO só com horário definido, 24/7 (sem horário comercial), QUALIFICADO = saída.

**Implementado hoje (PAULAO, Account 1, Inbox 1):**
- Bloco 1 ✅ — `rake spx:tozi:setup_funnel[1,1]` cria funil "Pré-Venda Tozi" (id=6) com 7 stages (automation_type: novo_lead, aguardando_1a, em_conversa, em_silencio, agendado, qualificado, frio). Idempotente, parametrizável pra prod (6,91).
- Bloco 2 ✅ — `Spx::Tozi::FunnelPlacementService` + hook no `CreateConversationService` → lead Meta entra em "Novo Lead". `rake spx:tozi:backfill_funnel[1]` colocou 45 leads existentes.

**Falta (próxima sessão):**
- Bloco 3 — `Spx::Tozi::FunnelAutomationService` (state machine): move cards por evento (incoming→em_conversa, pergunta+15min→em_silencio, cap→frio, handoff→qualificado). Hook em message_created.
- Bloco 4 — cadência via ScheduledMessages: cria mensagens agendadas (A/B) quando lead em espera, cancela pending quando responde. Reusa SendJob existente.

**Produção:** trabalho feito no PAULAO (WAHA). Em prod (Account 6, Inbox 91 = número fixo Tozi com Cloud API oficial), cadência usa templates HSM (janela 24h + categorias Marketing/Utility/Service valem). ScheduledMessage envia pelo canal da inbox → mesmo código, transparente.

### [2026-05-25] Meta Lead Ads — histórico de implementação
- **Objetivo:** webhook Meta Lead Ads → cria conversa na Inbox 1 (WAHA Tozi) → Clara assume e inicia atendimento automaticamente
- **Acesso confirmado:** Paulo tem app **Business MW (Midwest)** no Meta for Developers; página Tozi compartilhada via Lead Access; MCP Meta Marketing API já configurado (separado, não conflita)
- **Caminho escolhido:** UI manual no SPX (admin cola tokens) + webhook público. Caminho longo (Tech Provider OAuth tipo ManyChat) corre em paralelo em outra sessão.
- **Pesquisa-base:** [`Obsidian/pesquisas/meta-lead-ads-webhook-api.md`](C:/Users/paulo/Workspaces/Obsidian/pesquisas/meta-lead-ads-webhook-api.md)

**Decisões técnicas (cravadas):**
- Reusa `Integrations::Hook` (não nova tabela) — `app_id='meta_lead_ads'`, settings JSONB
- System User Token (não expira) é preferível ao Page Access Token
- Lookup por `page_id` do payload (`entry[0].id`), não slug na URL
- Verify token por hook (não global) — flexível multi-conta
- 1ª msg texto livre via WAHA por enquanto; campo `initial_message_template` no schema já prevê HSM quando migrar pra Cloud API
- OSS layer (não Enterprise overlay) — move depois se virar paga

**Estrutura a implementar:**
```
app/controllers/webhooks/meta_lead_ads_controller.rb   # GET verify + POST lead
app/services/meta/lead_ads/
  signature_verifier.rb        # X-Hub-Signature-256
  fetch_lead_service.rb        # Graph API GET leadgen_id
  create_conversation_service.rb # Contact + Conv + 1ª Message
app/javascript/dashboard/routes/dashboard/settings/integrations/MetaLeadAds.vue
config/routes.rb               # match /webhooks/meta_lead_ads via [:get, :post]
```

**Fluxo end-to-end:**
1. Lead preenche form Lead Ads (FB/IG)
2. Meta POST → `/webhooks/meta_lead_ads` → SignatureVerifier valida HMAC
3. Lookup `Integrations::Hook` por `entry[0].id` (page_id)
4. FetchLeadService busca leadgen → phone, nome, campos custom
5. CreateConversationService: normaliza phone (BR), Contact find_or_create, Conversation na Inbox alvo, 1ª Message com template renderizado
6. `message_created` callback → Captain → Clara assume

**Backend implementado (25/05/2026):**
- `config/integration/apps.yml` — entrada `meta_lead_ads` com `settings_form_schema` + `settings_json_schema` (hook_type=account, allow_multiple_hooks=true)
- `config/locales/en.yml` + `pt_BR.yml` — i18n da integração
- `config/routes.rb` — `get/post /webhooks/meta_lead_ads`
- `app/controllers/webhooks/meta_lead_ads_controller.rb` — GET (verify challenge) + POST (HMAC + enqueue job)
- `app/services/meta/lead_ads/`:
  - `signature_verifier.rb` — HMAC-SHA256 contra `app_secret` de cada hook ativo
  - `token_verifier.rb` — challenge verify_token
  - `hook_finder.rb` — lookup por page_id
  - `fetch_lead_service.rb` — Graph API v22.0 com System User Token, parse de field_data (cobre full_name/nome/phone/telefone/email/cidade)
  - `create_conversation_service.rb` — Contact via `ContactInboxWithContactBuilder` + Conversation em pending/open + 1ª Message outgoing renderizada via Liquid
- `app/jobs/webhooks/meta_lead_ads_job.rb` — processa entries.changes do payload

**Callback URL exposta** (cole no Meta Developers):
- Prod Tozi: `https://chat.simplexsolucoes.com.br/webhooks/meta_lead_ads`
- VM PAULAO: `https://paulo.chatspx.app/webhooks/meta_lead_ads`

**O que falta:**
- Frontend UI customizada (Task #10) — opcional, UI genérica já funciona via `NewHook.vue` + apps.yml. Push pra próxima sessão se quiser refinar UX (mostrar Callback URL com copy-button, botão Testar Conexão).
- Teste E2E com lead real (Task #11) — exige Paulo configurar Meta Developers + form de teste

**Setup no Meta Developers (passo-a-passo):**
1. App Business MW → Webhooks → Add Subscription (object: `page`, field: `leadgen`)
2. Callback URL: a URL acima. Verify Token: gerar string aleatória (qualquer texto), colar mesmo valor no SPX e no Meta
3. App Settings → Basic → App Secret (copiar)
4. Business Settings → System Users → criar/usar System User → Generate New Token → app=Business MW, permissões: `leads_retrieval`, `pages_show_list`, `pages_manage_metadata`, `pages_read_engagement`. **Marcar "Never expires"**
5. Subscribe page ao app: `curl -X POST "https://graph.facebook.com/v22.0/{PAGE_ID}/subscribed_apps?subscribed_fields=leadgen&access_token={SYSTEM_USER_TOKEN}"`
6. No SPX: Settings → Integrations → Meta Lead Ads → Add → preencher 7 campos
7. Testar via Meta Lead Ads Testing Tool: `https://developers.facebook.com/tools/lead-ads-testing/`

**⚠️ Atenção (gotcha conhecido):** Clara hoje tem `behavior.router.only_contact_phones = ["+5566996247866"]` (whitelist do Paulo). Pra leads reais responderem, REMOVER essa whitelist via API/console antes do teste E2E, ou Clara ignora todos os leads novos. Ver `MEMORY.md → reference-captain-v2-gotchas`.

### [2026-05-19] Captain V2 — Clara/Tozi rodando em produção (paulao)
- **Status:** E2E validado, tools nativas implementadas, follow-up + handoff + IGNORAR funcionando
- **Inbox:** 1 (Channel::Api WAHA, Account 1, `paulo.chatspx.app`)
- **VM:** `192.168.8.100` (PAULAO, hostname interno `paulo` — NÃO confundir com SENTINELA do AWS)
- **Último commit branch `paulao`:** `5db646c98` (follow-up decidido por agente + trava humana)
- **Backlog técnico (resumo):** UI editar `only_contact_phones`/`skip_groups`, UI `captain_auto_resolve_mode`, camada `app/services/spx/tozi/`, bug divergência chave OpenAI (Account.hooks vs InstallationConfig), `feature_ai_assistant_v2` bigint overflow → detalhes em `MEMORY.md → project-clara-tozi-spx`

### [2026-05-25] Sistema de memória multi-sessão Claude Code
- **Objetivo:** resolver perda de contexto entre sessões (este arquivo é a Camada 1)
- **Camadas:**
  1. ✅ `.claude/STATE.md` versionado (este arquivo)
  2. ⏳ Hook `SessionEnd` que força atualização — pendente, próxima sessão
  3. ⏳ MCP Supermemory ou Mem0 (opcional, só se Camadas 1+2 não derem conta)
- **Pesquisa-base:** `Obsidian/pesquisas/claude-code-memoria-persistente-2026.md`

---

## ✅ Decisões recentes (rolling 30 dias)

- **[2026-05-27]** Criado app **SPX Lead Ads Tozi** (id `1658426868710322`) dentro do BM Tozi (não cross-BM via Business MW). Caminho cross-BM exigia Partnership e era overhead — app no BM dono da página é mais limpo.
- **[2026-05-27]** Implementada UI de editar hook (`EditHook.vue`) — não é mais limitação do Chatwoot core, fork nosso. Vale pra todas integrações declarativas.
- **[2026-05-27]** Adicionada flag `skip_initial_message` no hook pra modo teste sem enviar msg ao lead.
- **[2026-05-25]** Adotado modelo STATE.md + hook SessionEnd como solução pra perda de contexto multi-sessão. MCP de memória semântica (Supermemory/Mem0) fica como opcional.
- **[2026-05-19]** SPX institucional (SimplexIA) usa **Meta WhatsApp Cloud API direta** (Account 3, Inbox 89, `provider=whatsapp_cloud`) — NÃO WAHA. Corrige assumption anterior.
- **[2026-05-17]** Stack escolhida pra agente IA Tozi: **Captain V2 nativo + camada fina futura** em `app/services/spx/tozi/`. Descartado tozi-agent/ Python e AIOX (meta-framework dev, não runtime).

---

## ⏳ Aguardando externos

- **Lead orgânico real** de campanha Tozi rodando → vai disparar webhook automático e criar conversa (Clara não responderá enquanto flag `skip_initial_message=true` e whitelist `only_contact_phones` estiverem ativos).
- **Paulo:** quando quiser, ampliar `only_contact_phones` da Clara + desligar `skip_initial_message` no hook.
- **(Opcional, limpeza):** deletar conversas de teste 144, 145, 146 (mesmo lead replay, source=meta_lead_ads).

---

## 📋 Backlog técnico longo-prazo

Detalhes em [`MEMORY.md`](../../../.claude/projects/C--Users-paulo-Workspaces-chatspx/memory/project-clara-tozi-spx.md):
- UI `RouterConfig.vue` editar `only_contact_phones` e `skip_groups`
- UI `captain_auto_resolve_mode` (hoje só via console)
- Camada `app/services/spx/tozi/` (debounce/humanizer/media)
- Bug divergência chave OpenAI (Account.hooks vs InstallationConfig)
- `feature_ai_assistant_v2` bigint overflow (posição 250)
- Reativar Captain auto-resolve com mensagem PT

---

## Protocolo de uso

- **Início de sessão:** Claude lê este arquivo automaticamente (via `@` no CLAUDE.md)
- **Durante sessão:** ao tomar decisão importante ou abrir frente nova, Claude adiciona aqui
- **Fim de sessão:** Claude atualiza "Em andamento" + "Aguardando externos" antes de encerrar
- **Mensal:** mover decisões >30 dias pro vault (`clientes/tozi-conversation-log.md`)
