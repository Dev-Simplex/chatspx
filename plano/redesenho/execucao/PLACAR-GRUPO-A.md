# Placar do Grupo A — execução por etapas

Base: `origin/homologacao` = `ce3adb2be9` (intacta, nunca empurrada).
Integrado até aqui: **171 commits**, 22 migrations, 1.675 arquivos.

Regra do placar: **um bloco só conta como FECHADO se um cético independente,
que não o implementou, desfez a correção e viu o vermelho.** Relato de
implementador não fecha bloco.

## A1 — fundação (5 frentes)

| Bloco | Veredito | O que decidiu |
|---|---|---|
| 0.1 | **FECHADO** | v4.16.2 em `config/app.yml`; `isWidgetColorLighter` (a fórmula YIQ que a auditoria provou viva) morta, só resta comentário "AQUI VIVIA" |
| 1.04 + 1.03 | **FECHADO** | conflito de `sdk.js` resolvido à mão contando o que devia sobreviver: `var(--w-brand, #2dc46f)` ×3 e `var(--w-on-brand, var(--w-surface))` ×4 |
| demais | PARCIAL | cláusulas nomeadas abaixo |

## A2 — dado e identidade (8 ramos, zero conflitos)

| Bloco | Veredito | O que decidiu |
|---|---|---|
| 1.20 | **FECHADO** | `referer_raw` não vaza mais por ActionCable. O cético não aceitou o relato: escreveu sonda própria com `POST` real, leitura do banco como controle positivo e o listener real dentro de `perform_enqueued_jobs` — **sem dublê entre listener e broadcast**. Ainda mutou a constante para `[]` para provar que a metade IA não passava no vácuo |
| 1.19 | **FECHADO** | ids de clique respeitam o catálogo; verificador reverteu cada metade **separadamente** para provar que as duas acusam |
| 1.22 | **FECHADO** | — |
| 1.23 | **FECHADO** | — |
| 1.16, 1.11, 1.14 | PARCIAL | 1.14: "sobra um buraco do mesmo tamanho na mesma requisição, declarado fora de escopo com justificativa que a medição refuta" |
| 1.17 | PARCIAL | só falta a cláusula "validado em navegador real, claro e escuro" — escalada, não feita. **Reaberta como frente própria** |

## A3 — telas de configuração (8 de 9 ramos)

| Bloco | Veredito | O que decidiu |
|---|---|---|
| 3.06, 3.17, 3.14, 3.15 | **FECHADO** | — |
| 3.18 | **NÃO FECHOU** | metade do aceite morta em produção: o widget reporta quais chaves o site sobrepõe e **isso não chega ao servidor**, então a tela nunca avisa. Passou por todos os testes dele. Reaberto |
| 3.08 | PARCIAL | a cláusula refutada fechou de verdade: `SURFACE.dark` = `#2c2d36` bate com `WidgetTokens::SURFACE_DARK`, fixture byte a byte da saída do gerador |
| 3.10 | PARCIAL | causa verdadeira e consertada (inline vence classe; `.wp-tokens` fora / `.wp-theme-*` filho), mas não a letra do aceite |
| 3.07 | PARCIAL | aceite passa e é medido, porém três peças de um lado só e dois comentários que a evidência do commit refuta |
| **3.19** | **NUNCA RODOU** | a worktree do agente morreu em `No space left on device`. Reaberto |

## O que o disco custou

A máquina chegou a **934 MB livres** com 24 agentes abertos. Um verificador
bateu em `No space left on device` escrevendo `log/test.log`; o bloco 3.19
perdeu a worktree inteira e não rodou. Liberado para 5,0 GB removendo só
worktrees de etapa **concluída** e 46 bancos efêmeros — os `chatwoot_test_a3_*`
ficaram intactos porque a A3 ainda usava.

Lição para as etapas seguintes: **lotes**, não 16 blocos de uma vez, e
higiene de disco escrita no briefing de cada agente.
