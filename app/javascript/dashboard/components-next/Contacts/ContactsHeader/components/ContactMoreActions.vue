<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import { usePolicy } from 'dashboard/composables/usePolicy';

const emit = defineEmits(['import', 'export']);

const { t } = useI18n();
const { checkPermissions } = usePolicy();
// RECONCILIAÇÃO — este é o par do ContactHeader.vue, e por isso NÃO é "um lado".
// Da homologação vem a AUSÊNCIA do item 'add': lá ele foi promovido a botão
// próprio no header, e o `defineEmits` deste arquivo (já mesclado acima) também
// veio de lá, sem 'add' — manter o item no menu deixaria um emit não declarado.
// O ContactHeader confirma: ele escuta só @import e @export.
// De ours fica o `checkPermissions`, que a homologação não tem: sem ele,
// exportar e importar contatos aparecem para qualquer papel. Controle de acesso
// não se perde numa reconciliação de menu — e é por isso que o
// `contactMenuItems` continua `computed`, já que a permissão é reativa.
const contactMenuItems = computed(() => [
  ...(checkPermissions(['administrator', 'contact_manage'])
    ? [
        {
          label: t(
            'CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.EXPORT_CONTACT'
          ),
          action: 'export',
          value: 'export',
          icon: 'i-lucide-upload',
        },
      ]
    : []),
  ...(checkPermissions(['administrator', 'contact_manage'])
    ? [
        {
          label: t(
            'CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.IMPORT_CONTACT'
          ),
          action: 'import',
          value: 'import',
          icon: 'i-lucide-download',
        },
      ]
    : []),
]);
const showActionsDropdown = ref(false);

const handleContactAction = ({ action }) => {
  if (action === 'import') {
    emit('import');
  } else if (action === 'export') {
    emit('export');
  }
};
</script>

<template>
  <div v-on-clickaway="() => (showActionsDropdown = false)" class="relative">
    <Button
      icon="i-lucide-ellipsis-vertical"
      color="slate"
      variant="ghost"
      size="sm"
      :class="showActionsDropdown ? 'bg-n-alpha-2' : ''"
      @click="showActionsDropdown = !showActionsDropdown"
    />
    <DropdownMenu
      v-if="showActionsDropdown"
      :menu-items="contactMenuItems"
      class="ltr:right-0 rtl:left-0 mt-1 w-52 top-full"
      @action="handleContactAction($event)"
    />
  </div>
</template>
