# Relatório geral de disparos — Tozi Imóveis

> Inbox 91 (WhatsApp Cloud API, número fixo Tozi). Dados extraídos da **base de produção em 2026-06-08**, contados por **mensagem HSM enviada** (status real de entrega da Meta). Período dos disparos: **02–08/jun/2026**.
> Status Meta: `sent` = aceito, aguardando entrega · `delivered` = entregue no aparelho · `read` = lido (tique azul) · `failed` = falhou.

## Resumo executivo

| Métrica | Valor |
|---|---|
| **HSM disparadas** | **7.249** |
| Alcançadas (entregue + lido) | **6.119** — **84,4%** |
| Lidas (tique azul) | **4.409** — **60,8%** |
| Falhas | **982** — **13,5%** |
| Pendentes (aceitas, sem confirmação) | 148 — 2,0% |
| Contatos únicos atingidos | 6.200 |
| **Contatos que responderam** | **1.501 — 24,2%** |
| Custo estimado (todas MARKETING) | **~US$ 382 ≈ R$ 1.950** |

## Por segmento

| Segmento | HSM | Alcançadas | Lidas | Falhas | Pendentes |
|---|---:|---:|---:|---:|---:|
| Lançamento / Locação (camp. 1) | 1.612 | 1.396 | 1.075 | 183 | 33 |
| Venda (camp. 2) | 3.426 | 2.807 | 2.058 | 562 | 57 |
| Inquilinos (com imagem) | 1.178 | 945 | 612 | 203 | 30 |
| Follow-up (re-bate em não-respondentes) | 1.027 | 965 | 659 | 34 | 28 |
| Lead / cadência (orgânico) | 6 | 6 | 5 | 0 | 0 |
| **TOTAL** | **7.249** | **6.119** | **4.409** | **982** | **148** |

> O follow-up (1.027) **não é audiência nova** — é o 2º toque nos não-respondentes de Lançamento/Venda. Nota: o follow-up teve a **menor taxa de falha** (3,3%) porque mandou na conversa que já existia (número já "conhecido").

## Detalhe por template

| Template | Enviadas | Alcançadas | Lidas | Falhas |
|---|---:|---:|---:|---:|
| **Lançamento/Locação** | | | | |
| tozi_lancamento_interagir | 300 | 260 | 212 | 34 |
| tozi_lancamento_qualifica | 228 | 199 | 151 | 26 |
| tozi_lancamento_curiosidade | 228 | 196 | 145 | 28 |
| tozi_lanc_prioridade | 276 | 238 | 184 | 30 |
| tozi_lanc_portfolio | 277 | 242 | 190 | 28 |
| tozi_lanc_investidor | 276 | 238 | 177 | 33 |
| tozi_disparo_interagir *(nome legado)* | 27 | 23 | 16 | 4 |
| **Venda** | | | | |
| tozi_venda_abertura *(curto)* | 1.645 | 1.350 | 1.017 | 265 |
| tozi_venda_condicao | 399 | 334 | 234 | 60 |
| tozi_venda_suites | 399 | 328 | 240 | 64 |
| tozi_venda_invest | 397 | 313 | 222 | 77 |
| tozi_venda_oportunidade *(A/B)* | 137 | 110 | 70 | 27 |
| tozi_venda_lembrei *(A/B)* | 135 | 112 | 82 | 21 |
| tozi_venda_condicoes | 105 | 83 | 63 | 20 |
| tozi_venda_prioridade | 105 | 94 | 69 | 10 |
| tozi_venda_investidor | 104 | 83 | 61 | 18 |
| **Inquilinos (imagem)** | | | | |
| tozi_inq_lancamento | 396 | 312 | 198 | 70 |
| tozi_inq_cliente | 392 | 308 | 196 | 73 |
| tozi_inq_invest | 390 | 325 | 218 | 60 |
| **Follow-up** | | | | |
| tozi_followup_lanc | 1.025 | 963 | 658 | 34 |
| tozi_followup_horario_combinado | 2 | 2 | 1 | 0 |
| **Lead** | | | | |
| tozi_lead_followup | 6 | 6 | 5 | 0 |

## Análise de falhas (982 = 13,5%)

- **Venda concentra 57% das falhas** (562). É a base mais fria (vendedores), número estava **YELLOW** durante parte do disparo → a Meta throttla marketing cedo. O template **curto `tozi_venda_abertura`** sozinho teve 265 falhas (16% dele) — volume alto numa base com muito número morto.
- **Inquilinos: 17% de falha** (203/1.178) — lista com muito contato inativo/sem WhatsApp (o Guilherme já tinha avisado).
- Causas recorrentes (sessões anteriores): números **sem WhatsApp** (ex. prefixo 131026) e **pacing da Meta** (130472/131049) em número degradado.

## Custo

Todos os 23 templates são **MARKETING** → cobrados por mensagem **entregue**. Base autoritativa de uma sessão anterior: 2.162 entregues = US$ 135,12 → **US$ 0,0625/msg**.
- Estimativa total: **6.119 entregues × US$ 0,0625 ≈ US$ 382 ≈ R$ 1.950** (câmbio ~5,10).
- ⚠️ Estimativa. **Valor exato** = Meta `pricing_analytics` (Graph API, por período). Posso puxar o acumulado fechado se precisar pro financeiro.

## A/B qualificado (venda)

`tozi_venda_oportunidade` vs `tozi_venda_lembrei` (botões iguais, isola a copy):
- oportunidade: 137 env, **51% lidas** (70).
- lembrei: 135 env, **61% lidas** (82).
- ⚠️ Leitura ≠ o objetivo do teste. A métrica real é **resposta QUALIFICADA** (cliques "Quero saber" + interesse real). Não medida aqui — pendente cruzar os cliques de botão.

## Notas

- **Respostas (1.501 = 24,2%)** contadas a nível de contato (≥1 incoming). Após a **consolidação de 08/06** (275 contatos com conversa duplicada fundidos), pode incluir algum histórico de atendimento antigo no mesmo fio — então é um teto, não piso.
- **Saúde do número:** degradou pra YELLOW no auge do disparo frio e **recuperou GREEN** após pausa + alto engajamento (o template curto que gera resposta protege a reputação; pitch longo em base fria derruba).
- Distribuição por corretor: round-robin entre Kettlen (#126), Lucas (#127), Marcus (#128), Bruno (#131) — variando por lote (alguns lotes só Bruno+Lucas, o A/B só Kettlen).
