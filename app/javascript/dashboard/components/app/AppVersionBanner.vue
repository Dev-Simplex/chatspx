<script setup>
import { onMounted, onUnmounted } from 'vue';

let loadedVersion = null;
let pollInterval = null;
let reloadTimer = null;

async function fetchVersion() {
  try {
    const res = await fetch(`/version.json?t=${Date.now()}`, {
      cache: 'no-store',
    });
    if (!res.ok) return null;
    const data = await res.json();
    return data.version || null;
  } catch {
    return null;
  }
}

onMounted(async () => {
  loadedVersion = await fetchVersion();

  pollInterval = setInterval(async () => {
    const current = await fetchVersion();
    if (current && loadedVersion && current !== loadedVersion) {
      clearInterval(pollInterval);
      reloadTimer = setTimeout(() => window.location.reload(), 5 * 60 * 1000);
    }
  }, 2 * 60 * 1000);
});

onUnmounted(() => {
  clearInterval(pollInterval);
  clearTimeout(reloadTimer);
});
</script>

<template>
  <div />
</template>
