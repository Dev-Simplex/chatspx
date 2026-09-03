<script>
import ChatArticle from 'widget/components/template/Article.vue';

export default {
  name: 'ArticleContent',
  components: { ChatArticle },
  inheritAttrs: false,
  props: {
    messageContentAttributes: { type: Object, default: () => ({}) },
  },
};
</script>

<template>
  <div>
    <ChatArticle :items="messageContentAttributes.items" />
  </div>
</template>
