# 读取数据
data <- read.table("length_to_tss.txt", header = FALSE, col.names = c("Gene", "Value"))

# 计算所有数字的平均值
all_mean <- mean(data$Value)

# 剔除负数和大于 10000 的值
filtered_data <- subset(data, Value >= 0 & Value <= 10000)

# 计算过滤后的平均值
filtered_mean <- mean(filtered_data$Value)

# 计算大于 10000 的数的数量
count_over_10000 <- sum(data$Value > 10000)
# 输出结果
cat("所有数字的平均值:", all_mean, "\n")
cat("剔除负数和大于 10000 的值之后的平均值:", filtered_mean, "\n")
cat("大于 10000 的数的数量:", count_over_10000, "\n")
