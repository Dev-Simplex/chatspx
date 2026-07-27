# Comprovação — Conversas sem NPS: janela de 24h e fechamentos em massa

> **Objetivo:** comprovar, com evidências do banco de produção, que a massa de conversas sem NPS nos relatórios anteriores decorre da **janela de 24h do WhatsApp (Meta)** — e demonstrar o **padrão de fechamento em massa** que a provoca. Período analisado: janeiro a 09/julho/2026. Auditoria 100% leitura, 09/07/2026.

São **três evidências independentes** que se confirmam mutuamente.

---

## Evidência 1 — O log do próprio sistema: bloqueios registrados ≈ gap, mês a mês

Toda vez que o sistema tenta enviar o NPS e a Meta bloqueia, ele grava na conversa a atividade:
*"Pesquisa NPS não foi enviada devido a restrições de envio de mensagens"*.

Esse registro, comparado com o gap de cada mês, fecha quase 1:1 desde fevereiro:

| Mês | Encerradas | Com NPS | Sem NPS (gap) | **Bloqueios de janela registrados** | Cobertura |
|---|---|---|---|---|---|
| Jan* | 1.844 | 397 | 1.447 | 681 | 21,5% |
| Fev | 2.475 | 1.297 | 1.178 | **1.309** | 52,4% |
| Mar | 2.721 | 1.308 | 1.413 | **1.590** | 48,1% |
| Abr | 3.023 | 1.091 | 1.932 | **2.182** | 36,1% |
| Mai | 2.754 | 1.232 | 1.522 | **1.671** | 44,7% |
| **Jun** | **8.394** | **1.294** | **7.100** | **7.340** | **15,4%** |
| Jul (até 09/07) | 766 | 488 | 278 | 223 | 63,7% |

*\*Janeiro: NPS foi ativado em 21/01, por isso o gap não fecha com os bloqueios (conversas encerradas antes da ativação não geraram registro).*

Os bloqueios superam levemente o gap porque a mesma conversa pode registrar mais de um bloqueio (re-encerramentos). **A cobertura despenca exatamente nos meses de faxina em lote (abril 36%, junho 15%) e sobe quando não há faxina (julho 64%).**

## Evidência 2 — O estado da janela no momento exato do encerramento

Para cada conversa do WhatsApp FIXO encerrada em junho, calculamos a distância entre o encerramento e a **última mensagem do cliente**:

| Situação da janela no encerramento | Conversas | % | NPS possível? |
|---|---|---|---|
| **Cliente nunca enviou mensagem** (conversas de campanha/prospecção sem resposta) | **4.720** | 63% | Não — sem mensagem do cliente, a janela da Meta **nunca existiu** |
| **Janela fechada** (última msg do cliente > 24h antes; mediana **325,7h ≈ 13,6 dias**) | **2.440** | 33% | Não — Meta bloqueia texto livre |
| **Janela aberta** (< 24h) | **308** | 4% | Sim — e **307 receberam NPS (99,7%)** |

O motor de envio funcionou em **99,7% dos casos em que era possível enviar**. Todo o resto era estruturalmente impossível.

## Evidência 3 — O padrão de fechamento em massa (existe e é recorrente)

### Anatomia do maior evento: 11/06/2026

- **4.111 conversas encerradas em um único dia** — o dia normal tem 100-300;
- **3.310 delas entre 18h e 19h**, com pico de **555 encerramentos por minuto** (impossível manualmente uma a uma — ação em lote);
- Executado por **3 operadores**: Kettlen Micoanski (1.169), Lucas Souza (1.160) e Bruno Reis (1.086) — 83% do dia;
- **98% dessas conversas (4.027) nunca tiveram resposta do cliente**: eram conversas de **campanha de prospecção ativa** ("Oi, aqui é Bruno, da Tozi Imóveis...", "Quis te mostrar uma oportunidade antes de abrir ao público: lançamento...") que ficaram abertas sem retorno e foram limpas de uma vez;
- O sistema registrou **4.016 bloqueios de janela nesse mesmo dia**.

### Segundo maior: 19/06/2026

- **1.937 encerramentos**; conversas com mediana de **351 horas (14,6 dias)** desde a última mensagem do cliente;
- **96,8% com janela fechada** no momento do encerramento;
- Executado por automação (566) + Lucas Souza (493) + Kettlen Micoanski (458);
- 1.857 bloqueios de janela registrados no dia.

### O padrão se repete nos meses anteriores

| Dia | Encerramentos | Mediana de idade (última msg do cliente) | % janela fechada | Bloqueios no dia | Principais executores |
|---|---|---|---|---|---|
| 04/03 | 297 | 40,5h | 75,3% | 188 | Gelson, Adrian |
| 09/04 | 482 | 118,8h (~5 dias) | 83,3% | 412 | Adrian, Gelson |
| 15/04 | 307 | 55,7h | 72,0% | 186 | Adrian, Emily |
| 24/04 | 302 | 101,5h (~4 dias) | 69,6% | 183 | Gelson, Adrian |
| 15/05 | 385 | 78,4h (~3 dias) | 76,9% | 268 | Gelson, Adrian |
| 18/06 | 474 | 72,9h (~3 dias) | 82,8% | 410 | Lucas, Adrian, Bruno |
| **11/06** | **4.111** | (98% sem msg do cliente) | ~98% | **4.016** | Kettlen, Lucas, Bruno |
| **19/06** | **1.937** | **351,3h (~15 dias)** | **96,8%** | **1.857** | Automação, Lucas, Kettlen |

**Padrão confirmado**: desde março existem dias de "faxina" — centenas a milhares de conversas velhas (ou de campanha sem resposta) encerradas em lote, sempre com a janela da Meta já fechada. Nos dias normais, os atendentes encerram no fluxo e o NPS sai.

---

## Implicação importante para a leitura dos relatórios

A régua "8.394 atendimentos em junho" está **inflada por conversas de campanha**: 4.720 delas eram prospecção ativa que o cliente nunca respondeu — **não houve atendimento** (e NPS não se aplicaria). Corrigindo a régua:

- **Atendimentos reais de junho** (com interação do cliente): ~3.674
- Pesquisados: 1.294 → **cobertura real de ~35%**
- O restante (~2.380) foi encerrado tardiamente, com janela fechada (mediana de ~14 dias após a última mensagem do cliente)

## Conclusão

**Comprovado.** A massa de conversas sem NPS tem duas origens, ambas ligadas à janela de 24h:

1. **Conversas de campanha sem resposta** (63% do gap de junho) — a janela nunca existiu; NPS estruturalmente impossível e conceitualmente não aplicável;
2. **Encerramento tardio/em lote de conversas velhas** (33%) — janela já expirada há dias quando a faxina acontece.

O log do sistema (7.340 bloqueios registrados em junho), a análise estrutural da janela e o padrão temporal dos fechamentos em massa (com dia, hora, volume por minuto e executores identificados) contam a mesma história de forma independente. **O motor de NPS enviou em 99,7% dos casos possíveis.**

Recomendações práticas: separar campanhas de atendimentos nos indicadores (não contam para NPS); encerrar atendimentos reais dentro da janela; para conversas velhas, considerar NPS via template HSM aprovado (com custo por mensagem).

---

*Metodologia: reporting_events (encerramentos, com autor e timestamp), nps_responses (envios), messages (atividades de bloqueio geradas pelo sistema; última mensagem do cliente antes de cada encerramento via SQL). Auditoria somente-leitura em produção; nenhum dado alterado.*
