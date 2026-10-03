const TOKEN_KEY = 'tars_cms_admin_token'
const USER_KEY = 'tars_cms_admin_user'

export function getToken(): string {
  return localStorage.getItem(TOKEN_KEY) || ''
}

export function setToken(token: string) {
  localStorage.setItem(TOKEN_KEY, token)
}

export function clearToken() {
  localStorage.removeItem(TOKEN_KEY)
  localStorage.removeItem(USER_KEY)
}

export function getUser(): Record<string, any> | null {
  const raw = localStorage.getItem(USER_KEY)
  if (!raw) return null
  try {
    return JSON.parse(raw)
  } catch {
    return null
  }
}

export function setUser(user: Record<string, any>) {
  localStorage.setItem(USER_KEY, JSON.stringify(user))
}
