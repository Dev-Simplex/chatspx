<script setup>
import { ref } from 'vue';
import FilterSelect from './FilterSelect.vue';

const options = [
  { value: 'EQUAL_TO', label: 'Equal To', icon: 'i-lucide-equal' },
  {
    value: 'NOT_EQUAL_TO',
    label: 'Not Equal To',
    icon: 'i-lucide-equal-not',
  },
  { value: 'IS_PRESENT', label: 'Is Present', icon: 'i-lucide-list-filter' },
  {
    value: 'IS_NOT_PRESENT',
    label: 'Is Not Present',
    icon: 'i-lucide-list-x',
  },
  { value: 'CONTAINS', label: 'Contains', icon: 'i-lucide-list-checks' },
  {
    value: 'DOES_NOT_CONTAIN',
    label: 'Does Not Contain',
    icon: 'i-lucide-list-minus',
  },
  {
    value: 'IS_GREATER_THAN',
    label: 'Is Greater Than',
    icon: 'i-lucide-chevron-right',
  },
  {
    value: 'IS_LESS_THAN',
    label: 'Is Less Than',
    icon: 'i-lucide-chevron-left',
  },
  {
    value: 'DAYS_BEFORE',
    label: 'Days Before',
    icon: 'i-lucide-calendar-minus',
  },
  {
    value: 'STARTS_WITH',
    label: 'Starts With',
    icon: 'i-lucide-chevron-last',
  },
];

const selected = ref(options[0].value);
</script>

<template>
  <Story
    title="Components/Filters/Filter Select"
    :layout="{ type: 'grid', width: '250px' }"
  >
    <Variant title="With Icon & Label">
      <div class="min-h-[400px]">
        <FilterSelect v-model="selected" :options="options" />
      </div>
    </Variant>
    <Variant title="Without Icon">
      <div class="min-h-[400px]">
        <FilterSelect v-model="selected" hide-icon :options="options" />
      </div>
    </Variant>
    <Variant title="Without Label">
      <div class="min-h-[400px]">
        <FilterSelect v-model="selected" hide-label :options="options" />
      </div>
    </Variant>
  </Story>
</template>
