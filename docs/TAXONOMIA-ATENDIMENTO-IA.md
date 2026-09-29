# Taxonomia do atendimento com IA — todas as hipóteses

> ⚠️ **Aviso de 28/09/2026:** o que este documento diz sobre o rodízio descreve a versão **anterior**
> ao PR #257 (abas Rodízio e Atenção, em `producao` desde 25/09). A escada de precedência que vale
> está em `Spx::Distribuicao::DistribuirService` e no `.claude/STATE.md`. Correção pendente na Arena
> ("Arrumar a documentação e os scripts do SPX").

> Levantado a pedido do Paulo em 25/09/2026. **Não é plano de implementação.** É o mapa do que pode
> acontecer num atendimento conduzido por IA, em **qualquer segmento** — não só imobiliária.
>
> Restrição que enquadra o documento inteiro: **o SPX não atende somente a Tozi.** Contas com Captain
> hoje: 6 (Tozi, imobiliária, 9 agentes), 1 (Fábrica dos Óculos, ótica, 5 agentes), 3 e 7. Onde este
> documento precisar de um exemplo concreto, ele traz **dois segmentos**, nunca um.

---

## 1. O insight central: os casos A e B não são erros

Os dois casos que o Paulo repetiu têm a mesma estrutura, e é a estrutura que importa:

| | O que o cliente pediu | O que a IA respondeu | Por que estava **correta** | O que o humano fez |
|---|---|---|---|---|
| **A** | casa para alugar, R$ 8 mil, condomínio fechado | não há imóvel assim no acervo | **é verdade** — a busca no Vista retornou vazio | **captou** um imóvel no perfil; converteu |
| **B** | terreno para investimento, na cidade dele | só há terrenos em Sinop | **é verdade** — o acervo é de Sinop | convenceu que Sinop era bom investimento |

**Nada foi alucinado. Nenhuma regra foi quebrada. O harness e o FactGuard dariam verde nos dois.**

A falha é outra: **a IA responde a pergunta feita; um vendedor responde a necessidade por trás dela.**

- Em **A**, "não tenho esse imóvel" deveria ser "**posso conseguir** esse imóvel". Ausência de estoque
  virou fim de conversa, quando era **pedido de captação** — e de um cliente disposto a pagar 2,3× o
  teto do acervo, ou seja, o melhor lead do mês.
- Em **B**, "não tenho nessa cidade" deveria ser "**a cidade é premissa sua, não minha**". Para quem
  compra para **investir**, geografia é negociável: o comprador não vai morar lá. A IA aplicou uma
  regra de moradia a uma intenção de investimento.

> **A generalização, que vale para qualquer segmento:** a IA trata o que o cliente declara como
> **filtro rígido**. Um bom vendedor trata como **posição inicial de negociação**.

E daí sai a consequência operacional mais importante deste documento:

> **Não se detecta A e B olhando o que a IA fez de errado. Detecta-se olhando o que a IA DISSE que
> encerra conversas.**

Isso muda o instrumento. Não é verificador de regra (FactGuard), não é nota de qualidade (eval). É
um **classificador da forma do "não"** — e está na §8.

---

## 2. A visão V2 do Paulo, registrada como ele a descreveu

Máquina de estados na aba de conversas da IA:

| Estado | Condição | IA | Humano |
|---|---|---|---|
| **em atendimento** | IA atendendo, cliente **ainda não pronto** para humano | atende | não vê / não age |
| **atenção** | cliente disse **o quê, onde, até quanto** | **continua atendendo** | revisa **antes de encerrar o expediente** e julga se manda ao rodízio |
| **handoff / rodízio** | cliente **demonstrou interesse** em item específico | **continua atendendo** | roda de mão em mão até alguém pegar |
| *(transição)* | **alguém pegou E enviou mensagem** | **cala** | atende; daí em diante só o **Eval** monitora o humano |
| **encerrada pela IA** | cliente parou de responder **sem demonstrar interesse**, ignorou follow-up, janela fechando | encerra | filtra depois: "encerrados pela IA" |

E o relógio, **24h independente do canal**:

- conversa **no rodízio**, ninguém pegou, janela vai expirar → **notificar supervisor**
- conversa em **atenção**, vai completar 24h desde a última mensagem do cliente → **notificar**

**Isso é V2.** Parte precisa sair já na versão atual — o que é decidido nas frentes da §10.

---

## 3. Eixo 1 — As SAÍDAS FALSAS: por que a conversa termina sem valor

É onde vivem A e B. A IA dá uma resposta **correta e terminal**. Cada linha é um "não" que um bom
atendente vira "ainda não" ou "e se".

| # | O "não" | Exemplo imobiliária | Exemplo ótica / outro segmento | O movimento que faltou |
|---|---|---|---|---|
| 1 | **Ausência de estoque** | "não temos casa nesse perfil" (**caso A**) | "não temos essa armação" | captar · encomendar · avisar quando entrar |
| 2 | **Fora da área** | "só temos em Sinop" (**caso B**) | "só entregamos na cidade" | para investimento/entrega/remoto a geografia é negociável |
| 3 | **Acima da faixa de preço** | pede R$ 8 mil, teto é R$ 3,5 mil | pede lente premium fora de linha | **pedido acima do acervo é lead BOM**, não ruim |
| 4 | **Abaixo da faixa de preço** | orçamento não alcança nada | quer o mais barato | existe entrada, parcelamento, financiamento, linha popular? |
| 5 | **Fora do catálogo** | pede sítio, só há urbano | pede lente de contato, só há óculos | existe **adjacente**? parceiro? indicação? |
| 6 | **Requisito não atendido** | sem renda comprovada, nome restrito | sem receita médica, sem convênio | fiador, co-titular, plano alternativo, outro produto |
| 7 | **Pergunta respondida e fim** | "como funciona o MCMV?" → resposta completa → silêncio (**caso C**) | "vocês aceitam meu convênio?" → "sim" → silêncio | a resposta completa **matou** a conversa; faltou a pergunta de volta |
| 8 | **Fora do horário** | chega 23h, recebe ausência, não volta | idem | o retorno no dia seguinte não acontece sozinho |
| 9 | **Canal errado** | pede algo que exige presencial/telefone | idem | a ponte para o outro canal não foi construída |
| 10 | **Intenção fora da alçada do agente** | agente de locação recebe compra | agente de venda recebe garantia | transferência entre agentes, não encerramento |
| 11 | **Cliente pede o que a empresa não faz mais** | produto descontinuado | idem | substituto? |
| 12 | **Concorrência citada** | "na outra imobiliária custa X" | "na outra ótica é mais barato" | não é objeção de preço, é pedido de justificativa de valor |

**O padrão:** nos 12 casos a IA está factualmente certa e comercialmente morta. E **cada um é
reconhecível pela forma da própria frase da IA** — é isso que torna o problema tratável.

---

## 4. Eixo 2 — As MORTES SILENCIOSAS: a conversa acaba sem nenhuma saída

Diferente do Eixo 1: aqui não houve resposta terminal. A conversa simplesmente **paralisou**. Os
números são da conta 6, medidos em 23–24/09/2026.

| # | Morte | Medido | Quem devia agir |
|---|---|---|---|
| 1 | Cliente engajou e parou de responder | — | follow-up / repescagem |
| 2 | Cliente nunca engajou e parou (**caso C**) | — | encerrar + marcar |
| 3 | **IA fez handoff e ninguém pegou** | **480 (34,2% de 1.421)**, 96 ainda abertas | supervisor / SLA de pickup |
| 4 | **Humano pegou e não respondeu** | 5 dos 7 `urgent` **têm assignee** | supervisor |
| 5 | **Janela do canal fechou e ninguém notou** | **1.843 de 2.550 abertas — 72%** | ninguém, hoje |
| 6 | Follow-up esgotou e nada aconteceu | — | escalar ou encerrar |
| 7 | Conversa presa em estado inconsistente | conv 4854: marcador nasceu depois do assignee, fila travada | código |
| 8 | **Falha técnica lida como ausência de dado** | corrigido pelo P0 (PR #226) | código |
| 9 | Cliente esperando e ninguém respondeu | **700 com o cliente falando por último** — 335 há 7–30d, 262 há +30d | operação |
| 10 | Conversa aberta que ninguém vê (sem fila, sem dono) | **17 MCMV**: sem marcador, sem assignee, 10–31 dias | ninguém, hoje |

> **A morte #10 é a mais perigosa porque é invisível por construção:** não está em "aguardando
> atendimento" (nunca houve marcador) nem com alguém (`assignee` nulo). Só `open` e esquecida.
> **Não foi negligência do time — a conversa não aparecia em lugar algum.**

---

## 5. Eixo 3 — Os ERROS da IA (aqui sim é erro)

Estes são os que o eval **já** classifica. A lista vem do enum real de
`Captain::ConversationEvalSchema`, mais o que falta nele.

**Já classificados (22 categorias):** `alucinacao` · `info_incorreta` · `nao_respondeu_pergunta` ·
`narrou_ferramenta` · `tom_robotico` · `repeticao` · `exemplo_copiado` · `quebrou_regra` ·
`promessa_indevida` · `handoff_ausente` · `handoff_tardio` · `transferencia_ausente` ·
`fora_horario_mal_tratado` · `contradisse_tool` · `nao_chamou_tool_obrigatoria` · `usou_tool_errada` ·
`ignorou_erro_da_tool` · `nao_entregue` · `pedido_ignorado` · `afirmou_esgotamento` ·
`lead_abandonado` · `outro`

**Volume real em conversas ABERTAS (30 dias, conta 6):** `nao_respondeu_pergunta` 99 ·
`contradisse_tool` 81 alta · `repeticao` 69 · `quebrou_regra` 61+45+45 · `lead_abandonado` 58+57 ·
`alucinacao` 56 alta · `promessa_indevida` 47 · `handoff_ausente` 37 alta · `info_incorreta` 38.

**O que NÃO está no enum e este documento propõe acrescentar:**

| Falta | O que é | Por que importa |
|---|---|---|
| `handoff_desnecessario` | passou para humano sem precisar | é o **erro trocado**: baixar o limiar fez a IA jogar curioso para os consultores |
| `encerrou_cedo` | encerrou conversa que devia seguir | hoje indistinguível de encerramento correto |
| `nao_encerrou` | deixou morta conversa que devia fechar | são as 1.843 |
| `oportunidade_perdida` | **os casos A e B** | nenhuma categoria atual cobre |
| `nao_negociou_premissa` | aceitou o filtro do cliente como absoluto | a forma acionável de A e B |

---

## 6. Eixo 4 — Estados de POSSE: quem é dono da conversa

A máquina de estados da §2, com o que pode dar errado em cada transição. **Vocabulário neutro de
propósito** — "pool de atendentes", não "corretores".

```
  [nova] ──► EM ATENDIMENTO (IA) ──► ATENÇÃO (IA atende, humano revisa)
                    │                        │
                    │                        ▼
                    │                 HANDOFF / RODÍZIO (IA AINDA atende)
                    │                        │
                    │                        ▼ alguém pega E FALA
                    │                 HUMANO (IA cala · Eval monitora)
                    ▼
             ENCERRADA PELA IA ──► elegível a repescagem
```

| Transição | O que pode dar errado |
|---|---|
| nova → em atendimento | IA não assume (espelho não aplicado); conversa nasce órfã |
| em atendimento → atenção | **não existe hoje**; é o estado novo da V2 |
| atenção → handoff | critério errado (§9); humano não revisou antes do expediente fechar |
| em atendimento → handoff (direto) | handoff prometido e não executado; time errado; fora da allowlist |
| handoff → humano | **ninguém pega** (480 casos); pega e não fala; pega e a IA cala cedo demais |
| humano → IA | humano devolve? **hoje não há caminho de volta** |
| qualquer → encerrada pela IA | encerrou cedo; não encerrou; encerrou sem marcar |
| encerrada → repescagem | **não existe hoje**; nada distingue encerramento da IA de encerramento humano |

> **Ponto fino da V2 que está certo e vale preservar:** a IA só cala quando alguém **pega E envia
> mensagem**. Isso já é o comportamento da plataforma — `captain_can_respond?` olha o espelho, não o
> marcador, e é o `assignee` que zera o espelho. **Nada a codar para essa parte.**

---

## 7. Eixo 5 — Os RELÓGIOS

Seis relógios diferentes, e hoje **nenhum deles notifica ninguém**.

| Relógio | Origem | Hoje |
|---|---|---|
| **Janela do canal** | WhatsApp 24h · Instagram 24h ou 7d · TikTok 48h · API configurável | `MessageWindowService#hours_remaining` existe, **um** consumidor, painel não vê |
| **Expediente** | grade da unidade | **3 fontes divergentes** (unidade × behavior do agente × caixa) |
| **SLA de pickup** | `sla_assumir_minutos` (default 30) | existe, `repasse_automatico` = **false** |
| **SLA de primeira resposta** | — | não existe |
| **Cadência de follow-up** | `behavior['followup']` | existe; **o marcador de handoff PARA a cutucada** |
| **Prazo externo** | boleto, matrícula, promoção, safra | não modelado |

**O cruzamento que ninguém faz, e é o pedido do Paulo:** minutos de **expediente** restantes **dentro
da janela**. Hora de relógio engana — cliente escreve 7:00, janela fecha 7:00 do dia seguinte,
expediente abre 7:30: `hours_remaining` diz "23,9h" e o tempo útil é **zero**.

**Medido com os cortes propostos** (`<4h úteis → high`, `<1h útil → urgent`): das 2.550 abertas, **23
acenderiam** (7 urgent, 16 high). **Três dos 7 urgent têm ZERO minutos úteis, e 5 dos 7 já têm
assignee** — conversa atribuída também morre.

---

## 8. A TAXONOMIA DE "NÃOS" — o detector que falta

A §3 listou 12 saídas falsas. Todas têm uma propriedade que as torna detectáveis **sem julgar o
mérito da conversa**: a **última mensagem da IA tem forma reconhecível**.

| Forma do "não" | Marcadores (qualquer segmento) |
|---|---|
| ausência de estoque | *não temos · não há · não encontrei · sem disponibilidade · esgotado* |
| fora da área | *só atendemos em · apenas na região · não entregamos* |
| fora da faixa | *acima do que temos · o mais próximo é · nosso teto* |
| fora do catálogo | *não trabalhamos com · não vendemos · não oferecemos* |
| requisito | *é necessário · exige · sem isso não* |
| encerramento cordial | *qualquer coisa estou à disposição · obrigado pelo contato* |

**Por que isso é a peça de maior valor:**

1. **É determinístico e barato.** Não precisa LLM para a primeira passada — é padrão de texto na
   mensagem de saída da IA, cruzado com "o cliente não respondeu depois".
2. **Serve qualquer segmento.** As formas são as mesmas; só os substantivos mudam.
3. **Pega A e B, que nenhum instrumento atual pega.** E pega **antes** do cliente esfriar, não depois.
4. **Vira a fila de revisão humana com o melhor retorno possível:** conversas em que a IA estava
   **certa** e o negócio **perdeu**. É exatamente o balde que o Paulo quer ver antes de fechar o
   expediente.
5. **É o gatilho natural do "atenção"** da V2: a IA disse um "não" terminal → humano olha antes de
   acabar o dia.

**Cuidado registrado:** a detecção não pode virar regra de prompt proibindo a IA de dizer "não temos"
— isso produz invenção de estoque, que é pior. **A IA continua dizendo a verdade; o sistema marca
para revisão.**

---

## 9. Onde a Jev entra — e a restrição que o próprio Paulo definiu

A ideia do Paulo: Jev (TypeSafe) para **decidir** — janela de contexto pequena, rápida, prática. Ajudar
o modelo a saber **quando chamar tool ou executar ação**, e definir **prioridade** do atendimento.

**Onde faz sentido, e é forte:**

| Uso | Por quê |
|---|---|
| Classificar a **forma do "não"** (§8) | decisão fechada entre ~8 opções; é exatamente o que ela faz bem |
| Decidir a **faixa de prioridade** | escolha entre 4 níveis, com sinais explícitos |
| Decidir **se a conversa merece humano** | escolha binária com critério declarado |
| Decidir **se a conversa deve ser encerrada** | idem |
| **Segunda opinião em sombra** sobre o handoff do modelo grande | gera desacordo, e desacordo é o que aponta onde olhar |

**Onde NÃO faz sentido:** decidir **quando chamar tool** dentro do turno. A tool é escolhida no meio do
raciocínio do modelo grande, com o contexto inteiro; intercalar um segundo modelo ali acrescenta
latência e um ponto de falha no caminho crítico da resposta. **A decisão de tool se conserta com
descrição de tool e retorno tipado — camada 1-3 — não com um segundo juiz.**

**Restrição que o Paulo mesmo estabeleceu e que continua valendo:** trocar de modelo ou usar a Jev
como decisora **depende de existir dataset julgado por humano e baseline comparável**. Não começar por
aí.

**Mas há uma distinção que libera o começo:** Jev **em sombra** não precisa do dataset — ela **ajuda a
produzi-lo**. Rodando em paralelo, sem efeito, ela marca onde discorda do modelo grande, e o desacordo
é uma fila de revisão humana muito mais rica que amostra aleatória. **Sombra primeiro, decisão depois.**

**Pegadinhas da Jev já registradas, para não redescobrir:**
- o `confidence` de um `Choice` é **normalizado pelo número de opções** — comparar confiança entre
  decisões com contagens diferentes de opção falha **em silêncio**;
- **o critério manda mais que o modelo** — escrever bem as opções vale mais que trocar de modelo;
- **lista vazia é resposta**, não erro.

---

## 10. Eixo 6 — O QUE VARIA POR SEGMENTO

A parte que impede este desenho de ser "a Tozi com outro nome".

| Dimensão | Imobiliária (Tozi) | Ótica (Fábrica) | Clínica | SaaS / serviço |
|---|---|---|---|---|
| **Estoque** | item **único**, **captável** | SKU, **reponível** | **agenda**, não estoque | capacidade |
| **"Posso conseguir"** | captar imóvel | encomendar armação | encaixar horário | fila / plano maior |
| **Geografia** | decisiva (morar) · **negociável** (investir) | entrega | deslocamento do paciente | irrelevante |
| **Ciclo** | semanas a meses | minutos a dias | dias | dias a semanas |
| **Ticket** | alto | baixo/médio | médio | recorrente |
| **Quem decide** | casal / família | o próprio | paciente + convênio | comitê |
| **Elegibilidade** | renda, restrição, financiamento | receita médica | convênio, carência | contrato, porte |
| **O que é conversão** | visita · proposta · contrato | venda no balcão | consulta agendada | assinatura |
| **Pool de atendentes** | corretor por produto e faixa | vendedor de loja | recepção + profissional | suporte + CS |
| **"Prioridade alta" significa** | lead quente | cliente na loja agora | urgência clínica | churn iminente |
| **Encerrar é** | esfriou · descartado | não comprou | não agendou | não converteu |

**O que isso obriga no desenho:**

1. **Nada de "corretor", "imóvel", "MCMV", "Vista" no código compartilhado.** Vocabulário: *pool de
   atendentes, item, faixa de valor, fonte de catálogo*.
2. **A taxonomia de "nãos" (§8) é a mesma; os substantivos vêm da conta.**
3. **"Posso conseguir" é configuração por conta**, não regra de código: captar, encomendar, encaixar
   ou nada.
4. **Cada peça opt-in por conta, default = comportamento de hoje.** Já é a regra da casa.
5. **A prioridade usa o enum nativo** (`low/medium/high/urgent`), que é neutro. "Quente/frio" é como
   vendas **lê** `urgent/high`, não campo novo.

---

## 11. As FRENTES

Mapeadas contra o que já existe no gestão, para não duplicar.

| Frente | Cobre | Tarefa |
|---|---|---|
| **F1 · Máquina de estados** | Eixo 4, a visão V2, o estado "atenção" | **CHAT-146** (desenho) |
| **F2 · Taxonomia de "nãos" + detector** | Eixo 1, §8, **casos A e B** | **a criar** |
| **F3 · Encerramento pela IA + repescagem** | **caso C**, morte #2, `nao_encerrou` | **a criar** |
| **F4 · Prioridade por faixa** | **caso D**, Eixo 5 | **CHAT-143** |
| **F5 · Rodízio: ponteiro por faixa** | o lead ruim que queima a vez | **CHAT-144** + CHAT-125 |
| **F6 · Relógio universal + notificação de supervisor** | Eixo 5, as 1.843 janelas fechadas | **a criar** |
| **F7 · Jev em sombra** | §9 | **a criar** |
| **F8 · Revisão humana antes do expediente fechar** | a fila de "atenção" | **CHAT-137** |
| **F9 · Categorias que faltam no eval** | §5, 5 categorias novas | **a criar** |
| **F10 · Fonte única de horário** | Eixo 5, as 3 fontes divergentes | dentro de **CHAT-146** |

**Ordem de dependência:** F1 primeiro (define os estados) → F2, F3, F6 e F9 em paralelo (cada um é
independente) → F4 e F5 juntos (não faz sentido faixa sem ponteiro por faixa) → F7 depois de F9 (a
Jev precisa das categorias para ter o que decidir) → F8 consome tudo.

---

## 12. O que este documento NÃO decide

- **Nada foi implementado.** Nenhum arquivo de código tocado.
- As 5 categorias novas de eval (§5) são **proposta**, não decisão — mexer no enum do juiz muda a série
  histórica e precisa de decisão do Paulo.
- Os marcadores de texto da §8 são **ponto de partida**, a calibrar contra conversa real.
- A ordem da §11 é **sugestão**.

## Procedência

Todos os números vêm de leitura **somente-leitura** da conta 6 em `3.94.9.51`, feita entre 23 e
25/09/2026. Nada foi escrito e nada foi enviado a cliente. **Os 5 agentes da conta 1 (Fábrica) NÃO
foram lidos** — o servidor exige OK explícito do Paulo por vez. Enquanto isso não acontecer, a coluna
"Ótica" da §10 é **inferência a partir do segmento**, não medição.
