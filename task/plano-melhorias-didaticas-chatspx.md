# Task: Melhorias didáticas do ChatSPX (2 features) — plano para executar depois

**Origem:** análise do ChatSPX (doc em `~/Downloads/ChatSPX-Ideias-de-Melhoria.{md,pdf}`).
**Lente:** deixar o uso do chat o mais **didático/intuitivo** possível (curva de aprendizado mínima — para o agente operar e para o cliente se autoexplicar).
**Status:** plano de implementação detalhado em geração (squad/workflow `chatspx-didactic-plan`, run `wf_4f13d619-df7`). Saída final irá para `~/Downloads/`.
**Regra:** isto é PLANEJAMENTO. Nenhum código alterado ainda. Implementar na branch `nicolas`, validar no staging `nicolas.chatspx.app` ANTES da frota.

> ❌ A melhoria de **Atalhos de teclado + "/" + cheat-sheet** foi **descartada** pelo usuário (não será implementada).

---

## As 2 melhorias (em ordem didática)

### 🥇 #1 — Respostas sugeridas por IA inline + botão "Resumir conversa" (item 2.5)
**Por que é didática:** tira a dúvida "o que eu respondo?" e "o que aconteceu aqui antes?". 3 sugestões com 1 clique = professor ao lado do agente; resumo no topo deixa pegar conversa transferida sem ler 50 mensagens.
**Reuso:** infraestrutura Captain/Copilot JÁ existe — é amplificar o uso.
**Efeito:** padroniza o tom do atendimento e elimina o "branco" do agente iniciante.

### 🥈 #2 — Listas e botões interativos nativos do WhatsApp (item 2.1)
**Por que é didática:** deixa o lado do CLIENTE autoexplicativo. Em vez de "digite 1 para Financeiro, 2 para Suporte", o cliente vê botões reais e toca → fluxo guiado, menos erro de triagem, menos retrabalho do agente.
**Estado no código:** botões só existem dentro de templates; há TODO para listas/botões interativos livres; recebimento já parseia `button_reply`/`list_reply`, mas o envio livre não está completo (WAHA).
**Efeito:** atendimento intuitivo para quem está do outro lado, não só para o operador.

**Lógica do conjunto:** #1 ensina o **agente** a responder · #2 ensina o **cliente** a se conduzir.

---

## Prompt original do usuário (verbatim)

> chame seu squad e faça este prompt
>
> 2. Respostas sugeridas por IA inline + "Resumir conversa" — (item 2.5)
> Por que é didática: tira a dúvida "o que eu respondo?" e "o que aconteceu aqui antes?". As 3 sugestões com 1 clique funcionam como um professor ao lado do agente, e o resumo no topo deixa qualquer um pegar uma conversa transferida sem ler 50 mensagens. A infraestrutura de IA (Captain/Copilot) já existe — é amplificar o uso.
> Efeito: padroniza o tom do atendimento e elimina o "branco" do agente iniciante.
>
> 🥉 3. Listas e botões interativos nativos — (item 2.1)
> Por que é didática: essa deixa o lado do cliente autoexplicativo. Em vez de "digite 1 para Financeiro, 2 para Suporte" (que confunde e gera erro), o cliente vê botões reais e toca. A conversa vira um fluxo guiado — menos erro de triagem, menos retrabalho do agente.
> Efeito: o atendimento fica intuitivo para quem está do outro lado, não só para o operador.
>
> Resumo da lógica: a #1 ensina o agente a usar a ferramenta, a #2 ensina o agente a responder, e a #3 ensina o cliente a se conduzir. Juntas, cobrem o "didático" de ponta a ponta.
>
> Onde eu começaria: pela #1 (atalhos + "/") — é a de menor esforço e a que mais reduz a curva de aprendizado imediatamente.
>
> monte o plano de implementação detalhado para executar depois.

**Atualização posterior:** usuário pediu para **remover a melhoria de atalhos**. Restam IA inline+resumo e listas/botões interativos.

---

## Próximo passo
Quando o workflow concluir, o plano detalhado por feature (arquivos a tocar, passos backend/frontend, testes, validação no staging, riscos, esforço) será consolidado em documento em `~/Downloads/`. Executar na ordem #1 (IA) → #2 (interativas).
