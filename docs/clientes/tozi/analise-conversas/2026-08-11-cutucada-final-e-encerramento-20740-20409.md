---
titulo: A cutucada final e o encerramento — conversas 20740 e 20409
frente: spx/followup
tipo: investigação read-only + recomendação de desenho (não implementa)
ambiente: Tozi PRODUÇÃO · conta 6 · 3.82.215.109
data: 2026-08-11
---

# O disparo ignorado entra na fila de encerramento — e a blindagem nunca teve chance de impedir

> **Investigação read-only.** Nada foi escrito, migrado, reiniciado ou deployado. Nenhuma chave foi
> ligada. Nenhum marcador residual foi limpo. Toda afirmação sai de `conversations`, `messages`,
> `Captain::AssistantLog` e do arquivo de código **lido no disco da VM** em 11/08/2026, entre
> 20:20 e 20:26 (UTC-4). Os scripts estão no fim.

## Resumo em seis linhas

1. **A premissa se confirma, mas por outra causa.** A conversa **20740** é exatamente "disparo
   ignorado que virou aguardando encerramento": zero mensagens do cliente, um único template
   entregue, e uma nota da IA classificando-a como `substantive` 63 minutos depois.
2. **A blindagem `campaign_without_reply?` não falhou. Ela nunca foi exercida — e não porque o
   marcador seja resíduo, mas porque ela não enxerga o disparo que a Tozi usa.** Ela pergunta por
   `conversation.campaign`; o funil vivo hoje é **Meta Lead Ads**, que **nunca preenche
   `campaign_id`**. Das 355 conversas marcadas, **nenhuma** casa com o predicado dela.
3. **Não é resíduo de um minuto do dia 03/08.** As marcas são de **01/08** (351), 02/08 (3) e
   03/08 (1), cada uma com a nota do classificador provando que o LLM rodou. É comportamento
   **reprodutível**: religar a chave repete tudo.
4. **248 das 355 marcadas (70%) são leads que nunca disseram uma palavra** — e **todas as 248 são
   `source = meta_lead_ads`**.
5. **A varredura gastou 634 chamadas de LLM para produzir zero ação ao cliente.** Nenhuma conversa
   recebeu aviso de encerramento (`encerramento_avisado_em` = 0) nem foi fechada pela política
   (`motivo_encerramento` = 0) — porque as duas conversas estavam **fora da janela de 24h** quando
   o classificador rodou, e `send_closing_notice` é gateado por `can_reply?`.
6. **Recomendação: opção (a)** — a conversa de disparo ignorado termina **fechada**, por regra
   determinística e sem LLM. Justificativa e escopo em §3.

## 1. As duas conversas

### Estado dos portões hoje (conta 6, lido em 11/08 20:20:46 -04)

| Portão | Valor |
|---|---|
| `captain_auto_resolve_mode` | `"disabled"` |
| `settings['auto_closure']` | `{"enabled" => false, "max_dias" => 0}` |
| `feature_enabled?('captain_tasks')` | `true` |

O levantamento de 31/07 registrava `auto_closure = nil`; hoje é um hash **explicitamente
desligado**. Alguém configurou e desligou no intervalo — coerente com o exercício de 03/08 descrito
no handoff. **A política está desligada agora**, e por isso nada do que segue está acontecendo
neste momento. O código, porém, está no disco da VM: `campaign_without_reply?`,
`route_with_closure_policy` e `PendingClosureService` presentes, arquivo com mtime **03/08 20:24**.
(Não está lá a exclusão de `aguardando_humano_desde` do `scannable` — essa é mudança local de outra
tarefa, ainda não commitada.)

### 20740 — o caso da premissa

| Campo | Valor |
|---|---|
| `id` / `display_id` | 41949 / 20740 |
| `campaign_id` | **nil** |
| `additional_attributes.source` | **`meta_lead_ads`** (plataforma `ig`, form `2545551432555984`) |
| `custom_attributes.meta_campanha` | `[FORMS] - PACAEMBU` |
| status · espelho · time | `open` · `agent_bot 17` · time 67 |
| mensagens | **2** — incoming: **0** |
| `aguardando_encerramento_desde` | `2026-08-02T20:05:04-04:00` (= o próprio `last_activity_at`) |

Linha do tempo inteira:

```
02/08 19:02  OUTGOING  template tozi_lead_meta_abertura  → status "delivered"
             "Oi Maiara, tudo bem? Aqui é da Tozi Imóveis. Vi que você se interessou nas
              casas com entrada facilitada aqui em Sinop..."
02/08 20:05  NOTA (Captain::Assistant#13)
             "Aguardando encerramento (substantive): The assistant introduced the service and
              offered to explain how it works but did not receive any response or confirmation
              from the customer to proceed or complete the interaction."
```

**O caminho pelo qual o marcador entrou está provado pela própria nota.** Só o
`dispatch_closure_action` escreve `Aguardando encerramento (<classe>)`, e ele só é alcançado por
`route_with_closure_policy` → ramo 3 (primeira passagem) → `evaluate_conversation` (chamada de LLM)
→ ação `queue` (o default) → `PendingClosureService`. A classe atribuída foi **`substantive`**.

O relógio: template às 19:02, `auto_resolve_cutoff_time` é `now - 1.hour`, marca às 20:05. **63
minutos entre o disparo e a IA declarar que o atendimento estava aguardando encerramento.**

### 20409 — não é o mesmo caso

| Campo | Valor |
|---|---|
| `id` / `display_id` | 41618 / 20409 |
| `campaign_id` | **nil** · `source` = `meta_lead_ads` (`fb`, RMKT, imóvel 7686) |
| mensagens | **12** — incoming: **2** |
| `followup_count` · `followup_token` | **2** · `null` (consumido) |
| `followup_status` | `"cutucada auto-programada em ~120 min"` |
| `aguardando_encerramento_desde` | `2026-08-01T15:32:28-04:00` |

```
28/07 18:42  OUTGOING  template tozi_rmkt_imovel (header com foto) → "read"
28/07 20:08  INCOMING  "Quero ver"
28/07 20:08  OUTGOING  3 fotos + "Mandei as primeiras fotos!" + ficha do imóvel (R$ 800 mil)
28/07 20:09  OUTGOING  "Essa casa é pra você morar ou é investimento?"
28/07 20:09  INCOMING  "Morar"
28/07 20:09  OUTGOING  "Legal! E você mora de aluguel hoje ou já tem um imóvel?"
29/07 08:00  OUTGOING  cutucada: "Oi Ingrid! Conseguiu dar uma olhada nas fotos da casa?..."
29/07 10:00  AssistantLog  ignored {"raw" => "[IGNORAR]"}     ← 2ª tentativa suprimida
01/08 15:32  NOTA  "Aguardando encerramento (substantive): ...the customer hasn't responded yet"
```

A **20409 é o caso legítimo do encerramento**: o lead engajou, respondeu duas perguntas, abandonou
no meio da qualificação, a escada de cutucada rodou (2 de 4, a terceira virou `[IGNORAR]`) e a
conversa ficou parada 3 dias. **Ela não é disparo ignorado.** As duas conversas do enunciado
pertencem a populações diferentes, e essa distinção é o eixo da recomendação.

**Detalhe que vale para as duas:** a última mensagem do cliente na 20409 foi 28/07 20:09 → a janela
fechou 29/07 20:09. O classificador rodou **01/08 15:32**, ~67h depois. Na 20740 a janela **nunca
abriu**. Nos dois casos `can_reply?` era falso quando a política agiu — por isso
`send_closing_notice` não mandou nada e o único produto de cada chamada de LLM foi **uma nota
privada e uma linha na fila do time**.

## 2. A blindagem falhou ou nunca foi exercida?

**Nunca foi exercida — e a razão é mais grave do que se tivesse falhado.**

Cruzamento das **355** conversas marcadas hoje na conta 6 (eram 536 em 31/07; **181 se limparam
sozinhas** pelos callbacks de `clear_awaiting_closure_marker` — a limpeza funciona):

| | sem `incoming` | com `incoming` |
|---|---|---|
| **sem `campaign`** | **248** | 106 |
| **com `campaign`** | **0** | 1 |

> **Zero conversas marcadas casam com `campaign.present? && !messages.incoming.exists?`.** O
> predicado da blindagem nunca foi verdadeiro para nenhuma delas. Ela não foi contornada: ela foi
> irrelevante.

E as **248 sem incoming são 100% `source = meta_lead_ads`** (checado chave a chave: 248/248 com
`additional_attributes.lead` e `meta_tipo`; 219 com `meta_campanha`).

O outro lado da mesma moeda: existem **5.950** conversas de campanha sem resposta na conta 6 —
**0 marcadas, e apenas 1 aberta**. Elas foram resolvidas em massa na higiene de 11/06 (decisão
2.7), e conversa resolvida não entra no scan (`resolvable_pending_conversations` pega `pending` +
`open` da IA). Ou seja: **a população que a blindagem protege já não passa por ali**, e a população
que passa por ali ela não reconhece.

### Por que ela não reconhece

São **dois caminhos de disparo** e só um preenche `campaign_id`:

| Caminho | Preenche `campaign_id`? | Blindado? |
|---|---|---|
| `Spx::Tozi::DisparoLeadJob` / campanhas nativas | sim | sim |
| `Meta::LeadAds::CreateConversationService` | **não** | **não** |

O comentário no código — *"C (campanha sem resposta) nunca fecha por tempo (janela nunca abriu —
espera o próximo template)"* — descreve a intenção certa. **A intenção é sobre a janela; a
implementação é sobre a tabela de campanhas.** Onde as duas divergem, é a implementação que vale, e
foi por essa fresta que 248 leads entraram na fila do time.

### E não é resíduo de 03/08

Distribuição das marcas por hora:

| Hora (UTC-4) | Marcas |
|---|---|
| 2026-08-01T15 | **350** |
| 2026-08-01T17 | 1 |
| 2026-08-02T08 | 1 |
| 2026-08-02T10 | 2 |
| 2026-08-02T20 | 1 *(= a 20740)* |

O grosso é uma janela de **~1 hora em 01/08**, não o minuto de 03/08 citado no handoff — que foi um
evento distinto (a ordem invertida das chaves) e menor. Foram criadas **634 notas** de
`Aguardando encerramento` (544 `substantive`, 90 `trivial`) — mais notas que marcas sobreviventes,
o que também confirma a corrida de ciclos sobrepostos já documentada no cabeçalho do job. **634
chamadas de LLM em cerca de uma hora**, para 355 entradas de fila e **zero** ação ao cliente.

Conclusão da §2: **o marcador é produto reprodutível do código atual, não sujeira histórica.**
Religar `auto_closure` hoje, sem mexer em nada, repete o mesmo resultado sobre as **306** conversas
sem incoming que estão paradas há mais de 1h na inbox 91.

## 3. Recomendação: opção (a) — a conversa de disparo ignorado termina fechada

**Recomendo (a).** Não como "nasce fechada no instante da criação", mas com o gatilho certo: **a
conversa de disparo sem resposta é encerrada por regra determinística, sem LLM, quando a tentativa
se esgota — janela fechada e zero mensagens do cliente.** É o mesmo destino de (a) com o momento
corrigido, e é a leitura fiel do comentário que já está no código.

### Por que não (b), para esta população

**(b) é impossível aqui, não apenas cara.** "A IA encerra depois da cutucada final" pressupõe uma
cutucada final. Para um lead que nunca respondeu, **a janela nunca abriu** — e pelo §1 do contrato
do eixo, *template não reabre a janela, só a resposta do cliente reabre*. Logo as engrenagens 1
(cutucada) e 2 (follow-up) são **estruturalmente inaplicáveis**: nada free-form é entregável. A
única engrenagem que pode agir é a 3 (repescagem, template pago), e ela é decisão do operador, não
da IA.

Escolher (b) para os disparos ignorados significa **pagar uma classificação de LLM por conversa
para concluir "o cliente nunca respondeu"** — um fato que um `NOT EXISTS` responde de graça. Foi
literalmente o que aconteceu: das 634 classificações, a maioria respondeu a essa pergunta.

**(b) continua sendo a forma certa para a classe da 20409** — lead que falou, engajou e abandonou.
Ali o LLM tem o que julgar, a escada rodou e o encerramento é o fim natural dela. Isso é outra
decisão, posterior, e não é o que o enunciado pergunta.

### Os quatro pesos exigidos, com o que foi medido

**NPS/CSAT.** Medido: `inbox 91.csat_survey_enabled = false`, e **nenhuma inbox da conta 6 tem CSAT
ligado**. Hoje, fechar não dispara pesquisa nenhuma na Tozi — o risco é **latente, não ativo**.
Mas o desenho não pode depender disso: num tenant com CSAT ligado, fechar uma conversa de lead que
**nunca falou** manda pesquisa de satisfação a quem não teve atendimento — o pior disparo possível.
Por isso a recomendação **inclui, como pré-requisito, suprimir CSAT quando a conversa tem zero
`incoming`**. Conversa sem mensagem do cliente não tem o que pesquisar; a guarda se justifica
sozinha, independentemente desta feature.
Sobre o ciclo fecha/reabre multiplicando pesquisas: medido nas 6.116 conversas de campanha da
inbox 91 — **6.105 resolvidas, 11 abertas, e as 11 têm incoming** (reabriram no engajamento).
**0,18% de reabertura.** O ciclo existe, mas é raro; o problema do CSAT aqui é de *natureza*, não
de volume.

**Multi-tenant.** Opt-in por conta, default off, sob a chave `auto_closure` que já existe — nunca
hardcode de cliente, nunca `if account_id == 6`. A Tozi tem `lock_to_single_conversation = true`:
fechar não cria conversa nova, o mesmo fio é reaberto — **conversa única é preservada**. Num tenant
sem `lock_to_single`, o mesmo desenho tende a produzir uma conversa nova por retorno, que é
justamente o "uma conversa ≠ um atendimento" pedido no escopo desta frente. A recomendação serve
melhor aos dois modelos do que o estado atual, que mantém tudo aberto para sempre.

**Contrato §1 — "reabre no engajamento" depende de evento que a empresa não controla.** Verdade, e
é por isso que a alternativa não é melhor: **manter aberto não controla esse evento tampouco.**
Deixar 310 conversas abertas não faz nenhum lead responder; só faz a fila mentir sobre o que está
vivo. O controle da empresa sobre essa população chama-se **repescagem**, e ela age igualmente bem
a partir de uma conversa fechada (precedente: o `FollowupHsmJob` manda HSM no fio existente e o
reabre). Fechar **não abre mão da alavanca**; abre mão da ilusão de fila.
Empiricamente o retorno funciona neste tenant: das 11 conversas de campanha reabertas, **8 têm
dono humano e 3 têm o espelho da IA** — nenhuma ficou órfã. E há **179** leads Meta hoje abertos
com incoming, ou seja, o caminho de reengajamento está em uso corrente.

**Custo de inferência.** `Limits::BULK_ACTIONS_LIMIT = 100` por ciclo, **uma chamada de LLM por
conversa**. Universo atual da inbox 91 (aberto, da IA, parado há +1h): **434 conversas — 306 sem
nenhum incoming, 420 de `meta_lead_ads`, 354 já marcadas.** Ligar a política como está hoje
classifica de novo as 306 que um predicado SQL resolveria, e **a cada ciclo**, porque conversa que
não muda continua elegível. Com a recomendação, essas 306 saem do scan **antes** do LLM: o custo do
encerramento passa a ser pago só onde há julgamento a fazer (a classe da 20409, hoje 128 com
incoming).

### O que é a recomendação, em uma frase

> Conversa iniciada pela empresa que **nunca recebeu mensagem do cliente** não é atendimento em
> aberto: quando a janela se fecha, ela termina **fechada**, sem LLM, sem nota ao cliente e sem
> passar pela fila do humano — e volta a existir se, e quando, o cliente responder.

## 4. O que isso exige de código, em ordem, e o que quebra

**Ordem importa: cada passo é seguro sozinho e o seguinte só faz sentido depois do anterior.**

1. **Corrigir a definição de "disparo sem resposta".** O predicado que hoje pergunta por
   `conversation.campaign` passa a perguntar pelo que a intenção sempre disse: **ausência de
   `incoming`** (conversa iniciada pela empresa). Só isso já estanca o sangramento — nenhum lead
   silencioso é classificado nem enfileirado.
   *Precisa entrar **antes** de a chave ser religada;* com a política desligada, é mudança inerte e
   de risco zero.
2. **Aplicar a exclusão no SQL do scan, não só no ramo.** Excluir dentro de
   `route_with_closure_policy` deixa a conversa **consumir uma das 100 vagas do ciclo** — a mesma
   patologia que o comentário do `scannable` já descreve para a fila de encerramento. Com 306 de
   434 no estado inerte, a fila útil seria engolida.
3. **Só então a regra de fecho determinístico**, sob `settings['auto_closure']` (nova ação para
   essa classe), **opt-in por conta, default off**, gravando `motivo_encerramento` — que o
   `finalize_close` já escreve — para que o relatório distinga "fechada sem resposta" de "fechada
   após atendimento".
4. **Suprimir CSAT/NPS quando a conversa tem zero `incoming`.** Bloqueia (3) para qualquer tenant
   com pesquisa ligada. Não bloqueia a Tozi (CSAT off, medido), mas bloqueia o produto.
5. **Depois de 1–4**, avaliar ligar o `auto_closure` para a classe substantiva (a da 20409) — onde
   o LLM tem o que julgar e (b) é a forma certa. Decisão separada, com o passivo já drenado.

### O que quebra, ou merece olho

- **Cards do funil.** Resolver move o card para "Resolvidos" (comportamento já observado na higiene
  de 11/06). O funil de pré-venda perde as conversas sem resposta das etapas visíveis — efeito
  desejado, mas é mudança de tela para o time; precisa de aviso, não de código.
- **O espelho cai no fecho.** `release_captain_mirror_on_resolve` zera o `assignee_agent_bot` ao
  resolver. O lead que voltar chega **sem dono** e depende da triagem (hook `assign_agent_bot_id`,
  regras #53/#66) para ser re-atribuído. Existe precedente em produção — as 6.105 de campanha vivem
  assim, e as 11 que voltaram acharam dono — mas **é dependência a verificar antes**, não depois:
  triagem quebrada transforma "reabre no engajamento" em "reabre e ninguém atende".
- **Corrida regra × primeira conversa**, já vista no go-live do Instagram (04/08): conversa criada
  segundos antes do wire fica sem dono. O mesmo risco vale na reabertura.
- **Os 355 marcadores residuais continuam lá.** Nada nesta recomendação os limpa — é decisão do
  Paulo e tem procedimento próprio (ordem invertida das chaves). Enquanto não forem limpos, seguem
  aparecendo na fila do time mesmo com tudo desligado.
- **A repescagem precisa existir para essa população.** Fechar sem a engrenagem 3 significa que os
  **480** leads Meta que nunca responderam (310 abertos + 170 já resolvidos) deixam de ter qualquer
  tratativa. Hoje eles também não têm — estão só abertos —, então não é regressão; mas fechar torna
  a falta visível, e é bom que torne.
- **Medição.** Fechar 306 conversas de uma vez muda taxas de resolução e tempo médio no painel do
  período. Vale drenar de forma controlada, como o handoff já recomendava.

## Como reproduzir (tudo read-only)

Scripts em `scratchpad/dump_E{1..5}.rb`, executados por
`scripts/ops/tozi-prod.sh run "bundle exec rails runner /home/chatwoot/dump_EN.rb"`.
Nenhum faz `update`, `create`, `destroy` ou migration; só `pluck`, `find_by` e `SELECT`.

Consultas-chave:

```sql
-- 1) A blindagem nunca casou: cruzamento campanha × incoming nas marcadas
SELECT (c.campaign_id IS NOT NULL) AS tem_campanha,
       EXISTS (SELECT 1 FROM messages m
               WHERE m.conversation_id = c.id AND m.message_type = 0) AS tem_incoming,
       COUNT(*)
FROM conversations c
WHERE c.account_id = 6
  AND c.custom_attributes->>'aguardando_encerramento_desde' IS NOT NULL
GROUP BY 1, 2;
-- => (false,false)=248  (false,true)=106  (true,true)=1  ·  (true,false)=0

-- 2) O universo que a blindagem protege já está fora do scan
SELECT COUNT(*) AS total,
       COUNT(*) FILTER (WHERE c.status = 0) AS abertas
FROM conversations c
WHERE c.account_id = 6 AND c.campaign_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM messages m
                  WHERE m.conversation_id = c.id AND m.message_type = 0);
-- => total=5950  abertas=1

-- 3) O que a política produziu ao cliente
SELECT COUNT(*) FROM conversations
WHERE account_id = 6 AND custom_attributes ? 'encerramento_avisado_em';  -- => 0
SELECT COUNT(*) FROM conversations
WHERE account_id = 6 AND custom_attributes ? 'motivo_encerramento';      -- => 0
```
