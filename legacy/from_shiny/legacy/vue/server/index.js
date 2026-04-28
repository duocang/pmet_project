const express = require('express')
const fs = require('fs')
const path = require('path')
const cors = require('cors')
const bodyParser = require('body-parser')
const nodemailer = require('nodemailer')
const { exec } = require('child_process')

const app = express()
const PORT = 3001

app.use(cors())
app.use(bodyParser.json())

// 获取data/indexing下的文件名
app.get('/api/files', (req, res) => {
  const dirPath = path.join(__dirname, '../../data/indexing')
  fs.readdir(dirPath, (err, files) => {
    if (err) return res.status(500).send('Error reading directory')
    res.json(files)
  })
})

// 接收任务请求并异步执行
app.post('/api/run', (req, res) => {
  const { mode, file, maxDistance, filterLowExpr, email } = req.body

  const id = Date.now()
  const outputPath = path.join(__dirname, `output_${id}.txt`)

  const command = `bash ../../PMETdev/pmet/run_pmet.sh ${mode} ${file} ${maxDistance} ${filterLowExpr} > ${outputPath}`

  // 异步执行
  exec(command, (error, stdout, stderr) => {
    if (error) {
      console.error(`运行错误: ${error.message}`)
      return
    }

    sendEmail(email, outputPath)
  })

  res.send({ status: 'running' })
})

// 发送邮件
function sendEmail(to, outputPath) {
  const transporter = nodemailer.createTransport({
    service: 'gmail',
    auth: {
      user: 'your_email@gmail.com',
      pass: 'your_password_or_app_password'
    }
  })

  const mailOptions = {
    from: 'PMET App <your_email@gmail.com>',
    to,
    subject: 'PMET 运算完成通知',
    text: '您提交的 PMET 运算已完成，结果如下：',
    attachments: [
      {
        filename: path.basename(outputPath),
        path: outputPath
      }
    ]
  }

  transporter.sendMail(mailOptions, (err, info) => {
    if (err) {
      console.error('发送邮件失败:', err)
    } else {
      console.log('邮件发送成功:', info.response)
    }
  })
}

app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`)
})
