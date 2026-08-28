<script setup>
import { computed } from 'vue';
import Avatar from 'next/avatar/Avatar.vue';
import { PREVIEW_AVATAR_ACCENT } from '../previewAvatarAccent';

/**
 * O teaser dentro do preview (bloco 4.07).
 *
 * Duas FORMAS, e nao dois componentes: `discreet` e o `bold` com a foto e os
 * chips escondidos. Dois componentes de teaser dobrariam o peso do arquivo que
 * 100% dos visitantes baixa para entregar a mesma coisa menor — e aqui, no
 * preview, dobrariam a chance de o que o cliente ve nao ser o que o visitante
 * recebe.
 *
 * As cores saem dos tokens do widget (`--w-brand`, `--w-on-brand`), como todo o
 * resto do preview depois do bloco 3.10: nao ha cor literal nem classe do
 * dashboard aqui dentro.
 */
const props = defineProps({
  /** `discreet` | `bold` — o nivel de abordagem configurado. */
  level: { type: String, default: 'bold' },
  text: { type: String, default: '' },
  senderName: { type: String, default: '' },
  avatarUrl: { type: String, default: '' },
  /** As opcoes nomeadas da inbox (`home_intents`), os chips reais. */
  intents: { type: Array, default: () => [] },
});

const isBold = computed(() => props.level === 'bold');
const chips = computed(() => (isBold.value ? props.intents.slice(0, 4) : []));
</script>

<template>
  <div
    v-if="text"
    class="flex flex-col gap-2 p-3 rounded-2xl shadow-md bg-wp-surface max-w-[17rem]"
    :data-testid="`teaser-${level}`"
  >
    <div class="flex items-start gap-2">
      <!-- Mesmo `accent` do rodape, e pela mesma razao: o remetente do teaser e'
           um nome livre, e a cor sorteada por `name.length` nao tem piso de
           contraste. Ver `previewAvatarAccent.js`. -->
      <Avatar
        v-if="isBold"
        :name="senderName || ' '"
        :src="avatarUrl"
        :size="28"
        :accent="PREVIEW_AVATAR_ACCENT"
        rounded-full
        data-testid="teaser-avatar"
      />
      <div class="flex flex-col gap-0.5">
        <span
          v-if="isBold && senderName"
          class="text-xs font-medium text-wp-text"
          data-testid="teaser-sender"
        >
          {{ senderName }}
        </span>
        <p class="m-0 text-sm text-wp-text" data-testid="teaser-text">
          {{ text }}
        </p>
      </div>
    </div>

    <div
      v-if="chips.length"
      class="flex flex-wrap gap-1"
      data-testid="teaser-chips"
    >
      <span
        v-for="intent in chips"
        :key="intent.id ?? intent.label"
        class="px-2 py-1 text-xs rounded-full bg-w-brand text-w-on-brand"
      >
        {{ intent.label }}
      </span>
    </div>
  </div>
</template>
