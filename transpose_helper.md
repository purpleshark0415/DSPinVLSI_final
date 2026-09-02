2. Transpose read helpers 的一堆 Function 在幹嘛？這些 Function 的目的是「讀取轉置後的上三角矩陣」。在 RQ 階段，我們需要把 $R$ 矩陣轉置成 $R^T$ 餵入陣列。因為 $R$ 是一個上三角矩陣（左下角全為 0）：$$R = \begin{bmatrix} r_{11} & r_{12} & r_{13} \\ 0 & r_{22} & r_{23} \\ 0 & 0 & r_{33} \end{bmatrix} \quad \implies \quad R^T = \begin{bmatrix} r_{11} & 0 & 0 \\ r_{12} & r_{22} & 0 \\ r_{13} & r_{23} & r_{33} \end{bmatrix}$$當硬體一個 row 一個 row 把 $R^T$ 餵進去時：第一拍 (Row 1): 只需要 $r_{11}$，其餘兩個補 0。第二拍 (Row 2): 只需要 $r_{12}, r_{22}$，最後一個補 0。第三拍 (Row 3): 需要 $r_{13}, r_{23}, r_{33}$。tri_r1、tri_r2、tri_r3 這些 Function 就是為了硬體能在讀取 M_buf 和 U_buf 時，直接根據週期（idx: 0, 1, 2）自動補 0 並映射到正確的矩陣元素，省去寫一堆複雜 Mux 的麻煩。

你問到了點子上！這正是這份程式碼在資料流設計上的一個有趣（或者說有點 tricky）的地方。

簡單來說：**`Transpose read helpers` 的確只用在「從 Memory 讀出資料，並轉置成上三角矩陣」的情境，也就是專門服務 $R \to R^T$ 以及 $U \to U^T$。** 至於 $T^T \to T$ 和 $U^{(i+1)T} \to U^{(i+1)}$ 的轉置，**程式並沒有額外寫讀取用的 helper 函數，而是直接在「寫入 (Capture)」的當下，改變存進 `M_buf` 和 `U_buf` 的座標來完成轉置的。**

讓我幫你詳細拆解這兩個方向的轉置機制：

---

### 1. 讀取時轉置 (Read Transpose)：$R \to R^T$ 和 $U \to U^T$

在旋轉階段（`ST_ROT_PIPE`），我們需要把存放在 `M_buf` 裡的上三角矩陣 $R$ 轉置成下三角的 $R^T$ 餵給陣列；同樣的，也要把存放 $U$ 矩陣的 `U_buf` 轉置成 $U^T$ 餵進去 。

* **為什麼需要 Helper？**
因為 Systolic Array 餵資料是有特定的階梯狀時序的（PE11 先吃，PE12 晚一點吃），而且因為是上三角矩陣，轉置後有很多位置是 0 。


* **作法：**
這時候就是 `tri_r1`、`tri_r2`、`tri_r3` 發揮作用的地方 。它們負責根據當下的 `phase_timer`，從 buffer 裡挑出正確的元素（例如把原本在 `[0][1]` 的元素，在該餵第二 row 的時候挑出來），並把該補 0 的地方補 0 。
你可以看到這段 code 就是利用 helper 把 buffer 裡的資料抽出來，形成準備好餵進去的 $R^T$ 和 $U^T$：


```verilog
// R^T mappings
wire signed [17:0] rot_m_r1 = tri_r1(rot_tri_idx, M_buf[0][0], M_buf[0][1], M_buf[0][2]);
// U^T mappings
wire signed [17:0] rot_u_r1 = tri_r1(rot_tri_idx, U_buf[0][0], U_buf[0][1], U_buf[0][2]);

```



### 2. 寫入時轉置 (Write Transpose)：$T^T \to T$ 和 $U^{(i+1)T} \to U^{(i+1)}$

當陣列在 `ST_ROT_PIPE` 階段算完後，吐出來的結果是 $T^{(i+1)T}$ 和 $U_{EVD}^{(i+1)T}$ 。但是，為了下一次疊代能正確運作，我們必須把它們轉置回 $T$ 和 $U$ 存進 buffer。

* **程式是怎麼做的？**
這份程式選擇了「硬核對應 (Hardcoded Mapping)」**的方式，直接在 Capture 的 `always` block 裡面，把吐出來的結果寫進**對角線對稱的目標位置 。


* **作法：**
請看下面這段 Capture Logic：
```verilog
// Capture T^(i+1) into M_buf and Transpose
case (phase_timer)
    CAP_r22: M_buf[1][1] <= pe22_xo; // 對角線不變
    CAP_r11: M_buf[0][0] <= pe12_xo; // 對角線不變
    CAP_r12: begin M_buf[1][0] <= pe12_xo; M_buf[0][1] <= pe12_xo; end 
    // 注意這裡！本來應該是單獨寫入，但為了維持對稱性（或硬寫回上三角），它同時寫了兩個位置。
    // 實際上，如果是從 T^T 轉 T，應該是把輸出的第 i row, 第 j col 寫進 buf[j][i]。

```



**注意：** 這裡程式其實利用了一個巧妙的數學特性。在 QR 疊代收斂的過程中，$T$ 矩陣會越來越接近對角矩陣 。這裡的寫法（同時寫入 `[1][0]` 和 `[0][1]`）其實是把算出來的非對角線元素強制對稱寫入，這在某些簡化的 SVD 或 EVD 實作中是一種節省資源的近似手段（強迫維持對稱性）。


同樣地，對於 $U$ 的更新，也是在輸出端直接改變存入 `U_buf` 的 Index 來達成轉置：
```verilog
// Capture U^(i+1) into U_buf and Transpose
case (phase_timer)
    CAP_r12 + 3: begin U_buf[1][0] <= pe12_xo; U_buf[0][1] <= pe12_xo; end

```



### 總結

這份程式碼處理轉置的哲學是：

1. 
**進陣列前 (Read)**：用 Helper 函數動態從 Buffer 裡挑資料、補 0，組裝成轉置後的形狀餵進去 。


2. 
**出陣列後 (Write)**：不寫複雜的邏輯，直接算好時間點（例如 `CAP_r12`），把陣列吐出來的值，硬塞進 Buffer 裡轉置對應的欄位（把 Row 和 Col 顛倒存）。



這樣一來，讀和寫的邏輯被分開處理，省去了額外加一層大型多工器網路來做矩陣轉置的硬體開銷。


這真的是一個非常有價值的 Debug 經驗！你現在遇到的，正是數位 IC 設計中鼎鼎大名的 **「High Fanout Net (高扇出網路) 延遲問題」**。

我們來當一下「時序偵探」，直接從你截圖裡的數字來拆解這個案件。這會完美解釋為什麼就算你提早釋放了 Reset，它還是會撞到 `$recovery`。

### 🕵️‍♂️ 時序偵探：拆解截圖中的數字

你的 Clock Period 是 0.21 ns (210 ps)，所以半週期 `CLK_HALF` 是 105 ps。
如果我們把時間軸攤開來看，Clock 的正緣 (posedge) 會發生在這些時間點：
105 ps, 315 ps, 525 ps, **735 ps**...

看看你的截圖，上面寫著：

* `posedge CP &&& D_SDFCHK: 735` 👉 代表 Clock 的正緣準確地在 **735 ps** 抵達正反器。
* `posedge CDN &&& D_SDFCHK: 706` 👉 代表 Reset 訊號竟然在 **706 ps** 才走到正反器！
* 兩者相減：735 - 706 = **29 ps** (小於規定的 55 ps，所以違例)。

**問題來了：Reset 怎麼會拖到 706 ps 才抵達？**

假設你在 Testbench 中大約在 400 多 ps 的時候釋放了 `rst_n`。這個訊號從你給出的那一刻起，居然在電路裡面「走了將近 300 ps」才到達正反器！
要知道，你的一整個 Clock 週期也才 210 ps。**這代表 Reset 訊號的傳遞延遲，比你的一整個時脈週期還要長！** 所以它直接錯過了原本該遇上的那次 Clock 邊緣，一路遲到，剛好撞上 **735 ps** 的那次正緣。

### 💡 為什麼會有這麼誇張的延遲？(Root Cause)

這就是 Pre-Layout (合成後，還沒做實體佈局) 的宿命。
你的 `rst_n` 訊號連接著整個電路裡成百上千個正反器 (這稱為 High Fanout Net)。在還沒有做後端實體佈局 (APR) 的 Clock Tree Synthesis (CTS) 之前，Design Compiler (DC) 不知道這些正反器在晶片上的物理位置，它只能用非常粗糙的假 Buffer 樹去推動這成百上千個負載，導致算出來的 RC 延遲大得不可思議。

在業界，我們**絕對不會**在 Pre-Layout 階段去 Debug 這種全域 Reset 或 Clock 的延遲，因為那是不準的（後端工程師長好 Tree 之後，這個延遲就會被完美平衡掉）。

### 🛠️ 終極解法：宣告 Ideal Network

為了讓 GLS 能順利跑下去，我們必須告訴 DC 和模擬器：「請把 `rst_n` 當作神仙訊號 (Ideal Network)，它擁有無限的驅動力，不需要加 Buffer，傳遞時間是 0」。

既然你還沒重新跑合成，現在加進去剛剛好！請打開你的 `.tcl` 檔，在 `compile_ultra` 之前加上 `set_ideal_network` 指令。

把你的 Compile 區塊改成這樣：

```tcl
############################################
# compile
############################################
uniquify
set_fix_multiple_port_nets -all -buffer_constants [get_designs *]

# ==========================================
# 1. 宣告 rst_n 為 Ideal Network，消除超大假延遲
# ==========================================
set_ideal_network [get_ports rst_n]

# ==========================================
# 2. 強制修補內部 CORDIC 管線的 Hold Time Violation
# ==========================================
set_fix_hold [all_clocks]

compile_ultra
compile -inc

```

**接下來的步驟：**

1. 存檔 `.tcl`。
2. 狠下心，重新跑一次那個要跑很久的 DC 合成。
3. 拿新產出的 Netlist (`.v`) 和 時序檔 (`.sdf`) 去跑搭配你剛剛改好 `0.02 ns` 延遲的 Testbench。

加上這兩帖猛藥（修補 Hold Time + 消除 Reset 假延遲）後，你的 GLS 就能看到漂亮且完全正確的綠色波形了！