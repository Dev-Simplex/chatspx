<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { getLanguageName } from 'dashboard/components/widgets/conversation/advancedFilterItems/languages';
import ContactDetailsItem from './ContactDetailsItem.vue';
import CustomAttributes from './customAttributes/CustomAttributes.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  conversationAttributes: {
    type: Object,
    default: () => ({}),
  },
  contactAttributes: {
    type: Object,
    default: () => ({}),
  },
});

const { t } = useI18n();

const referer = computed(() => props.conversationAttributes.referer);
const initiatedAt = computed(
  () => props.conversationAttributes.initiated_at?.timestamp
);

const browserInfo = computed(() => props.conversationAttributes.browser);

const browserName = computed(() => {
  if (!browserInfo.value) return '';
  const { browser_name: name = '', browser_version: version = '' } =
    browserInfo.value;
  return `${name} ${version}`;
});

const browserLanguage = computed(() =>
  getLanguageName(props.conversationAttributes.browser_language)
);

const platformName = computed(() => {
  if (!browserInfo.value) return '';
  const { platform_name: name = '', platform_version: version = '' } =
    browserInfo.value;
  return `${name} ${version}`;
});

// Mesma razao do ContactPanel: dependendo de por onde o contato veio, a chave
// chega camelizada pela store ou crua da API.
const createdAtIp = computed(
  () =>
    props.contactAttributes.created_at_ip || props.contactAttributes.createdAtIp
);

// O IP do visitante e dado pessoal e ficava em claro no painel, visivel para
// qualquer agente com a conversa aberta, sem nenhuma acao deliberada. Passa a
// nascer mascarado; quem precisa dele revela por clique.
const isIpRevealed = ref(false);
const maskedIp = computed(() => {
  if (!createdAtIp.value) return '';
  // Mantem o primeiro octeto (ou o primeiro grupo, em IPv6) para dar contexto
  // de rede sem entregar o endereco.
  const separator = createdAtIp.value.includes(':') ? ':' : '.';
  const [head] = createdAtIp.value.split(separator);
  return `${head}${separator}•••`;
});
const displayedIp = computed(() =>
  isIpRevealed.value ? createdAtIp.value : maskedIp.value
);
// Chaves literais de proposito: chave dinamica em $t esconde o texto do
// extrator de i18n e do lint.
const ipToggleLabel = computed(() =>
  isIpRevealed.value
    ? t('CONTACT_PANEL.IP_ADDRESS_HIDE')
    : t('CONTACT_PANEL.IP_ADDRESS_REVEAL')
);

const staticElements = computed(() =>
  [
    {
      content: initiatedAt,
      title: 'CONTACT_PANEL.INITIATED_AT',
      key: 'static-initiated-at',
      type: 'static_attribute',
    },
    {
      content: browserLanguage,
      title: 'CONTACT_PANEL.BROWSER_LANGUAGE',
      key: 'static-browser-language',
      type: 'static_attribute',
    },
    {
      content: referer,
      title: 'CONTACT_PANEL.INITIATED_FROM',
      key: 'static-referer',
      type: 'static_attribute',
    },
    {
      content: browserName,
      title: 'CONTACT_PANEL.BROWSER',
      key: 'static-browser',
      type: 'static_attribute',
    },
    {
      content: platformName,
      title: 'CONTACT_PANEL.OS',
      key: 'static-platform',
      type: 'static_attribute',
    },
    {
      content: createdAtIp,
      title: 'CONTACT_PANEL.IP_ADDRESS',
      key: 'static-ip-address',
      type: 'static_attribute',
    },
  ].filter(attribute => !!attribute.content.value)
);
</script>

<template>
  <div class="conversation--details">
    <CustomAttributes
      :static-elements="staticElements"
      attribute-class="conversation--attribute"
      attribute-from="conversation_panel"
      attribute-type="conversation_attribute"
    >
      <template #staticItem="{ element }">
        <ContactDetailsItem
          :key="element.title"
          :title="$t(element.title)"
          :value="element.content.value"
        >
          <template v-if="element.key === 'static-ip-address'" #button>
            <NextButton
              ghost
              xs
              :icon="isIpRevealed ? 'i-lucide-eye-off' : 'i-lucide-eye'"
              :title="ipToggleLabel"
              :aria-label="ipToggleLabel"
              data-testid="toggle-ip-address"
              @click="isIpRevealed = !isIpRevealed"
            />
          </template>
          <a
            v-if="element.key === 'static-referer'"
            :href="element.content.value"
            rel="noopener noreferrer nofollow"
            target="_blank"
            class="text-n-brand"
          >
            {{ element.content.value }}
          </a>
          <span
            v-else-if="element.key === 'static-ip-address'"
            data-testid="ip-address-value"
          >
            {{ displayedIp }}
          </span>
        </ContactDetailsItem>
      </template>
    </CustomAttributes>
  </div>
</template>
