<script setup>
import { ref, watch, nextTick, onBeforeUnmount } from 'vue';
import { useToggle } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import { onClickOutside } from '@vueuse/core';
import { provideDropdownContext } from './provider.js';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';

const props = defineProps({
  /** Quando 'top', o menu abre para cima (acima do trigger), com Teleport para não ser cortado. Default: 'bottom' */
  placement: {
    type: String,
    default: 'bottom',
    validator: v => ['top', 'bottom'].includes(v),
  },
});

const emit = defineEmits(['close']);
const [isOpen, toggle] = useToggle(false);
const triggerRef = ref(null);
const menuRef = ref(null);
const teleportStyle = ref({});
let stopClickOutside = null;

const closeMenu = () => {
  if (isOpen.value) {
    emit('close');
    toggle(false);
  }
};

const useTeleport = () => props.placement === 'top';

function getTriggerEl() {
  const v = triggerRef.value;
  if (!v) return null;
  return v?.$el ?? v;
}

function updateTeleportPosition() {
  if (!useTeleport()) return;
  const triggerEl = getTriggerEl();
  if (!triggerEl?.getBoundingClientRect) return;
  const rect = triggerEl.getBoundingClientRect();
  const menuEl = menuRef.value?.$el ?? menuRef.value;
  const menuHeight = menuEl?.offsetHeight ?? 320;
  const gap = 6;
  const padding = 8;
  const top = Math.max(padding, rect.top - menuHeight - gap);
  const minW = Math.max(rect.width, 192);
  const isRTL = document.documentElement.getAttribute('dir') === 'rtl';
  teleportStyle.value = {
    position: 'fixed',
    top: `${top}px`,
    left: isRTL ? 'auto' : `${rect.left}px`,
    right: isRTL ? `${window.innerWidth - rect.right}px` : 'auto',
    bottom: 'auto',
    zIndex: 9999,
    minWidth: `${minW}px`,
    maxHeight: 'min(70vh, 400px)',
    overflowY: 'auto',
  };
}

watch(isOpen, open => {
  if (open && useTeleport()) {
    nextTick(() => {
      updateTeleportPosition();
      nextTick(updateTeleportPosition);
      // Só registra click-outside depois do menu estar no DOM, evitando que o próprio clique do trigger feche o menu
      stopClickOutside = onClickOutside(
        menuRef,
        () => closeMenu(),
        { ignore: [triggerRef] }
      );
    });
  } else {
    if (stopClickOutside) {
      stopClickOutside();
      stopClickOutside = null;
    }
  }
});

onBeforeUnmount(() => {
  if (stopClickOutside) stopClickOutside();
});

provideDropdownContext({
  isOpen,
  toggle,
  closeMenu,
});

function onTriggerClick(e) {
  toggle();
  e.stopPropagation();
}
</script>

<template>
  <div class="relative space-y-2">
    <div
      ref="triggerRef"
      class="inline-block max-w-full min-w-0"
      @click.capture="onTriggerClick"
    >
      <slot name="trigger" :is-open="isOpen" :toggle="() => toggle()" />
    </div>

    <!-- Inline (placement bottom): menu no fluxo -->
    <div
      v-if="isOpen && !useTeleport()"
      v-on-click-outside="closeMenu"
      class="absolute z-10"
    >
      <slot />
    </div>

    <!-- Teleport (placement top): menu no body, posicionado acima do trigger -->
    <TeleportWithDirection v-else-if="isOpen && useTeleport()" to="body">
      <div
        ref="menuRef"
        class="dropdown-menu-teleport bg-n-alpha-3 backdrop-blur-[100px] border border-n-weak shadow-xl rounded-xl overflow-y-auto overflow-x-hidden"
        :style="teleportStyle"
      >
        <!-- DropdownBody usa position:absolute; dentro do teleport o pai colapsa (altura 0). 
             Forçar o filho direto a position:relative para o conteúdo ocupar espaço e ficar visível. -->
        <div class="dropdown-menu-teleport-inner">
          <slot />
        </div>
      </div>
    </TeleportWithDirection>
  </div>
</template>

<style scoped>
.dropdown-menu-teleport-inner {
  position: relative;
  display: block;
  min-height: 0;
}
.dropdown-menu-teleport-inner :deep(> div) {
  position: relative !important;
}
</style>
