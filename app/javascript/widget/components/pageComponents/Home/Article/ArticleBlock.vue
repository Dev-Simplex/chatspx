<script setup>
import { defineProps, defineEmits, computed } from 'vue';
import ArticleListItem from './ArticleListItem.vue';

const props = defineProps({
  articles: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['view', 'viewAll']);

const articlesToDisplay = computed(() => props.articles.slice(0, 6));

const onArticleClick = link => {
  emit('view', link);
};
</script>

<template>
  <div class="flex flex-col gap-3">
    <h3 class="font-medium text-n-slate-12">
      {{ $t('PORTAL.POPULAR_ARTICLES') }}
    </h3>
    <div class="flex flex-col gap-4">
      <ArticleListItem
        v-for="article in articlesToDisplay"
        :key="article.slug"
        :link="article.link"
        :title="article.title"
        @select-article="onArticleClick"
      />
    </div>
    <div>
      <!-- Blocos 1.03/1.04: o estilo inline que havia aqui pintava a MARCA CRUA
           sobre o fundo claro do painel — 2,27:1 no verde da casa.
           `text-w-brand-readable` é a mesma marca escurecida até 4,5:1 pelo
           servidor, e tem par próprio no tema escuro. -->
      <button
        class="font-medium tracking-wide inline-flex text-w-brand-readable"
        @click="$emit('viewAll')"
      >
        <span>{{ $t('PORTAL.VIEW_ALL_ARTICLES') }}</span>
      </button>
    </div>
  </div>
</template>
