<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import {
  APPEARANCE_LIMITS,
  APPEARANCE_ENUMS,
  LAUNCHER_ICON_TYPES,
} from '../composables/widgetAppearanceContract';

/**
 * O lançador: posição, distância das bordas, formato, texto e esconder.
 *
 * Tudo isto vivia no `localStorage` do navegador do administrador (D1) ou só
 * no snippet. Aqui vira campo de configuração — o valor viaja em
 * `widget_appearance` e é o mesmo para todo administrador da conta.
 *
 * Os limites vêm de `widgetAppearanceContract`, que espelha o JSON Schema do
 * bloco 3.18 e é cruzado com o arquivo Ruby por teste: a tela avisa antes, o
 * servidor recusa depois. Validação de verdade é a do servidor; esta é
 * cortesia — e cortesia que mente é pior que nenhuma.
 */
const props = defineProps({
  appearance: { type: Object, required: true },
  /** Campos que o `chatwootSettings` do site sobrescreve. */
  overriddenFields: { type: Array, default: () => [] },
  /**
   * Bloco 3.07: o formato expandido é seção de marketing
   * (`PROFILE_SECTIONS['appearance.launcherExpanded']`). Quem decide é a tela,
   * que conhece o perfil; aqui só se obedece. O default é `true` para que este
   * componente continue completo para quem o monte sem perfil.
   */
  showExpandedLauncher: { type: Boolean, default: true },
  /**
   * Bloco 3.19: o endereço da imagem já anexada, ou vazio. Quem sabe se existe
   * byte é o servidor — `additional_attributes` guarda só o MODO.
   */
  launcherIconUrl: { type: String, default: '' },
});

const emit = defineEmits(['update', 'uploadIcon', 'removeIcon']);

const { t } = useI18n();

const POSITIONS = ['left', 'right'];
const TYPES = ['standard', 'expanded_bubble'];
const {
  offsetMin: OFFSET_MIN,
  offsetMax: OFFSET_MAX,
  launcherTextMax: LAUNCHER_TEXT_MAX,
} = APPEARANCE_LIMITS;

const isExpanded = computed(
  () => props.appearance.launcher_type === 'expanded_bubble'
);

const visibleTypes = computed(() =>
  props.showExpandedLauncher
    ? TYPES
    : TYPES.filter(type => type !== 'expanded_bubble')
);

const launcherTextTooLong = computed(
  () => (props.appearance.launcher_text ?? '').length > LAUNCHER_TEXT_MAX
);

const set = (field, value) => emit('update', field, value);

const setOffset = (field, raw) => {
  const parsed = Number.parseInt(raw, 10);
  if (Number.isNaN(parsed)) return;
  set(field, Math.min(OFFSET_MAX, Math.max(OFFSET_MIN, parsed)));
};

const isOverridden = field => props.overriddenFields.includes(field);

/* ── Bloco 3.19: o ícone do lançador ─────────────────────────────────────────
 *
 * O ícone era um `path` fixo no `bubbleHelpers.js`, com o branco cravado. Agora
 * são três modos — e `default` é o padrão de fábrica de TODA caixa nova, em
 * qualquer perfil.
 *
 * O padrão por perfil CAIU (decisão D5). Nenhuma inbox nasce com foto, porque a
 * única foto que o produto poderia escolher sozinho seria genérica, e foto
 * genérica é pior que balão. O que a tela faz em vez disso é SUGERIR — o aviso
 * abaixo, permanente enquanto o modo é `default`, com a razão escrita e sem
 * oferecer nem linkar banco de imagem.
 * ────────────────────────────────────────────────────────────────────────── */
const ICON_MODES = APPEARANCE_ENUMS.launcher_icon;
const ICON_MAX_BYTES = APPEARANCE_LIMITS.launcherIconMaxBytes;
const toKb = bytes => Math.ceil(bytes / 1024);
const ICON_MAX_KB = toKb(ICON_MAX_BYTES);

/** O valor gravado tem duas formas: a string do modo, ou `{mode, url}`. */
const iconMode = computed(() => {
  const stored = props.appearance.launcher_icon;
  return (
    (stored && typeof stored === 'object' ? stored.mode : stored) ?? 'default'
  );
});

const uploadError = ref('');

const onIconPicked = event => {
  const [file] = event.target.files ?? [];
  // Zera o input: sem isto, escolher o MESMO arquivo de novo (depois de
  // corrigir o tamanho, que é o caso comum) não dispara `change` nenhum.
  event.target.value = '';
  if (!file) return;

  if (!LAUNCHER_ICON_TYPES.includes(file.type)) {
    uploadError.value = t('INBOX_WIDGET.APPEARANCE.LAUNCHER.ICON_WRONG_TYPE');
    return;
  }
  if (file.size > ICON_MAX_BYTES) {
    // A recusa é do servidor; esta é a mesma recusa, antes de gastar o upload.
    uploadError.value = t('INBOX_WIDGET.APPEARANCE.LAUNCHER.ICON_TOO_BIG', {
      size: toKb(file.size),
      max: toKb(ICON_MAX_BYTES),
    });
    return;
  }

  uploadError.value = '';
  emit('uploadIcon', file);
};

const removeIcon = () => {
  uploadError.value = '';
  emit('removeIcon');
};
</script>

<template>
  <div class="flex flex-col">
    <SettingsFieldSection
      :label="t('INBOX_WIDGET.APPEARANCE.LAUNCHER.POSITION')"
      :help-text="
        isOverridden('position')
          ? t('INBOX_WIDGET.APPEARANCE.OVERRIDE.FIELD_HINT')
          : ''
      "
    >
      <div class="grid gap-3 sm:grid-cols-2">
        <RadioCard
          v-for="position in POSITIONS"
          :id="`position-${position}`"
          :key="position"
          :label="
            t(
              `INBOX_WIDGET.APPEARANCE.LAUNCHER.POSITIONS.${position.toUpperCase()}`
            )
          "
          :description="
            t(
              `INBOX_WIDGET.APPEARANCE.LAUNCHER.POSITIONS.${position.toUpperCase()}_HINT`
            )
          "
          :is-active="appearance.position === position"
          :data-testid="`position-${position}`"
          @select="set('position', position)"
        />

        <!-- Rotulo acessivel do radio do `RadioCard` — a razao completa esta em
             `ThemeModeField.vue`, junto do numero medido. Em resumo: o
             componente nao amarra o `<h3>` ao `<input>`, o axe reprova com
             `label` [critical], e a correcao de raiz (em
             `components-next/radioCard/`) esta escalada por ser de outra
             trilha. `sr-only` e absoluto: nao ocupa celula do grid. -->
        <label
          v-for="position in POSITIONS"
          :key="`label-${position}`"
          :for="`position-${position}`"
          class="sr-only"
        >
          {{
            t(
              `INBOX_WIDGET.APPEARANCE.LAUNCHER.POSITIONS.${position.toUpperCase()}`
            )
          }}
        </label>
      </div>
    </SettingsFieldSection>

    <SettingsFieldSection
      :label="t('INBOX_WIDGET.APPEARANCE.LAUNCHER.OFFSETS')"
      :help-text="t('INBOX_WIDGET.APPEARANCE.LAUNCHER.OFFSETS_HINT')"
    >
      <div class="flex gap-4">
        <Input
          id="offset-x"
          type="number"
          class="w-28"
          :model-value="appearance.offset_x"
          :label="t('INBOX_WIDGET.APPEARANCE.LAUNCHER.OFFSET_X')"
          data-testid="offset-x"
          @update:model-value="setOffset('offset_x', $event)"
        />
        <Input
          id="offset-y"
          type="number"
          class="w-28"
          :model-value="appearance.offset_y"
          :label="t('INBOX_WIDGET.APPEARANCE.LAUNCHER.OFFSET_Y')"
          data-testid="offset-y"
          @update:model-value="setOffset('offset_y', $event)"
        />
      </div>
    </SettingsFieldSection>

    <SettingsFieldSection :label="t('INBOX_WIDGET.APPEARANCE.LAUNCHER.TYPE')">
      <div class="grid gap-3 sm:grid-cols-2">
        <RadioCard
          v-for="type in visibleTypes"
          :id="`launcher-${type}`"
          :key="type"
          :label="
            t(`INBOX_WIDGET.APPEARANCE.LAUNCHER.TYPES.${type.toUpperCase()}`)
          "
          :description="
            t(
              `INBOX_WIDGET.APPEARANCE.LAUNCHER.TYPES.${type.toUpperCase()}_HINT`
            )
          "
          :is-active="appearance.launcher_type === type"
          :data-testid="`launcher-${type}`"
          @select="set('launcher_type', type)"
        />

        <!-- Idem: rotulo acessivel do radio. Ver `ThemeModeField.vue`. -->
        <label
          v-for="type in visibleTypes"
          :key="`label-${type}`"
          :for="`launcher-${type}`"
          class="sr-only"
        >
          {{
            t(`INBOX_WIDGET.APPEARANCE.LAUNCHER.TYPES.${type.toUpperCase()}`)
          }}
        </label>
      </div>
    </SettingsFieldSection>

    <SettingsFieldSection :label="t('INBOX_WIDGET.APPEARANCE.LAUNCHER.ICON')">
      <div class="grid gap-3 sm:grid-cols-3">
        <RadioCard
          v-for="mode in ICON_MODES"
          :id="`launcher-icon-${mode}`"
          :key="mode"
          :label="
            t(`INBOX_WIDGET.APPEARANCE.LAUNCHER.ICONS.${mode.toUpperCase()}`)
          "
          :description="
            t(
              `INBOX_WIDGET.APPEARANCE.LAUNCHER.ICONS.${mode.toUpperCase()}_HINT`
            )
          "
          :is-active="iconMode === mode"
          :data-testid="`launcher-icon-${mode}`"
          @select="set('launcher_icon', mode)"
        />

        <!-- Idem: rotulo acessivel do radio. Ver `ThemeModeField.vue`. -->
        <label
          v-for="mode in ICON_MODES"
          :key="`label-icon-${mode}`"
          :for="`launcher-icon-${mode}`"
          class="sr-only"
        >
          {{
            t(`INBOX_WIDGET.APPEARANCE.LAUNCHER.ICONS.${mode.toUpperCase()}`)
          }}
        </label>
      </div>

      <!-- Decisão D5: enquanto o lançador é o balão, a tela SUGERE a foto de
           alguém do time, com a razão escrita. Nunca oferece banco de imagem —
           foto genérica é pior que balão, e é por isso que nenhuma caixa nasce
           com foto. -->
      <Banner
        v-if="iconMode === 'default'"
        color="blue"
        class="mt-3"
        data-testid="launcher-icon-suggestion"
      >
        {{ t('INBOX_WIDGET.APPEARANCE.LAUNCHER.ICON_SUGGESTION') }}
      </Banner>

      <div v-if="iconMode === 'image'" class="flex flex-col gap-2 mt-3">
        <div class="flex items-center gap-3">
          <img
            v-if="launcherIconUrl"
            :src="launcherIconUrl"
            :alt="t('INBOX_WIDGET.APPEARANCE.LAUNCHER.ICON')"
            class="object-cover w-10 h-10 rounded-full bg-n-slate-3"
            data-testid="launcher-icon-preview"
          />
          <label
            for="launcher-icon-file"
            class="px-3 py-2 text-sm rounded-lg cursor-pointer bg-n-slate-3 hover:bg-n-slate-4 text-n-slate-12"
          >
            {{
              launcherIconUrl
                ? t('INBOX_WIDGET.APPEARANCE.LAUNCHER.ICON_REPLACE')
                : t('INBOX_WIDGET.APPEARANCE.LAUNCHER.ICON_UPLOAD')
            }}
          </label>
          <!-- O input fica escondido e o `<label for>` é o botão: `sr-only` e
               não `display:none`, senão o campo some do foco por teclado. -->
          <input
            id="launcher-icon-file"
            type="file"
            class="sr-only"
            :accept="LAUNCHER_ICON_TYPES.join(',')"
            data-testid="launcher-icon-file"
            @change="onIconPicked"
          />
          <button
            v-if="launcherIconUrl"
            type="button"
            class="px-3 py-2 text-sm rounded-lg text-n-ruby-11 hover:bg-n-ruby-3"
            data-testid="launcher-icon-remove"
            @click="removeIcon"
          >
            {{ t('INBOX_WIDGET.APPEARANCE.LAUNCHER.ICON_REMOVE') }}
          </button>
        </div>

        <p
          v-if="uploadError"
          class="text-sm text-n-ruby-11"
          data-testid="launcher-icon-error"
        >
          {{ uploadError }}
        </p>
        <p
          v-else-if="!launcherIconUrl"
          class="text-sm text-n-amber-11"
          data-testid="launcher-icon-needs-image"
        >
          {{ t('INBOX_WIDGET.APPEARANCE.LAUNCHER.ICON_NEEDS_IMAGE') }}
        </p>
        <p v-else class="text-sm text-n-slate-11">
          {{
            t('INBOX_WIDGET.APPEARANCE.LAUNCHER.ICON_HINT', {
              max: ICON_MAX_KB,
            })
          }}
        </p>
      </div>
    </SettingsFieldSection>

    <SettingsFieldSection
      v-if="isExpanded"
      :label="t('INBOX_WIDGET.APPEARANCE.LAUNCHER.TEXT')"
    >
      <Input
        id="launcher-text"
        class="max-w-sm"
        :model-value="appearance.launcher_text"
        :placeholder="t('INBOX_WIDGET.APPEARANCE.LAUNCHER.TEXT_PLACEHOLDER')"
        :message="
          launcherTextTooLong
            ? t('INBOX_WIDGET.APPEARANCE.LAUNCHER.TEXT_TOO_LONG', {
                max: LAUNCHER_TEXT_MAX,
              })
            : ''
        "
        :message-type="launcherTextTooLong ? 'error' : 'info'"
        data-testid="launcher-text"
        @update:model-value="set('launcher_text', $event)"
      />
    </SettingsFieldSection>

    <SettingsFieldSection
      :label="t('INBOX_WIDGET.APPEARANCE.LAUNCHER.HIDE_BUBBLE')"
      :help-text="t('INBOX_WIDGET.APPEARANCE.LAUNCHER.HIDE_BUBBLE_HINT')"
    >
      <Switch
        :model-value="appearance.hide_bubble"
        :aria-label="t('INBOX_WIDGET.APPEARANCE.LAUNCHER.HIDE_BUBBLE')"
        data-testid="hide-bubble"
        @update:model-value="set('hide_bubble', $event)"
      />
    </SettingsFieldSection>
  </div>
</template>
