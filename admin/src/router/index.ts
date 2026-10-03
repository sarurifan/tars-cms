import { createRouter, createWebHistory } from 'vue-router'
import { getToken } from '@/utils/auth'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/login',
      name: 'Login',
      component: () => import('@/views/login/Login.vue'),
      meta: { title: '登录', public: true }
    },
    {
      path: '/',
      component: () => import('@/layout/AdminLayout.vue'),
      redirect: '/dashboard',
      children: [
        {
          path: 'dashboard',
          name: 'Dashboard',
          component: () => import('@/views/dashboard/Dashboard.vue'),
          meta: { title: '仪表盘', icon: 'Odometer' }
        },
        {
          path: 'article',
          name: 'Article',
          component: () => import('@/layout/EmptyRoute.vue'),
          meta: { title: '文章管理', icon: 'Document' },
          children: [
            {
              path: 'list',
              name: 'ArticleList',
              component: () => import('@/views/article/ArticleList.vue'),
              meta: { title: '文章列表' }
            },
            {
              path: 'create',
              name: 'ArticleCreate',
              component: () => import('@/views/article/ArticleEdit.vue'),
              meta: { title: '写文章', hidden: true }
            },
            {
              path: 'edit/:id',
              name: 'ArticleEdit',
              component: () => import('@/views/article/ArticleEdit.vue'),
              meta: { title: '编辑文章', hidden: true }
            }
          ]
        },
        {
          path: 'category',
          name: 'Category',
          component: () => import('@/layout/EmptyRoute.vue'),
          meta: { title: '分类管理', icon: 'Folder' },
          children: [
            {
              path: 'list',
              name: 'CategoryList',
              component: () => import('@/views/category/CategoryList.vue'),
              meta: { title: '分类列表' }
            }
          ]
        },
        {
          path: 'member',
          name: 'Member',
          component: () => import('@/layout/EmptyRoute.vue'),
          meta: { title: '成员管理', icon: 'User' },
          children: [
            {
              path: 'list',
              name: 'MemberList',
              component: () => import('@/views/member/MemberList.vue'),
              meta: { title: '成员列表' }
            }
          ]
        },
        {
          path: 'media',
          name: 'Media',
          component: () => import('@/layout/EmptyRoute.vue'),
          meta: { title: '媒体管理', icon: 'Picture' },
          children: [
            {
              path: 'list',
              name: 'MediaList',
              component: () => import('@/views/media/MediaList.vue'),
              meta: { title: '媒体库' }
            }
          ]
        },
        {
          path: 'config',
          name: 'Config',
          component: () => import('@/layout/EmptyRoute.vue'),
          meta: { title: '系统设置', icon: 'Setting' },
          children: [
            {
              path: 'site',
              name: 'SiteConfig',
              component: () => import('@/views/config/SiteConfig.vue'),
              meta: { title: '站点配置' }
            }
          ]
        }
      ]
    }
  ]
})

// 路由守卫
router.beforeEach((to, _from, next) => {
  if (to.meta.title) {
    document.title = String(to.meta.title) + ' - tars-cms'
  }
  const token = getToken()
  const isPublic = to.meta.public === true
  if (!token && !isPublic) {
    next('/login')
  } else if (token && to.path === '/login') {
    next('/')
  } else {
    next()
  }
})

export default router
