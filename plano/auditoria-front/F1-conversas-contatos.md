# F1 — Auditoria de front-end: Conversas e Contatos

**Ambiente:** `http://localhost:3000` (mesmo código de `chatspx.app`), conta **3** (Simplex Tecnologia).
**Usuário:** `playwright-test@simplex.local` · **Ferramenta:** Playwright 1.59 · **Data:** 29/07/2026
**Viewports:** 1440×900 e 1280×800, claro e escuro.
**Screenshots:** `/tmp/claude-1001/-home-chatwoot-chatwoot/0b66ddfb-e350-438e-866e-1e9495d73ca2/scratchpad/f1/shots/` (62 arquivos)

Nada foi enviado para número/grupo real. Nenhuma ação destrutiva executada. Nenhum dado alterado
(ver "Efeitos colaterais" no fim).

---

## Achados

| # | sev | rota/tela | o que acontece | evidência | conserto sugerido |
|---|-----|-----------|----------------|-----------|-------------------|
| 1 | **P0** | toda a app (barra lateral) | Se `cdn.lordicon.com` não responder em 3s, **os 13 ícones da barra lateral somem** e a barra fica em branco. O usuário vê os ícones por ~3s e depois eles desaparecem — restam só um retângulo cinza e um badge. Não dá para navegar. | Com o CDN bloqueado (simula firewall de cliente): `04-cdnblock-t2s.png` = 13 ícones Lucide visíveis; `04-cdnblock-t9s.png` = **zero ícones**. Causa: `LordIconIcon.vue:120-122` faz `setTimeout(() => loaded.value = true, 3000)`, e `loaded=true` esconde o fallback (`v-if="!loaded && fallbackLucide"`, linha 150) sem que o `<lord-icon>` tenha carregado. | Só marcar `loaded=true` no evento `ready` do player. No timeout, fazer o **oposto**: manter/forçar o fallback Lucide (`loadFailed=true`) e não revelar o `<lord-icon>` vazio. O time já conhece o problema — há comentário sobre ele em `Sidebar.vue:551`. |
| 2 | **P1** | `/conversations/:id` → aba **CRM** | Tela **completamente em branco**. Sem conteúdo, sem "carregando", sem estado vazio, sem erro no console. | `11-aba-CRM.png` — painel vazio; `innerText` da página cai de 5802 para 328 caracteres. É um iframe para `https://crmspx.simplexsolucoes.com.br/` (`dashboard_apps.id=4`), e o domínio **não responde** (`curl -I` retorna vazio, sem HTTP). | Envolver o iframe num wrapper que trate `onerror`/timeout e mostre "Não foi possível carregar o CRM" + botão "Tentar de novo". Independentemente, o domínio precisa voltar ou o Dashboard App ser removido da conta 3. |
| 3 | **P1** | `/conversations/:id` → aba **SPX Dashboard** | Mostra o texto cru **`404 page not found`** em fonte monoespaçada, sem moldura nem explicação. | `11-aba-SPXDashboard.png`. Iframe para `https://marketplace.simplexsolucoes.com.br` (`dashboard_apps.id=9`) → `HTTP/2 404`, `content-type: text/plain`. | Mesmo wrapper do #2. Bônus: o `title` no banco é `" SPX Dashboard"` — **com espaço no início**. |
| 4 | **P1** | busca dentro da conversa (lupa do cabeçalho) | Busca por uma palavra que **está** na conversa retorna **nada**, e a tela não diz nada — nem "nenhum resultado", nem "carregando". A busca só enxerga mensagens dos **últimos 3 meses**, e isso não é informado em lugar nenhum. | Conversa 444 tem **325 mensagens** com "Tecnologia" (SQL), todas com mais de 3 meses. `GET /api/v1/accounts/3/search/messages?q=Tecnologia&page=1&conversation_id=444` → `200 {"payload":{"messages":[]}}`. Já `q=prioridade` → 2 msgs e `q=reabriu` → 1 msg (ambas recentes). Limite em `app/services/search_service.rb:100`: `.where('created_at >= ?', 3.months.ago)`. | (a) Renderizar um estado "Nenhuma mensagem encontrada" quando `payload.messages` vier vazio; (b) na mesma tela, dizer "a busca cobre os últimos 3 meses". |
| 5 | **P1** | busca dentro da conversa | Com a busca vazia **e** com 0 resultados, a tela mostra o mesmo texto: *"Procurar por ID de conversa, e-mail, número de telefone, mensagens para melhores resultados de busca."* — texto da busca **global**, reaproveitado numa busca que só procura mensagens desta conversa. O usuário não distingue "ainda não busquei" de "não achei". | `16-busca-net.png`; `dialog.innerText` idêntico antes e depois da requisição retornar `[]`. | Separar os dois estados: dica antes de digitar, "Nenhuma mensagem encontrada para «X»" depois. A lista de conversas já faz isso muito bem (ver #6) — copiar o padrão de lá. |
| 6 | **P1** | composer → seletor de emoji | O painel de emoji abre **236px à esquerda do botão**, em cima da **coluna da lista de conversas**. Não encosta na coluna do composer. | Medido: botão emoji em `x=509..549` (centro 529); popover `.emoji-dialog` em `x=133..453`, `y=559..859` (centro 293) → **desvio de −236px**. A lista de conversas ocupa `x=72..452`. Screenshot `35-Emoji.png`. Reproduz em 1440px e 1280px. | Ancorar o popover no botão (`v-popper`/`floating-ui` com `reference` = botão de emoji) em vez de posicionar relativo ao painel de resposta. |
| 7 | **P1** | toda mensagem, toda conversa | O **horário de cada mensagem sai em inglês** — `Jun 30, 1:42 PM` — enquanto o separador de dia logo acima está em português (`30 de junho de 2026`). Formato de 12h com AM/PM num produto pt-BR. | `08-conv444-1440.png`, `34-conv1a1.png` (duas conversas diferentes). Causa: `app/javascript/shared/helpers/timeHelper.js:16` e `:27-34` chamam `format(...)` **sem** `{ locale: ptBR }` — apesar de o arquivo já importar `ptBR` na linha 8 e usá-lo em `dynamicTime` (linha 43), que por isso sai certo ("há 2 dias"). | Passar `{ locale: ptBR }` nos `format()` de `messageStamp` e `messageTimestamp`, e trocar o formato para 24h. Validado: `format(d, "d 'de' LLL, HH:mm", {locale: ptBR})` → **`30 de jun, 13:42`**. |
| 8 | **P1** | conversa com janela de 24h expirada | O banner do topo fica **cortado e sobreposto**: o botão **"Enviar Templa…"** é truncado pela borda direita e o botão flutuante de abrir o painel de contato passa por cima dele. No cabeçalho, o aviso também corta no meio da palavra: **"Janela expirada — use te"**. | `34-conv1a1.png` (conversa 665, 1440×900). Botão do painel em `x≈1078..1104`; o botão "Enviar Template" termina embaixo dele. | Dar `min-width` / `flex-shrink: 0` ao botão do banner e reservar o espaço do FAB (padding-right) na faixa. O aviso já é repetido em bloco grande no rodapé (ver #21) — o do topo pode virar só ícone + texto curto. |
| 9 | **P1** | global (tema claro) | **Contraste abaixo do mínimo WCAG AA em 31 pontos da tela.** Três tokens explicam quase todos. | Medido no navegador (fórmula WCAG 2.1): · botão primário **"Resolver"**: branco sobre `#2dc46f` = **2.27:1** (mín. 4.5) · título da conversa / aba ativa / filtro ativo: `#2dc46f` sobre `#f0f2f5` = **2.03:1** · texto secundário (preview da conversa, timestamps, separadores de dia, abas inativas, "8 participantes"): `#667781` sobre `#f0f2f5` = **4.14:1**. Em modo escuro só sobram 2 casos — o problema é do tema claro. | · `#2dc46f` + branco → **`#12864A`** (4.63:1) ou `#0E7A42` (5.41:1); · texto secundário `#667781` → **`#54656F`** (5.40:1) — que é exatamente a cor idle que o `LordIconIcon.vue:43` já usa, então fica consistente. |
| 10 | **P2** | modal "novo contato" (ícone 1 do topo da lista de conversas, e Contatos → ⋮ → Adicionar contato) | Modal de **criar** contato tem o título **"Alterar detalhes do contato"**, com todos os campos vazios e o botão "Salvar contato". | `39-modal-contato.png`, `06-topicon-0.png` | Título condicional: "Novo contato" na criação, "Alterar detalhes do contato" na edição. |
| 11 | **P2** | mesmo modal | O campo **telefone já aparece com contorno vermelho de erro antes de o usuário digitar qualquer coisa** — e sem nenhuma mensagem explicando o que está errado. | `39-modal-contato.png`; `input[placeholder="Digite o número de telefone"]` com contorno vermelho e `value=""`. | Só validar após `blur` ou após a primeira tentativa de submit; quando marcar erro, mostrar a mensagem junto. |
| 12 | **P2** | modal "Nova conversa" | Mostra o atalho **"Enviar (⌘ + ↵)"** — tecla de **Mac** — num app que roda em Linux/Windows. O composer da conversa, na mesma sessão, mostra corretamente **"Enviar (CTRL + ↵)"**. Dois lugares, dois textos, um errado. | Saída dos testes `s10` (composer: `Enviar (CTRL + ↵)`) e `s27` (modal: `Enviar (⌘ + ↵)`). Código: `components-next/NewConversation/components/ActionButtons.vue:162` → `const keyCode = isEditorHotKeyEnabled('cmd_enter') ? '⌘ + ↵' : '↵';` — hardcoded. | Usar o helper que já existe: `useKbd.js:36` → `isMacOS() ? '⌘' : 'Ctrl'`. Uma linha. |
| 13 | **P2** | seletor de emoji | As 8 categorias estão **todas em inglês**: "Smileys & Emotion", "Animals & Nature", "Food & Drink", "Travel & Places", "Activities", "Objects", "Symbols", "Flags". | `35-Emoji.png` + extração do DOM (`s36`). | Traduzir as categorias no i18n do emoji picker. |
| 14 | **P2** | linha de atividade da conversa | *"Playwright Test definiu a prioridade para **low**"* — o valor da prioridade não é traduzido. | `08-conv444-1440.png`. Causa: `app/models/concerns/priority_activity_message_handler.rb:24` interpola `new_priority: new_priority` com o valor cru do enum; `config/locales/pt_BR.yml:277` só traduz a frase ao redor. | Traduzir o valor antes de interpolar (`I18n.t("conversations.priority.#{new_priority}")` → baixa/média/alta/urgente). Vale para `added`, `updated` e `removed`. |
| 15 | **P2** | cabeçalho da conversa | **"Sem prioridade"** aparece cortado como **"Sem priorida…"** — mesmo em 1440px, onde sobra espaço de sobra no cabeçalho. | Medido: `clientWidth=80px`, `scrollWidth=83px`. Reproduz em 1280 e 1440, claro e escuro. | Faltam 3px: aumentar a largura do slot ou remover o `truncate` desse rótulo. |
| 16 | **P2** | ficha do contato (`/contacts/:id`) | A aba **"Andamento"** aparece cortada como **"Andame…"**. | Medido: `clientWidth=100px`, `scrollWidth=107px`. `28-ficha.png`. | As 4 abas (Atributos/Histórico/Andamento/Mesclar) não cabem em 400px com largura fixa de 100px: usar largura flexível ou reduzir o padding. |
| 17 | **P2** | lista de contatos (`/contacts`) | Para **cada** linha da lista, a página renderiza no DOM o **formulário de edição inteiro + o bloco de exclusão** ("Excluir contato / Esta ação é permanente e irreversível / Excluir agora"), escondidos. Com 15 contatos por página isso vira **226 `<input>` e 9.532 nós**. Além do peso, um leitor de tela lê "Excluir agora" 15 vezes. | Medido no DOM: `inputs=226`, `nós=9532`, `blocos "Excluir agora"=15`, para 15 linhas visíveis. | Renderizar o formulário sob demanda (`v-if` no accordion aberto), não `v-show`/sempre. |
| 18 | **P2** | ações da mensagem (hover) | Os botões que aparecem ao passar o mouse na mensagem têm **18×28px** — um terço da área mínima recomendada. E o segundo botão não tem `title` nem `aria-label` (o primeiro tem "Responder"). | Medido: `@1034,460 18x28` e `@1052,460 18x28`. | Aumentar a área clicável (padding) para ≥32px e rotular o segundo botão. |
| 19 | **P2** | conversa com janela expirada | Frase quebrada: *"Você só pode responder a esta conversa usando um modelo de mensagem devido a"* + link *"Restrições de janela de mensagem de 24 horas"*. Lida em voz alta dá "devido a Restrições de janela de mensagem" — tradução literal do inglês. | `34-conv1a1.png` | Reescrever como frase única: "Só é possível responder com um modelo de mensagem porque a janela de 24 horas do WhatsApp expirou." |
| 20 | **P2** | conversa com janela expirada | A mesma tela chama a mesma coisa de **três** jeitos: "modelo de mensagem" (banner), **"Enviar Template"** (botão, em inglês e Title Case) e "template aprovado" (rodapé). | `34-conv1a1.png` | Escolher um termo. Se o time usa "template" no dia a dia, então "Enviar template" em todos os lugares — minúsculo e sem "modelo de mensagem". |
| 21 | **P2** | código (bug latente, **não** reproduzível hoje) | `enterprise/app/services/enterprise/search_service.rb:6` faz `where_conditions[:conversation_id] = params[:conversation_id].to_i`, usando o **display_id** que o front envia como se fosse o **id** interno. A versão community trata isso certo (`app/services/search_service.rb:104-108`, com comentário explícito). Hoje esta instância não usa Elasticsearch, então cai no caminho community; **no dia em que ligarem o ES, a busca dentro da conversa passa a retornar zero em 100% dos casos.** | Comparação dos dois arquivos. Confirmado que o ES está desligado (`.env` sem `ELASTICSEARCH_*`) e que a requisição retorna resultados recentes normalmente. | Replicar a conversão display_id → id no serviço enterprise. |
| 22 | **P3** | global | Alvos clicáveis abaixo de 44×44px, medidos: ícones da barra lateral **40×40**; os 3 ícones do topo da lista de conversas **32×32**; lupa do cabeçalho da conversa **28×28**; chevron e kebab do "Resolver" **28×28**. | Medição do DOM (`s02`, `s13`). | Aumentar o padding mantendo o ícone visual do mesmo tamanho. |
| 23 | **P3** | global | Botões que são só ícone, **sem `aria-label` nem `title`**: os 3 do topo da lista de conversas (Adicionar contato / Nova conversa / menu) e os 3 do topo de Contatos (Filtrar / Ordenar / menu). Têm tooltip visual, mas leitor de tela lê "botão". | `aria=null title=null` nos 6 (`s07`, `s27`). | Adicionar `aria-label` com o mesmo texto do tooltip. |
| 24 | **P3** | Contatos | Capitalização inconsistente para a mesma ação: **"Enviar Mensagem"** (lista de contatos) vs **"Enviar mensagem"** (ficha do contato). Idem "Enviar Template", "Nota Privada", "Enviar Transcrição" — Title Case do inglês em meio a "Nova conversa", "Bloquear contato", "Ver detalhes". | `25-contatos.png` vs `28-ficha.png` | Padronizar em sentence case (padrão pt-BR), que já é a maioria. |
| 25 | **P3** | ficha do contato | **"Adicionar Github"** — a grafia correta é **GitHub**. | `28-ficha.png` | Corrigir a string. |
| 26 | **P3** | modal Importar contatos | *"Importar contatos através de um arquivo CSV. Baixar um exemplo de **csv**."* — minúsculo, enquanto o rótulo logo abaixo é "Arquivo **CSV**:". | Texto do modal (`s38`) | Padronizar "CSV". |
| 27 | **P3** | painel lateral da conversa | O painel se chama **"Contatos"** (plural) mostrando **um** contato. | `19-toggle-1.png` | "Contato". |
| 28 | **P3** | painel → Integrantes do grupo | Os avatares dos 8 integrantes mostram todos **"+6"** — são as duas primeiras letras de "+55 66 …". Oito círculos idênticos e sem sentido. | `23-integrantes.png` | Quando não há nome, usar os últimos dígitos do telefone ou um ícone genérico de pessoa. |
| 29 | **P3** | painel lateral | A mesma tela tem **"Integrantes (8)"** (participantes do grupo no WhatsApp) e **"Participantes da conversa"** (agentes acompanhando). Nomes quase iguais para coisas diferentes. | `23-integrantes.png` | Renomear o segundo para "Agentes acompanhando". |
| 30 | **P3** | conversa com janela expirada | O aviso de 24h aparece **duas vezes** na mesma tela: banner no topo e bloco grande no rodapé. | `34-conv1a1.png` | Manter só o do rodapé (que tem a explicação e as ações). |

---

## O que funciona bem (verificado, não é achado)

Registro porque foram testados de verdade e podem servir de referência para consertar o resto:

- **Rolagem infinita da lista de conversas**: funciona. 5 requisições paginadas por cursor,
  `scrollHeight` de 2.774 → 16.115px, terminando em "Todas as conversas carregadas".
- **Estado vazio da busca de conversas**: exemplar — *"Nenhum resultado encontrado / Nenhuma conversa
  encontrada para «X». Tente outro termo ou verifique a ortografia."* É o padrão que falta na busca
  dentro da conversa (#5).
- **Estado vazio da busca de contatos**: "Nenhum contato corresponde à sua pesquisa".
- **Botão Enviar do composer**: aparece corretamente ao digitar, substituindo o microfone.
- **Nota privada, respostas prontas com `/`, menu de contexto da mensagem (Copiar / Adicionar às
  respostas prontas), kebab do cabeçalho, filtros e ordenação de contatos, modal Importar, abas
  Histórico/Andamento da ficha**: todos abrem e respondem.
- **Modo escuro**: sem quebras de layout; só 2 falhas de contraste (contra 31 no claro).
- **Sem overflow horizontal** em 1280px nem 1440px, nos dois temas.
- **Nenhuma chave de i18n crua** (`ALGO.OUTRA_COISA`) encontrada em nenhuma tela varrida.
- **Nenhum erro de JS e nenhuma requisição 4xx/5xx** da aplicação em nenhum dos fluxos.

### Sobre "o botão que some"

O relato do Walisson tem uma explicação concreta: **é o achado #1**. Com o CDN de ícones fora do ar,
os ícones da barra lateral aparecem por 3 segundos e **desaparecem** — comportamento que bate
exatamente com "clico no botão e ele some". Vale confirmar com ele se o botão que sumiu era um dos
da barra lateral esquerda.

Passei por todos os botões do cabeçalho da lista de conversas e do cabeçalho da conversa. **Nenhum
outro botão desapareceu, ficou inerte ou deixou de responder.** Dois candidatos que investiguei e
descartei, para constar:

- A **lupa** do cabeçalho da conversa: parecia inerte num teste por coordenada, mas abre o diálogo
  de busca corretamente (o clique é que errava o alvo — ele tem só 28×28px, o que é o achado #22).
- O **toggle do painel de contato**: parecia abrir/não abrir aleatoriamente. É um toggle com estado
  **persistido** entre sessões — o comportamento está correto.

---

## Os 5 primeiros para um dev júnior

Conserto claro, risco baixo, ganho visível:

1. **#7 — Horário das mensagens em inglês.** Adicionar `{ locale: ptBR }` a dois `format()` em
   `shared/helpers/timeHelper.js` (o `ptBR` já está importado no arquivo) e mudar para 24h.
   Duas linhas, e corrige o horário de **toda mensagem de toda conversa**.
2. **#12 — Atalho `⌘` em Linux/Windows.** Trocar a string hardcoded de
   `NewConversation/components/ActionButtons.vue:162` pelo helper `useKbd.js` que já existe. Uma linha.
3. **#9 — Contraste do botão "Resolver" (2.27:1).** Trocar o verde do botão primário de `#2dc46f`
   para `#12864A`. É o botão mais usado da tela. Mudança de token, sem lógica.
4. **#4/#5 — Busca da conversa que não diz nada.** Renderizar "Nenhuma mensagem encontrada" quando a
   API voltar vazia e avisar do limite de 3 meses. O componente da lista de conversas já tem esse
   estado pronto para copiar.
5. **#10/#11 — Modal de novo contato.** Título condicional ("Novo contato" na criação) e parar de
   pintar o telefone de vermelho antes de o usuário digitar. Duas correções pequenas, no mesmo arquivo.

O **#1 (P0)** ficou fora desta lista de propósito: é o mais grave e o mais valioso, mas mexe na
lógica de carregamento assíncrono do `LordIconIcon.vue` e merece um dev com mais contexto.

---

## NÃO TESTADO

- **Anexo (clipe) e gravação de áudio** — o clipe abre o seletor de arquivos nativo do sistema
  operacional e o microfone dispara pedido de permissão; nenhum dos dois é controlável de forma
  confiável pelo Playwright neste ambiente headless. Confirmei apenas que os botões existem
  (40×40px) e estão habilitados.
- **Mesclar contato** e **Excluir contato/conversa** — botões existem e estão visíveis; **não
  cliquei**, por serem ações destrutivas (regra da tarefa).
- **Envio real de mensagem** — não enviei nada, em nenhuma inbox. O botão Enviar foi verificado só
  quanto à sua aparição ao digitar; o texto foi limpo antes de fechar o navegador e não ficou
  rascunho salvo (verificado: `localStorage` sem chaves de draft).
- **Editar atributos personalizados do contato** — vi os 4 atributos da conta ("Não Envia Menu",
  "WhatsApp Chat ID", "WhatsApp JID", "WhatsApp LID") e o campo "Inserir valor", mas não gravei
  valores para não sujar dado real.
- **Aba "Mesclar" da ficha do contato** — não abri, pelo mesmo motivo.
- **Fluxo de importação de CSV até o fim** — abri o modal e li o texto; não subi arquivo.
- **Copilot (ícone de IA do composer)** — não acionei, para não gastar crédito da OpenAI.
- **Modo escuro em Contatos com medição de contraste** — medi contraste em dark só na tela de
  conversa. Em Contatos, verifiquei apenas layout/overflow.
- **Emoji** — a VM não tem fonte de emoji instalada, então nos screenshots eles aparecem como
  caixas. Isso é limitação do servidor de teste, não do produto, e foi desconsiderado.

## Efeitos colaterais / o que ficou alterado

Nada foi alterado. Não adicionei rótulo, não mudei prioridade, não resolvi/reabri conversa, não
criei nem editei contato, não enviei mensagem. As atividades "Playwright Test definiu a prioridade
para low" e "Playwright Test removeu a prioridade" que aparecem na conversa 444 são de **28/07**,
anteriores a esta auditoria. O único estado que mudou foi o **toggle do painel lateral de contato**
(preferência de UI do usuário de teste), que é persistido — sem impacto em dado de cliente.
