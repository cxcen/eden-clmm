# $x^N \cdot y = k$ 曲线AMM数学推导

## 前言

本文完整推导基于 $x^N \cdot y = k$ 不变量的自动做市商 (AMM) 数学模型。与传统的 $x \cdot y = k$ 恒定乘积模型相比，该模型通过引入可调参数 $N$ 提供了更灵活的价格曲线特性。

---

## 第一部分：基础理论

### 1.1 不变量定义

设流动性池包含两种代币：
- 代币 X：数量为 $x$
- 代币 Y：数量为 $y$

定义不变量函数：
$$
\boxed{x^N \cdot y = k}
$$

其中：
- $N \in \mathbb{N}^+$：曲线参数（$N=1$ 时退化为经典 Uniswap 模型）
- $k > 0$：流动性常数

### 1.2 瞬时价格推导

价格定义为边际汇率，即 Y 代币相对于 X 代币的价格：
$$
P = -\frac{dy}{dx}
$$

对不变量进行全微分：
$$
d(x^N \cdot y) = 0
$$
$$
N \cdot x^{N-1} \cdot y \cdot dx + x^N \cdot dy = 0
$$

解得：
$$
\frac{dy}{dx} = -\frac{N \cdot x^{N-1} \cdot y}{x^N} = -\frac{N \cdot y}{x}
$$

因此瞬时价格为：
$$
\boxed{P = \frac{N \cdot y}{x}}
$$

结合不变量 $y = \frac{k}{x^N}$，可得价格的另一表达式：
$$
\boxed{P = \frac{N \cdot k}{x^{N+1}}}
$$

### 1.3 储备量与价格的关系

从价格公式反解储备量：
$$
x = \left(\frac{N \cdot k}{P}\right)^{\frac{1}{N+1}}
$$
$$
y = \frac{k}{x^N} = k \cdot \left(\frac{P}{N \cdot k}\right)^{\frac{N}{N+1}}
$$

简化得：
$$
\boxed{x(P) = (N \cdot k)^{\frac{1}{N+1}} \cdot P^{-\frac{1}{N+1}}}
$$
$$
\boxed{y(P) = (N \cdot k)^{-\frac{N}{N+1}} \cdot P^{\frac{N}{N+1}}}
$$

---

## 第二部分：集中流动性理论

### 2.1 价格区间与虚拟储备

考虑价格区间 $[P_{\min}, P_{\max}]$，其中 $P_{\min} < P_{\max}$。

在该区间内，我们定义**虚拟储备**的概念：
- 虚拟 X 储备：$x_v = x(P_{\min}) - x(P_{\max})$
- 虚拟 Y 储备：$y_v = y(P_{\max}) - y(P_{\min})$

### 2.2 流动性度量

定义流动性 $L$ 为使得价格区间内虚拟储备满足不变量的常数：
$$
L = x_v \cdot P_{\min}^{\frac{1}{N+1}} = y_v \cdot P_{\max}^{-\frac{N}{N+1}} \cdot N
$$

通过代入虚拟储备表达式：
$$
\boxed{L = (N \cdot k)^{\frac{1}{N+1}} \cdot \left(P_{\min}^{-\frac{1}{N+1}} - P_{\max}^{-\frac{1}{N+1}}\right)}
$$

$$
\boxed{k = \frac{L^{N+1}}{N}} \quad \text{和} \quad \boxed{L = (N \cdot k)^{\frac{1}{N+1}}}
$$



### 2.3 储备量计算公式

给定流动性 $L$ 和价格区间 $[P_{\min}, P_{\max}]$，所需储备量为：

**X 代币储备量：**
$$
\boxed{\Delta x = L \cdot \left(P_{\min}^{-\frac{1}{N+1}} - P_{\max}^{-\frac{1}{N+1}}\right)}
$$

**Y 代币储备量：**
$$
\boxed{\Delta y = \frac{L}{N} \cdot \left(P_{\max}^{\frac{N}{N+1}} - P_{\min}^{\frac{N}{N+1}}\right)}
$$

### 2.4 反向计算流动性

给定储备量，可反向计算流动性：

**由 X 储备计算：**
$$
\boxed{L = \frac{\Delta x}{P_{\min}^{-\frac{1}{N+1}} - P_{\max}^{-\frac{1}{N+1}}}}
$$

**由 Y 储备计算：**
$$
\boxed{L = \frac{N \cdot \Delta y}{P_{\max}^{\frac{N}{N+1}} - P_{\min}^{\frac{N}{N+1}}}}
$$

---

## 第三部分：交换机制

### 3.1 交换基本原理

交换过程本质上是沿着不变量曲线的移动。设当前价格为 $P_1$，交换后价格变为 $P_2$。

### 3.2 精确输入交换（Exact Input Swap）

#### X → Y 交换（卖出 X，获得 Y）

**输入：** $\Delta x_{in}$ 数量的 X 代币

**步骤1：计算新价格**
$$
P_2 = P_1 \cdot \left(1 + \frac{\Delta x_{in}}{L} \cdot P_1^{\frac{1}{N+1}}\right)^{-(N+1)}
$$

$$
P_2^{\frac{1}{N+1}}  = P_1^{\frac{1}{N+1}} \cdot \left(1 + \frac{\Delta x_{in}}{L} \cdot P_1^{\frac{1}{N+1}}\right)^{-1}
$$



**步骤2：计算输出**
$$
\boxed{\Delta y_{out} = \frac{L}{N} \cdot \left(P_1^{\frac{N}{N+1}} - P_2^{\frac{N}{N+1}}\right)}
$$

#### Y → X 交换（卖出 Y，获得 X）

**输入：** $\Delta y_{in}$ 数量的 Y 代币

**步骤1：计算新价格**
$$
P_2 = \left(P_1^{\frac{N}{N+1}} + \frac{N \cdot \Delta y_{in}}{L}\right)^{\frac{N+1}{N}}
$$

**步骤2：计算输出**
$$
\boxed{\Delta x_{out} = L \cdot \left(P_2^{-\frac{1}{N+1}} - P_1^{-\frac{1}{N+1}}\right)}
$$

### 3.3 精确输出交换（Exact Output Swap）

#### 期望获得 $\Delta y_{out}$ 的 Y 代币

**步骤1：计算目标价格**
$$
P_2^{\frac{N}{N+1}} = P_1^{\frac{N}{N+1}} - \frac{N \cdot \Delta y_{out}}{L}
$$

**步骤2：计算所需输入**
$$
\boxed{\Delta x_{in} = L \cdot \left(P_1^{-\frac{1}{N+1}} - P_2^{-\frac{1}{N+1}}\right)}
$$

#### 期望获得 $\Delta x_{out}$ 的 X 代币

**步骤1：计算目标价格**
$$
P_2^{-\frac{1}{N+1}} = P_1^{-\frac{1}{N+1}} + \frac{\Delta x_{out}}{L}
$$

**步骤2：计算所需输入**
$$
\boxed{\Delta y_{in} = \frac{L}{N} \cdot \left(P_2^{\frac{N}{N+1}} - P_1^{\frac{N}{N+1}}\right)}
$$

---

## 第四部分：费用机制

### 4.1 费用模型

设交换费率为 $\gamma \in (0, 1)$，费用从输入代币中扣除。

### 4.2 含费用的交换计算

#### X → Y 交换（含费用）

**实际用于交换的 X 数量：**
$$
\Delta x_{effective} = \Delta x_{in} \cdot (1 - \gamma)
$$

**费用收取：**
$$
\Delta x_{fee} = \Delta x_{in} \cdot \gamma
$$

**输出计算：**
使用 $\Delta x_{effective}$ 代入第三部分的精确输入公式

#### Y → X 交换（含费用）

**实际用于交换的 Y 数量：**
$$
\Delta y_{effective} = \Delta y_{in} \cdot (1 - \gamma)
$$

**费用收取：**
$$
\Delta y_{fee} = \Delta y_{in} \cdot \gamma
$$

**输出计算：**
使用 $\Delta y_{effective}$ 代入第三部分的精确输入公式

### 4.3 费用分配

收取的费用通常按以下方式分配：
- 流动性提供者费用：$\alpha \cdot \Delta token_{fee}$
- 协议费用：$(1-\alpha) \cdot \Delta token_{fee}$

其中 $\alpha \in [0, 1]$ 为费用分配参数。
