# Portfolio Management on NVDA, CMCSA and EA stocks
# Author: Paul Muriithi
# Date: 2022-06-18

# ----------------------
# Setup
# ----------------------

rm(list = ls(all = TRUE))

# Load required libraries
library(tidyquant)
library(tidyverse)
library(broom)
library(knitr)
library(kableExtra)
library(ggplot2)
library(plotly)
library(gridExtra)
library(e1071)

# ----------------------
# 1. Importing Stocks Data
# ----------------------

stocks <- tq_get(c("NVDA", "CMCSA", "EA"),
                 get = "stock.prices",
                 from = "2000-01-01",
                 to = "2022-06-18") %>%
  select(symbol, date, adjusted)

head(stocks)

# ----------------------
# 2.1 Plot prices over time
# ----------------------

NVDA <- filter(stocks, symbol == "NVDA")
CMCSA <- filter(stocks, symbol == "CMCSA")
EA <- filter(stocks, symbol == "EA")

plot1 <- ggplot(NVDA, aes(x = date, y = adjusted)) +
  geom_line(color = "darkblue") +
  labs(title = "NVDA prices")

plot2 <- ggplot(CMCSA, aes(x = date, y = adjusted)) +
  geom_line(color = "orange") +
  labs(title = "CMCSA prices")

plot3 <- ggplot(EA, aes(x = date, y = adjusted)) +
  geom_line(color = "tomato") +
  labs(title = "EA prices")

grid.arrange(plot1, plot2, plot3, ncol = 3)

# ----------------------
# 2.2 Percentage Returns
# ----------------------

stocks <- stocks %>%
  group_by(symbol) %>%
  mutate(per_returns = 100 * (log(adjusted) - log(lag(adjusted)))) %>%
  ungroup() %>%
  drop_na()

NVDA_RT <- filter(stocks, symbol == "NVDA")
CMCSA_RT <- filter(stocks, symbol == "CMCSA")
EA_RT <- filter(stocks, symbol == "EA")

plt1 <- ggplot(NVDA_RT, aes(x = date, y = per_returns)) +
  geom_line(color = "darkblue") +
  labs(title = "NVDA Daily Percentage Returns")

plt2 <- ggplot(CMCSA_RT, aes(x = date, y = per_returns)) +
  geom_line(color = "orange") +
  labs(title = "CMCSA Daily Percentage Returns")

plt3 <- ggplot(EA_RT, aes(x = date, y = per_returns)) +
  geom_line(color = "tomato") +
  labs(title = "EA Daily Percentage Returns")

grid.arrange(plt1, plt2, plt3, ncol = 2)

# ----------------------
# 2.3 Histogram of Returns
# ----------------------

hist1 <- ggplot(NVDA_RT, aes(x = per_returns)) +
  geom_histogram(bins = 151, fill = "darkblue") +
  labs(title = "NVDA returns Histogram")

hist2 <- ggplot(CMCSA_RT, aes(x = per_returns)) +
  geom_histogram(bins = 96, fill = "orange") +
  labs(title = "CMCSA returns Histogram")

hist3 <- ggplot(EA_RT, aes(x = per_returns)) +
  geom_histogram(bins = 91, fill = "tomato") +
  labs(title = "EA returns Histogram")

grid.arrange(hist1, hist2, hist3, ncol = 2)

# ----------------------
# 2.4 Summary Statistics
# ----------------------

summary_stats <- function(data, type_col) {
  data %>%
    group_by(symbol) %>%
    summarise(
      type = type_col,
      mean = mean(!!sym(type_col)),
      median = median(!!sym(type_col)),
      variance = var(!!sym(type_col)),
      sd = sd(!!sym(type_col)),
      skewness = skewness(!!sym(type_col)),
      kurtosis = kurtosis(!!sym(type_col)),
      .groups = "drop"
    )
}

tab1 <- summary_stats(stocks, "adjusted")
tab2 <- summary_stats(stocks, "per_returns")
summary <- bind_rows(tab1, tab2)
print(summary)

# ----------------------
# 2.5 T-tests for Significance
# ----------------------

nvda_test <- t.test(NVDA_RT$per_returns, mu = 0, conf.level = 0.99)
cmcsa_test <- t.test(CMCSA_RT$per_returns, mu = 0, conf.level = 0.99)
ea_test <- t.test(EA_RT$per_returns, mu = 0, conf.level = 0.99)

tests <- data.frame(
  Type = c("NVDA", "CMCSA", "EA"),
  T_stat = c(nvda_test$statistic, cmcsa_test$statistic, ea_test$statistic),
  T_crit = rep(qt(0.01, df = nrow(NVDA_RT) - 1, lower.tail = FALSE), 3),
  P_value = c(nvda_test$p.value, cmcsa_test$p.value, ea_test$p.value)
)
print(tests)

# ----------------------
# 2.6 Tests for Equality of Means and Variances
# ----------------------

# Pairwise t-tests
t_nvda_cmcsa <- t.test(NVDA_RT$per_returns, CMCSA_RT$per_returns, var.equal = FALSE)
t_nvda_ea <- t.test(NVDA_RT$per_returns, EA_RT$per_returns, var.equal = FALSE)
t_cmcsa_ea <- t.test(CMCSA_RT$per_returns, EA_RT$per_returns, var.equal = TRUE)

pairwise_tests <- list(
  NVDA_CMCSA = t_nvda_cmcsa,
  NVDA_EA = t_nvda_ea,
  CMCSA_EA = t_cmcsa_ea
)

lapply(pairwise_tests, summary)

# ----------------------
# 2.7 Correlation Analysis
# ----------------------

corr_df <- data.frame(
  NVDA = NVDA_RT$per_returns,
  CMCSA = CMCSA_RT$per_returns,
  EA = EA_RT$per_returns
)

cor_matrix <- cor(corr_df)
print(cor_matrix)

# ----------------------
# 2.8 Correlation Tests
# ----------------------

cor1 <- cor.test(NVDA_RT$per_returns, CMCSA_RT$per_returns)
cor2 <- cor.test(NVDA_RT$per_returns, EA_RT$per_returns)
cor3 <- cor.test(CMCSA_RT$per_returns, EA_RT$per_returns)

cor_results <- data.frame(
  Pair = c("NVDA_CMCSA", "NVDA_EA", "CMCSA_EA"),
  Statistic = c(cor1$statistic, cor2$statistic, cor3$statistic),
  P_value = c(cor1$p.value, cor2$p.value, cor3$p.value)
)
print(cor_results)

# ----------------------
# 2.9 Portfolio Optimization
# ----------------------

optimize_portfolio <- function(mean1, mean2, var1, var2, covar) {
  h <- function(w1) {
    w2 <- 1 - w1
    expected_return <- w1 * mean1 + w2 * mean2
    variance <- w1^2 * var1 + w2^2 * var2 + 2 * w1 * w2 * covar
    happiness <- expected_return - variance
    return(-happiness)
  }
  
  result <- optim(par = 0.5, fn = h, method = "Brent", lower = 0, upper = 1)
  w1 <- result$par
  w2 <- 1 - w1
  E_r <- w1 * mean1 + w2 * mean2
  Var_r <- w1^2 * var1 + w2^2 * var2 + 2 * w1 * w2 * covar
  h_r <- E_r - Var_r
  return(c(w1, w2, E_r, Var_r, h_r))
}

means <- c(mean(NVDA_RT$per_returns), mean(CMCSA_RT$per_returns), mean(EA_RT$per_returns))
vars <- c(var(NVDA_RT$per_returns), var(CMCSA_RT$per_returns), var(EA_RT$per_returns))
cov_mat <- cov(corr_df)

res1 <- optimize_portfolio(means[1], means[2], vars[1], vars[2], cov_mat[1,2])
res2 <- optimize_portfolio(means[1], means[3], vars[1], vars[3], cov_mat[1,3])
res3 <- optimize_portfolio(means[2], means[3], vars[2], vars[3], cov_mat[2,3])

optimal_portfolios <- data.frame(
  Pair = c("NVDA & CMCSA", "NVDA & EA", "CMCSA & EA"),
  Weight1 = round(c(res1[1], res2[1], res3[1]), 4),
  Weight2 = round(c(res1[2], res2[2], res3[2]), 4),
  `E(r)` = round(c(res1[3], res2[3], res3[3]), 4),
  `Var(r)` = round(c(res1[4], res2[4], res3[4]), 4),
  `h(r)` = round(c(res1[5], res2[5], res3[5]), 4)
)
print(optimal_portfolios)

# ----------------------
# 2.10 Event Impact Analysis
# ----------------------

extract <- function(stocks, smb) {
  stoc <- subset(stocks, symbol == smb)
  lehman <- filter(stoc, date == "2008-09-15")
  pandemic <- filter(stoc, date == "2020-03-11")
  BAU <- filter(stoc, !date %in% c("2008-09-15", "2020-03-11"))
  lehman$event <- "lehman"
  pandemic$event <- "pandemic"
  BAU$event <- "BAU"
  events <- bind_rows(lehman, pandemic, BAU)
  events$event <- factor(events$event)
  na.omit(events)
}

NVDA_EVENTS <- extract(stocks, "NVDA")
CMCSA_EVENTS <- extract(stocks, "CMCSA")
EA_EVENTS <- extract(stocks, "EA")

summary(lm(per_returns ~ event, data = NVDA_EVENTS))
summary(lm(per_returns ~ event, data = CMCSA_EVENTS))
summary(lm(per_returns ~ event, data = EA_EVENTS))
