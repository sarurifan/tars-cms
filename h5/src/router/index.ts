import { createRouter, createWebHistory } from 'vue-router'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/',
      name: 'Home',
      component: () => import('@/views/HomePage.vue'),
      meta: { title: '首页' }
    },
    {
      path: '/category/:slug?',
      name: 'Category',
      component: () => import('@/views/CategoryPage.vue'),
      meta: { title: '分类' }
    },
    {
      path: '/article/:id',
      name: 'Article',
      component: () => import('@/views/ArticlePage.vue'),
      meta: { title: '文章详情' }
    },
    {
      path: '/login',
      name: 'Login',
      component: () => import('@/views/LoginPage.vue'),
      meta: { title: '登录' }
    },
    {
      path: '/register',
      name: 'Register',
      component: () => import('@/views/RegisterPage.vue'),
      meta: { title: '注册' }
    },
    {
      path: '/:pathMatch(.*)*',
      name: 'NotFound',
      component: () => import('@/views/NotFoundPage.vue'),
      meta: { title: '页面不存在' }
    }
  ],
  scrollBehavior() {
    return { top: 0 }
  }
})

router.beforeEach((to) => {
  if (to.meta.title) {
    document.title = String(to.meta.title) + ' - tars-cms'
  }
})

export default router
