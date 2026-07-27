<script>
import emojis from './emojisGroup.json';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import { getRecentEmojis, addRecentEmoji } from 'shared/helpers/recentEmojis';
const SEARCH_KEY = 'Search';
const RECENT_KEY = 'Recent';

// Ícone de cada aba do rodapé, por slug de categoria do emojisGroup.json.
// As classes i-lucide-* vêm do plugin de ícones do tailwind.config.js, cujo
// content já cobre shared/ — logo valem também no widget.
const CATEGORY_ICONS = {
  smileys_emotion: 'i-lucide-smile',
  people_body: 'i-lucide-hand',
  animals_nature: 'i-lucide-paw-print',
  food_drink: 'i-lucide-utensils',
  travel_places: 'i-lucide-plane',
  activities: 'i-lucide-party-popper',
  objects: 'i-lucide-lightbulb',
  symbols: 'i-lucide-shapes',
  flags: 'i-lucide-flag',
};
const FALLBACK_CATEGORY_ICON = 'i-lucide-smile';
const RECENT_TAB_ICON = 'i-lucide-clock';
const SEARCH_TAB_ICON = 'i-lucide-search';

export default {
  components: { FluentIcon, NextButton },
  props: {
    onClick: {
      type: Function,
      default: () => {},
    },
    showRemoveButton: {
      type: Boolean,
      default: false,
    },
  },
  data() {
    return {
      selectedKey: 'Search',
      emojis,
      search: '',
      recentEmojis: getRecentEmojis(),
      recentKey: RECENT_KEY,
      recentTabIcon: RECENT_TAB_ICON,
      searchTabIcon: SEARCH_TAB_ICON,
    };
  },
  computed: {
    categories() {
      return [...this.emojis];
    },
    hasRecentEmojis() {
      return this.recentEmojis.length > 0;
    },
    isRecentSelected() {
      return this.selectedKey === RECENT_KEY;
    },
    selectedCategory() {
      return this.emojis.find(category => category.name === this.selectedKey);
    },
    filterEmojisByCategory() {
      return this.selectedCategory?.emojis;
    },
    filterAllEmojisBySearch() {
      return this.emojis.map(category => {
        const allEmojis = category.emojis.filter(emoji =>
          emoji.slug.replaceAll('_', ' ').includes(this.search.toLowerCase())
        );
        return allEmojis.length > 0
          ? { ...category, emojis: allEmojis }
          : { ...category, emojis: [] };
      });
    },
    hasNoSearch() {
      return (
        this.selectedKey !== SEARCH_KEY &&
        this.selectedKey !== RECENT_KEY &&
        this.search === ''
      );
    },
    // Estado inicial da caixa (aba de busca, sem termo digitado): os recentes
    // aparecem no topo, acima de todas as categorias.
    showRecentSection() {
      return (
        this.hasRecentEmojis &&
        this.selectedKey === SEARCH_KEY &&
        this.search === ''
      );
    },
    hasEmptySearchResult() {
      return this.filterAllEmojisBySearch.every(
        category => category.emojis.length === 0
      );
    },
  },
  watch: {
    search() {
      this.selectedKey = 'Search';
    },
    selectedKey() {
      return this.selectedKey === 'Search' ? this.focusSearchInput() : null;
    },
  },
  mounted() {
    this.focusSearchInput();
  },
  methods: {
    changeCategory(category) {
      this.search = '';
      this.$refs.emojiItem.scrollTo({ top: 0 });
      this.selectedKey = category;
    },
    // Todo emoji escolhido pela caixa passa por aqui, para alimentar os recentes.
    selectEmoji(emoji) {
      this.recentEmojis = addRecentEmoji(emoji);
      this.onClick(emoji);
    },
    categoryIcon(categorySlug) {
      return CATEGORY_ICONS[categorySlug] || FALLBACK_CATEGORY_ICON;
    },
    // Os nomes das categorias vêm em inglês do emojisGroup.json; traduzimos na
    // exibição, caindo no nome original se a chave não existir no locale.
    categoryLabel(category) {
      if (!category) return '';
      const key = `EMOJI.CATEGORIES.${category.slug.toUpperCase()}`;
      const label = this.$t(key);
      return label === key ? category.name : label;
    },
    focusSearchInput() {
      this.$nextTick(() => {
        this.$refs.searchbar.focus();
      });
    },
  },
};
</script>

<template>
  <div
    role="dialog"
    class="emoji-dialog bg-n-background shadow-lg rounded-md outline outline-1 outline-n-weak box-content h-[18.75rem] absolute right-0 -top-[95px] w-80 z-20"
  >
    <div class="flex flex-col">
      <div class="flex gap-2 m-2 sticky top-2">
        <input
          ref="searchbar"
          v-model="search"
          type="text"
          class="focus:box-shadow-blue dark:focus:box-shadow-dark !mb-0 !h-8 !text-sm"
          :placeholder="$t('EMOJI.PLACEHOLDER')"
        />
        <NextButton
          v-if="showRemoveButton"
          faded
          sm
          slate
          class="flex-shrink-0"
          :label="$t('EMOJI.REMOVE')"
          @click="onClick('')"
        />
      </div>
      <div v-if="isRecentSelected" ref="emojiItem" class="emoji-item">
        <h5
          class="text-sm text-n-slate-12 font-medium leading-normal m-0 py-1 px-2"
        >
          {{ $t('EMOJI.RECENT') }}
        </h5>
        <div class="emoji--row">
          <button
            v-for="emoji in recentEmojis"
            :key="emoji"
            v-dompurify-html="emoji"
            class="emoji--item"
            @click="selectEmoji(emoji)"
          />
        </div>
      </div>
      <div v-else-if="hasNoSearch" ref="emojiItem" class="emoji-item">
        <h5
          class="text-sm text-n-slate-12 font-medium leading-normal m-0 py-1 px-2"
        >
          {{ categoryLabel(selectedCategory) }}
        </h5>
        <div class="emoji--row">
          <button
            v-for="item in filterEmojisByCategory"
            :key="item.slug"
            v-dompurify-html="item.emoji"
            class="emoji--item"
            track-by="$index"
            @click="selectEmoji(item.emoji)"
          />
        </div>
      </div>
      <div v-else ref="emojiItem" class="emoji-item">
        <div v-if="showRecentSection">
          <h5
            class="text-sm text-n-slate-12 font-medium leading-normal m-0 py-1 px-2"
          >
            {{ $t('EMOJI.RECENT') }}
          </h5>
          <div class="emoji--row">
            <button
              v-for="emoji in recentEmojis"
              :key="emoji"
              v-dompurify-html="emoji"
              class="emoji--item"
              @click="selectEmoji(emoji)"
            />
          </div>
        </div>
        <div v-for="category in filterAllEmojisBySearch" :key="category.slug">
          <h5
            v-if="category.emojis.length > 0"
            class="text-sm text-n-slate-12 font-medium leading-normal m-0 py-1 px-2"
          >
            {{ categoryLabel(category) }}
          </h5>
          <div v-if="category.emojis.length > 0" class="emoji--row">
            <button
              v-for="item in category.emojis"
              :key="item.slug"
              v-dompurify-html="item.emoji"
              class="emoji--item"
              track-by="$index"
              @click="selectEmoji(item.emoji)"
            />
          </div>
        </div>
        <div
          v-if="hasEmptySearchResult"
          class="items-center flex flex-col h-[13.25rem] justify-center"
        >
          <div class="text-n-slate-11 mb-2">
            <FluentIcon icon="emoji" size="48" />
          </div>
          <span class="text-n-slate-11 text-sm font-medium">
            {{ $t('EMOJI.NOT_FOUND') }}
          </span>
        </div>
      </div>

      <div
        class="emoji-dialog--footer relative w-full py-0 rounded-b-[0.34rem] px-1 bg-n-slate-3"
        role="menu"
      >
        <ul
          class="flex relative left-[2px] rtl:left-[unset] rtl:right-[2px] list-none m-0 overflow-auto py-1 px-0"
        >
          <li>
            <button
              class="emoji--item"
              :class="{ active: selectedKey === 'Search' }"
              :title="$t('EMOJI.PLACEHOLDER')"
              @click="changeCategory('Search')"
            >
              <span class="emoji--tab-icon" :class="searchTabIcon" />
            </button>
          </li>
          <li v-if="hasRecentEmojis">
            <button
              class="emoji--item"
              :class="{ active: isRecentSelected }"
              :title="$t('EMOJI.RECENT')"
              @click="changeCategory(recentKey)"
            >
              <span class="emoji--tab-icon" :class="recentTabIcon" />
            </button>
          </li>
          <li
            v-for="category in categories"
            :key="category.slug"
            @click="changeCategory(category.name)"
          >
            <button
              class="emoji--item"
              :class="{ active: selectedKey === category.name }"
              :title="categoryLabel(category)"
              @click="changeCategory(category.name)"
            >
              <span
                class="emoji--tab-icon"
                :class="categoryIcon(category.slug)"
              />
            </button>
          </li>
        </ul>
      </div>
    </div>
  </div>
</template>

<style scoped>
@tailwind components;

@layer components {
  .box-shadow-blue {
    box-shadow:
      0 0 0 1px #2dc46f,
      0 0 1px 2px #d0f4e3;
  }

  .box-shadow-dark {
    box-shadow:
      0 0 0 1px #212222,
      0 0 1px 2px #4c5155;
  }
}
</style>

<style lang="scss">
.emoji-dialog {
  &::before {
    @apply absolute -bottom-3 h-3 w-6 bg-n-slate-3 content-[""];
    clip-path: polygon(50% 100%, 0% 0%, 100% 0%);
  }
}

.emoji--item {
  @apply bg-transparent border-0 rounded cursor-pointer text-lg h-6 m-0 py-0 px-1 hover:bg-n-slate-4;
}

.emoji--row {
  @apply box-border p-1;

  .emoji--item {
    @apply h-[1.625rem] w-[1.625rem] leading-normal m-1;
  }
}

.emoji-item {
  @apply h-[13.25rem] overflow-y-auto;
}

.emoji-dialog--footer {
  ul {
    > li {
      @apply items-center cursor-pointer flex justify-center p-1;
    }

    li .active {
      @apply bg-n-background;
    }

    .emoji--item {
      @apply items-center flex justify-center text-sm;

      &:hover {
        @apply bg-n-slate-2;
      }
    }

    // Abas de categoria: ícones de traço no lugar do emoji representativo.
    .emoji--tab-icon {
      @apply text-base text-n-slate-11;
    }

    .active .emoji--tab-icon {
      @apply text-n-slate-12;
    }
  }
}
</style>
