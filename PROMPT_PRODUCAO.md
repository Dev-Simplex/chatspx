# Prompt para Aplicar Background na Produção

## Objetivo
Adicionar imagem de background na área de conversa (dashboard e widget) que muda baseado no tema (dark/light), cobrindo toda a área scrollable com opacidade.

## Arquivos de Imagem Necessários
Certifique-se de que as seguintes imagens estão em `public/assets/images/`:
- `chat-spx-background.png` (imagem original para dark mode)
- `chat-spx-background-light.png` (imagem invertida para light mode)

## Alterações Necessárias

### 1. Arquivo: `app/javascript/dashboard/components/widgets/conversation/MessagesView.vue`

**Localizar a seção `.conversation-panel` no `<style scoped lang="scss">` e adicionar:**

```scss
.conversation-panel {
  position: relative;
  background-image: 
    linear-gradient(rgba(0, 0, 0, 0.85), rgba(0, 0, 0, 0.85)),
    url('/assets/images/chat-spx-background.png');
  background-size: auto, 400px;
  background-position: 0 0, 0 0;
  background-repeat: repeat, repeat;

  &::before {
    content: '';
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background-image: url('/assets/images/chat-spx-background.png');
    background-size: 400px;
    background-position: 0 0;
    background-repeat: repeat;
    z-index: 0;
    pointer-events: none;
    display: none;
  }

  &.conversation-panel-light {
    background-image:
      linear-gradient(rgba(255, 255, 255, 0.85), rgba(255, 255, 255, 0.85)),
      url('/assets/images/chat-spx-background-light.png');
    background-size: auto, 400px;
    background-position: 0 0, 0 0;
    background-repeat: repeat, repeat;
  }

  > * {
    position: relative;
    z-index: 2;
  }
}
```

**No template, garantir que o elemento `MessageList` tenha as classes condicionais:**

```vue
<MessageList
  ref="conversationPanelRef"
  class="conversation-panel flex-shrink flex-grow basis-px flex flex-col overflow-y-auto relative h-full m-0 pb-4"
  :class="{ 'conversation-panel-dark': isDarkMode, 'conversation-panel-light': !isDarkMode }"
  ...
>
```

**Garantir que há uma variável `isDarkMode` no componente (já deve existir):**

```javascript
data() {
  return {
    // ... outros dados
    isDarkMode: false,
    themeObserver: null,
  };
},
methods: {
  // ... outros métodos
  initializeThemeObserver() {
    this.isDarkMode = document.body.classList.contains('dark');
    this.themeObserver = new MutationObserver(() => {
      this.isDarkMode = document.body.classList.contains('dark');
    });
    this.themeObserver.observe(document.body, {
      attributes: true,
      attributeFilter: ['class'],
    });
  },
  removeThemeObserver() {
    if (this.themeObserver) {
      this.themeObserver.disconnect();
      this.themeObserver = null;
    }
  },
},
mounted() {
  // ... outros códigos
  this.initializeThemeObserver();
},
beforeUnmount() {
  // ... outros códigos
  this.removeThemeObserver();
},
```

### 2. Arquivo: `app/javascript/widget/components/ConversationWrap.vue`

**Localizar a seção `.conversation--container` no `<style scoped lang="scss">` e adicionar:**

```scss
.conversation--container {
  display: flex;
  flex-direction: column;
  flex: 1;
  overflow-y: auto;
  color-scheme: light dark;
  position: relative;

  &.light-scheme {
    color-scheme: light;
  }

  &.dark-scheme {
    color-scheme: dark;
  }

  position: relative;
  background-image: 
    linear-gradient(rgba(0, 0, 0, 0.85), rgba(0, 0, 0, 0.85)),
    url('/assets/images/chat-spx-background.png');
  background-size: auto, 400px;
  background-position: 0 0, 0 0;
  background-repeat: repeat, repeat;

  &::before {
    content: '';
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background-image: url('/assets/images/chat-spx-background.png');
    background-size: 400px;
    background-position: 0 0;
    background-repeat: repeat;
    z-index: 0;
    pointer-events: none;
    display: none;
  }

  &.conversation-container-light {
    background-image: linear-gradient(
        rgba(255, 255, 255, 0.85),
        rgba(255, 255, 255, 0.85)
      ),
      url('/assets/images/chat-spx-background-light.png');
    background-size: auto, 400px;
    background-position:
      0 0,
      0 0;
    background-repeat: repeat, repeat;
  }

  > * {
    position: relative;
    z-index: 2;
  }
}
```

**No template, garantir que o elemento tenha as classes condicionais:**

```vue
<div
  class="conversation--container"
  :class="[colorSchemeClass, prefersDarkMode ? 'conversation-container-dark' : 'conversation-container-light']"
>
```

**Garantir que há o composable `useDarkMode` importado (já deve existir):**

```javascript
import { useDarkMode } from 'widget/composables/useDarkMode';

setup() {
  const { darkMode, prefersDarkMode } = useDarkMode();
  return { darkMode, prefersDarkMode };
},
```

## Resumo das Alterações

1. **Imagens**: Colocar `chat-spx-background.png` e `chat-spx-background-light.png` em `public/assets/images/`

2. **MessagesView.vue**:
   - Adicionar estilos CSS para `.conversation-panel` e `.conversation-panel-light`
   - Garantir classes condicionais no template baseadas em `isDarkMode`
   - Garantir que `isDarkMode` está sendo detectado corretamente

3. **ConversationWrap.vue**:
   - Adicionar estilos CSS para `.conversation--container` e `.conversation-container-light`
   - Garantir classes condicionais no template baseadas em `prefersDarkMode`
   - Garantir que `useDarkMode` está importado e usado

## Verificação

Após aplicar as alterações:
- Dark mode: deve mostrar fundo escuro com imagem `chat-spx-background.png`
- Light mode: deve mostrar fundo branco com imagem `chat-spx-background-light.png`
- Background deve aparecer em toda a área scrollable, não apenas no viewport inicial
- Opacidade deve estar aplicada (0.85 no gradient)

