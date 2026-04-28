import { createRouter, createWebHistory } from 'vue-router'
import Home from '../views/Home.vue'
import PMET from '../views/PMET.vue'

const routes = [
  { path: '/', name: 'Home', component: Home },
  { path: '/pmet', name: 'PMET', component: PMET }
]

export default createRouter({
  history: createWebHistory(),
  routes
})