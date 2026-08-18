<script>
import ChatCard from 'shared/components/ChatCard.vue';

export default {
  name: 'CardsContent',
  components: { ChatCard },
  inheritAttrs: false,
  props: {
    messageContentAttributes: { type: Object, default: () => ({}) },
  },
};
</script>

<template>
  <div>
    <ChatCard
      v-for="item in messageContentAttributes.items"
      :key="item.title"
      :media-url="item.media_url"
      :title="item.title"
      :description="item.description"
      :actions="item.actions"
    />
  </div>
</template>
