import { createApp } from 'vue'
import App from './App.vue'
import router from './router'  // 引入我们刚刚创建的 router

const app = createApp(App)

app.use(router)  // 使用 router
app.mount('#app')