<template>
  <div class="pmet-page" style="display: flex;">
    <!-- 左侧参数栏 -->
    <div class="sidebar" style="width: 300px; padding: 20px;">
      <h2>参数设置</h2>

      <!-- 单选按钮 -->
      <div>
        <label><input type="radio" value="precomputed" v-model="mode"/> Promoters (precomputed)</label><br/>
        <label><input type="radio" value="promoters" v-model="mode"/> Promoters</label><br/>
        <label><input type="radio" value="intervals" v-model="mode"/> Genomic intervals</label>
      </div>

      <!-- 下拉选择框 -->
      <div style="margin-top: 15px;">
        <label>选择文件：</label>
        <select v-model="selectedFile">
          <option v-for="file in files" :key="file" :value="file">{{ file }}</option>
        </select>
      </div>

      <!-- 模拟参数 -->
      <div style="margin-top: 15px;">
        <label>最大距离：</label>
        <input type="number" v-model="maxDistance" :disabled="mode === 'precomputed'" />
      </div>

      <div style="margin-top: 15px;">
        <label>是否过滤低表达：</label>
        <select v-model="filterLowExpr" :disabled="mode === 'precomputed'">
          <option value="yes">是</option>
          <option value="no">否</option>
        </select>
      </div>

      <!-- 邮箱 -->
      <div style="margin-top: 15px;">
        <label>邮箱：</label>
        <input type="email" v-model="email" :class="{ valid: emailValid, invalid: !emailValid }" @input="validateEmail"/>
      </div>

      <!-- 运行按钮 -->
      <div style="margin-top: 20px;">
        <button @click="runPMET">RUN</button>
      </div>
    </div>

    <!-- 右侧展示栏 -->
    <div class="main-content" style="flex: 1; padding: 20px;">
      <h2>PMET 页面</h2>
      <p>运行结果将在邮件中通知。</p>
    </div>

    <!-- Modal -->
    <div v-if="modalVisible" class="modal">
      <div class="modal-content">
        <p>任务已提交，运行时间较长，请关闭网页等待结果邮件。</p>
        <button @click="modalVisible = false">关闭</button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import axios from 'axios'

const mode = ref('precomputed')
const files = ref([])
const selectedFile = ref('')
const maxDistance = ref(1000)
const filterLowExpr = ref('yes')
const email = ref('')
const emailValid = ref(false)
const modalVisible = ref(false)

const validateEmail = () => {
  const regex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
  emailValid.value = regex.test(email.value)
}

const fetchFiles = async () => {
  const res = await axios.get('/api/files')
  files.value = res.data
  selectedFile.value = files.value[0]
}

const runPMET = async () => {
  if (!emailValid.value) {
    alert("请输入正确的邮箱地址")
    return
  }

  await axios.post('/api/run', {
    mode: mode.value,
    file: selectedFile.value,
    maxDistance: maxDistance.value,
    filterLowExpr: filterLowExpr.value,
    email: email.value
  })

  modalVisible.value = true
}

onMounted(fetchFiles)
</script>

<style scoped>
.valid {
  border: 2px solid green;
}
.invalid {
  border: 2px solid red;
}
.modal {
  position: fixed;
  top: 0; left: 0;
  width: 100%; height: 100%;
  background: rgba(0,0,0,0.5);
}
.modal-content {
  background: white;
  padding: 20px;
  margin: 100px auto;
  width: 300px;
  text-align: center;
}
</style>
