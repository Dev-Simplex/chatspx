# Handoff — sessão orquestradora geral · 14/08/2026

> Handoff **corrente**. Substitui o de 13/08, que fica como histórico.
> Complementa `docs/ORQUESTRACAO-ORCA.md` (a prática) e `.claude/STATE.md` (o in-flight).

---

## 1. O papel, e as três superfícies do Orca

O Paulo toca **vários projetos em paralelo** — o chatspx é um deles — e usa o Claude Code para tudo,
inclusive o que não é código. O Orca organiza branch, worktree, commit, push, merge e PR, e tem três
superfícies com custos diferentes:

| superfície | para quê | custo |
|---|---|---|
| **terminal flutuante** | conversa com ele, decisão, triagem, qualquer projeto | nenhum |
| **sessão em worktree** | um repo, uma branch, um trabalho; herda o `CLAUDE.md` do projeto | isolamento de checkout |
| **orquestração** | supervisão de várias frentes com `worker_done` | **a fila vira notificação para ele** |

**Regra:** orquestração **só** quando você precisa mesmo de conclusão estruturada de várias frentes
simultâneas. Para o resto, terminal comum e leitura direta da saída — ou faça você mesmo. Em 13/08 os
batimentos dos workers geraram dezenas de "You have N orchestration messages" na conversa dele, e ele
reclamou duas vezes. Pedir silêncio **na spec não pega**: o worker só obedece a mensagem recebida no
meio do trabalho, e isso chega tarde.

**Nunca relate batimento.** Só resultado, decisão ou problema.

---

## 2. 🔴 Tozi — a queixa do time sobre a Clara: MEDIDA, e procede em parte

> *"Uma boa parte dos nossos leads entra por WhatsApp, e a Clara, que deveria repassar para a Júlia,
> está fazendo os atendimentos 100%, e ela não está treinada para isso, até porque faz zero
> follow-up."*

**Medição — 14 dias, inbox 91, conta 6:** 606 conversas, sendo 350 de Meta Lead Ads e **256 inbound**.

### O que é falso

A Clara falou em 143 das 256 e **repassou em 116 (81%)**, com **mediana de 2 mensagens** antes de
entregar. Foram **178 execuções de `transferir_para_agente`**. Outras 50 conversas caíram direto numa
especialista, sem passar por ela.

E o roteamento **acerta**: das 74 que ela mandou para a Bruna (locação), **62 falam de aluguel e zero
de compra**. A Júlia recebe menos porque **o inbound orgânico é majoritariamente locação** — não por
erro de triagem.

### 🔴 O que é verdade, e é o ponto real

**Existem campanhas Meta de clique-para-WhatsApp** (o lead clica no anúncio e **ele** inicia a
conversa). Elas entram como inbound comum e **não são reconhecidas como campanha**:

- **41 das 256 (16%)** vieram de anúncio, de 5 criativos — um domina com 29 leads.
- O dado **chega**: o Meta manda o criativo em `content_attributes['referral']` do primeiro incoming
  (`source_type: 'ad'`, `source_id`, `source_url`, `body`). Exemplo real: conv display **22975**.
- O criativo **já é injetado no contexto da IA** — `open_ai_message_builder_service.rb:151`,
  `referral_note`. A Clara **vê** o anúncio.
- ⚠️ **Mas `meta_campanha` está vazio nos 41.** Eles não aparecem em relatório de campanha, não podem
  ser roteados por override, e o marketing não mede o retorno por anúncio.
- **26 foram para a Júlia** (mediana **2,6 min**). **14 ficaram presas na Clara** — e **em 13 delas o
  cliente simplesmente não respondeu** à primeira pergunta. Conversas `open`, 4 mensagens, paradas.

**Comparação que define o problema:** preso na Clara é **5,6%** no orgânico (12 de 215) e **34%** no
lead de anúncio (14 de 41) — **seis vezes mais**, e a diferença inteira é gente que abriu e sumiu.

**E a Clara não tem `programar_followup`.** Ferramentas dela: `transferir_para_agente`,
`salvar_info_lead`, `enviar_localizacao`, `atualizar_resumo`, `registrar_observacao`,
`registrar_assunto`, `responder_em_audio`.

### O conserto, em ordem de retorno

1. **Carimbar os atributos de campanha a partir do `referral`** (`source_id` → `meta_campanha` /
   `meta_anuncio` / `meta_origem`), igual ao lead de formulário. É o que o Paulo pediu: *"esse tipo
   tem que ser considerado como campanha"*. **Código.**
2. **Rotear pelo `source_id` na criação**, reusando o mecanismo de override por campanha — assim o
   lead de MCMV vai direto para a Júlia sem depender do julgamento da Clara. **Código.**
3. **Follow-up para quem abre e some** — 13 leads de campanha pagos, parados em 2 semanas, sem
   ninguém atrás. Pode ser conduta + ferramenta, mais rápido que 1 e 2.

⚠️ Ao falar com o time da Tozi: a percepção deles nasce de ver o nome da Clara **primeiro em toda
conversa**, porque ela é a primeira a responder por desenho. Vale mostrar os números — se acharem que
a IA não funciona, param de confiar nela.

---

## 3. 🔴 Tozi Instagram — tem volume, e o envio de imagem da IA não sai

**Inbox 101 (`toziimoveis.com.br`), conta 6.** Token válido até 03/10, zero erro de auth,
`active_bot? = true`, **7 IAs elegíveis** (Clara + as especialistas).

**Volume, e crescendo:**
- 30 dias: **62 conversas, 630 mensagens** (191 de entrada)
- 7 dias: **45 conversas, 451 mensagens** (124 de entrada) — ou seja, 3 de cada 4 conversas do mês
  são da última semana
- total histórico: 62 conversas (o canal nasceu em 04/08)

**A IA atende normalmente:** Clara 97 mensagens, Bruna 55, Júlia 47, Marina 3 — com humanos por cima
(Evellyn 26, Cibele 11, Gelson 3). O mesmo padrão de triagem do WhatsApp.

### 🔴 O achado: a tool de fotos roda e nada sai

| medida | valor |
|---|---|
| outgoing em 60d | 318 |
| com anexo | 57 |
| status desses 57 | **51 `read`, 6 `delivered`** |
| falhas de envio na inbox | **0** |
| erro externo registrado | **0** |
| anexos enviados pela **IA** | **0** |
| `enviar_fotos_imovel` chamada | **9 vezes, em 2 conversas** |

Os 57 anexos que saíram são do **time humano** (44 por eco do app do Instagram, 12 do usuário 137,
1 do 72). **Nenhum da IA.**

Ou seja: **a ferramenta é chamada, não entrega imagem, e não registra falha.** É no-op silencioso — a
mesma família de defeito que já mordeu três vezes neste projeto.

Para comparar, no WhatsApp a mesma tool roda **137 vezes em 47 conversas** e entrega.

**Próximo passo:** rastrear uma das 2 conversas que chamaram a tool — ver se a mensagem chega a ser
criada, se nasce sem anexo, ou se o `Instagram::BaseSendService#send_attachments` falha antes de
gravar. Não foi investigado; só medido.

⚠️ Contexto do canal que pode estar no meio: o Instagram **não tem template**, a janela é de 24h, e
`Instagram::SendOnInstagramService` manda anexo por **URL** (`attachment.download_url`) — a Meta
precisa conseguir buscar essa URL.

---

## 4. Estado do código: sete PRs abertos

| PR | conteúdo | urgência |
|---|---|---|
| **#46** | fecha acesso indevido em 13 tools do copilot | **alta** — corretora alcançava 24.206 conversas com nota privada contra 217 permitidas (111×) |
| **#41** | nil-safety do `track_urls` | **alta** — a `homologacao` está vermelha até entrar |
| **#40** | `dados_imoveis` vazando para o prompt | |
| **#43** | fronteira de conta no copilot | derrubou a premissa "copilot tem humano no meio" |
| **#44** | marketing edita roteamento por campanha, com validação anti-`#132000` | |
| **#45** | camada mídia → contexto para imagem (eixo 3) | |
| **#42** | documentação | |

**Aplicado e provado:** guarda de departamento na Fábrica (15 execuções sem vazar) · conduta do beco
sem saída (9 rodadas) · tools do MTM · override do Pacaembu · agente da BigStore criado e gateado ·
pool da `.232` restaurado.

**Disparo da Tozi:** encerrado — **4.862 enviadas, zero falhas**, campanhas 4/5/6 deixadas em
`paused`. Falta o relatório de resultado por corretor, se pedirem.

---

## 5. Os três eixos de LLM (a conversa que ficou pela metade)

| eixo | o que é | como resolve a chave | estado |
|---|---|---|---|
| **1** | modelo das IAs | `InstallationConfig.CAPTAIN_*` — **uma chave por box**, lida no **boot** | por isso a Anthropic secar derrubou as 4 contas da `.232` juntas |
| **2** | transcrição de áudio da plataforma | `Copilot::OpenaiSettings.api_key(account)` → `ENV['OPENAI_API_KEY']` — **por conta com fallback**, modelo `whisper-1` | funciona; nenhuma conta tem chave própria hoje |
| **3** | mídia virando contexto | **construído em 14/08 no PR #45**, seguindo o padrão do eixo 2 | imagem pronta; **vídeo em aberto** |

**Decisão pendente do Paulo:** vídeo exige `ffmpeg` na frota, mais quadros por minuto e teto de
custo. ⚠️ Antes de priorizar: **97,1% dos story replies já trazem texto**; o caso 100% cego é
**2,9%**, e nesses o próprio time humano não responde.

---

## 6. O que falta, por dono

**Paulo:** crédito da Anthropic na `.232` (segura duas provas de conduta da BigStore, já escritas,
scripts em `scratchpad/bigstore-conduta/`) · decisão do vídeo · escopo
`instagram_business_manage_comments` no painel da Meta (brief em
`instagram-comentarios/Temp/BRIEF-META-escopo-comentarios.md`).

**Walisson:** os 7 PRs · como subir os **16 commits off-origin** da box de homologação.

**Tozi:** mapa de CTA → slug de intenção (bloqueia `intencao-site/Temp/SPEC-intencao-site.md`).

**BigStore:** tabela de lojas — reconstruída em parte pelo atendimento: **Rondonópolis, Primavera do
Leste e Cláudia foram transferidas** (75 respostas do time, zero telefone entregue), contra o vault.

**Sem dono:** allowlist de times da Fábrica (inerte até deploy naquele box) · deploy da Fábrica (249
commits atrás, feature ativa fora do git, resgatada em `backup/fabrica-box-offgit-20260812`) · custom
tools indo todos ao copilot ignorando a coluna que os marcaria como exclusivos, **4 escrevendo no CRM
externo da Fábrica**.

---

## 7. ⚠️ Deploy da homologação: SUSPENSO

A `.232` tem **144 arquivos off-git** (não 70 — `git status --porcelain` conta diretório untracked
como uma linha) e **16 commits em 7 branches** fora do GitHub. Tudo resgatado e provado por hash em
`scratchpad/homologacao-offgit/`.

O trabalho é **dirigido pelo Walisson**, executado por sessões de agente na própria box — e **havia
sessões rodando durante o levantamento**. Um deploy hoje trava num untracked que colide, **perderia
20 arquivos em silêncio absoluto**, e traria **10 migrations** que o "zero pendente" do Almirante não
enxerga, porque ele mede **antes** do checkout.

---

## 8. Armadilhas de medição — todas produziram relatório errado antes de serem pegas

1. **`order(id: :desc)` devolve registro velho.** Ordene por `created_at` ou use `maximum(:id)`.
2. **Laço de monitor dentro de um `rails runner` congela** — o query cache repete a primeira resposta.
   Reportei "disparo parado há 12 minutos" com a fila andando a 19/min. Use
   `ActiveRecord::Base.uncached { }` em **cada** amostra. Sintoma: um número que não mexe **nenhum**
   enquanto outro do mesmo script varia.
3. **`.group(...)` em `Message` colide com a gem groupdate** e explode. Faça `pluck` + agrupamento em
   Ruby.
4. **`external_error` NÃO é coluna de `messages`** — o erro de envio vive em
   `content_attributes['external_error']`. Em `campaign_recipients` **é** coluna.
5. **`contact_id` é nulo em `campaign_recipients` pendente** — o contato só nasce no envio. Cruze por
   telefone.
6. **`assignee_type` é `'AgentBot'`, não `'agent_bot'`** — com a grafia errada o serviço trata como
   humano, procura usuário inexistente e **limpa os dois campos**.
7. **O número da URL do painel é `display_id`**, não o `id` interno.
8. **Baseline é o próprio ramo sem o próprio commit** — nunca `origin/homologacao`.

---

## 9. O que funcionou e vale repetir

**Exigir prova, não relatório.** Três propostas foram **derrubadas pela medição** antes de ir para
produção: a conduta de locação da Júlia (0/8 no formato dominante do dado), a regra de string sobre a
jornada (falso positivo irredutível — três jornadas byte a byte idênticas foram para times
diferentes) e o renome dos times do Atacadão (0% de eficácia).

**Testar a queixa antes de agir sobre ela.** A do time da Tozi era metade falsa e metade verdadeira,
e a metade verdadeira **não era a que eles nomearam**.

**Olhar antes de sobrescrever.** Duas VMs tinham trabalho vivo fora do git; nas duas o deploy teria
apagado em silêncio.
