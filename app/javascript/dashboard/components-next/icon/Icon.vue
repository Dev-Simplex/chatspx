<script setup>
import { h, isVNode, useAttrs, computed } from 'vue';

const props = defineProps({
  icon: { type: [String, Object, Function], required: true },
});

const attrs = useAttrs();

const combinedClass = computed(() => {
  if (typeof props.icon === 'string') {
    const iconClass = props.icon;
    const additionalClasses = attrs.class;
    if (typeof additionalClasses === 'string') {
      return `${iconClass} ${additionalClasses}`.trim();
    } else if (Array.isArray(additionalClasses)) {
      return [iconClass, ...additionalClasses];
    } else if (typeof additionalClasses === 'object' && additionalClasses !== null) {
      return { [iconClass]: true, ...additionalClasses };
    }
    return iconClass;
  }
  return attrs.class;
});

const renderIcon = () => {
  if (!props.icon) return null;
  if (typeof props.icon === 'function' || isVNode(props.icon)) {
    return props.icon;
  }
  // Remover 'class' dos attrs para evitar duplicação
  const { class: _, ...restAttrs } = attrs;
  // Garantir que o span tenha display inline-block para ícones aparecerem
  const finalClass = typeof combinedClass.value === 'string' 
    ? combinedClass.value.includes('inline-block') 
      ? combinedClass.value 
      : `${combinedClass.value} inline-block`.trim()
    : combinedClass.value;
  return h('span', { class: finalClass, ...restAttrs });
};
</script>

<template>
  <component :is="renderIcon" />
</template>
