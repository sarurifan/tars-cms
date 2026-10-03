<template>
  <!-- 加载状态（h5 专属） -->
  <div class="h5-loading" v-if="loading">
    <div class="loading-spinner"></div>
    <span class="loading-text">{{ text }}</span>
  </div>
</template>

<script setup lang="ts">
withDefaults(
  defineProps<{
    loading: boolean
    text?: string
  }>(),
  { text: '加载中…' }
)
</script>

<style scoped>
.h5-loading {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 56px 0;
  gap: 14px;
}

.loading-spinner {
  width: 34px;
  height: 34px;
  border: 3px solid var(--h5-primary-light);
  border-top-color: var(--h5-primary);
  border-radius: 50%;
  animation: h5-spin 0.8s linear infinite;
}

@keyframes h5-spin {
  to {
    transform: rotate(360deg);
  }
}

.loading-text {
  font-size: 14px;
  color: var(--h5-text-tertiary);
}
</style>
