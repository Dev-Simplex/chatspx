<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import { APPEARANCE_LIMITS } from '../composables/widgetAppearanceContract';

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
});

const emit = defineEmits(['update']);

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
