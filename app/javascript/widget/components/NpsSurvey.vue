<template>
  <div class="nps-survey p-4 bg-white rounded-lg shadow-sm">
    <p class="mb-4 text-sm">{{ messageContent }}</p>
    
    <div v-if="!submitted" class="nps-input">
      <div class="flex gap-2 mb-4">
        <button
          v-for="score in scores"
          :key="score"
          class="flex-1 py-2 px-3 border rounded hover:bg-slate-50"
          :class="selectedScore === score ? 'bg-blue-100 border-blue-500' : 'border-slate-300'"
          @click="selectScore(score)"
        >
          {{ score }}
        </button>
      </div>
      
      <button
        class="w-full py-2 px-4 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50"
        :disabled="!selectedScore"
        @click="submitScore"
      >
        Enviar
      </button>
    </div>
    
    <div v-else class="thank-you">
      <p class="text-sm text-green-600 mb-2">{{ thankYouMessage }}</p>
      <textarea
        v-if="showCommentField"
        v-model="comment"
        class="w-full p-2 border rounded mb-2"
        :placeholder="commentPlaceholder"
        rows="3"
      />
      <button
        v-if="showCommentField"
        class="w-full py-2 px-4 bg-blue-600 text-white rounded hover:bg-blue-700"
        @click="submitComment"
      >
        Enviar Comentário
      </button>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue';

const props = defineProps({
  message: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['submit']);

const scores = Array.from({ length: 11 }, (_, i) => i);
const selectedScore = ref(null);
const submitted = ref(false);
const comment = ref('');
const showCommentField = ref(false);

const messageContent = computed(() => {
  return props.message.content || 'On a scale of 0 to 10, how likely are you to recommend us?';
});

const thankYouMessage = computed(() => {
  return 'Thank you for your feedback!';
});

const commentPlaceholder = computed(() => {
  return 'Would you like to leave a comment? (optional)';
});

const selectScore = (score) => {
  selectedScore.value = score;
};

const submitScore = async () => {
  if (selectedScore.value === null) return;
  
  // Submit score
  emit('submit', {
    score: selectedScore.value,
    comment: null,
  });
  
  submitted.value = true;
  showCommentField.value = true;
};

const submitComment = () => {
  if (selectedScore.value === null) return;
  
  emit('submit', {
    score: selectedScore.value,
    comment: comment.value,
  });
  
  showCommentField.value = false;
};
</script>
