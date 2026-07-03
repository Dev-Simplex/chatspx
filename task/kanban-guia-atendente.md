# Guia do Kanban — para Atendentes

Guia prático de como usar o Kanban no dia a dia. O Kanban organiza suas **conversas** em **etapas** (colunas) de um **funil**, para você ver rapidinho em que pé está cada atendimento e o que precisa de ação.

---

## 1. Como abrir o Kanban
- No menu lateral, clique em **Kanban**.
- Se já existe um funil, ele abre direto. Se houver mais de um, use o seletor **Funil** no topo para trocar.
- Sem nenhum funil ainda? A tela mostra **"Criar funil"** (em geral isso é configurado por um administrador).

---

## 2. As 3 visões (botões no topo, à direita)
| Visão | Ícone | Para quê |
|---|---|---|
| **Kanban** | quadradinhos | Quadro com colunas e cards — o dia a dia. |
| **Lista** | linhas | Tabela com todas as conversas do funil, ordenadas por etapa e atividade. Boa p/ varrer muita coisa. |
| **Calendário** | calendário | Mostra as **mensagens agendadas** por dia. |

---

## 3. Lendo um card (o que cada coisa quer dizer)
- **Foto + nome** do contato e **ícone do canal** (WhatsApp, e-mail, etc.).
- **Última mensagem** (prévia) — o assunto num relance.
- **Etiquetas** coloridas (labels) — clique numa para **filtrar** o quadro por ela (clique de novo para tirar o filtro).
- **Prioridade** (bandeira) — urgente / alta / média / baixa.
- **Sinais de tempo** (rodapé do card):
  - 🕐 **"há 2h"** — tempo desde a última atividade.
  - ⏰/❄️ **"Parada há X"** (âmbar/vermelho) — conversa **sem resposta** há muito tempo (≥1 dia âmbar, ≥3 dias vermelho). Precisa de atenção.
  - ⏳ **"Neste estágio há X"** (âmbar/vermelho) — o card está **travado na mesma etapa** há muito (≥5 dias âmbar, ≥10 dias vermelho). É gargalo do funil.
- **Telefone** do contato.
- **Responsável** (avatar à direita) — quem cuida. Se aparece um contorno tracejado, está **sem responsável**.

> Dica: o **rodapé da coluna** resume a etapa: total de cards, quantos **sem responsável** (👤✕) e quantos **parados** (❄️).

---

## 4. Tarefas do dia a dia

### Abrir uma conversa
Clique no card. Você vai direto para a tela da conversa. *(O sistema diferencia clique de arrastar — um clique rápido abre; segurar e arrastar move.)*

### Mover uma conversa de etapa
**Arraste o card** para a coluna desejada. Enquanto arrasta, a coluna de destino fica levemente realçada; ao soltar, a conversa muda de etapa. Se a etapa tiver automação, ela pode marcar a conversa como **aberta** ou **resolvida** automaticamente.

### Adicionar uma conversa ao funil
1. No rodapé da coluna, clique em **"Adicionar card"**.
2. Digite ao menos **2 letras** (nome, telefone ou trecho da mensagem).
3. Clique na conversa na lista. Ela entra naquela etapa.
   - Se já estiver no funil, o sistema avisa ("já está neste funil").

### Atribuir um responsável
1. Clique no **avatar/ícone de responsável** (canto inferior direito do card).
2. Escolha um agente na lista (ou **"Não atribuído"**).
3. O card atualiza na hora.

### Agendar uma mensagem
1. Passe o mouse no card e clique no **🕐 (relógio)**.
2. Escreva a mensagem, escolha **data/hora** (tem atalhos: hoje, amanhã…) e anexos se precisar.
3. Clique em **Agendar**. O card passa a mostrar um contador de agendadas pendentes (✈️).

### Remover do funil
Passe o mouse no card e clique no **✕**. Confirme.
> Isso **só tira a conversa do funil** — a conversa continua existindo na caixa de entrada. Não apaga nada.

---

## 5. Encontrar conversas rápido (busca e filtros)
- **Busca** (campo no topo): filtra em tempo real por nome, telefone, etapa e última mensagem.
- **Filtros avançados** (botão de controles deslizantes): filtre por **status**, **etapa**, **etiqueta** e **responsável**. O número ao lado mostra quantos filtros estão ativos; o botão de **limpar** zera tudo.
- **Filtrar por etiqueta**: clique numa etiqueta colorida em qualquer card.

---

## 6. Ajustes de exibição (visão Kanban)
- **Densidade** (ícone de linhas): alterna cards **compactos** ↔ **confortáveis**.
- **Capa colorida** (ícone de pincel): pinta o topo do card com a cor da etiqueta principal — bom para agrupar por cor.
- **Recolher coluna** (setas no cabeçalho da coluna): vira uma faixa fina. Fica guardado mesmo se recarregar a página.
- **Barra de funil** (faixa colorida no topo do quadro): mostra a distribuição de cards por etapa. Clique num trecho para pular até a coluna.
- Esses ajustes ficam **salvos no seu navegador** (cada um vê do seu jeito).

---

## 7. Mensagens agendadas (central)
- Botão **🕐 "Agendamentos"** no topo (com contador de pendentes) abre um painel lateral.
- Lá você **vê, busca, edita e cancela** mensagens agendadas, filtrando por status (pendente, enviada, falhou, cancelada). O painel atualiza sozinho.

---

## 8. Boas práticas (para o quadro trabalhar a seu favor)
- **Olho nos sinais vermelhos**: card com ❄️ (sem resposta) ou ⏳ (parado na etapa) é prioridade.
- **Use o rodapé da coluna**: muitos "sem responsável" = distribuir; muitos "parados" = destravar.
- **Atribua cedo**: card sem responsável tende a esfriar.
- **Etiquetas + filtro**: clique numa etiqueta para focar só naquele tipo de atendimento.
- **Agende follow-ups** em vez de confiar na memória.

---

*Observação técnica (para o time de produto): o botão "Mover" do card está aguardando correção — por ora, mova arrastando. Ver `task/kanban-auditoria-usabilidade.md` (item #1).*
