# Plano de Execução — Migração para Lordicon + Limpeza Menu Perfil

> **Status:** 🟢 Pronto para execução (planejamento aprovado pelo Walisson)
> **Autor original do plano:** Orion (aiox-master)
> **Data:** 2026-04-24
> **Objetivo:** substituir todos os ícones Lucide do sidebar do ChatSPX por ícones animados Lordicon (com hover-parent, fallback e cores por modo), e remover duplicação do toggle dark/light do menu de perfil.

---

## 📌 Contexto necessário (ler antes de começar)

### Sobre o projeto

- **Produto:** **ChatSPX** — fork do Chatwoot mantido pela Simplex Soluções (produto SaaS próprio, **build-to-earn**, produção com clientes reais)
- **Ambientes:**
  - Homologação: `https://hmlchat.simplexsolucoes.com.br` (VM 192.168.8.232 — esta VM aqui)
  - Produção: `https://chat.simplexsolucoes.com.br` (192.168.8.229)
- **Branch atual:** `homologacao`
- **Pai:** `develop` (main)
- **Stack:** Rails + Vue 3 Composition API + Vite + Tailwind CSS
- **Ícones atuais:** Lucide via UnoCSS (classes tipo `i-lucide-inbox`)

### Onde estamos no redesign

O ChatSPX está em um **redesign WhatsApp-fiel** aprovado pelo Walisson (CEO/dev Simplex). Já foram aplicadas várias fases de polish visual (cards, tooltips, modais, popovers, cores, etc). Esta task é a **substituição dos ícones do sidebar** por animados do Lordicon PRO (assinatura do Walisson).

### Comandos operacionais

```bash
# Ativar rbenv e rodar ruby tasks
export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"

# Precompile assets Vite
RAILS_ENV=production bundle exec rails assets:precompile

# Restart serviços (sudo sem senha já configurado pra chatwoot.target)
sudo -n systemctl restart chatwoot.target

# Probe servidor
curl -sk -o /dev/null -w "%{http_code}\n" https://hmlchat.simplexsolucoes.com.br/app
```

### Arquivo de referência crítico

**`/home/chatwoot/chatwoot/lordicons.txt`** — contém os 41 CDN URLs que o Walisson escolheu no Lordicon PRO. **Este arquivo é o source of truth** para os ícones. Formato:

```
mailbox: <script src="https://cdn.lordicon.com/lordicon.js"></script>
<lord-icon
    src="https://cdn.lordicon.com/vxnjveem.json"
    trigger="hover"
    stroke="bold"
    style="width:22px;height:22px">
</lord-icon>
```

Extraímos apenas o `src="..."` de cada um pra mapear em `constants/lordicons.js`.

---

## 🎯 Decisões de UX confirmadas

| Decisão | Valor | Por quê |
|---------|-------|---------|
| **Estado ativo** | Anima 1x na entrada da rota + verde `#00a884` estático depois | Walisson: "opção a" |
| **Cor idle (dark mode)** | `#8696a0` | Cinza WhatsApp Web dark |
| **Cor idle (light mode)** | `#54656f` | Cinza WhatsApp Web light |
| **Cor ativa (ambos)** | `#00a884` | Verde WhatsApp oficial, já usado em `--wa-primary` |
| **Hover trigger** | **DIV pai do item** (não só o ícone) | Walisson: "quando passar mouse pela div ja animar" |
| **Chevron** | 1 ícone só + CSS `rotate-180` quando expandido | Walisson: "opção a" |
| **Estratégia de carga** | Todos 41 ícones de uma vez via CDN | Walisson: "opção a" |
| **Fallback inicial** | Lucide visível ~200ms enquanto Lordicon carrega | Walisson: "pode ser esse fallback entao" |
| **Acessibilidade** | `aria-hidden="true"` no `<lord-icon>` | Padrão ícone decorativo |
| **Stroke padrão** | `bold` | Conforme `lordicons.txt` |
| **Size padrão** | 22px | WhatsApp Web usa ~20-22px |

---

## 🎯 Decisão UX ADICIONAL — Remoção de toggle dark/light do menu perfil

Walisson pediu para **remover** os itens `Dark Mode` / `Light Mode` / `Auto Mode` do menu perfil (dropdown do avatar), porque o botão **"Aparência" (palette)** já abre uma command palette (`ninja-keys`) com `parent: 'appearance_settings'` que contém essas 3 opções. Duplicar era redundante.

**Impacto:** remoção de ~40 linhas de lógica do `SidebarProfileMenu.vue` (state de color scheme + funções toggle/setAutoMode + event listeners de `prefers-color-scheme`).

---

## 🗺️ Mapeamento completo dos 41 slots (ordem da UI)

### 🔹 Rail principal (top-level) — 11 ícones

| # | Slot | Lucide atual | Chave Lordicon | CDN ID |
|---|------|--------------|----------------|--------|
| 1 | Inbox | `i-lucide-inbox` | `mailbox` | `vxnjveem` |
| 2 | Conversas | `i-lucide-message-circle` | `chatMessage` | `ncdmfugz` |
| 3 | Kanban | `i-lucide-layout-grid` | `kanban` | `ervhjijl` |
| 4 | Captain (AI) | `i-woot-captain` | `captain` | `ohcvbvqh` |
| 5 | Contatos | `i-lucide-contact` | `contacts` | `lawxkrzu` |
| 6 | Empresas | `i-lucide-building-2` | `companies` | `mzcapxae` |
| 7 | Relatórios | `i-lucide-chart-spline` | `reports` | `osnqlnce` |
| 8 | Ao Vivo | `i-lucide-activity` | `live` | `susybnwv` |
| 9 | Campanhas | `i-lucide-megaphone` | `megaphone` | `jdnoclpe` |
| 10 | Central de Ajuda | `i-lucide-library-big` | `helpCenter` | `vcavyyll` |
| 11 | Configurações | `i-lucide-bolt` | `settings` | `ripbvsga` |

### 🔸 Sub-Conversas — 5 novos + 1 reuso

| # | Slot | Lucide | Chave Lordicon | CDN ID |
|---|------|--------|----------------|--------|
| 12 | Não atendidas (UnattendedGroup) | `i-lucide-clock` | `unattended` | `warimioc` |
| 13 | Status (filtro) | `i-lucide-filter` | `filter` | `tophydxf` |
| 14 | Pastas (custom views) | `i-lucide-folder` | `folder` | `tsrgicte` |
| 15 | Times | `i-lucide-users` | `team` | `zjdxuyoy` |
| 16 | Canais (Inboxes) | `i-lucide-mailbox` | **reusa #1** `mailbox` | — |
| 17 | Etiquetas (Labels) | `i-lucide-tag` | `label` | `vhlsvodo` |

### 🔸 Sub-Contatos — reusos

| # | Slot | Lucide | Chave Lordicon |
|---|------|--------|----------------|
| 18 | Segmentos | `i-lucide-group` | **reusa #15** `team` |
| 19 | Tagged With | `i-lucide-tag` | **reusa #17** `label` |

### 🔸 Settings — 15 itens (+ reuses)

Ordem real do código (`Sidebar.vue` linhas 682–848):

| # | Slot | Label | Lucide | Chave Lordicon | CDN ID |
|---|------|-------|--------|----------------|--------|
| 20 | Conta/Geral | Account Settings | `i-lucide-briefcase` | `account` | `zhiiqoue` |
| 21 | Agentes | Agents | `i-lucide-square-user` | `agent` | `ucbznuay` |
| 22 | Times Settings | Teams | `i-lucide-users` | **reusa #15** `team` | — |
| 23 | Agent Assignment | Agent Assignment | `i-lucide-user-cog` | **reusa #11** `settings` | — |
| 24 | Inboxes Settings | Inboxes | `i-lucide-inbox` | **reusa #1** `mailbox` | — |
| 25 | WAHA Connections | WAHA WhatsApp | SVG custom (logo WhatsApp) | `waha` | `dnphlhar` |
| 26 | Labels Settings | Labels | `i-lucide-tags` | **reusa #17** `label` | — |
| 27 | Custom Attributes | Custom Attributes | `i-lucide-code` | `customAttrs` | `gvtjlyjf` |
| 28 | Automation | Automation | `i-lucide-repeat` | `automation` | `freooygd` |
| 29 | Agent Bots | Bots | `i-lucide-bot` | `bots` | `jhntkrwu` |
| 30 | Macros | Macros | `i-lucide-toy-brick` | `macros` | `glzqezmf` |
| 31 | Canned Responses | Respostas Prontas | `i-lucide-message-square-quote` | `cannedResp` | `mhjhxcxu` |
| 32 | Integrations | Integrações | `i-lucide-blocks` | `integration` | `adbkylwa` |
| 33 | Audit Logs | Audit Logs | `i-lucide-briefcase` | `audit` | `zttqeqnn` |
| 34 | Custom Roles | Custom Roles | `i-lucide-shield-plus` | `customRoles` | `gjlzobte` |
| 35 | SLA | SLA | `i-lucide-clock-alert` | `sla` | `psyssele` |
| 36 | Conversation Workflow | Conv. Workflow | `i-lucide-workflow` | `workflow` | `ygqtedpk` |
| 37 | Security | Security | `i-lucide-shield` | **reusa #34** `customRoles` | — |
| 38 | Billing | Billing | `i-lucide-credit-card` | `billing` | `uemybdyy` |

### 🔸 Busca (botão no topo do sidebar)

| # | Slot | Lucide | Chave Lordicon | CDN ID |
|---|------|--------|----------------|--------|
| 39 | Botão Busca | `i-lucide-search` | `search` | `wjyqkiew` |

### 🔸 Profile Menu (dropdown do avatar) — 9 itens ativos

| # | Slot | Label | Lucide | Chave Lordicon | CDN ID |
|---|------|-------|--------|----------------|--------|
| 40 | Suporte | Contact Support | `i-lucide-life-buoy` | `support` | `lemrzdkt` |
| 41 | Atalhos Teclado | Keyboard Shortcuts | `i-lucide-keyboard` | `keyboard` | `nyrkwwyh` |
| 42 | Editar Perfil | Profile Settings | `i-lucide-user-pen` | **reusa #21** `agent` | — |
| 43 | Aparência (palette) | Appearance | `i-lucide-palette` | `theme` | `cyzlkgid` |
| 44 | ~~Dark/Light Mode~~ | — | — | **REMOVIDO** | — |
| 45 | ~~Auto Mode~~ | — | — | **REMOVIDO** | — |
| 46 | Docs | Docs | `i-lucide-book` | **reusa #10** `helpCenter` | — |
| 47 | Changelog | Changelog | `i-lucide-scroll-text` | `changelog` | `wqxkssmu` |
| 48 | Super Admin | Super Admin Console | `i-lucide-castle` | `superAdmin` | `qpuplinu` |
| 49 | Logout | Logout | `i-lucide-power` | `logout` | `pbalszem` |

> **Ícone `devices` (`hmskmhmi`)** foi fornecido no `lordicons.txt` mas era pra "Auto Mode" que vamos remover. Mantemos no mapa para uso futuro se necessário.

### 🔸 Chevron (seta expansão)

| # | Slot | Lucide | Chave Lordicon | CDN ID |
|---|------|--------|----------------|--------|
| 50 | Chevron Down | `i-lucide-chevron-down` | `chevronDown` | `ptsmfzxx` |
| 51 | Chevron Up | — | `chevronUp` (sobra, opção B não usada) | `wxatatht` |

**Uso:** apenas `chevronDown` + CSS `rotate-180` quando expandido. `chevronUp` fica no mapa por via das dúvidas.

---

## 📂 Arquivos a modificar/criar

### Novos (2)

1. **`app/javascript/dashboard/components-next/icon/LordIconIcon.vue`** — wrapper Vue
2. **`app/javascript/dashboard/constants/lordicons.js`** — mapa dos CDN URLs

### Modificados (7)

3. **`app/views/dashboard/show.html.erb`** OU layout equivalente — adicionar `<script src="https://cdn.lordicon.com/lordicon.js" defer></script>`. **Investigar durante execução onde é o layout do dashboard** (pode ser `app/views/layouts/dashboard.html.erb` ou `app/views/dashboard/index.html.erb`).
4. **`app/javascript/dashboard/components-next/sidebar/Sidebar.vue`** — trocar ~37 ocorrências de `icon:`
5. **`app/javascript/dashboard/components-next/sidebar/SidebarProfileMenu.vue`** — remover toggle dark/light/auto + trocar 9 ícones
6. **`app/javascript/dashboard/components-next/sidebar/SidebarCollapsedPopover.vue`** — chevron Lordicon (linhas ~136-141)
7. **`app/javascript/dashboard/components-next/sidebar/SidebarSubGroup.vue`** — chevron Lordicon
8. **`app/javascript/dashboard/components-next/sidebar/SidebarGroupLeaf.vue`** — adicionar `data-hover-host` no `<a>`/`<router-link>` que envolve o item
9. **`app/javascript/dashboard/components-next/sidebar/SidebarGroupHeader.vue`** — idem
10. **`app/javascript/dashboard/assets/scss/_wa-skin.scss`** — regras de tamanho e transição para `<lord-icon>`

---

## 🧩 Código-fonte de referência

### `constants/lordicons.js` (copiar/colar completo)

```js
// Mapa de ícones Lordicon usados no sidebar do ChatSPX.
// Fonte de verdade: /home/chatwoot/chatwoot/lordicons.txt (assinatura Lordicon PRO).
// Substituição dos ícones Lucide no dashboard. Renderizado via <LordIconIcon />.

export const LORDICON = {
  // Top-level (rail principal)
  mailbox:      'https://cdn.lordicon.com/vxnjveem.json',
  chatMessage:  'https://cdn.lordicon.com/ncdmfugz.json',
  kanban:       'https://cdn.lordicon.com/ervhjijl.json',
  captain:      'https://cdn.lordicon.com/ohcvbvqh.json',
  contacts:     'https://cdn.lordicon.com/lawxkrzu.json',
  companies:    'https://cdn.lordicon.com/mzcapxae.json',
  reports:      'https://cdn.lordicon.com/osnqlnce.json',
  live:         'https://cdn.lordicon.com/susybnwv.json',
  megaphone:    'https://cdn.lordicon.com/jdnoclpe.json',
  helpCenter:   'https://cdn.lordicon.com/vcavyyll.json',
  settings:     'https://cdn.lordicon.com/ripbvsga.json',

  // Sub-conversas / sub-contatos
  unattended:   'https://cdn.lordicon.com/warimioc.json',
  filter:       'https://cdn.lordicon.com/tophydxf.json',
  folder:       'https://cdn.lordicon.com/tsrgicte.json',
  team:         'https://cdn.lordicon.com/zjdxuyoy.json',
  label:        'https://cdn.lordicon.com/vhlsvodo.json',

  // Settings sub-items
  account:      'https://cdn.lordicon.com/zhiiqoue.json',
  agent:        'https://cdn.lordicon.com/ucbznuay.json',
  waha:         'https://cdn.lordicon.com/dnphlhar.json',
  customAttrs:  'https://cdn.lordicon.com/gvtjlyjf.json',
  automation:   'https://cdn.lordicon.com/freooygd.json',
  bots:         'https://cdn.lordicon.com/jhntkrwu.json',
  macros:       'https://cdn.lordicon.com/glzqezmf.json',
  cannedResp:   'https://cdn.lordicon.com/mhjhxcxu.json',
  integration:  'https://cdn.lordicon.com/adbkylwa.json',
  audit:        'https://cdn.lordicon.com/zttqeqnn.json',
  customRoles:  'https://cdn.lordicon.com/gjlzobte.json',
  sla:          'https://cdn.lordicon.com/psyssele.json',
  workflow:     'https://cdn.lordicon.com/ygqtedpk.json',
  billing:      'https://cdn.lordicon.com/uemybdyy.json',

  // Busca / profile menu / outros
  search:       'https://cdn.lordicon.com/wjyqkiew.json',
  support:      'https://cdn.lordicon.com/lemrzdkt.json',
  keyboard:     'https://cdn.lordicon.com/nyrkwwyh.json',
  theme:        'https://cdn.lordicon.com/cyzlkgid.json',
  devices:      'https://cdn.lordicon.com/hmskmhmi.json',  // não usado após remoção de auto mode
  changelog:    'https://cdn.lordicon.com/wqxkssmu.json',
  superAdmin:   'https://cdn.lordicon.com/qpuplinu.json',
  logout:       'https://cdn.lordicon.com/pbalszem.json',

  // Chevron
  chevronDown:  'https://cdn.lordicon.com/ptsmfzxx.json',
  chevronUp:    'https://cdn.lordicon.com/wxatatht.json',  // não usado (usamos CSS rotate)
};
```

### `LordIconIcon.vue` (wrapper)

```vue
<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';

const props = defineProps({
  /** URL do JSON do Lordicon (ex.: https://cdn.lordicon.com/xxxxx.json) */
  src: { type: String, required: true },
  /** Se true, pinta com cor ativa (#00a884) e anima 1x na montagem */
  active: { type: Boolean, default: false },
  /** Tamanho em px */
  size: { type: Number, default: 22 },
  /** Lordicon stroke: 'light' | 'regular' | 'bold' */
  stroke: { type: String, default: 'bold' },
  /** Seletor do ancestor que dispara animação ao receber mouseenter */
  hoverHostSelector: { type: String, default: '[data-hover-host]' },
  /** Classe Lucide exibida como fallback até o Lordicon carregar */
  fallbackLucide: { type: String, default: '' },
});

const wrapperRef = ref(null);
const iconRef = ref(null);
const loaded = ref(false);

// Detecta dark mode via class .dark no <html> (padrão Tailwind)
const isDarkMode = ref(
  typeof document !== 'undefined' &&
    document.documentElement.classList.contains('dark')
);

// Observer pra sincronizar quando usuário muda o tema
let themeObserver = null;

const colors = computed(() => {
  if (props.active) return 'primary:#00a884,secondary:#00a884';
  const idle = isDarkMode.value ? '#8696a0' : '#54656f';
  return `primary:${idle},secondary:${idle}`;
});

let cleanup = () => {};

onMounted(() => {
  const iconEl = iconRef.value;
  if (!iconEl) return;

  // Marca como loaded quando Lordicon emite 'ready'
  const onReady = () => { loaded.value = true; };
  iconEl.addEventListener('ready', onReady);

  // Hover-parent: anima quando mouse entra no DIV pai com data-hover-host
  const host = wrapperRef.value?.closest(props.hoverHostSelector);
  let onEnter = null;
  if (host) {
    onEnter = () => iconEl.playerInstance?.playFromBeginning();
    host.addEventListener('mouseenter', onEnter);
  }

  // Observer pra trocar cor quando tema muda (.dark no <html>)
  themeObserver = new MutationObserver(() => {
    isDarkMode.value = document.documentElement.classList.contains('dark');
  });
  themeObserver.observe(document.documentElement, {
    attributes: true,
    attributeFilter: ['class'],
  });

  // Se já começa ativo, anima uma vez na entrada
  if (props.active) {
    setTimeout(() => iconEl.playerInstance?.playFromBeginning(), 100);
  }

  // Fallback: se Lordicon não carregar em 3s, considera loaded pra remover fallback
  const loadTimeout = setTimeout(() => { loaded.value = true; }, 3000);

  cleanup = () => {
    iconEl.removeEventListener('ready', onReady);
    if (host && onEnter) host.removeEventListener('mouseenter', onEnter);
    themeObserver?.disconnect();
    clearTimeout(loadTimeout);
  };
});

onBeforeUnmount(() => cleanup());

// Quando prop active muda de false → true, anima 1x (entrada em rota)
import { watch } from 'vue';
watch(
  () => props.active,
  (isActive) => {
    if (isActive && loaded.value) {
      iconRef.value?.playerInstance?.playFromBeginning();
    }
  }
);
</script>

<template>
  <span
    ref="wrapperRef"
    class="lord-icon-wrapper"
    :style="{ width: size + 'px', height: size + 'px' }"
    aria-hidden="true"
  >
    <!-- Fallback Lucide enquanto Lordicon carrega -->
    <span
      v-if="!loaded && fallbackLucide"
      :class="fallbackLucide"
      class="lord-icon-fallback"
    />
    <!-- Lordicon Web Component (nativo) -->
    <lord-icon
      ref="iconRef"
      :src="src"
      :stroke="stroke"
      :colors="colors"
      trigger="in"
      :style="{
        width: '100%',
        height: '100%',
        opacity: loaded ? 1 : 0,
        transition: 'opacity 0.2s',
      }"
    />
  </span>
</template>

<style scoped>
.lord-icon-wrapper {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  position: relative;
  flex-shrink: 0;
}
.lord-icon-fallback {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  color: currentColor;
}
</style>
```

### Uso no `Sidebar.vue` (padrão)

```js
import { h } from 'vue';
import LordIconIcon from 'dashboard/components-next/icon/LordIconIcon.vue';
import { LORDICON } from 'dashboard/constants/lordicons';

// Helper para criar função render que retorna VNode do LordIconIcon
const lordIcon = (srcKey, fallback = '') =>
  () => h(LordIconIcon, {
    src: LORDICON[srcKey],
    fallbackLucide: fallback,
  });

// Em menuItems — antes:
// icon: 'i-lucide-inbox',

// Depois:
icon: lordIcon('mailbox', 'i-lucide-inbox'),
```

### Limpeza em `SidebarProfileMenu.vue`

**REMOVER** estas seções:

```js
// Linha 12 — import não-usado após remoção:
import { setColorTheme } from 'dashboard/helper/themeHelper';

// Linhas 52-62 — state do color scheme:
const prefersDarkMedia = window.matchMedia('(prefers-color-scheme: dark)');
const isOSOnDarkMode = ref(prefersDarkMedia.matches);
const colorScheme = ref(
  LocalStorage.get(LOCAL_STORAGE_KEYS.COLOR_SCHEME) || 'auto'
);
const isCurrentlyDark = computed(() => {
  if (colorScheme.value === 'dark') return true;
  if (colorScheme.value === 'light') return false;
  return isOSOnDarkMode.value;
});

// Linhas 64-79 — funções:
const toggleDarkMode = () => { /* ... */ };
const setAutoMode = () => { /* ... */ };
const handleOSColorSchemeChange = event => { /* ... */ };

// Linhas 81-87 — hooks:
onMounted(() => {
  prefersDarkMedia.addEventListener('change', handleOSColorSchemeChange);
});
onBeforeUnmount(() => {
  prefersDarkMedia.removeEventListener('change', handleOSColorSchemeChange);
});

// Linhas 127-142 — items do menu (Dark/Light Mode + Auto Mode):
{
  show: true,
  label: isCurrentlyDark.value ? t('...LIGHT_MODE') : t('...DARK_MODE'),
  icon: isCurrentlyDark.value ? 'i-lucide-sun' : 'i-lucide-moon',
  click: toggleDarkMode,
},
{
  show: colorScheme.value !== 'auto',
  label: t('...AUTO_MODE'),
  icon: 'i-lucide-monitor-smartphone',
  click: setAutoMode,
},
```

**MANTER** o item "Appearance" (palette) que abre a command palette:

```js
{
  show: true,
  showOnCustomBrandedInstance: true,
  label: t('SIDEBAR_ITEMS.APPEARANCE'),
  icon: lordIcon('theme', 'i-lucide-palette'),
  click: () => {
    document.querySelector('ninja-keys')?.open?.({ parent: 'appearance_settings' });
  },
},
```

### Chevron em popovers (Opção A — CSS rotate)

**Antes** (em `SidebarCollapsedPopover.vue` e `SidebarSubGroup.vue`):

```vue
<span
  class="size-3 transition-transform i-lucide-chevron-down"
  :class="{ 'rotate-180': expandedSubGroup === child.name }"
/>
```

**Depois:**

```vue
<LordIconIcon
  :src="LORDICON.chevronDown"
  fallback-lucide="i-lucide-chevron-down"
  :size="12"
  class="transition-transform duration-200"
  :class="{ 'rotate-180': expandedSubGroup === child.name }"
/>
```

### `data-hover-host` nos itens do menu

Em `SidebarGroupLeaf.vue`, o `<a>` / `<router-link>` / `<button>` mais externo que contém o ícone+label ganha `data-hover-host`:

```vue
<router-link data-hover-host :to="to" class="...">
  <Icon :icon="icon" />
  <span>{{ label }}</span>
</router-link>
```

O `LordIconIcon` por default faz `closest('[data-hover-host]')` e anexa listener `mouseenter` nesse ancestor.

### CSS em `_wa-skin.scss`

Adicionar no final do arquivo:

```scss
/* =======================================================================
   LORDICON — integração com sidebar
   ======================================================================= */
lord-icon {
  display: block;
  width: 100%;
  height: 100%;
}
.lord-icon-wrapper {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  position: relative;
}
aside .lord-icon-wrapper {
  /* 22px padrão no rail; pode ser overridado por size prop */
}

/* Transição suave ao entrar no estado ativo */
aside lord-icon {
  transition: filter 0.2s ease;
}
```

### Script Lordicon no layout

Adicionar no `<head>` do layout que serve `/app`:

```erb
<script src="https://cdn.lordicon.com/lordicon.js" defer></script>
```

Localização provável: `app/views/dashboard/show.html.erb` (investigue com `grep -rn "lordicon\|<head" app/views/dashboard/ app/views/layouts/` no começo).

---

## 🧪 Comportamento esperado final

1. **Ao carregar a página**:
   - Lucide aparece imediatamente como fallback em cada ícone
   - Script `lordicon.js` carrega do CDN
   - Lordicons fazem fade-in, Lucide some
   - Animação `trigger="in"` roda 1x em cada ícone na entrada

2. **Idle** (rota não ativa, mouse longe):
   - Cor `#54656f` (light) ou `#8696a0` (dark), ícone estático

3. **Hover no DIV pai do item**:
   - Ícone anima do início (mesmo se mouse estiver fora do ícone, só sobre o label)

4. **Rota ativa**:
   - Cor `#00a884` (verde WA)
   - Anima 1x na mudança `active: false → true`
   - Depois fica estático verde até sair da rota

5. **Mudança de tema** (dark ↔ light):
   - `MutationObserver` na `<html>` detecta mudança de classe `.dark`
   - Cor idle atualiza automaticamente

6. **Chevron em subgrupo**:
   - Aponta pra baixo quando fechado
   - Rotaciona 180° (CSS) quando expandido

---

## 📋 Ordem de execução (sequencial, ~2h30)

| # | Ação | Arquivo(s) | Tempo |
|---|------|-----------|-------|
| 1 | Localizar layout do dashboard (grep) | — | 5 min |
| 2 | Criar `constants/lordicons.js` | novo | 5 min |
| 3 | Criar `LordIconIcon.vue` | novo | 25 min |
| 4 | Adicionar `<script>` Lordicon no layout | `show.html.erb` ou layout | 5 min |
| 5 | Editar `Sidebar.vue` (37 trocas) | `Sidebar.vue` | 30 min |
| 6 | Editar `SidebarProfileMenu.vue` (remoção + 9 trocas) | `SidebarProfileMenu.vue` | 20 min |
| 7 | Adicionar `data-hover-host` | `SidebarGroupLeaf.vue`, `SidebarGroupHeader.vue` | 10 min |
| 8 | Trocar chevron | `SidebarCollapsedPopover.vue`, `SidebarSubGroup.vue` | 10 min |
| 9 | Adicionar CSS | `_wa-skin.scss` | 10 min |
| 10 | ESLint nos arquivos tocados (`pnpm eslint <arquivos>`) | — | 5 min |
| 11 | Precompile assets | — | 3 min |
| 12 | Restart `chatwoot.target` | — | 1 min |
| 13 | QA via Playwright (headless, HTML local c/ CSS servido) | — | 20 min |
| **TOTAL** | | | **~2h30** |

---

## ✅ QA — Checklist de validação

Após precompile + restart:

### Validação estática (via `curl` + parse)

- [ ] Server HTTP 200 em `https://hmlchat.simplexsolucoes.com.br/app`
- [ ] Novo CSS fingerprint aparece no HTML (ex.: `dashboard-XXXXXX.css`)
- [ ] Novo JS bundle idem
- [ ] Script Lordicon presente no HTML da rota
- [ ] `constants/lordicons.js` contém os 41 URLs sem typo

### Validação visual (via Playwright local em página isolada)

Criar `/tmp/sidebar_test.html` importando o CSS+JS servido + markup de ícone:

```html
<!DOCTYPE html>
<html class="dark">
<head>
  <script src="https://cdn.lordicon.com/lordicon.js"></script>
  <link rel="stylesheet" href="https://hmlchat.simplexsolucoes.com.br/vite/assets/dashboard-<HASH>.css">
</head>
<body style="background:#0b141a;padding:40px">
  <div data-hover-host style="display:inline-flex;gap:8px;align-items:center;padding:8px;color:#8696a0">
    <lord-icon src="https://cdn.lordicon.com/vxnjveem.json"
      stroke="bold"
      colors="primary:#8696a0,secondary:#8696a0"
      trigger="in"
      style="width:22px;height:22px"></lord-icon>
    <span>Inbox</span>
  </div>
</body>
</html>
```

Rodar Playwright (venv já instalado em `~/.local/`):

```python
from playwright.sync_api import sync_playwright
import os
os.environ['LD_LIBRARY_PATH'] = '/tmp/pwdeps_local/usr/lib/x86_64-linux-gnu'

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True, args=['--no-sandbox'])
    page = browser.new_page()
    page.goto('file:///tmp/sidebar_test.html')
    page.wait_for_timeout(1000)
    page.screenshot(path='/tmp/sidebar_test.png')
    browser.close()
```

Abrir `/tmp/sidebar_test.png` e verificar se Lordicon renderiza.

### Checklist de aceitação final

- [ ] Ícones Lordicon visíveis em TODOS os 37 slots únicos
- [ ] Fallback Lucide aparece por ~200ms e some
- [ ] Hover no DIV do item dispara animação
- [ ] Rota ativa mostra ícone verde `#00a884`
- [ ] Troca de tema atualiza cor idle
- [ ] Menu perfil NÃO tem mais "Modo Escuro/Claro" nem "Modo Automático"
- [ ] Menu perfil AINDA tem "Aparência" (palette) funcionando
- [ ] Chevron rotaciona 180° ao expandir subgrupo
- [ ] Console do browser sem warnings relacionados a `<lord-icon>`
- [ ] Screenshot de teste local mostra ícone renderizado

---

## ⚠️ Pontos de atenção / possíveis armadilhas

1. **Vue + Web Components**: `<lord-icon>` é um custom element. O Vite/Vue pode avisar sobre tags desconhecidas. Se der warning, adicionar no `vite.config.js` ou no app:
   ```js
   app.config.compilerOptions.isCustomElement = tag => tag === 'lord-icon';
   ```

2. **Captain (i-woot-captain) não é Lucide**. É um ícone custom do Chatwoot, mas o fallback Lucide no wrapper pode ser `null` (string vazia) pra esse caso — ou usar `i-lucide-bot` como fallback genérico.

3. **ChannelIcon dinâmico** em `Sidebar.vue:366`: o ícone dos canais de inbox é renderizado via `h(ChannelIcon, { inbox, class: 'size-[16px]' })`. **NÃO TOCAR** — é um ícone dinâmico baseado no tipo de canal (WhatsApp, Instagram, etc).

4. **Labels com bolinha colorida**: em `Sidebar.vue:384` e `Sidebar.vue:525`, as labels individuais usam ícone `h('span', { class: 'size-2 rounded-full', style: { backgroundColor: label.color } })`. Isso **NÃO É LORDICON** — mantém. Só o ícone do GRUPO "Labels" (#17 `i-lucide-tag`) que vira Lordicon.

5. **Fallback Lucide 200ms**: se o `<script src="https://cdn.lordicon.com/lordicon.js">` falhar em carregar (adblock, rede corporativa), o fallback Lucide permanece indefinidamente (timeout de 3s no wrapper marca `loaded=true` pra remover o fallback — mas como `<lord-icon>` não existe, mostra vazio). **Mitigação:** se Walisson reportar "ícones sumiram", verificar se o CDN está acessível.

6. **Audit e Billing no txt**: Walisson mandou `style="width:250px"` (provavelmente typo pra 22px). Nosso wrapper ignora o `style` do txt e usa `size=22` padrão. ✅

7. **Agente e WAHA no txt**: **URLs DIFERENTES** agora (`ucbznuay` e `dnphlhar`). O txt foi atualizado pelo Walisson após a pergunta. ✅

8. **Performance**: 37 JSONs × ~8KB = ~300KB no primeiro load. Cache do CDN Lordicon é agressivo (1 ano). Próximas visitas são instantâneas.

---

## 🔗 Arquivos relacionados pra referência

- `/home/chatwoot/chatwoot/lordicons.txt` — source of truth dos URLs
- `/home/chatwoot/chatwoot/app/javascript/dashboard/components-next/sidebar/Sidebar.vue` — 218 a 852 são os menuItems
- `/home/chatwoot/chatwoot/app/javascript/dashboard/components-next/sidebar/SidebarProfileMenu.vue` — menu do avatar
- `/home/chatwoot/chatwoot/app/javascript/dashboard/components-next/sidebar/SidebarCollapsedPopover.vue` — chevron linhas ~136
- `/home/chatwoot/chatwoot/app/javascript/dashboard/assets/scss/_wa-skin.scss` — skin WhatsApp
- `/home/chatwoot/chatwoot/docs/plan-lordicon-migration.md` — **este arquivo**

---

## 🎓 Para o agente do próximo chat

**Contexto mínimo a carregar:**
1. Ler este arquivo (`docs/plan-lordicon-migration.md`) de cabo a rabo
2. Ler `/home/chatwoot/chatwoot/lordicons.txt` para conferir que os CDN URLs são os mesmos mapeados aqui
3. Rodar `grep -n "icon:" app/javascript/dashboard/components-next/sidebar/Sidebar.vue` pra confirmar as linhas
4. Verificar que a VM está rodando (`curl -sk -o /dev/null -w "%{http_code}\n" https://hmlchat.simplexsolucoes.com.br/app` deve retornar 200)
5. Executar na ordem da seção "📋 Ordem de execução"

**Modo de execução:** YOLO end-to-end. Não pausar pra confirmar decisões — todas já foram tomadas e estão documentadas aqui. Se algo quebrar, parar e reportar o bug específico com contexto técnico.

**Output esperado ao final:** resumo do que foi aplicado, listagem de arquivos tocados, confirmação de precompile + restart + screenshot de QA, e link pra validar no browser do Walisson.

---

**Fim do plano.**

— Orion, orquestrando o sistema 🎯
