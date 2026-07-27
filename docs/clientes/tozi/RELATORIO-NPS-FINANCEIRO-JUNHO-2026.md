# Relatório NPS — Junho/2026 · Departamento Financeiro · Tozi Imóveis

> **Escopo:** caixa de atendimento **[Tozi] Financeiro** (canal API, sem janela de 24h da Meta). Visão complementar do time "financeiro e suporte" ao final. Auditoria 100% leitura no banco de produção, 09/07/2026.

## Resumo executivo

O Financeiro é o departamento com a apuração **mais saudável** da Tozi: **99,8% das conversas encerradas receberam a pesquisa** (543 encerradas → 542 pesquisadas — no restante da operação esse número é 15%). Aqui o funil perde em dois pontos: a taxa de resposta natural (1 em cada 3 clientes responde — normal) e o **bug da expiração de 1 hora**, que descartou **31 notas reais do departamento em junho (17% do total)** — já corrigido em 01-03/07. O NPS do Financeiro em junho foi **83,89** (média 9,37); com as notas perdidas incluídas, seria **~85,6**.

## O funil do Financeiro (junho)

```
543  conversas encerradas na caixa Financeiro
 ↓   cobertura de envio: 99,8% (542) — sem janela Meta neste canal      [911 envios no total]
542  conversas pesquisadas
 ↓   taxa de resposta: 33,2% (padrão de mercado: 20-40%)
180  clientes responderam com nota
 ↓   bug da expiração de 1 hora (corrigido em 01-03/07): –31 notas
149  notas contadas no painel
```

## Indicadores de junho (contados no painel)

| Indicador | Valor |
|---|---|
| NPS | **83,89** |
| Média das notas | **9,37** |
| Promotores (9-10) | 133 (89%) |
| Passivos (7-8) | 8 |
| Detratores (0-6) | 8 |
| Distribuição | 123×"10" · 10×"9" · 7×"8" · 1×"7" · 8 notas ≤6 |

## As 31 notas perdidas (bug da expiração de 1h)

Perfil: **23 notas "10", 6 notas "9", 1 "8", 1 "7" — média 9,65** (acima da média contada). Todas respostas inequívocas ("10", "9", "Nota 10") que chegaram mais de 1h após a pesquisa e foram descartadas em silêncio. Com elas, o NPS de junho do Financeiro subiria de 83,89 para **~85,6** e o volume de avaliações cresceria 21%.

## Por atendente (caixa Financeiro, junho)

| Atendente | Pesquisas enviadas | Notas contadas | Média | Notas perdidas (bug 1h) | Média das perdidas |
|---|---|---|---|---|---|
| Misya Correa | 161 | 37 | 9,32 | 2 | 10,0 |
| Cibely Oliveira | 212 | 35 | 9,60 | 8 | 9,63 |
| (sem atendente atribuído) | 125 | 23 | 9,13 | 6 | 9,83 |
| Claudia Kaminski | 59 | 18 | 9,39 | 3 | 10,0 |
| Natalia Silva | 81 | 7 | 10,0 | 4 | 9,0 |
| Camila Schlindvein | 102 | 7 | 8,57 | 1 | 10,0 |
| Paloma Abreu | 40 | 7 | 8,29 | 2 | 10,0 |
| Gelson de Paula | 34 | 5 | 9,60 | 2 | 9,5 |
| Victória Fabonatto | 22 | 4 | 10,0 | 0 | — |
| Maria Vitoria | 13 | 2 | 10,0 | 0 | — |
| Ivanete Motta | 23 | 1 | 10,0 | 0 | — |
| Ana Paula De Oliveira | 11 | 1 | 10,0 | 0 | — |
| Adrian Metzler | 17 | 1 | 10,0 | 1 | 8,0 |
| Ingridy Born | 3 | 1 | 10,0 | 0 | — |
| Cibele Heloisa | 8 | 0 | — | 2 | 10,0 |
| **Total** | **911** | **149** | **9,37** | **31** | **9,65** |

Destaques para a bonificação:

- **Cibele Heloisa ficou ZERADA no Financeiro em junho** — as 2 únicas notas que recebeu (ambas 10) caíram no bug. Caso mais grave do departamento.
- **Natalia Silva**: 7 contadas + 4 perdidas (**+57%** se recuperadas).
- **Cibely Oliveira**: 35 contadas + 8 perdidas (+23%) — maior volume absoluto perdido.
- **23 notas contadas estão "sem atendente"** (encerramento sem responsável atribuído) + 6 perdidas nessa mesma condição — definir regra de atribuição se a bonificação é individual.
- As perdidas têm média 9,65 (≥ contadas): recuperar **não derruba a média de ninguém**.

## Visão complementar: time "financeiro e suporte"

Existe também a marcação de **time** (equipe) "financeiro e suporte" nas conversas — 341 encerradas em junho, espalhadas por 3 caixas (176 na caixa Financeiro, 104 no WhatsApp FIXO, 61 na Prestação). Nesse recorte: cobertura 81,5% (as do WhatsApp FIXO sofrem a janela de 24h da Meta), **65 notas contadas, NPS 87,69, média 9,6**, e 14 notas perdidas pelo bug. A marcação de time é aplicada de forma irregular (só 176 das 543 conversas da caixa Financeiro têm o time marcado), por isso a caixa é o recorte mais confiável para bonificação.

## Recomendações específicas do Financeiro

1. **Reprocessar as 31 notas perdidas de junho** — impacto direto na bonificação (uma atendente zerada, outra com +57%); mensagens e datas preservadas no banco.
2. **Definir atribuição das 29 notas "sem atendente"** (23 contadas + 6 perdidas).
3. **Não é preciso mudar o processo de encerramento do Financeiro** — a cobertura de 99,8% mostra que este departamento já encerra dentro do fluxo correto. O problema de cobertura (janela de 24h) é dos atendimentos no WhatsApp FIXO.
4. Padronizar a **marcação do time** nas conversas do departamento, se quiserem relatórios por equipe além de por caixa.

---

*Metodologia: mesma auditoria somente-leitura do relatório geral de junho (funil encerramentos × envios × respostas × capturas + releitura das mensagens originais para validar cada nota perdida; falsos positivos excluídos manualmente). Duas das 31 notas perdidas chegaram após 48h (limites de 53,6h e 119,6h) — mesmo com a configuração corrigida elas não teriam sido capturadas, mas são notas reais dadas pelos clientes.*
