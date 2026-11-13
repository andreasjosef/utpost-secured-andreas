<script setup lang="ts">
import { RouterLink, RouterView, useRouter } from 'vue-router'
import { useAuthStore } from './stores/auth'

const auth = useAuthStore()
const router = useRouter()
const logout = () => {
  auth.logout()
  router.push('/')
}
</script>

<template>
  <header>
    <RouterLink to="/">Utpost</RouterLink>
    <nav>
      <RouterLink to="/guider">Guider</RouterLink>
      <RouterLink to="/turer">Turer</RouterLink>
      <span v-if="auth.user" class="who">
        {{ auth.user.display_name }}
        <button type="button" @click="logout">Logga ut</button>
      </span>
      <RouterLink v-else to="/logga-in">Logga in</RouterLink>
    </nav>
  </header>
  <main>
    <RouterView />
  </main>
</template>

<style scoped>
.who {
  margin-left: 12px;
  font-size: 14px;
}
.who button {
  margin-left: 6px;
}
</style>
