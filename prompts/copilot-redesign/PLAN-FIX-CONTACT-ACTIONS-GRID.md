# Fix — Grid de ações do contato (sobreposição de texto)

> Investigação visual do bug reportado por Walisson: "uns texto ficando em cima
> dos outros" no painel lateral de contato (`ContactInfo.vue`), seção de ações
> rápidas (Nova Mensagem / Ligar / Editar / Mesclar / Excluir).

## Sintoma

No painel lateral direito da conversa, abaixo do avatar e dos ícones sociais,
há um grid de 5 botões verticais (ícone em cima, label em baixo). Com as
labels traduzidas em pt-BR (`Nova Mensagem`, `Mesclar contatos`, `Editar
Contato`, `Excluir Contato`), os textos estouram a célula da grid e visualmente
se sobrepõem aos botões vizinhos.

Reprodução:
1. Abrir uma conversa qualquer.
2. Abrir o painel "Detalhes do contato" à direita.
3. Observar a tira de 5 ações horizontais sob os ícones sociais.

## Diagnóstico (causa raiz)

Arquivos envolvidos:
- `app/javascript/dashboard/routes/dashboard/conversation/contact/ContactInfo.vue:245`
- `app/javascript/dashboard/assets/scss/_wa-skin.scss:1697-1732`

Estrutura atual (linha 245):
```html
<div class="grid grid-cols-5 gap-2 mt-6 w-full max-w-[260px] mx-auto">
```

CSS atual (`.wa-action-btn` / `.wa-action-label`):
```scss
.wa-action-btn { display: flex; flex-direction: column; align-items: center;
  gap: 4px; padding: 10px 4px; border-radius: 8px; }
.wa-action-label { font-size: 11px; line-height: 1.2; text-align: center; }
```

Cálculo da largura por célula:
- container = `max-w-[260px]` => 260px de largura útil
- `grid-cols-5` + `gap-2` (8px) => 4 gaps de 8px = 32px
- largura por coluna = `(260 - 32) / 5 = ~45.6px`
- com `padding: 10px 4px` no botão sobra `~37.6px` de área de texto

Problemas que isso gera:
1. **`Nova Mensagem`** (12 chars) e **`Mesclar contatos`** (16 chars) e
   **`Excluir Contato`** (15 chars) e **`Editar Contato`** (14 chars) NÃO
   cabem em 37px com `font-size: 11px`. Cada palavra precisa quebrar em
   2-3 linhas (ex.: "Mes-clar / con-ta-tos").
2. Como `.wa-action-label` não tem `overflow:hidden` nem `word-break`/
   `hyphens`, o navegador faz **overflow visível** no eixo X — o texto
   transborda da coluna e fica desenhado por cima da célula vizinha.
3. O botão tem `display:flex flex-direction:column`, então a altura de
   cada item passa a depender da quantidade de linhas, criando um grid
   com células de alturas desiguais — visual quebrado.
4. Existe ainda o `<VoiceCallButton>` (linha 264) ocupando a 2ª célula
   sem usar `.wa-action-btn` — o desalinhamento vertical fica pior.

Quebra em qualquer viewport (não é só mobile) — o `max-w-[260px]` força
260px independente do espaço do painel. Em dark/light idem (problema é
geometria pura, não cor).

Comportamento esperado: 5 ações alinhadas, ícone + rótulo curto, sem
sobreposição, mesma altura, label legível em pt-BR e en.

## Opções propostas

### Opção A — Esconder labels, manter só ícones + tooltip
- Remover `<span class="wa-action-label">` (ou `.wa-action-label{ display:none }`).
- Tooltip já existe (`v-tooltip.top-end="..."`).
- Ajustar `padding` do botão para compensar.

Trade-off: visual super clean e WhatsApp-like (WA Web só usa ícones nessa
mesma área). Porém perde descobribilidade — usuário leigo precisa hover
para entender. Ruim para mobile (sem hover).

Esforço: **S** (1 arquivo, ~5 linhas).

### Opção B — Trocar para 2 colunas (`grid-cols-2`)
- 2 botões por linha, label fica horizontal ao lado do ícone.
- Mudar `.wa-action-btn` para `flex-direction: row; gap: 8px;` e
  `text-align: left`.

Trade-off: cada label ganha ~110px de largura, sobra espaço pro texto.
Mas perde a estética WA (faixa horizontal compacta) e ocupa o dobro
da altura vertical (5 linhas em vez de 1).

Esforço: **M** (template + SCSS revisado).

### Opção C — Manter 5 colunas, soltar `max-w` e usar truncate
- Trocar `max-w-[260px] mx-auto` por `w-full` (deixa o painel definir).
- Em `.wa-action-label` adicionar `white-space:nowrap; overflow:hidden;
  text-overflow:ellipsis; max-width:100%;`.
- Em pt-BR, "Nova Mensagem" virara "Nova Men…" — feio.

Trade-off: mantém layout, mas sacrifica leitura. Tooltip mitiga.

Esforço: **S** (2 arquivos, ~6 linhas).

### Opção D — Manter grid, encurtar labels + estilo de quebra controlada
- Encurtar i18n: "Nova Mensagem" => "Mensagem" (ou "Nova"), "Mesclar
  contatos" => "Mesclar", "Editar Contato" => "Editar", "Excluir
  Contato" => "Excluir". Já temos chaves dedicadas (`CONTACT_PANEL.NEW_MESSAGE`
  etc.) — pode-se criar variantes `*_SHORT` ou simplesmente atualizar
  o copy.
- Em `.wa-action-label`: `font-size:10px; line-height:1.15;
  white-space:nowrap; overflow:hidden; text-overflow:clip; max-width:100%;
  display:block;`.
- Tooltip mantém o nome completo.

Trade-off: precisa coordenar i18n (pt-BR e en) e revisar com Walisson.
Solução mais "WA-fiel" e estável — labels de 1 palavra cabem nos ~46px.

Esforço: **S-M** (1 .vue + 1 .scss + 2 i18n .json).

### Opção E — Layout adaptativo (ícones em < md, ícone+label em >= md)
- `<md`: só ícone (Opção A). `>=md`: 2 colunas (Opção B).
- Usar breakpoints Tailwind (`md:grid-cols-2`).

Trade-off: mais código condicional, dois layouts pra manter. O painel
de detalhes em si já é largura fixa (~340-360px), então o "responsive"
real é limitado.

Esforço: **M-L**.

## Recomendação

**Opção D** (encurtar labels + endurecer regras de quebra), com
fallback em **Opção A** se Walisson preferir o look WA puro.

Justificativa:
- Resolve o bug sem mudar a estética geral (faixa de 5 ações
  horizontais — alinhada com a direção WA-fiel já aprovada).
- Mantém descobribilidade (texto visível, sem depender de hover).
- Tooltip já existe e fornece o nome completo se precisar.
- Esforço pequeno, alto valor visual.

Mockup textual (após fix, painel ~340px de largura):
```
┌──────────────────────────────────────────┐
│              [Avatar 96x96]              │
│           Nome do contato                │
│             +55 65 9...                  │
│         [icones sociais opcionais]       │
│                                          │
│   ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐           │
│   │💬│  │📞│  │✏ │  │⇄ │  │🗑 │           │
│   │ M│  │Lig│ │Edit│ │Mesc│ │Excl│        │
│   └──┘  └──┘  └──┘  └──┘  └──┘           │
│  Mens.  Ligar  Editar Mesclar Excluir    │
└──────────────────────────────────────────┘
```
(label de 1 palavra, fonte 10px, line-height 1.15, sem quebra)

## Validação proposta

Após implementar, validar via Playwright (regra
`feedback_validate_ui_with_playwright`):

- Login em `https://hmlchat.simplexsolucoes.com.br` com user de teste.
- Abrir conversa qualquer e o painel direito de contato.
- Capturar screenshot nos viewports:
  - 1440x900 (desktop padrão)
  - 1280x720 (laptop pequeno)
  - 1024x768 (tablet landscape)
- Trocar idioma para `en` e repetir 1440x900.
- Conferir: nenhum texto sobrepõe outro, todos os 5 botões com mesma
  altura, ícone centralizado sobre label, tooltip funcional.

## Arquivos afetados

1. `app/javascript/dashboard/routes/dashboard/conversation/contact/ContactInfo.vue`
   - Linha 245: revisar grid (`grid-cols-5 gap-2 mt-6 w-full max-w-[260px] mx-auto`)
     — manter ou aumentar `max-w` (ex.: `max-w-[300px]`).
   - Linhas 252-305: nenhuma mudança estrutural; só os textos virão de
     chaves i18n já atualizadas.

2. `app/javascript/dashboard/assets/scss/_wa-skin.scss`
   - Linhas 1723-1729 (`.wa-action-label`): adicionar
     `white-space:nowrap; overflow:hidden; text-overflow:clip;
     max-width:100%; display:block;` e reduzir `font-size` de 11px para
     10px e `line-height` para 1.15.

3. `app/javascript/dashboard/i18n/locale/pt_BR/contact.json` (e equivalentes
   em `conversation.json` se as chaves estiverem lá — confirmar via
   `rg "NEW_MESSAGE|MERGE_CONTACT|BUTTON_LABEL" app/javascript/dashboard/i18n/locale/pt_BR`):
   - `CONTACT_PANEL.NEW_MESSAGE`: "Nova Mensagem" => "Mensagem"
   - `CONTACT_PANEL.MERGE_CONTACT`: "Mesclar contatos" => "Mesclar"
   - `EDIT_CONTACT.BUTTON_LABEL`: "Editar Contato" => "Editar"
   - `DELETE_CONTACT.BUTTON_LABEL`: "Excluir Contato" => "Excluir"
   - Os tooltips podem manter o texto longo (separar chaves
     `*_SHORT` para o label vs chave atual para o tooltip, se quiser
     preservar o copy completo no hover).

4. `app/javascript/dashboard/i18n/locale/en/conversation.json` (mesma
   tratativa): `New Message` => `Message`, `Merge contact` => `Merge`,
   `Edit Contact` => `Edit`, `Delete Contact` => `Delete`. Lembrando
   regra do projeto (CLAUDE.md): editar `en.json` é OK, demais idiomas
   são da comunidade — mas pt-BR é prioridade ChatSPX (override pessoal
   do Walisson).

5. (Opcional) Verificar `VoiceCallButton.vue` para garantir que ele se
   ajusta como `.wa-action-btn` no mesmo grid — provavelmente precisará
   herdar visual idêntico (ícone + label curta "Ligar"). Se hoje só
   renderiza ícone redondo, ficará visualmente diferente das outras 4
   células.
