<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { format, isToday, isYesterday, isThisYear } from 'date-fns';
import { ptBR, enUS } from 'date-fns/locale';

const props = defineProps({
  date: {
    type: [Date, Number, String],
    required: true,
  },
});

const { t, locale } = useI18n();

const dateLocale = computed(() => {
  return locale.value === 'pt_BR' ? ptBR : enUS;
});

const formattedDate = computed(() => {
  const dateObj = new Date(props.date);
  
  if (isToday(dateObj)) {
    return t('CONVERSATION.TODAY');
  }
  
  if (isYesterday(dateObj)) {
    return t('CONVERSATION.YESTERDAY');
  }
  
  if (isThisYear(dateObj)) {
    // Format: "15 de Nov" or "Nov 15"
    return format(dateObj, locale.value === 'pt_BR' ? "dd 'de' MMM" : 'MMM dd', {
      locale: dateLocale.value,
    });
  }
  
  // Format: "15 de Nov de 2024" or "Nov 15, 2024"
  return format(dateObj, locale.value === 'pt_BR' ? "dd 'de' MMM 'de' yyyy" : 'MMM dd, yyyy', {
    locale: dateLocale.value,
  });
});
</script>

<template>
  <div class="sticky top-0 z-10 flex justify-center my-4">
    <div
      class="inline-flex items-center px-3 py-1 rounded-full bg-slate-200/80 dark:bg-slate-700/80 backdrop-blur-sm shadow-sm"
    >
      <span class="text-xs font-medium text-slate-600 dark:text-slate-300 uppercase tracking-wide">
        {{ formattedDate }}
      </span>
    </div>
  </div>
</template>



