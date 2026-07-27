# Relatório NPS — Junho/2026 · Tozi Imóveis

> **Pergunta que motivou este relatório:** "É muito estranho ter tantos atendimentos com tão poucos NPS."
> **Resposta curta:** a impressão está correta e tem explicação exata. De 8.394 atendimentos encerrados em junho, só 367 notas apareceram no painel (4,4%). Esse afunilamento acontece em 3 degraus — o maior deles é uma **regra do WhatsApp (Meta)**, não uma falha dos atendentes nem má vontade dos clientes. E um dos degraus era um **bug de configuração já corrigido**, que descartou ~70 notas reais em junho (quase todas nota 10).

*Auditoria 100% leitura no banco de produção (conta Tozi), realizada em 09/07/2026. Nenhum dado foi alterado.*

---

## 1. O funil de junho — onde os NPS "somem"

```
8.394  conversas encerradas em junho
   ↓  ── DEGRAU 1: janela de 24h do WhatsApp (85% barrado)
1.294  conversas receberam a pesquisa (15,4%)  →  2.083 envios no total
   ↓  ── DEGRAU 2: cliente não responde (comportamento normal)
  436  clientes responderam com nota (33,7% das conversas pesquisadas)
   ↓  ── DEGRAU 3: bug da expiração de 1 hora (corrigido em 01-03/07)
  367  notas capturadas e exibidas no painel
```

**4,4% dos atendimentos viram nota no painel = 15,4% × 33,7% × 84%.** Cada degrau explicado abaixo.

### Degrau 1 — 7.100 conversas encerradas SEM pesquisa (o maior fator, 85% do funil)

A pesquisa NPS é disparada **no momento em que a conversa é encerrada**. No WhatsApp oficial (Meta), só é permitido enviar mensagem de texto livre **até 24h após a última mensagem do cliente** — depois disso a Meta bloqueia o envio (regra da plataforma, sem exceção).

O que os dados mostram: as conversas do WhatsApp principal são encerradas **em lote, dias ou semanas depois do atendimento**:

- **11/06: 4.019 conversas encerradas num único dia** (54% do mês, em sequência ~18h50-19h00)
- **19/06: mais 1.854** num dia
- Das 7.100 sem pesquisa, **1.621 tinham a última mensagem do cliente entre 7 e 30 dias antes** do encerramento; 247 entre 3-7 dias; 144 com mais de 30 dias

Ou seja: quando a conversa foi encerrada, a janela da Meta já estava fechada há muito tempo — **era impossível enviar a pesquisa**. O sistema tentou em todas e registrou o bloqueio (7.338 registros "não enviada devido a restrições de envio" em junho).

**Prova de que o motor de envio funciona:** das conversas encerradas *dentro* da janela de 24h, **99,7% receberam a pesquisa** (307 de 308). E nas caixas sem janela da Meta (Financeiro e Prestação, via API), a cobertura foi **99,8% e 100%**.

| Caixa de entrada | Encerradas | Com pesquisa | Cobertura |
|---|---|---|---|
| WhatsApp FIXO (janela Meta de 24h) | 7.468 | 369 | **4,9%** |
| Financeiro (API, sem janela) | 543 | 542 | 99,8% |
| Prestação (API, sem janela) | 383 | 383 | 100% |

### Degrau 2 — taxa de resposta de ~34% (normal)

Das 1.294 conversas que receberam a pesquisa, 436 clientes responderam com nota (33,7% por conversa; 20,9% por envio). **Taxa de resposta de NPS via WhatsApp entre 20% e 40% é o esperado de mercado** — este degrau não tem anomalia.

### Degrau 3 — bug da expiração de 1 hora: ~70 notas reais de junho descartadas (CORRIGIDO)

De 03/02 a 01/07, a configuração de validade da pesquisa esteve em **1 hora** (deveria ser 48h). Consequência: **toda nota enviada pelo cliente mais de 1h depois da pesquisa era ignorada silenciosamente** — sem registro, sem aparecer no painel.

- **~70 notas legítimas de junho se perderam assim** (16% das respostas reais do mês)
- Eram respostas inequívocas: "10" seco (55 casos), "9", "8", "Nota 10"
- Perfil: **~88% notas 9-10** — os clientes que respondem mais tarde elogiam tanto quanto os rápidos
- Casos extremos: um cliente respondeu "10" **três vezes** em pesquisas diferentes e nenhuma contou; outro deu "9" duas vezes no mesmo dia
- A prova técnica: em maio e junho, **nenhuma** das 686 notas capturadas chegou mais de 1h após o envio (máximo 0,97h e 0,98h); em julho, com a config corrigida para 48h, já há capturas de até 14h depois

**Correção aplicada em 01/07 (WhatsApp) e 03/07 (Financeiro/Prestação)** — a partir de julho essas notas passam a contar. As ~70 de junho (e ~421 desde fevereiro) estão no banco e **podem ser reprocessadas retroativamente** se a Tozi desejar.

---

## 2. Impacto na bonificação por atendente (junho)

A boa notícia: **a nota média NÃO muda** com as perdas (NPS de junho: 77,66 → ~78,9 se incluídas as perdidas). O prejuízo é de **VOLUME**: atendentes receberam menos notas do que os clientes de fato deram.

| Atendente | Pesquisas enviadas | Notas contadas | Média | Notas perdidas (bug 1h) | Média das perdidas |
|---|---|---|---|---|---|
| (sem atendente atribuído) | 519 | 102 | 8,85 | 17 | 9,24 |
| Cibely Oliveira | 318 | 50 | 9,68 | 11 | 9,64 |
| Misya Correa | 201 | 45 | 9,22 | 4 | 10,0 |
| Claudia Kaminski | 98 | 31 | 9,03 | 4 | 9,5 |
| Natalia Silva | 185 | 29 | 9,48 | 5 | 9,4 |
| Paloma Abreu | 143 | 26 | 8,42 | 6 | 9,0 |
| Cibele Heloisa | 104 | 15 | 8,33 | 3 | 8,67 |
| Adrian Metzler | 86 | 15 | 9,60 | 8 | 9,25 |
| Camila Schlindvein | 127 | 11 | 9,09 | 3 | 10,0 |
| Maria Vitoria | 58 | 10 | 10,0 | 0 | — |
| Victória Fabonatto | 54 | 9 | 9,89 | 3 | 10,0 |
| Ana Paula De Oliveira | 40 | 7 | 10,0 | 2 | 10,0 |
| Gelson de Paula | 65 | 6 | 9,50 | 2 | 10,0 |
| Demais (8 atendentes) | 85 | 11 | — | 3 | 10,0 |

Destaques para a conversa de bonificação:

- **Adrian Metzler foi o mais prejudicado proporcionalmente**: 15 notas contadas + 8 perdidas (**+53%** se recuperadas)
- **Cibely Oliveira**: 50 + 11 perdidas (+22%)
- **102 notas contadas estão "sem atendente"** (conversa encerrada sem responsável atribuído — em geral resoluções automáticas/IA). Se a bonificação é individual, vale definir a regra de atribuição desses casos
- As notas perdidas têm média **igual ou superior** às contadas — nenhum atendente teria a média puxada para baixo pela recuperação

---

## 3. Resumindo a explicação para a Tozi

1. **"Muitos atendimentos, poucos NPS" é real e esperado no processo atual.** O grosso (85%) é a **janela de 24h da Meta**: como as conversas do WhatsApp são encerradas em lote dias/semanas depois do atendimento, a pesquisa não tem como ser enviada. Não é falha do atendente nem do sistema — é o momento do encerramento.
2. Dos que recebem a pesquisa, 1 em cada 3 responde — taxa normal.
3. Um bug de configuração (validade de 1h) descartou ~70 notas reais em junho, quase todas 10. **Já foi corrigido (01-03/07)** — julho naturalmente registrará mais notas sem qualquer mudança no atendimento.
4. O painel de "enviadas" também subconta (mostra 1.165 de 2.083 envios reais) — em correção.

## 4. Recomendações (decisão da Tozi)

| # | Ação | Efeito esperado |
|---|---|---|
| 1 | **Encerrar a conversa logo ao fim do atendimento** (não em faxina semanal) | Cobertura do WhatsApp sobe de 4,9% para perto de 99% — maior alavanca disponível, custo zero |
| 2 | **Reprocessar retroativamente as notas perdidas** (~70 de junho; 421 desde fevereiro — todas identificadas no banco) | Corrige a bonificação de junho e o histórico; mecanismo de recuperação já existe no sistema |
| 3 | Para encerramento tardio: **pesquisa via template aprovado da Meta (HSM)** | Alcança conversas fora da janela de 24h (tem custo por mensagem) |
| 4 | Definir regra de atribuição das notas "sem atendente" (102 em junho) | Bonificação individual completa |

---

*Metodologia: auditoria somente-leitura no banco de produção — trilha de auditoria de configurações, reconstrução do funil (encerramentos × envios × respostas × capturas) e releitura das mensagens originais dos clientes para validar cada nota perdida (falsos positivos como "5 de agosto" e valores monetários foram excluídos manualmente). Números de perdas variam ±2 conforme critério de deduplicação de pesquisas repetidas na mesma conversa.*
