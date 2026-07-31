<script setup>
import { shallowRef, computed, onMounted } from 'vue';
import emojiGroups from 'shared/components/emoji/emojisGroup.json';
import { getRecentEmojis, addRecentEmoji } from 'shared/helpers/recentEmojis';
import MentionBox from '../mentions/MentionBox.vue';

const props = defineProps({
  searchKey: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['selectEmoji']);

const allEmojis = shallowRef([]);
const recentEmojis = shallowRef([]);

const items = computed(() => {
  if (!props.searchKey) return [];
  const searchTerm = props.searchKey.toLowerCase();
  const matches = allEmojis.value.filter(emoji =>
    emoji.searchString.includes(searchTerm)
  );

  // Entre os resultados da busca, os usados recentemente vêm primeiro.
  const recentRank = new Map(recentEmojis.value.map((emoji, i) => [emoji, i]));
  if (!recentRank.size) return matches;

  return [...matches].sort(
    (a, b) =>
      (recentRank.get(a.emoji) ?? Number.MAX_SAFE_INTEGER) -
      (recentRank.get(b.emoji) ?? Number.MAX_SAFE_INTEGER)
  );
});

function loadEmojis() {
  allEmojis.value = emojiGroups.flatMap(({ emojis }) =>
    emojis.map(({ name, slug, ...rest }) => ({
      ...rest,
      name,
      slug,
      searchString: `${name.replace(/\s+/g, '')} ${slug}`.toLowerCase(), // Remove all whitespace and convert to lowercase
    }))
  );
}

function handleMentionClick(item = {}) {
  recentEmojis.value = addRecentEmoji(item.emoji);
  emit('selectEmoji', item.emoji);
}

onMounted(() => {
  loadEmojis();
  recentEmojis.value = getRecentEmojis();
});
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <MentionBox
    v-if="items.length"
    type="emoji"
    :items="items"
    @mention-select="handleMentionClick"
  >
    <template #default="{ item, selected }">
      <span
        class="max-w-full inline-flex items-center gap-0.5 min-w-0 mb-0 text-sm font-medium text-n-slate-12 group-hover:text-n-brand truncate"
      >
        {{ item.emoji }}
        <p
          class="relative mb-0 truncate bottom-px"
          :class="{
            'text-n-brand': selected,
            'font-normal': !selected,
          }"
        >
          :{{ item.name }}
        </p>
      </span>
    </template>
  </MentionBox>
</template>
