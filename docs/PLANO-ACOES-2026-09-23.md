# Plano de ações — varredura de 23/09/2026

> Levantado com leitura **somente-leitura** da produção Tozi (`3.94.9.51`, conta 6) e do repositório.
> Cada ação tem **evidência**, **tamanho** e, quando existe, a **decisão do Paulo** que a destrava.
> **Nada aqui foi executado.** Documento para discutir ação por ação.

## Legenda de tamanho

| | Significado |
|---|---|
| **P** | até ~30 min |
| **M** | até ~1 dia |
| **G** | vários dias / é um módulo |
| **D** | é **decisão**, não execução — não tem timebox |

---

# Bloco 0 — ~~Destrave imediato~~ · RESOLVIDO SOZINHO

## A1 · ~~Reiniciar a VM Tozi PROD para liberar 5 PRs pulados~~ — ✅ não existe como ação

**Eu propus esta ação por não conhecer o mecanismo. O Paulo corrigiu: a VM reinicia todo dia às
20h.** Conferido na box e confirmado:

```
chatwoot-restart-noturno.timer
  OnCalendar=*-*-* 20:00:00 America/Cuiaba
  Persistent=false      # "se a VM estava fora as 20:00, o boot ja subiu o codigo novo"
  Description=Restart noturno do SPX (web e workers, nunca a VM)
```

Os 5 PRs que eu vi "no disco e não rodando" (#246 EA-01, #219 t45, #220 t04, #221 t05, #236 tema)
**subiram às 20h de 23/09**: `chatwoot-web.1` e `chatwoot-worker.1` com
`ActiveEnterTimestamp = 2026-09-24 00:00:13/00:00:15 UTC` = **23/09 20:00:13 Cuiabá**, e
`HEAD = 501d10eb0` (#236, o último dos cinco). O que eu medi era uma **janela** entre o pull e o
restart noturno, não um defeito.

> **O que fica desta correção, e é útil para planejar:** não existe passo de deploy manual na VM da
> Tozi. A cadência é **mergeado e puxado antes das 20h → no ar naquela noite**. O `OnCalendar` está
> declarado com `America/Cuiaba` explícito, então não repete o bug do `cron-digest-7h` ("o digest
> saía às 11h, não às 7h — o cron é do fuso do processo").
>
> **Consequência para a medição do P0:** o restart de `2026-09-23 00:00:09 UTC` que eu chamei de
> "deploy de 22/09 20h" era **este mesmo timer**. A conclusão segue valendo — o P0 (#226, mergeado
> 22/09 14:29 Cuiabá) entrou no ar no restart daquela noite —, mas o mecanismo é o timer, não uma
> ação humana.

**Tamanho:** — · **Decisão:** nenhuma.

---

# Bloco 1 — Dinheiro parado

## A2 · Decidir a conduta MCMV — transferir cedo ou seguir qualificando

**É a ação de maior retorno da lista.** Não é código: é decisão.

**Evidência.** Dos 45 chamados abertos que o juiz do eval marcou como *"exigia humano e ninguém
passou"*, **cerca de 25 são leads de anúncio MCMV / "entrada facilitada"** — IDs 51xxx a 54xxx,
**22 a 31 dias parados**, **sem assignee**, com o mesmo enredo: a IA qualificou em profundidade e deu
condição comercial em vez de transferir. Notas do juiz entre 1 e 5.

Casa com o item já registrado no `BACKLOG.md`: *"🟡 Simulação de financiamento na conduta MCMV —
parado por decisão"*. **A decisão parada está custando leads há um mês.**

**Tamanho:** D · **Decisão:** qual regra vale — transferir ao primeiro sinal de compra, ou qualificar
antes? E a IA pode ou não falar de condição/financiamento?

## A3 · Repescar o que já está parado

**Evidência.** Conta 6: **2.543 conversas abertas**. **700 com o cliente falando por último** — 43 há
menos de 24h, 60 entre 1 e 7 dias, **335 entre 7 e 30 dias**, **262 há mais de 30**. E **486 handoffs
(34,2% de 1.421 em 30 dias) ninguém assumiu**; 96 dessas conversas seguem abertas.

Os mais quentes com resposta pendente: `#24610` Sandra (pós-venda, nota 3), `#63748` Renato (locação,
**pediu explicitamente falar com humano**), `#19755` Silvya (reclamação **sinalizando
judicialização**, nota 2), `#41046` Pablo (reclamação **sem nenhuma resposta**, nota 1).

**Tamanho:** M (a lista existe; o trabalho é operacional, do time) · **Decisão:** quem assume a
repescagem e com que corte de idade.

---

# Bloco 2 — Vista: o pedido novo da Tozi

> **O achado que muda o desenho:** o Vista tem **duas camadas separadas**, e o pedido da Tozi se
> parte nelas.
>
> | | Endpoint | Precisa corretor? | O que é |
> |---|---|---|---|
> | Lista de leads | `POST /clientes/detalhes` | **não** | cadastro do lead. Bucket `Corretor #20 = "Tozi Imóveis Lead"` para lead sem dono |
> | Card do pipeline | `POST /negocios/detalhes` | **sim** | `CodigoPipe` (3 = vendas, 4 = locação) + `EtapaAtual` + `CorretorNegocio` |
>
> O `VistaCardService` já implementa as duas em sequência (`garantir_cliente` → `criar_negocio`).

## A4 · Desacoplar o cadastro do lead do rodízio

**O problema.** As duas camadas estão atrás do mesmo portão:

```ruby
def perform
  return unless @policy.espelho_vista?        # ← trava as DUAS
  ...
  corretor = vista_corretor
  return pular('pool sem vista_corretor')     # ← só a camada 2 precisa disto
```

E o serviço só é chamado de dentro do `DistribuirService`. Resultado: **para cadastrar um lead na
lista do Vista hoje é preciso ter o rodízio ligado, com pool preenchido e corretor mapeado** — o que
não é verdade no Vista, onde a lista de leads não tem dono.

**O que muda.** A camada 1 passa a ter gatilho próprio, independente do rodízio: todo lead de venda
entra na lista do Vista. Fecha o buraco que o vault registrou — *"leads do SPX (form Pacaembu/RMKT)
não aparecem no Vista, só via Cibele manual"*.

**Tamanho:** M · **Decisão:** o gatilho é a **entrada** do lead de venda, ou a **qualificação**?

## A5 · Card no pipeline a partir da qualificação

**O gancho já existe.** `salvar_info_lead(status: qualificado)` grava `degrau: qualificado` no
`Captain::EpisodeOutcomeService`. Não precisa inventar sinal.

**O que falta, e é config, não código:** `CodigoPipe`, `EtapaAtual` e o mapeamento
`user_id → vista_corretor`. Hoje `policy.vista_padrao = {}` e `distribuicao_produtos` da conta 6 tem
**0 linhas**.

**⚠️ Dois riscos a nomear antes de ligar:**

1. **Não existe desfazer.** O DELETE do Vista responde 401. Card no corretor errado é permanente. E,
   medido em 23/09, ~25 qualificações do cluster MCMV foram reprovadas pelo próprio juiz — ou seja,
   "todo e qualquer lead qualificado vira card" hoje criaria cards permanentes a partir de
   qualificações ruins.
2. **Contrato não validado.** O aviso está no próprio serviço: *"CONTRATO EMPÍRICO: o Vista não
   publica catálogo de campos... validar antes de ligar `espelho_vista` em produção"*. **Nenhum card
   foi criado por este serviço até hoje.**

**Mudança de processo, não só técnica.** Vault (23/07): a Cibele escreve uma nota e encaminha ao
corretor — **ela não cria o card; quem cria o negócio e move as etapas
(PROSPECTO→CONTATO→QUALIFICAR) é o corretor**. O pedido da Tozi transfere isso para o SPX.

**Tamanho:** M (código) + D (processo) · **Decisão:** (a) ligar o rodízio de vendas para haver
corretor; (b) card num corretor/pipe default e o Vista atribui depois; ou (c) card só quando a
qualificação passar por um gate de qualidade.

---

# Bloco 3 — Medição: o que destrava todo o resto

## A6 · Abrir o PR do harness offline nível 1 + CI

**Onde está.** `origin/fix/resultado-tipado-de-tool` — **30 arquivos, 7.614 linhas, sem PR**. Contém
o motor (`nivel1/roteiro.rb`, modelo roteirizado, zero LLM), o CI
(`.github/workflows/harness_offline.yml`), 4 fixtures de conversa real gravadas (foto fantasma, par
preço/link, condomínio/finalidade, preço sem busca), pseudonimizador e guarda de vazamento.

**Risco:** baixo. É infra de teste, não muda comportamento de produção.

**⚠️ Atenção no tracker:** `CHAT-109` está **"Concluído"**, mas o harness **não tem PR e não está em
`producao`**. O tracker afirma entregue o que o código diz que não foi.

**Duas armadilhas já documentadas:** o CI precisa de `db:schema:load` (nunca `db:prepare`, que roda
seed e estoura ~30 specs de Captain com `PG::UniqueViolation`); e o portão roda
`--tag ~defeito_aberto`, porque suíte permanentemente vermelha vira ruído e o vermelho novo passa
junto com os velhos.

**Tamanho:** P (o trabalho está feito; falta PR + merge).

## A7 · Re-medir o baseline de conduta, agora que o P0 está no ar

**Por que agora.** O baseline dos 10 cenários foi medido em **21/09, antes do P0**. O P0 subiu em
**22/09 20h** (Cuiabá). Dá para responder a pergunta que o piso não responde: *"PIOROU?"*.

**Contexto do baseline congelado:** 2 dos 10 cenários estavam **abaixo do próprio piso** (visita em
condomínio 4/6 e taxa de condomínio 4/6, piso 5) — ou seja, o código no ar não cumpria os pisos de
forma estável já antes do P0.

**Tamanho:** M · **Depende de:** A6.

## A8 · Abrir o PR do FactGuard em sombra e dar a ele um leitor

**Onde está.** `origin/PauloSeze/factguard-shadow` — **34 arquivos, 1.569 linhas, sem PR**.

**Gate por conta:** `assistant.account.custom_attributes['captain_fact_guard_shadow'] == true`,
**false por default**. Em sombra ele emite telemetria com `decision: 'would_block'` e **nunca
aplica** — o comentário no código é explícito: *"callers never enforce its verdict"*.

**Três passos:** (1) PR + merge — seguro, porque com a flag desligada o comportamento é byte a byte o
de hoje; (2) ligar a flag na conta 6 para coletar; (3) **um lugar para ler a telemetria**.

**O passo 3 é o que ninguém fez, e é a doença central:** o eval já produz e ninguém consome — 583
`contradisse_tool` e 311 alucinações em 30 dias parados no painel. Ligar o FactGuard sem leitor
repete o mesmo erro com um instrumento novo.

**Tamanho:** P (1 e 2) + M (3).

## A9 · Revisão amostral humana — a peça que falta no ciclo

**O que é.** Uma tela que apresenta conversas encerradas para alguém marcar em dois cliques
(boa / ruim / merecia humano) com lista curta de motivos, gravando **quem** marcou e **quando**. É ela
que transforma *"acho que piorou"* em número e gera o dataset que calibra o eval — que hoje dá nota
sem ninguém saber se a nota está certa.

**Os números mudaram o desenho: não é sorteio, é censo.** Com 321 episódios encerrados por dia e o
juiz já opinando em 305, sortear 20 tem chance quase nula de cair no caso que importa. Os baldes onde
a falha pode morar são pequenos o bastante para revisar **100%**:

| Balde | 30 dias | por dia | Como |
|---|---|---|---|
| `precisava_nao_fez` + `tardio` | 136 | 4,5 | censo |
| `funil: frio` com agente de IA atribuído | 75 | 2,5 | censo |
| degrau `descartado`/`esfriou` gravado por IA | 21 | 0,7 | censo |
| controle cego — aleatório de atendimento real | — | ~8 | amostra |

≈ **15 itens/dia**, ~80s cada. O controle cego não é opcional: sem ele você só olha onde já
desconfia e nunca descobre o viés.

**O que a medição de 23/09 provou.** Os 21 episódios em que a IA registrou descarte foram todos
avaliados pelo juiz e receberam **nota média 8,52**, com **zero `precisava_nao_fez`**. E das 1.822
conversas que terminaram `frio`, o juiz disse `nao_precisou` em **1.788 (98%)**. **A oportunidade
perdida entra hoje como uma linha com nota 8,5** — não é que nenhuma medição pegaria, é que a medição
olhou e aprovou.

**Tamanho:** M (desenho) + G (implementação) · **Duas decisões:**

1. **O nome do rótulo.** São dois julgamentos diferentes e só um é possível hoje: *"merecia humano e
   não teve"* é julgável pela transcrição; *"o negócio se perdeu"* exige o desfecho, e o desfecho não
   volta — o próprio código do `EpisodeOutcome` decidiu não confiar no Vista para isso: *"o corretor
   não alimenta o CRM com disciplina"*. Misturar os dois no mesmo rótulo calibra o eval contra ruído.
2. **Quem clica** — você ou o time da Tozi. Muda o modelo de dados (identidade do revisor) e o perfil
   de viés: se o cliente rotula, entra a prescrição dele.

---

# Bloco 4 — Conhecimento das IAs

## A10 · `knowledge_mode=hybrid` apontando para base vazia em 6 dos 9 agentes

**Evidência.** Conta 6:

| Agente | docs | knowledge_mode |
|---|---|---|
| Júlia | 20 | hybrid |
| Sofia | 3 | hybrid |
| Clara | 1 | — |
| **Bruna** | **0** | **hybrid** |
| **Letícia** | **0** | **hybrid** |
| **Marina** | **0** | **hybrid** |
| **Rafa** | **0** | **hybrid** |
| **Helena** | **0** | **hybrid** |
| Feirão | 0 | faq *(correto para zero docs)* |

A Bruna sozinha faz **4.188 mensagens/30d** em locação, e o prompt manda consultar a base antes de
afirmar. **Regra dura apontando para fonte vazia produz preenchimento** — o modelo não tem de onde
tirar e inventa.

**Tamanho:** P (trocar o modo) ou M (popular a base) · **Decisão:** para cada um dos 5, o certo é
mudar o modo ou alimentar a base?

## A11 · Rodar o render e o lint do prompt nos 9 agentes

**Por que.** A auditoria contou **951 frases-regra e 7 contradições** só no template comum. Uma delas
— o ping de espera — **já custou 16h de silêncio com cliente real**.

**Importante:** cada contradição exige **decisão sua** sobre qual regra fica. Eu não escolho.

**Tamanho:** M · **Ferramenta:** a skill `prompt-camadas` já existe para isso.

## A12 · Inventário de ferramentas por agente

**O que confirmar:** quantas tools simultâneas por turno (o levantamento aponta Júlia com 18);
quantas descrições dizem **quando NÃO usar** (13 de 29 não dizem); `faq_lookup` (71 chars, em inglês)
e `search_knowledge` (99 chars, em inglês) são as piores descrições **e** as que o template designa
como fonte factual primária; sobreposição `buscar_localizacao` × `buscar_lugar`.

**Nota:** a conta 6 tem **2 custom tools** (o levantamento dizia 1) — o número precisa ser refeito
pelo render, não pela contagem de tabela.

**Tamanho:** M.

## A13 · Base de conhecimento × FAQ × tool

**A hipótese a testar:** FAQ e base são portas paralelas para a mesma pergunta, difíceis de manter e
propensas a divergir; boa parte deveria viajar junto do retorno de uma tool que já vai acontecer.

**Evidências já levantadas:** `buscar_unidades` com 1 chamada em 30 dias contra 52 convites ao
escritório em 45 dias; `search_knowledge` trunca 84,6% e `buscar_empreendimento` 58,8%; Playbook,
tabela ETNA e Fronteira MCMV duplicados; endereço e horário em FAQ, unidade e guarda ao mesmo tempo;
`assistant.liquid:46` manda usar só as FAQs e **contradiz** as instruções que mandam consultar a
tool.

**Entrega:** classificar o conteúdo em **dado vivo** (tool), **processo previsível** (anexado ao
retorno de uma busca) e **processo raro** (consulta única).

**Tamanho:** M.

---

# Bloco 5 — Campanhas

> **Correção de leitura minha.** O motor **não** parou no teste: `campaign_recipients` tem **24.110
> linhas** e a campanha #29 ("Mega Feirão — base completa") disparou **13.391 destinatários em 21
> minutos** em 08/09. As 10 campanhas "TESTE" eram o ensaio dela. **24.575 de 41.859 conversas** têm
> `campaign_id`. O que falta é **superfície de controle**, não motor.

## A14 · Abrir o PR de `spx/disparo-guarda` — já está pronto

4 commits em `origin/spx/disparo-guarda`, não mergeados: confirmação mostrando a mensagem antes de
disparar, a tela sabendo dizer que deu errado, preview preso por teste, segmento por campanha
respeitando o canal, e `Select` aceitando `id`/`aria-label`.

**É o PR mais barato da lista.** **Tamanho:** P.

## A15 · UI "Novo disparo"

**Dói.** Iniciar um disparo hoje é subir CSV para `/home/chatwoot/` e rodar
`rake spx:tozi:disparo[...]` por SSH. Inviável para o time operar.

**Escopo:** upload de CSV, multiselect de corretores e de templates (com rotação decorrelacionada),
slider de pacing, preview da audiência limpa (dedup + blacklist na hora). Reusa o motor existente.

**Tamanho:** G — é um módulo.

## A16 · Controle do disparo: pausar, retomar, redistribuir

Hoje é 100% console: pausar foi `Sidekiq::ScheduledSet ... j.delete`; retomar, re-enqueue com dedup;
trocar corretor, script. Nada tem botão.

**Tamanho:** M.

## A17 · `campaign_stats` agregando por `campaign_recipients`

Hoje agrega por `@campaign.conversations`, que é **origem**. Com a semântica de origem, a 2ª campanha
sobre a mesma base **subnotifica**. Cruza com a P5.1 (N+1 + full-scan) e vale fazer junto.

**Tamanho:** M.

**Menores, do mesmo bloco:** tela de detalhe estática (P) · falhas sem drill-down (M) ·
`Meta::LeadAds::CreateConversationService` ainda monta `template_params` inline em 2 pontos (P) ·
matriz corretor×template invisível na UI (P).

---

# Bloco 6 — Rodízio: reconciliar as duas metades

> Já existe a tarefa **CHAT-125** ("Rodízio + IA: levantar tudo que falta") — esta ação é o **conteúdo
> dela**, não uma tarefa nova.

**Não são dois rodízios: é um motor só, e duas metades com autores e datas diferentes.**

```
app/{models,services,jobs,listeners}/spx/distribuicao/
  13 commits  Paulo Seze     01/07 → 30/07/2026
   6 commits  Nicolas Silva  16/09 → 17/09/2026
   7 commits  simplex        setembro/2026
```

| | A metade do Paulo (julho) | A metade da Catatau (setembro) |
|---|---|---|
| **Decide** | **quem merece** o lead | **quando tirar** o lead de alguém |
| Eixo | produto → corretor → Vista | SLA → repasse → guarda de dono |
| Peças | `distribuicao_produtos`, `resolver_produto_service`, `pool[].produtos[{produto, valor_max}]`, `espelho_vista`, `vista_card_service`, `modo_posse: designacao`, `continuidade_dias: 30` | `guarda_de_dono`, `repasse_service`/`repasse_job`, `referral_team_routing_service`, `sla_assumir_minutos`, `max_repasses`, `pool_esgotado_destino`, `horario`, `modo: fila` |

**Os incidentes que geraram a metade da Catatau** (todos com data e conversa):

- **15/09** — cliente voltando ao menu chamava o Motor de novo e **queimava a vez de 5 vendedores em
  5 minutos**; e o lead que alguém já atendia ia para outro, porque *"em vendas se responde SEM
  assumir a conversa, e o Motor só enxergava `assignee`"*.
- **16/09, conv 194** — Adrian tinha 3 respostas, recebeu a designação às 10h11, abriu na hora, e às
  10h45 o lead foi para a Larissa porque o cliente não escreveu de novo. O *"clica para ver e já foi
  para outro"*.
- **15/09** — **45 conversas de anúncio caindo em 5 times diferentes**, porque quem decidia o time
  era o menu do flow (ou seja, o lead), e o Motor só era acionado pelo nó `distribuir`, **depois** do
  menu — e lead de anúncio não passa por menu.

**O ponto de atrito: `modo_posse`.** Você criou `designacao` para a IA continuar atendendo sem dono. A
Catatau roda em `assignee`. **As duas metades resolvem o mesmo fato por caminhos opostos:** a sua tira
o `assignee` da equação; a da Catatau ensina o Motor a olhar resposta humana em vez de `assignee`.

**E a sua metade nunca rodou na Tozi.** A única policy da conta 6:

```
id=1  time=27 ("locação")  ativo=FALSE  pool=[]  espelho_vista=FALSE
modo=rodizio  modo_posse=assignee  vista_padrao={}
criada 09/09 18:22 UTC, nunca atualizada
distribuicao_produtos da conta 6: 0
```

Casca criada e abandonada — e no time de **locação**, não de vendas, que é onde a linha do Vista faria
sentido. Com 0 produtos, o `ResolverProdutoService` devolve `nil` de saída
(`return nil if produtos.empty?`) e o filtro por produto e faixa de valor **não tem o que filtrar**.

**Tamanho:** D + G · **Decisão:** ligar o rodízio de vendas na Tozi (com pool, produtos e
`vista_corretor` mapeados), ou manter desligado e resolver o Vista por fora dele (A4)?

---

# Bloco 7 — Higiene

## A18 · Abrir o PR de `spx/fix-fotos-handoff-hml` — 10 commits de conserto de IA parados

`origin/spx/fix-fotos-handoff-hml`, 10 commits fora de `producao`, incluindo: recursão infinita em
`track_imoveis` (`SystemStackError`), retry na busca do Vista (*"mata o transitório virando sistema
caiu"*), follow-up viciado em `[IGNORAR]`, `buscar_imovel` trazendo o campo `Condominio` (separa
fechado de avulso **pelo dado**, não pelo nome), limpeza de link markdown na saída para o WhatsApp, e
**remoção de exemplos copiáveis das tools**.

**É a família de defeitos que está doendo agora.** **Tamanho:** M (revisar 10 commits antes do PR).

## A19 · Duas branches quase homônimas — armadilha ativa

| Branch | O que tem | Estado |
|---|---|---|
| `fix/tool-result-tipado` | o P0 | ✅ em `producao` (PR #226) |
| `fix/resultado-tipado-de-tool` | o **harness nível 1 + CI** | ❌ sem PR |

Confundir as duas custa uma hora. **Tamanho:** P (renomear a segunda ou fechá-la no PR de A6).

## A20 · 988 branches remotas

`feat/*` 180 · `fix/*` 149 · **`backup/*` 124** · raiz 108 · **`pr/*` 94** · `PauloSeze/*` 77 ·
`spx/*` 59 · `chore/*` 48 · `feature/*` 46. Das 59 `spx/*`, **51 já estão em `producao`** e podem ser
apagadas.

**Tamanho:** M · **Decisão:** autorizar a limpeza (é irreversível no remoto).

---

# Resumo: ordem sugerida

| # | Ação | Tamanho | Trava |
|---|---|---|---|
| — | ~~A1 restart da VM~~ | ✅ | resolvido pelo timer das 20h |
| 1 | A2 decisão MCMV | D | **sua decisão — é dinheiro parado** |
| 2 | A14 PR do `disparo-guarda` | P | — |
| 3 | A6 PR do harness | P | — |
| 4 | A10 `hybrid` com 0 docs | P | sua decisão por agente |
| 5 | A8 PR do FactGuard (passos 1 e 2) | P | — |
| 6 | A3 repescagem | M | quem assume |
| 7 | A4 lead na lista do Vista | M | qual gatilho |
| 8 | A7 re-medir baseline | M | depende de A6 |
| 9 | A11 contradições do prompt | M | sua decisão por contradição |
| 10 | A18 PR do `fix-fotos-handoff-hml` | M | — |
| 11 | A5 card no pipeline | M+D | qual das 3 opções |
| 12 | A9 revisão amostral | M+G | rótulo + quem clica |
| 13 | A12 / A13 tools e conhecimento | M | — |
| 14 | A16 / A17 controle e stats de campanha | M | — |
| 15 | Bloco 6 rodízio (CHAT-125) | D+G | ligar ou não na Tozi |
| 16 | A15 UI "Novo disparo" | G | — |
| 17 | A19 / A20 higiene de branch | P/M | autorizar a limpeza |

> **Cadência de entrega, para planejar as ações acima:** PR mergeado e puxado **antes das 20h** está
> no ar naquela noite, pelo `chatwoot-restart-noturno.timer`. Nenhuma das ações abaixo precisa de
> restart manual.

---

## Tarefas no gestão (projeto CHAT) — criadas em 23/09/2026

| Tarefa | Ação | Prioridade |
|---|---|---|
| [CHAT-126](https://gestao.spx.ia.br/workbench/spx/tracker/CHAT-126) | A2 · DECISÃO conduta MCMV | Urgente |
| [CHAT-127](https://gestao.spx.ia.br/workbench/spx/tracker/CHAT-127) | A10 · `knowledge_mode=hybrid` com base vazia em 5 agentes | Urgente |
| [CHAT-128](https://gestao.spx.ia.br/workbench/spx/tracker/CHAT-128) | A6 · PR do harness nível 1 + CI | Alta |
| [CHAT-129](https://gestao.spx.ia.br/workbench/spx/tracker/CHAT-129) | A14 · PR de `spx/disparo-guarda` | Alta |
| [CHAT-130](https://gestao.spx.ia.br/workbench/spx/tracker/CHAT-130) | A18 · PR de `spx/fix-fotos-handoff-hml` | Alta |
| [CHAT-131](https://gestao.spx.ia.br/workbench/spx/tracker/CHAT-131) | A8 · PR do FactGuard em sombra + leitor | Média |
| [CHAT-132](https://gestao.spx.ia.br/workbench/spx/tracker/CHAT-132) | A3 · Repescar os 45 chamados abertos | Alta |
| [CHAT-133](https://gestao.spx.ia.br/workbench/spx/tracker/CHAT-133) | A4 · Desacoplar o cadastro do lead no Vista do rodízio | Alta |
| [CHAT-134](https://gestao.spx.ia.br/workbench/spx/tracker/CHAT-134) | A5 · Card no pipeline a partir da qualificação | Alta |
| [CHAT-135](https://gestao.spx.ia.br/workbench/spx/tracker/CHAT-135) | A7 · Re-medir o baseline pós-P0 | Média |
| [CHAT-136](https://gestao.spx.ia.br/workbench/spx/tracker/CHAT-136) | A11 · Render e lint do prompt nos 9 agentes | Média |
| [CHAT-137](https://gestao.spx.ia.br/workbench/spx/tracker/CHAT-137) | A9 · Desenhar a revisão amostral humana | Alta |

**Todas com responsável Paulo Seze, e isso está certo:** as 4 branches sem PR
(`spx/disparo-guarda`, `spx/fix-fotos-handoff-hml`, `fix/resultado-tipado-de-tool`,
`PauloSeze/factguard-shadow`) são **100% commits do Paulo** — 4, 10, 15 e 1 respectivamente. Não há
o que redistribuir. As ações que podem ir para Nicolas (backend/campanha) ou Thalysson (tela) são as
de campanha (A15, A16, A17) e as de higiene (A19, A20), que **deliberadamente não viraram tarefa
ainda** — são segundo turno e encheriam a lista antes das decisões acima.

### Tarefas que já existiam e receberam comentário de cruzamento

| Tarefa | O que foi registrado |
|---|---|
| **CHAT-125** (Rodízio + IA) | O levantamento que ela pede **está feito** — o Bloco 6 inteiro foi colado nela. Não criei tarefa nova de rodízio |
| **CHAT-109** (construir o harness) | Fica **Concluído**: "construir" foi feito. Faltou **entregar** → CHAT-128 |
| **CHAT-110** (medir o baseline) | Fica **Concluído**: medido em 21/09. A re-medição pós-P0 → CHAT-135 |
| **CHAT-106** (descongelar o harness) | Pressupõe o harness entregue, que não está. **Depende de CHAT-128** |
| **CHAT-103** (deploy do P0) | **Metade feita** — a Tozi está no ar desde 22/09 20h. Resta a Fábrica e a validação do trace |
| **CHAT-111** (inventário de conduta, Walisson) | Encosta em CHAT-136. Registrada a fronteira de escopo para não medir duas vezes |

**Por que não reabri CHAT-109 e CHAT-110.** Os títulos dizem *"construir"* e *"medir"*, e as duas
coisas foram feitas. Reabrir reescreveria história correta; o que faltava era entrega e re-medição,
que são trabalho novo e viraram tarefa própria.

---

## O que este documento NÃO decide

- **Nenhuma ação foi executada.**
- A2, A5, A9, A10, A11 e o Bloco 6 dependem de **decisão do Paulo**, não de implementação.
- A ordem acima é sugestão, não compromisso.

## Duas leituras minhas que estavam erradas, corrigidas em 23/09

- **Unidades está certo.** `Unit` = **filial** (um endereço com horário próprio que agrupa caixas). A
  Tozi tem uma, então 1 linha é o número correto. Conferido: "Tozi Imóveis", `America/Cuiaba`,
  coordenadas preenchidas, 7 `working_hours`, 23 exceções, 5 das 6 caixas vinculadas. Falta só
  `address_number` (coluna nova de 21/09) e 1 caixa sem unidade.
- **Campanhas não parou no teste** — ver a nota do Bloco 5.
- **Lição:** contagem baixa numa tabela não é sinal de abandono sem antes entender a unidade de medida
  do modelo. Nos dois casos eu li o número antes de ler o comentário do modelo.

## Procedência das medições

Todas as contagens vêm de leitura **somente-leitura** da conta 6 em `3.94.9.51`, feita em 23/09/2026
com scripts em `/tmp`. Nada foi escrito e nada foi enviado a cliente. O corte de deploy usado nas
comparações é `2026-09-23 00:00:09 UTC` (restart do `chatwoot-web.1`) = **22/09 20:00 Cuiabá**.
