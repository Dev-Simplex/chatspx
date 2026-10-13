<script setup>
import { computed } from 'vue';
import { Line } from 'vue-chartjs';
import {
  Chart as ChartJS,
  Tooltip,
  Filler,
  LineElement,
  PointElement,
  CategoryScale,
  LinearScale,
} from 'chart.js';

// Recebidas x resolvidas no tempo. As cores saem das variaveis do tema, entao
// o grafico acompanha o modo claro e o escuro sem cor fixa.
const props = defineProps({
  labels: { type: Array, required: true },
  received: { type: Array, required: true },
  resolved: { type: Array, required: true },
  receivedLabel: { type: String, required: true },
  resolvedLabel: { type: String, required: true },
});

ChartJS.register(
  Tooltip,
  Filler,
  LineElement,
  PointElement,
  CategoryScale,
  LinearScale
);

const cssColor = (name, alpha = 1) => {
  const value = getComputedStyle(document.documentElement)
    .getPropertyValue(name)
    .trim();
  return `rgb(${value} / ${alpha})`;
};

const chartData = computed(() => ({
  labels: props.labels,
  datasets: [
    {
      label: props.receivedLabel,
      data: props.received,
      borderColor: cssColor('--violet-9'),
      backgroundColor: cssColor('--violet-9', 0.15),
      fill: true,
      cubicInterpolationMode: 'monotone',
      borderWidth: 2.5,
      pointRadius: 0,
      pointHoverRadius: 4,
    },
    {
      label: props.resolvedLabel,
      data: props.resolved,
      borderColor: cssColor('--teal-9'),
      backgroundColor: 'transparent',
      fill: false,
      cubicInterpolationMode: 'monotone',
      borderWidth: 2,
      pointRadius: 0,
      pointHoverRadius: 4,
    },
  ],
}));

const chartOptions = computed(() => ({
  responsive: true,
  maintainAspectRatio: false,
  animation: { duration: 0 },
  interaction: { mode: 'index', intersect: false },
  plugins: { legend: { display: false } },
  scales: {
    x: {
      grid: { display: false },
      border: { display: false },
      ticks: { color: cssColor('--slate-10'), maxRotation: 0, autoSkip: true },
    },
    y: {
      beginAtZero: true,
      border: { display: false },
      grid: { color: cssColor('--slate-6', 0.6) },
      ticks: { color: cssColor('--slate-10'), precision: 0, maxTicksLimit: 5 },
    },
  },
}));
</script>

<template>
  <div class="relative h-56">
    <Line :data="chartData" :options="chartOptions" />
  </div>
</template>
