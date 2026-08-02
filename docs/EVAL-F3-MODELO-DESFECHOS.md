# Eval 2.0 · F3 — Modelo de desfechos e autoria

> **Status:** modelo definido, não implementado. Escrito na frente `spx/eval` (30/07/2026).
> **Decisões congeladas** (não reabrir): ver `CLAUDE.local.md` da frente, § DECISÕES TOMADAS (30/07).
> **Contrato cross-frente:** a § 5 é acordo com a frente `spx/rodizio` — ler antes de codar o leitor.

---

## 0. Por que F3 existe

Hoje o juiz (`Captain::ConversationEvalService`) sabe cobrar **norma**: a IA narrou a ferramenta,
alucinou, não respondeu a pergunta. Ele nunca sabe dizer **o que converte**, porque não existe
desfecho registrado — não há com o que correlacionar a conduta.

F3 registra o desfecho de cada episódio como **fato observado**, e a autoria de quem o causou.
Com isso, "resposta curta converte mais no público Pacaembu?" vira uma query, não uma opinião.

**O juiz fica FORA do caminho do dado de conversão.** ~80% dos degraus já têm sinal determinístico
no código de hoje. O juiz só entra onde não há sinal (por que esfriou, qualidade da abordagem) —
nunca para produzir o número de conversão. Esse era o maior risco do F3 (alucinação virando
métrica) e sai de cena por construção, não por disciplina.

---

## 1. A escada

Dois eixos separados: **progressão** (ascendente, o que queremos) e **saída** (terminal).

### Progressão

| # | Degrau | O que significa |
|---|---|---|
| 1 | `respondeu` | o lead deu sinal de vida (≥1 mensagem entrante no episódio) |
| 2 | `qualificado` | tem perfil e caminho — vale o tempo de uma pessoa |
| 3 | `handoff` | passou pro humano (dossiê registrado, conversa marcada) |
| 4 | `assumido` | um humano de fato respondeu depois do handoff |
| 5 | `visita` | o corretor marcou/realizou visita — **só via Vista** |
| 6 | `venda` | negócio fechado — **só via Vista** |

### Saída

| Degrau | O que significa | Reabordagem |
|---|---|---|
| `esfriou` | pessoa real, sem fit imediato → pool de reabordagem | sim |
| `descartado` | sem perfil pra nada (`nao_qualificado`) | **não** (não gasta HSM nem tempo) |

> A distinção `esfriou` × `descartado` não é cosmética: é o modelo quente/frio já decidido em
> 16/07 — um mis-gauge de renda cai no pool frio, não some. Colapsar os dois em "perdido"
> destruiria justamente a informação que protege contra o erro de enquadramento.

### O corte da conversão

**Conversão = `qualificado` + `assumido` com a IA tendo atendido antes.** Os degraus 1–4 são do
SPX; os degraus 5–6 são do Vista e entram como **camada externa** (§ 4).

O corte para em `assumido` porque é até aí que **a IA de fato controla**. Visita e venda dependem
do corretor: incluí-las mede o time comercial, não o atendimento.

> **Decidido em 31/07 com dado, não no papel.** O corte original era `qualificado + handoff`. O
> dry-run rodou os dois lado a lado na conta 6 (499 episódios): **A = 23,4% · B = 24,2%** —
> praticamente idênticos. `handoff` só existe onde o F2 gravou a tool (403 dos 499 episódios não
> tinham tool call nenhuma), então seria refém permanente da cobertura do F2; `assumido` vem de
> mensagem + log `human_takeover`, duráveis. Escolher o durável não custou precisão.
>
> **O qualificador não é opcional.** `assumido` sozinho contaria atendimento que sempre foi humano
> como conversão da IA — e ele é a MAIORIA: dos 342 assumidos, **248 eram só-humano**. Por isso o
> filtro autoritativo é o scope `conversao` do model, e não a constante `DEGRAUS_CONVERSAO` (que
> serve só pra marcar os degraus na tela).

---

## 2. Detecção — sinal por degrau

Tudo abaixo já existe no código de hoje. Nenhuma tool nova, nenhuma chamada de LLM.

| Degrau | Sinal | Onde está |
|---|---|---|
| `respondeu` | ≥1 `message` `incoming` na janela do episódio | `Captain::ConversationEpisode#first_message_id..last_message_id` |
| `qualificado` | `custom_attributes['tozi_status_lead'] ∈ {qualificado, convertido}` **ou** `FunnelItem` no estágio `qualificado` | `SalvarInfoLeadTool` · `Spx::Tozi::FunnelPlacementService` |
| `handoff` | `Captain::ToolCall` de `handoff`/`transferir_para_agente` — **só onde o F2 gravou** | F2 |
| `assumido` | 1ª `outgoing` com `sender_type = 'User'`, qualificada por "a IA atendia antes?" | `messages` + log `human_takeover` |
| `esfriou` | status ∈ `{esfriado, perdido}` **ou** estágio `frio` | `SalvarInfoLeadTool#move_funnel_by_status` |
| `descartado` | status `nao_qualificado` **ou** label `nao-qualificado` | idem + `add_labels` |
| `visita` / `venda` | etapa do card no Vista | § 5 (leitor) |

**Regra de ouro:** o degrau é gravado quando o sinal aparece, com o `ocorreu_em` do sinal — nunca
inferido retroativamente por leitura de transcrição.

### ⚠️ O que o dry-run de 30/07 (conta 6, 500 episódios) derrubou

A v1 deste modelo detectava `handoff` por `custom_attributes['aguardando_humano_desde']`. **Estava
cega:** nas 349 conversas analisadas, 287 tinham assignee humano e 322 tinham mensagem de um humano
— e o detector achou **zero handoff**. Duas causas, ambas do produto e não do eval:

1. **`aguardando_humano_desde` é TRANSITÓRIO.** É um "está aguardando", limpo quando o humano
   assume — 2 conversas em 20.170 o têm agora. Nunca foi registro histórico.
2. **AssistantLog `handoff` nunca é escrito.** O event_type está declarado em
   `Captain::AssistantLog::EVENT_TYPES`, mas `HandoffTool` chama `log_tool_usage`, que só escreve
   em `Rails.logger` e **não cria registro**. Constante morta desde sempre.

Consequência de modelo: **o degrau durável é o `assumido`, não o `handoff`.** A intenção da IA de
passar o bastão só é reconstituível onde o F2 gravou a tool; o fato de um humano ter assumido é
detectável sempre, pela mensagem.

`assumido` sozinho não serve de conversão — atendimento que sempre foi humano entraria como
crédito da IA. Por isso ele carrega `detalhe['ia_atendia_antes']`, respondido pelo log
`human_takeover` (que o `log_captain_mirror_transition` só emite quando o espelho captain **estava**
na conversa, logo já prova que a IA atendia) ou pela varredura das mensagens anteriores.

> ✅ **RESOLVIDO pela `spx/rodizio` em `0f320f967` (31/07).** O `HumanHandoffService` passou a
> escrever `Captain::AssistantLog` com `event_type: 'handoff'` — e ficou no **service**, não no
> tool, porque o service é a fonte única dos 6 call sites (tool, transferência entre agentes,
> escalada do follow-up, safety-nets do `ResponseBuilderJob`). O `handoff` **é degrau durável a
> partir dessa data**, e este serviço lê o log como evidência principal, usando a `ToolCall` só
> pra discriminar autoria (com tool = a IA pediu; sem tool = sistema).
>
> ⚠️ **Duas ressalvas que não somem com o fix:**
> - **O evento nasceu em 31/07.** `handoff` = 0 antes disso é ausência de instrumento, não de
>   comportamento. Nunca compare pré×pós como mudança de conduta.
> - **Ainda não está em produção.** Verificado em 02/08: `0f320f967` **não é ancestral** do que a
>   VM roda (`f542675b7`). Até deployar, prod segue sem evento durável de handoff.

> ✅ **Suspeita DESCARTADA (31/07):** cheguei a suspeitar que o `EpisodeSegmenterService` tivesse
> o mesmo erro de enum (comparar `message_type` com inteiro sobre valor de `pluck`). **Não tem.**
> O dry-run v2 mostrou as fronteiras disparando na conta 6 — `gap 10085 · resolve 1653 ·
> hsm_campanha 218`. O F1 normaliza corretamente; **não mexer nele**.

---

## 3. Autoria

`causado_por` ∈ `ia` · `humano` · `sistema` · `contato` · `externo`. Deriva do sinal, não de
julgamento:

- **`ia`** — existe `Captain::ToolCall` com a tool correspondente (`salvar_info_lead`, `handoff`,
  `transferir_para_agente`) na janela do degrau. É prova direta: a IA chamou a ferramenta que
  produziu o fato.
- **`humano`** — o fato existe mas não há tool call da IA (um atendente moveu o card na mão —
  `FunnelItem#moved_by_id`), ou o degrau é `assumido`. Grava `ator_id` = `user_id`.
- **`sistema`** — job/automação (fallback do `ResponseBuilderJob`, escalada do `FollowupJob`).
- **`contato`** — o próprio lead. Só o degrau `respondeu`; forçá-lo em `externo` corromperia o
  eixo, que reserva `externo` pro CRM.
- **`externo`** — veio do Vista. O SPX **não sabe** quem causou; sabe apenas a qual episódio
  atribuir. Rotular isso honestamente é o que impede a camada externa de virar crédito da IA.

> **Correção descoberta ao implementar:** o marcador `aguardando_humano_desde` é escrito **só**
> pelo `HumanHandoffService`, chamado de quatro lugares — `HandoffTool`,
> `TransferirParaAgenteTool`, fallback do `ResponseBuilderJob` e escalada do `FollowupJob`.
> **Nenhum caminho humano escreve esse atributo.** Logo a autoria do degrau `handoff` é sempre
> `ia` (pediu via tool) ou `sistema` (fallback/escalada) — **nunca `humano`**, como este doc
> supunha na primeira versão.

O eixo é o mesmo que o painel já usa em `findings_stats` (`ia`/`humano`) — o drill-down do F4.1
funciona sem mudança conceitual.

---

## 4. Onde grava — e por que não é coluna

Tabela nova: **`captain_episode_outcomes`**. Uma linha **por degrau atingido**, não uma coluna de
estado.

```
account_id, conversation_id, episode_id
degrau         respondeu|qualificado|handoff|assumido|visita|venda|esfriou|descartado
causado_por    ia|humano|sistema|externo
ator_id        user_id (humano) · assistant_id (ia) · nil
origem         tool|funnel|label|mensagem|vista
detalhe        jsonb  {tool_call_id, status_lead, stage, etapa_vista, ...}
ocorreu_em     datetime
-- denormalizado NO MOMENTO DO REGISTRO:
campanha, anuncio, publico, empreendimento, lead_tipo
unique (episode_id, degrau)
```

Três razões para tabela separada, cada uma sozinha suficiente:

1. **Fato ≠ opinião.** O eval é veredito reprocessável (`spx:eval:reprocess`). Se o desfecho morar
   no eval, re-julgar apaga fato. Desfecho é observação; veredito é leitura.
2. **Desfecho tem tempo próprio.** O episódio fecha hoje; o corretor move o card daqui a cinco
   dias. Coluna no episódio obrigaria a mutar um registro fechado e perderia a linha do tempo —
   que é justamente o que responde "quanto tempo entre handoff e assumido".
3. **Escada é N degraus, não 1 estado.** Precisamos de *"qualificado 14h02 pela IA · handoff 14h09
   pela IA · assumido 15h30 pelo Lucas"*. Uma linha por degrau resolve; uma coluna força escolher
   um só e perder o resto.

**A denormalização de campanha/anúncio/público/empreendimento é obrigatória.** Esses campos vivem
em `conversation.custom_attributes` (carimbados pelo Meta Lead Ads: `meta_campanha`, `meta_anuncio`,
`meta_publico`, `meta_tipo`, `meta_imovel`) e **mudam**. Métrica histórica não pode mudar de valor
retroativamente porque alguém reetiquetou a conversa.

> ✅ **Verificado em 02/08 — a atribuição por campanha NÃO usa `campaign_id`, e isso a salva.**
> Existem dois motores de disparo e o `campaign_id` da conversa é furado nos dois (o
> `RecipientDispatchService` só grava se estiver nulo — bug "grudento" no BACKLOG; o
> `Spx::Tozi::DisparoLeadJob` tem `campaign_id: nil` por default e o rake não passa). Medido: 1 de
> 152 conversas amostradas tem `campaign_id`.
>
> O F3 lê **`custom_attributes['meta_campanha']`**, escrito num lugar só —
> `meta/lead_ads/create_conversation_service.rb:152`, a partir do `campaign_name` que a Meta
> devolve. **Nenhum errata é necessário:** PACAEMBU 60% × RMKT 37% mediram o que diziam medir.
>
> **A ressalva é de população, não de correção:** o corte por campanha só enxerga conversa criada
> pelo webhook do Meta Lead Ads. Conversa de disparo não tem `meta_campanha` e cai em
> "(sem campanha)". Isso mantém a comparação PACAEMBU × RMKT limpa (mesmo canal de aquisição, o
> mesmo carimbo), mas ela fala de um **subconjunto** do tráfego da conta — não do todo.

> ⚠️ **Gap encontrado ao implementar: `empreendimento` NÃO é carimbado na conversa.** Ele só existe
> no `template_render_context` do `CreateConversationService` (linha ~529), consumido pelo opener e
> descartado — vem do `hook_setting('empreendimento')` do override de campanha. A coluna fica no
> lugar e é preenchida se o atributo aparecer, mas **hoje nasce vazia**. Até alguém carimbá-lo, o
> corte por empreendimento sai por `campanha`/`anuncio` (que carregam o nome: `FORMS-ETNA`,
> `[FORMS] - ACQUA`, Pacaembu). Carimbar é mudança de uma linha no `stamp_campaign_visibility` —
> mas é código de outra frente (meta lead ads), então fica anotado, não corrigido aqui.

### Traços de conduta (o outro lado da correlação)

Desfecho sozinho não responde nada — precisa do traço da conduta que o produziu. Todos
determinísticos e baratos, **colunas em `captain_conversation_episodes`**:

`turnos_ia` · `turnos_cliente` · `chars_resposta_media` · `ferramentas_usadas` · `enviou_midia` ·
`duracao_segundos` · `campanha`

Moram no episódio (e não em tabela própria) porque são 1:1 com ele, imutáveis depois que fecha e
da mesma natureza do `mensagens`, que já vivia ali. O `EpisodeSegmenterService` atribui uma lista
explícita de colunas, então re-segmentar não os apaga.

> **Por que `campanha` também no episódio, se já vai em cada linha de desfecho.** A unidade da
> análise tem de ser o **episódio**, não a linha de desfecho: um episódio onde o lead nunca
> respondeu não atinge degrau nenhum e portanto **não tem linha em `captain_episode_outcomes`**.
> Se a segmentação por campanha dependesse da linha de desfecho, esses episódios sumiriam da
> conta — e eles são exatamente o denominador de *"o opener funcionou?"*. Com a campanha no
> episódio, a taxa de conversão tem denominador honesto.

Cruzados com `degrau` e segmentados por `campanha`, respondem a pergunta que originou o F3:
*"no público Pacaembu, episódio com resposta média mais curta chega a handoff com que
frequência?"* — hoje impresso por `spx:eval:outcomes`, e no painel no passo 3.

---

## 5. Camada externa — o leitor do Vista

> **Contrato com `spx/rodizio`.** A `rodizio` **escreve** `vista_negocio_codigo` na conversa ao
> criar o card. Esta frente **constrói o leitor**. É **um leitor só**, com dois consumidores.

### O guard-rail (não pode cair)

O corretor não alimenta o CRM com disciplina. Se "card parado" entrar na métrica primária, o painel
passa a medir **disciplina de CRM do corretor**, não qualidade de atendimento.

Portanto, e isto é regra de implementação, não convenção:

- degraus `visita`/`venda` gravam sempre `origem = 'vista'` e `causado_por = 'externo'`;
- **o agregador de conversão filtra `origem != 'vista'` por padrão** — não é toggle, é o default;
- o dado do Vista aparece em seção própria e rotulada ("CRM Vista"), nunca somada;
- o Vista serve para **correlação e atribuição**, jamais para julgar a IA.

### O job

Periódico, varre **apenas** conversas com `vista_negocio_codigo` presente (volume baixo — só lead
com handoff). Read-only: **não escreve nada no Vista**. Sem webhook.

### Campos a gravar em `conversation.custom_attributes` — proposta

| Campo | Conteúdo | Quem consome |
|---|---|---|
| `vista_negocio_codigo` | código do card (**escrito pela `rodizio`**, eu só leio) | ambos |
| `vista_pipe` | 3 = vendas · 4 = locação | eval |
| `vista_etapa` | nome da etapa atual | ambos |
| `vista_etapa_codigo` | código (PROSPECTO 67 · CONTATO 73 · …) | ambos |
| `vista_etapa_desde` | data da última mudança de etapa | **rodizio** (SLA) |
| `vista_corretor` / `vista_corretor_codigo` | corretor responsável | ambos |
| `vista_motivo_perda` | motivo, quando perdido | eval |
| `vista_lido_em` | timestamp da última varredura | ambos (frescor) |

### Os dois consumidores

- **eval (F3):** fecha a escada — `visita`/`venda` como degraus externos + atribuição do card ao
  episódio que o gerou.
- **rodizio:** `vista_etapa_desde` mudou ou etapa avançou de PROSPECTO = **"o corretor engajou"** →
  Sofia entra em silêncio. Mesmo campo vira base do **SLA de vendas** (tempo parado na etapa).

### ⚠️ Gotcha que muda o desenho — `data da última mudança de etapa`

O endpoint natural para isso, `GET /negocios/atividades`, **tem bug conhecido**: retorna formato
colunar com arrays de tamanhos diferentes (vault, `clientes/tozi-vista-capacidades.md`). Não dá
para confiar nele.

Três saídas, em ordem de preferência:

1. **Probe primeiro:** verificar se `GET /negocios/detalhes` já traz um campo de data de alteração
   de etapa. Se trouxer, acabou — é o dado real.
2. **Workaround do vault:** reconstruir via `historicos_do_cliente()` cruzando `DataInicial`/
   `DataFinal`. Funciona, mas é caro por card.
3. **Derivar por diferença entre varreduras:** o leitor guarda a etapa anterior e carimba a data
   quando ela muda. Robusto e barato, **mas mede "quando nós notamos", não quando aconteceu** — e
   só tem resolução a partir do dia em que o leitor liga.

**A opção 3 é aceitável para o eval** (correlação tolera ruído de horas) e **arriscada para o SLA
da `rodizio`**, que conta tempo contra o corretor. Se o probe (1) falhar, a `rodizio` precisa saber
que o SLA nasce com a resolução do intervalo de varredura.

### O que precisa de acordo antes de codar

1. Os nomes de campo da tabela acima — em especial `vista_etapa_desde`, que é o insumo do SLA.
2. Quem grava `vista_negocio_codigo` e em que momento exato (na criação do card, presumo).
3. Resultado do probe do item 1 do gotcha — decide de onde vem a data de etapa.

---

## 6. Ordem de implementação

1. ✅ **`captain_episode_outcomes` + degraus determinísticos do SPX** (`respondeu`, `qualificado`,
   `handoff`, `assumido`, `esfriou`, `descartado`). Commit `b7c221406`.
2. ✅ **Traços de conduta por episódio** + cruzamento conduta × desfecho por campanha impresso
   pela `spx:eval:outcomes`.
3. ✅ **Seção "Desfecho" no painel F4**: taxa de conversão, escada com split de autoria, tabela
   conduta × desfecho e o corte por campanha. Seção some sozinha enquanto não houver dado
   (o `desfechos` do controller devolve `{}` em qualquer erro, inclusive migration ausente).
4. ⬜ Leitor do Vista (§ 5) — depende do acordo com a `rodizio` e do card existir.

Os passos 1+2 respondem à pergunta pela linha de comando; o 3 leva a resposta pro painel. O 4
acrescenta o degrau externo e é o único que depende de outra frente.

> **⚠️ Nada disto foi executado.** Não há Ruby no ambiente onde o código foi escrito (nem WSL):
> `ruby -c`, RuboCop, migration e rake seguem **pendentes de verificação** numa box com Ruby. As
> premissas de associação foram conferidas estaticamente uma a uma contra o código existente. O
> `record_f3_facts` do `EpisodeEvalJob` é best-effort (`rescue StandardError`), então código no ar
> sem a migration degrada pra warning no log em vez de derrubar o julgamento.
