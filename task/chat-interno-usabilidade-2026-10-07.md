# Chat interno — usabilidade (07/10/2026)

Pedido: "melhore a usabilidade do chat interno, ele precisa ser intuitivo, fácil de usar".
O visual (estilo iMessage) ficou como está; aqui o foco é o **uso**: achar, entender e terminar a tarefa sem pensar.

Ambiente: staging `nicolas.chatspx.app`, branch `nicolas`, conta 1, logado como **QA Admin (id 18)**.
Prints em `chat-interno-usabilidade-prints/` (prefixo `ux-antes-` e `ux-depois-`).

---

## 1. Avaliação ANTES (como um atendente novo)

Cada tarefa foi feita no navegador (Chrome, 1440 e 1024 px, claro e escuro). "Cliques" conta só o caminho feliz,
sem as hesitações; a coluna "o que o usuário sente" é o que trava.

| # | Tarefa | Cliques | O que aconteceu / o que o usuário sente |
|---|--------|---------|------------------------------------------|
| a | Mandar mensagem a um colega pela 1ª vez | 3 + rolar | "Nova conversa" abre uma janelinha com **20 nomes e só 5 visíveis**, sem campo de busca: tem de rolar e ler nome por nome. Se ele digita o nome na busca da lista ("Natalia"), a tela responde **"Nenhuma mensagem encontrada"** — parece que a pessoa não existe. (`ux-antes-nova-conversa.png`, `ux-antes-busca-pessoa-sem-conversa.png`) |
| b | Criar um grupo com 3 pessoas | 6 + rolar | Aba "Novo grupo": o campo do nome não tem rótulo (só o exemplo "ex.: Plantão do fim de semana"), a lista de pessoas não tem busca nem diz quantas foram marcadas, e o botão **"Criar grupo" fica apagado sem dizer por quê** (falta o nome). A aba "Grupos de time" quebra em duas linhas. (`ux-antes-novo-grupo.png`) |
| c | Achar uma conversa antiga e uma mensagem | 2 | A busca acha a mensagem ("almo" → Ana Paula), mas o clique **abre a conversa no fim**, não na mensagem: o usuário tem de rolar e procurar de novo. Não há seção "Conversas" separada dos resultados. (`ux-antes-busca-mensagem.png`) |
| d | Responder a uma mensagem específica | 3 (com hover certeiro) | A única porta é uma **setinha ⌄ que só aparece ao passar o mouse dentro do balão**, no canto. Quem não sabe não acha; no toque é pressionar e segurar. Depois de achar, o menu tem rótulos e funciona bem. (`ux-antes-hover-balao.png`, `ux-antes-menu-mensagem.png`) |
| e | Mencionar alguém | 2 | Bom: "@" abre a lista com a dica "a pessoa recebe um aviso"; Enter escolhe. (`ux-antes-mencao-lista.png`) |
| f | Anexar arquivo e gravar áudio | 2 / 3 | Bom: chip do anexo antes de enviar; áudio com "Gravando 0:02", prévia e "Ouça e envie, ou descarte". (`ux-antes-anexo-chip.png`, `ux-antes-audio-gravando.png`, `ux-antes-audio-previa.png`) |
| g | Compartilhar uma conversa de cliente | 3 + rolar | Na conversa do cliente, ⋮ › "Compartilhar no chat interno" abre a janela; a lista **"CANAIS" mistura grupos com conversas de 1 a 1** (a Ana Paula aparece em "Canais" e de novo em "Pessoas"), sem busca. Citar `#905` no texto funciona e vira link. (`ux-antes-compartilhar-dialogo.png`) |
| h | Silenciar / favoritar / sair de um grupo | 2 cada | Favoritar move a conversa para "Favoritas" (dá para perceber). Silenciar só troca um sininho de 12 px. **"Sair do grupo" sai na hora, sem perguntar e sem volta** (não dá para se readicionar). (`ux-antes-menu-mais.png`, `ux-antes-h-favoritou-1024-claro.png`) |
| i | Ligar os avisos automáticos na sala do time | 2 | Bom: Detalhes › "Avisos automáticos" com chave, texto do que faz e "Salvo. Os avisos novos aparecem em até 5 minutos". (`C-11-detalhes-light.png` da rodada anterior) |
| j | Editar / apagar / reagir | 3 cada | Mesma porta escondida do item d. O menu diz **"Excluir"** e a confirmação diz **"Apagar mensagem?"** — duas palavras para a mesma coisa, e não diz que some para todos. A confirmação cobre o próprio texto. Se editar/apagar/reagir falhar no servidor, **nada aparece** (erro só no console). (`ux-antes-apagar-confirma.png`, `ux-antes-apagada.png`) |
| k | Voltar depois de horas e entender o que é novo | 1 | Bom: "2 conversas com mensagem nova" no topo, ponto e número na conversa, "Abrir Ana Paula de Oliveira" na tela inicial e o divisor **"Mensagens novas"** dentro da conversa. (`ux-antes-k-voltar-1024-claro.png`, `ux-antes-k-nao-lidas-1024-claro.png`) |
| l | Só teclado e tela de 1024 px | — | **Esc não fecha nada**: nem o menu ⋮, nem a janela "Nova conversa", nem a busca na conversa, nem o painel Detalhes. Não há atalho para nova conversa, buscar ou ir para a próxima conversa (o Ctrl+K abre a paleta geral do sistema). O foco do teclado aparece (anel preto do navegador). A 1024 px o convite "Quer ser avisado…" cobre um terço da lista. (`ux-antes-esc-compose.png`, `ux-antes-menu-mais-esc.png`, `ux-antes-ctrl-k-1024-claro.png`, `ux-antes-detalhes-1024-escuro.png`) |

### Heurísticas de Nielsen (o que pesa)

| Heurística | Situação |
|---|---|
| 1. Visibilidade do estado | Boa em envio (Enviando / Entregue / Lida / Não enviada · tentar de novo) e em não lidas. Fraca em silenciar (ícone mínimo) e **muda em falhas** de editar/apagar/reagir/sair/criar. |
| 2. Linguagem do usuário | Boa no geral. Ruído: "Excluir" × "Apagar"; "CANAIS" no compartilhar; "Grupos de time" quebrado. |
| 3. Controle e liberdade | **Sair do grupo sem confirmação**; Esc não fecha nada; sem "voltar" do menu a não ser clicar fora. |
| 4. Consistência | Menu de mensagem igual ao do chat normal (bom). Duas palavras para apagar. |
| 5. Prevenção de erro | Botão "Criar grupo" desabilitado sem motivo; sair do grupo sem freio. |
| 6. Reconhecer em vez de lembrar | **Ações da mensagem escondidas**; busca de pessoa não existe — o usuário tem de lembrar que "Nova conversa" é o caminho. |
| 7. Flexibilidade e eficiência | **Sem atalhos** de teclado no chat. |
| 8. Estética e minimalismo | Boa (não mexer). |
| 9. Ajudar a reconhecer e sair do erro | Falhas silenciosas (item 1). |
| 10. Ajuda | Tela inicial "O que dá para fazer aqui" e a linha de dicas do campo de escrita ajudam; faltam os atalhos. |

### Problemas por gravidade

**Alta**
1. **Buscar uma pessoa com quem ainda não conversei diz "Nenhuma mensagem encontrada"** — o atendente acha que a pessoa não está no sistema. (a, c)
2. **"Nova conversa" e "Novo grupo" sem busca de pessoas**, numa janela com 5 nomes visíveis; grupo sem rótulo no nome e botão apagado sem dizer o que falta. (a, b)
3. **Resultado de mensagem da busca abre a conversa no fim**, não na mensagem. (c)
4. **"Sair do grupo" sem confirmação** (e sem volta). (h)
5. **Esc não fecha menu, janela, busca nem Detalhes.** (l)

**Média**
6. Responder/reagir só pela setinha ⌄ escondida dentro do balão. (d, j)
7. Falhas mudas: editar, apagar, reagir, sair do grupo, criar conversa/grupo. (j, h, a, b)
8. Nenhum atalho de teclado próprio do chat (nova conversa, buscar, próxima/anterior). (l)
9. Silenciar/favoritar sem confirmação visível do que mudou. (h)
10. Compartilhar conversa de cliente: "CANAIS" mistura conversas de 1 a 1, pessoa aparece duas vezes, sem busca. (g)
11. "Excluir" no menu × "Apagar mensagem?" na confirmação, sem dizer que some para todos. (j)
12. Aba "Grupos de time" quebra em duas linhas. (b)

**Baixa**
13. Convite de aviso cobre um terço da lista a 1024 px até a pessoa responder. (k, l)
14. Faixa "Online agora" aparece e some conforme a presença e empurra a lista.
15. Apagar não tem "desfazer" (o servidor não tem restauração; a confirmação segura).

---

## 2. O que foi corrigido

Branch `nicolas`, no ar no staging (build + restart às ~22:10). Commits:
`b288a98575`, `834d3bf681`, `4b6ca76362`, `251e55afad`, `3bdaf37988`, `7180c20c14`.
Nada de visual novo: mesmas cores, balões e componentes; só caminho, texto e retorno.

| Problema (gravidade) | O que mudou para quem usa | Onde ver |
|---|---|---|
| 1. Busca não achava pessoa sem conversa (alta) | Digitar o nome na busca mostra **PESSOAS › Natalia Silva · Começar conversa**; um clique abre a conversa. O texto da busca diz "Buscar pessoa ou mensagem…". | Chat interno › busca no alto da lista › digite um nome |
| 2. Nova conversa/grupo sem busca (alta) | A janela abre **com o cursor num campo "Digite o nome da pessoa…"**; Enter com um só nome já abre a conversa. No grupo: busca, "3 marcada(s)", marcar alguém limpa a busca para o próximo, campo **"Nome do grupo"** com rótulo, botão **"Criar grupo com 3 pessoa(s)"** e a frase do que falta ("Marque ao menos uma pessoa." / "Falta dar um nome ao grupo."). Aba "Grupos de time" virou **"Times"**. | Botão verde de lápis (ou Alt+N) |
| 3. Resultado de mensagem abria no fim (alta) | O clique abre a conversa **já na mensagem, com destaque**; o resultado diz "em [nome da conversa]". Se a mensagem for antiga, carrega as páginas anteriores até achar. | Busca › digite um trecho › clique no resultado em MENSAGENS |
| 4. Sair do grupo sem confirmação (alta) | Abre **"Sair do grupo X?"** explicando que só volta se alguém adicionar; depois avisa "Você saiu do grupo X.". Vale para o ⋮ e para "Gerenciar grupo". | Grupo › ⋮ › Sair do grupo |
| 5. Esc não fechava nada (alta) | **Esc fecha a camada de cima**: menu ⋮, Nova conversa, notificações, emoji, menu/reação/confirmação da mensagem, lista de @menção, edição; depois Detalhes, busca na conversa e a resposta em andamento. Na busca com texto, Esc limpa. | Qualquer tela do chat |
| 6. Responder/reagir escondidos (média) | Ao passar o mouse (ou focar com Tab) no balão aparecem **↩ Responder** e **☺ Reagir** ao lado, junto do horário, com dica. A setinha ⌄ e o clique direito continuam. | Passe o mouse num balão |
| 7. Falhas mudas (média) | Editar, apagar, reagir, sair e criar conversa/grupo **avisam "Não foi possível concluir a ação. Tente novamente."** quando o servidor recusa (o envio já tinha "Não enviada · tentar de novo"). | — (só aparece em erro) |
| 8. Sem atalhos (média) | **Alt+N** nova conversa · **Alt+B** buscar · **Alt+J / Alt+K** conversa anterior/próxima (as mesmas da lista de conversas do sistema) · **Esc**. Mostrados na tela inicial ("Teclado") e na dica do botão de nova conversa. | Tela inicial do chat |
| 9. Silenciar/favoritar sem retorno (média) | Aviso "Conversa silenciada. Menção a você continua avisando." / "Avisos desta conversa reativados." / "Adicionada às favoritas, no topo da lista." / "Removida das favoritas." | ⋮ › Silenciar / Favoritar |
| 10. Compartilhar com lista confusa (média) | Campo **"Buscar pessoa, grupo ou time…"**; "CANAIS" virou **"GRUPOS E TIMES"** e não repete mais a pessoa (conversa de 1 a 1 é por "Pessoas"). | Conversa do cliente › ⋮ › Compartilhar no chat interno |
| 11. Excluir × Apagar (média) | Menu diz **"Apagar"** e a confirmação **"Apagar para todos?"**. | Seta ⌄ do balão |

## 3. Reavaliação DEPOIS (mesmas tarefas, no navegador)

| # | Tarefa | Cliques antes → depois | Como ficou |
|---|--------|------------------------|-----------|
| a | 1ª mensagem a um colega | 3 + rolar e ler 20 nomes → **2** (digita o nome na busca, clica "Começar conversa") ou Alt+N, nome, Enter | `ux-depois-busca-pessoa.png`, `ux-depois-busca-pessoa-1024-claro.png`, `ux-depois-a-primeira-mensagem.png` |
| b | Grupo com 3 pessoas | 6 + rolar, sem saber por que o botão não acende → **6 sem rolar**, com contagem e dica do que falta | `ux-depois-novo-grupo-vazio.png`, `ux-depois-novo-grupo-pronto.png`, `ux-depois-grupo-criado.png`, `ux-depois-novo-grupo-1024-escuro.png` |
| c | Achar conversa e mensagem | 2 + rolar procurando → **2**, cai na mensagem destacada | `ux-depois-busca-mensagem.png`, `ux-depois-busca-leva-na-mensagem.png` |
| d | Responder a uma mensagem | 3 com hover certeiro dentro do balão → **2** (hover, ↩) | `ux-depois-grupo-hover-1440-claro.png`, `ux-depois-grupo-hover-1024-escuro.png`, `ux-depois-respondendo.png` |
| e | Mencionar | 2 → 2 (já era bom) | — |
| f | Anexo e áudio | 2 / 3 → igual (já era bom) | — |
| g | Compartilhar conversa de cliente | 3 + rolar → **3 com busca**, sem nome repetido | `ux-depois-compartilhar.png`, `ux-depois-compartilhar-busca.png` |
| h | Silenciar / favoritar / sair | 2, sem retorno; sair sem freio → **2 com aviso**; sair pede confirmação (Esc cancela) e avisa | `ux-depois-silenciou.png`, `ux-depois-sair-confirma.png`, `ux-depois-sair-1440-escuro.png`, `ux-depois-saiu.png` |
| i | Avisos automáticos na sala do time | 2 → 2 (já era bom; não mexido) | — |
| j | Editar / apagar / reagir | 3 cada → reagir **2** pelo ☺ ao lado; apagar com "Apagar para todos?"; erros avisam | `ux-depois-menu-mensagem.png`, `ux-depois-apagar-confirma.png`, `ux-depois-reagir-picker.png` |
| k | Voltar depois de horas | 1 → 1 (já era bom) | `ux-depois-inicio-1440.png` |
| l | Só teclado / 1024 px | Esc não fechava nada, sem atalhos → **Esc fecha tudo, Alt+N/B/J/K** | `ux-depois-inicio-1024-claro.png`, `ux-depois-inicio-1024-escuro.png` |

Conferido no navegador (script): Alt+B põe o cursor na busca; Alt+N abre Nova conversa com o cursor no nome;
Esc fecha ⋮, Detalhes, busca, confirmação de apagar, seletor de reação, cancela a resposta e a saída do grupo;
Alt+K/Alt+K/Alt+J anda Natalia → Ana Paula → Natalia. **Zero erro de console** da tela nas 4 combinações
(1440/1024 × claro/escuro), fora o 503 global de `waha_connections`. `vitest` do chat interno: 8/8.

## 4. Ficou para depois (e por quê)

- **Desfazer ao apagar mensagem** — o servidor não tem restauração; precisaria de backend novo. A confirmação "Apagar para todos?" segura o erro.
- **Convite "Quer ser avisado…" cobrindo um terço da lista a 1024 px** — some ao responder; mexer na posição é visual.
- **Faixa "Online agora" que aparece e some** — empurra a lista quando alguém entra; baixa gravidade.
- **Grupo recém-criado vai para o fim da lista** (ordem pela última mensagem; sem mensagem fica por último). Ele abre selecionado, então não se perde; resolver pede a data de criação do canal na ordenação.
- **Remover membro em "Gerenciar grupo" sem confirmação** — é reversível (dá para adicionar de novo), por isso ficou.
- **Busca da lista não navega por setas** — Alt+J/K cobre a troca de conversa; setas na lista de resultados seria o próximo passo.

## 5. Dados de teste criados (só contas de teste) e como apagar

- Mensagens 112–114 (Ana Paula id 2 → QA Admin, DM canal 25) e 115 (Misya id 4 → QA Admin, DM canal 26): seed de "não lidas".
- Mensagens 110 (resposta com menção) e 111 (anexo, já apagada) no grupo `[TESTE] Demo layout` (canal 24).
- DM **canal 32** QA Admin ↔ Natalia Silva (id 6), mensagens 116–117.
- Grupo **canal 33** "[UX-TESTE] Grupo de 3" (Victoria 7, Gelson 8, Cibele 9; o QA Admin saiu), mensagem 118.
- Apagar tudo: `cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner ~/qa-chat-interno-ux-limpar.rb`
  (apaga as mensagens 110–118 com anexos e os canais 32 e 33).
