<script setup>
import { computed } from 'vue';
import { Pie } from 'vue-chartjs';
import {
  Chart as ChartJS,
  Title,
  Tooltip,
  ArcElement,
  Legend,
} from 'chart.js';

const props = defineProps({
  collection: {
    type: Object,
    default: () => ({}),
  },
  chartOptions: {
    type: Object,
    default: () => ({}),
  },
});

ChartJS.register(Title, Tooltip, ArcElement, Legend);

const fontFamily =
  'Inter,-apple-system,system-ui,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif';

const defaultChartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  plugins: {
    legend: {
      display: false,
      labels: {
        fontFamily,
      },
    },
    tooltip: {
      callbacks: {
        label(context) {
          const value = context.parsed || 0;
          return `${context.label}: ${value}`;
        },
        title(context) {
          return context[0]?.label || '';
        },
      },
    },
  },
};

const options = computed(() => {
  return { ...defaultChartOptions, ...props.chartOptions };
});
</script>

<template>
  <Pie :data="collection" :options="options" />
</template>
