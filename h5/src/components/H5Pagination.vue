<template>
  <!-- 分页（h5 专属，独立实现，不复用 admin 的 el-pagination） -->
  <div class="h5-pagination" v-if="total > 0">
    <button
      class="page-btn page-prev"
      :disabled="page <= 1"
      @click="goTo(page - 1)"
    >
      ‹ 上一页
    </button>

    <div class="page-numbers">
      <button
        v-for="p in pages"
        :key="p.key"
        class="page-num"
        :class="{ active: p.num === page, ellipsis: p.ellipsis }"
        :disabled="p.ellipsis"
        @click="!p.ellipsis && goTo(p.num)"
      >
        {{ p.ellipsis ? '…' : p.num }}
      </button>
    </div>

    <button
      class="page-btn page-next"
      :disabled="page >= totalPages"
      @click="goTo(page + 1)"
    >
      下一页 ›
    </button>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'

const props = defineProps<{
  page: number
  size: number
  total: number
}>()

const emit = defineEmits<{
  (e: 'change', page: number): void
}>()

const totalPages = computed(() => Math.max(1, Math.ceil(props.total / props.size)))

// 生成页码（含省略号）
const pages = computed(() => {
  const cur = props.page
  const tot = totalPages.value
  const result: { key: string; num: number; ellipsis: boolean }[] = []

  if (tot <= 7) {
    for (let i = 1; i <= tot; i++) {
      result.push({ key: String(i), num: i, ellipsis: false })
    }
    return result
  }

  result.push({ key: '1', num: 1, ellipsis: false })

  if (cur > 4) {
    result.push({ key: 'left-ellipsis', num: 0, ellipsis: true })
  }

  const start = Math.max(2, cur - 1)
  const end = Math.min(tot - 1, cur + 1)
  for (let i = start; i <= end; i++) {
    result.push({ key: String(i), num: i, ellipsis: false })
  }

  if (cur < tot - 3) {
    result.push({ key: 'right-ellipsis', num: 0, ellipsis: true })
  }

  result.push({ key: String(tot), num: tot, ellipsis: false })
  return result
})

function goTo(p: number) {
  if (p < 1 || p > totalPages.value) return
  emit('change', p)
}
</script>

<style scoped>
.h5-pagination {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  margin-top: 28px;
  flex-wrap: wrap;
}

.page-btn,
.page-num {
  min-width: 36px;
  height: 36px;
  padding: 0 13px;
  border: 1px solid var(--h5-border);
  background: #fff;
  border-radius: var(--h5-radius);
  font-size: 14px;
  color: var(--h5-text);
  cursor: pointer;
  transition: all 0.15s;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}

.page-btn:hover:not(:disabled),
.page-num:hover:not(.active):not(:disabled) {
  border-color: var(--h5-primary);
  color: var(--h5-primary);
}

.page-btn:disabled,
.page-num:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}

.page-num.active {
  background: var(--h5-primary);
  border-color: var(--h5-primary);
  color: #fff;
  font-weight: 600;
}

.page-num.ellipsis {
  border: none;
  background: transparent;
  cursor: default;
  min-width: 24px;
}

.page-num.ellipsis:hover {
  border: none;
  color: var(--h5-text);
}

.page-numbers {
  display: flex;
  gap: 6px;
}
</style>
