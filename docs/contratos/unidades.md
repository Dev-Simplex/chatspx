---
titulo: Contrato — unidades do cliente (`unidades`, `unidade_horarios`, `unidade_excecoes`)
status: PROPOSTA — aguardando decisão do Paulo nas questões da §9
motivador: BigStore (conta 7), mas o desenho nasce agnóstico
data: 2026-08-17
---

# Contrato — unidades do cliente

> **Nomeado por capacidade, não por cliente.** O caso que motiva é a BigStore, mas isto é código
> compartilhado: precisa nascer genérico e opt-in por conta, pela mesma regra que foi violada
> quando conduta de óticas da Fábrica vazou pra Tozi.

## 1. O problema, medido

Hoje **não existe lugar nenhum no SPX** para as unidades físicas de um cliente. Verificado no
código em 17/08/2026:

- **`WorkingHour`** é por *inbox* — é quando o **SPX** atende, não quando a loja abre. Só dia da
  semana, sem endereço, sem telefone, **e sem nenhum conceito de exceção ou feriado** (procurado
  no repositório inteiro: não existe).
- **`Captain::CustomTool`** exige `endpoint_url`. Ele *consulta*, não *guarda*.
- **Knowledge/FAQ** responde por similaridade: ruim em listagem ("quais abrem domingo?") e
  incapaz de fazer conta de data.

Consequência na BigStore: o prompt da assistente diz literalmente *"você não tem nenhuma fonte de
dados conectada"*, e **toda** pergunta sobre horário, endereço, telefone ou preço vira handoff.
No n8n a mesma IA respondia, porque tinha uma Data Table com 22 linhas.

**O que fazia doer no n8n não era guardar — era a exceção.** A tabela só sabia expressar a regra
(`abre_domingo: true/false`), então "neste domingo as lojas de MT abrem" virava edição manual
linha a linha, e alguém tinha que lembrar de **desfazer** na segunda. Quem esquece, mente pro
cliente na semana seguinte.

## 2. O princípio

> **Regra padrão e exceção são coisas diferentes. A exceção tem data e morre sozinha.**

Duas camadas, como qualquer calendário resolve:

1. **Horário padrão** por unidade e dia da semana. Muda raramente.
2. **Exceção datada**, que vence e some. Ninguém precisa desmarcar nada.

E uma terceira propriedade, que é o que torna isso usável: **exceção vale para um conjunto**.
Campanha nunca é uma loja — é "as unidades de MT neste domingo". Com etiqueta na unidade isso é
**um registro**; sem etiqueta, você troca "editar 20 linhas" por "criar 20 exceções", e não
ganhou nada.

**Unidade que fechou é `ativa: false`, nunca linha apagada** — mesmo princípio do
`distribuicao_produtos`. O histórico continua legível e a IA para de oferecê-la.

## 3. Onde aparece

| Onde | O quê |
|---|---|
| `Configurações › Unidades` | A tela. Aba **Unidades** (cadastro, muda pouco) + aba **Exceções** (o que muda toda semana; lista só as futuras) |
| `Agentes IA › Ferramentas` | A `buscar_unidades` na lista de tools do agente, em leitura — onde se liga por agente |
| Tela de conversa | **Nada.** A IA consome; o atendente não ganha painel novo |

Fica em Configurações, e não dentro de Agentes IA, porque **o dado é do negócio, não do agente**
— amanhã serve a roteamento, relatório e campanha por região. Além disso o módulo de Agentes é
viewer por decisão de projeto, e esta tela precisa ser editável pelo cliente.

Item da sidebar gateado por conta (precedente literal: o *Internal Chat* já é), e admin-only.

## 4. Schema

```
unidades
  account_id, slug, nome, cidade, uf
  ativa       boolean  default true
  endereco    text
  telefone    string
  timezone    string   default 'America/Cuiaba'
  etiquetas   jsonb    []    -- agrupamento p/ exceção em lote
  atributos   jsonb    {}    -- campos livres POR CLIENTE
  índice único (account_id, slug)

unidade_horarios
  unidade_id, dia_semana (0..6)
  abre, fecha  time
  fechada      boolean default false
  índice (unidade_id, dia_semana)

unidade_excecoes
  account_id
  unidade_id   nullable  -- exceção de UMA unidade
  etiqueta     nullable  -- OU de um grupo
  data_inicio, data_fim  date
  fechada      boolean
  abre, fecha  time
  motivo       string
  índice (account_id, data_fim)
```

**`atributos`** é o que evita uma coluna nova por cliente: a BigStore guarda `valores` (faixa de
preço) ali; outro cliente guardará outra coisa. É texto para a IA ler, não filtro programático —
mesma disciplina do `apresentacao` em [`apresentacao-produto.md`](apresentacao-produto.md).

**Resolução (a regra que decide o que a IA responde):** exceção de unidade vence exceção de
etiqueta, que vence o horário padrão. **Mais específico vence.** Empate na especificidade, vence
a criada por último. Exceção sem `unidade_id` e sem `etiqueta` vale para a conta inteira (feriado
nacional).

## 5. A tool `buscar_unidades`

**Entrada:**

| param | tipo | obrigatório | descrição |
|---|---|---|---|
| `cidade` | string | não | o município que a pessoa citou **nesta conversa** |
| `quando` | string | não | a expressão de tempo **como a pessoa escreveu** |

⚠️ **REGRA #1 vale para a descrição dos parâmetros.** Nada de `(ex: <cidade>)` ou
`(ex: <expressão de data>)`: exemplo em descrição de parâmetro vira molde, e o modelo devolve o
exemplo quando não tem o dado. Já aconteceu — um exemplo de código de imóvel numa tool fez a IA
mandar sempre aquele imóvel. **Descreva a origem do valor, nunca um valor.**

**Saída** — por unidade: nome, cidade, UF, endereço, telefone, `atributos`, e o **estado
resolvido para a data pedida**: aberta ou fechada, horário, e o `motivo` quando o que valeu foi
uma exceção (a IA pode dizer *"neste domingo abre por causa da campanha"*, que é melhor resposta
que só o horário).

**O ganho concreto sobre o n8n:** lá, a sub-agente `buscar_lojas` recebia a instrução *"converta
expressões relativas de data para data absoluta ANTES de consultar"* — ou seja, o **modelo** fazia
calendário. É exatamente onde ele erra, e erra com convicção. Aqui `amanhã`, `domingo que vem` e
`está aberta agora?` são resolvidos **em Ruby**, no fuso da unidade. A IA recebe pronto.

## 6. O "não achei" é conduta, não só retorno

Quando não houver unidade na cidade, a tool devolve **ausência explícita** — distinguível de
falha de consulta. E isso **não basta**: o prompt do agente precisa saber o que fazer com esse
"não".

Foi a lição da Fábrica, em 12/08: a guarda passou a devolver `NAO_ACHOU_LOJA`, o prompt da Bia
não conhecia esse retorno, ela **ignorou** e seguiu qualificando o cliente — gênero, presente,
CPF — até ele descobrir no fim que não havia loja. Guarda sem conduta correspondente cria beco
sem saída.

## 7. Multi-tenant

Conta sem unidade cadastrada não muda de comportamento: a tool não entra no toolset do agente
(o `configured_agent_tools` já gateia por `active?`), o item some da sidebar, nada acontece.

Segundo consumidor já visível: a **Fábrica**, cuja IA hoje pergunta ao MTM qual a loja mais
próxima e recebe endereço do **Atacadão** — marca errada, medido 3 de 3 em 12/08. Uma tabela de
unidades por conta, com etiqueta de marca, dá ao SPX um lugar de onde filtrar sem depender do
sistema do cliente. **Não substitui o MTM** — o estoque e a agenda continuam lá.

## 8. Não-objetivos

- **Não** é agenda de atendimento do SPX (isso é `WorkingHour`, por inbox) nem o
  `business_hours` do Captain (que decide se a IA responde). São três coisas distintas e não
  devem se misturar.
- **Não** guarda estoque, produto nem preço por item.
- **Não** tem hierarquia (rede → regional → loja). Taxonomia plana com etiquetas, pelo mesmo
  motivo do `distribuicao_produtos`: hierarquia rígida quebra na primeira exceção.
- **Não** faz roteamento nesta fase. Mandar conversa para o time da unidade é outra frente.

## 9. Questões em aberto — decisão do Paulo

1. **Fases.** Proposta: (1) tabelas + tool + carga por rake, e a IA já responde; (2) tela de
   **exceções**, que é o que muda toda semana; (3) CRUD de unidades. A prioridade é invertida de
   propósito — endereço muda uma vez por ano e eu carrego; exceção muda toda semana e **precisa**
   ser do cliente, senão a gente reconstruiu a dor do n8n com mais passos.
2. **Quem edita a exceção do lado do cliente?** Se for uma pessoa só, a tela é trivial. Se for o
   gerente de cada unidade, entra permissão por unidade e o desenho cresce.
3. **Exceção precisa de aprovação?** Uma unidade se declarar aberta num domingo em que não abre
   custa cliente na porta fechada.
4. **A IA pode dizer o `motivo` da exceção?** *"Neste domingo abre por causa da campanha de
   aniversário"* é melhor atendimento, mas expõe calendário comercial no direct.
