<template>
  <!-- 空状态（h5 专属） -->
  <div class="h5-empty">
    <div class="empty-icon">{{ icon }}</div>
    <p class="empty-text">{{ text }}</p>
    <slot />
  </div>
</template>

<script setup lang="ts">
withDefaults(
  defineProps<{
    text?: string
    icon?: string
  }>(),
  { text: '暂无数据', icon: '📭' }
)
</script>

<style scoped>
.h5-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 56px 0;
  gap: 12px;
}

.empty-icon {
  font-size: 48px;
  opacity: 0.7;
}

.empty-text {
  font-size: 14.5px;
  color: var(--h5-text-tertiary);
}
</style>
