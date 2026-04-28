#!/usr/bin/env Rscript

# Histogram of intergenic gap to the upstream neighbour per gene — a
# diagnostic over the annotation, not over any particular PMET result.

library(ggplot2)

args <- commandArgs(trailingOnly = TRUE)
input_file  <- args[1]
output_file <- ifelse(length(args) > 1,
                      args[2],
                      paste0(dirname(input_file), "/histogram_intergenic_gap.png"))

data <- read.table(input_file, header = FALSE, col.names = c("Gene", "Gap"))
# Keep a readable range for the histogram (0 < gap <= 10kb).
data <- data[data$Gap > 0 & data$Gap <= 10000, ]

p <- ggplot(data, aes(x = Gap)) +
  geom_histogram(binwidth = 100, fill = "#1ba784", color = "#1ba784") +
  labs(title = "Intergenic gap to upstream neighbour",
       x = "Gap (bp)", y = "Number of genes") +
  theme_minimal()

ggsave(output_file, plot = p, width = 8, height = 5)
cat(sprintf("          Histogram saved to: %s\n", basename(output_file)))
