// Fully pipelined (streaming) CORDIC processing element — coupled d model.
// (Optimized for Q6.11 format with Separated Zero-Adder Round Half Up logic)

module cordic_pe #(
    parameter integer WIDTH  = 17,
    parameter integer STAGES = 10
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 mode,       // 1: vectoring, 0: rotation
    input  wire signed [WIDTH-1:0] X_in,
    input  wire signed [WIDTH-1:0] Y_in,
    input  wire [STAGES-1:0]    d_in,
    output reg  signed [WIDTH-1:0] X_out,
    output reg  signed [WIDTH-1:0] Y_out,
    output reg  [STAGES-1:0]    d_out
);

    localparam integer LATENCY = STAGES + 2;

    reg signed [WIDTH-1:0] X_st [0:STAGES];
    reg signed [WIDTH-1:0] Y_st [0:STAGES];
    reg [STAGES-1:0]       d_st [0:STAGES];
    reg                    mode_st [0:STAGES];
    reg                    force_d_in_st [0:STAGES];
    reg                    d_latch [0:STAGES-1];

    // -------------------------------------------------------------------------
    // Stage 0: input register + vectoring quadrant fix
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            X_st[0]          <= {WIDTH{1'b0}};
            Y_st[0]          <= {WIDTH{1'b0}};
            d_st[0]          <= {STAGES{1'b0}};
            mode_st[0]       <= 1'b0;
            force_d_in_st[0] <= 1'b0;
        end else begin
            mode_st[0]       <= mode;
            d_st[0]          <= d_in;
            force_d_in_st[0] <= !mode && (|d_in);
            if (mode && X_in[WIDTH-1]) begin
                X_st[0] <= -X_in;
                Y_st[0] <= -Y_in;
            end else begin
                X_st[0] <= X_in;
                Y_st[0] <= Y_in;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Stages 1..STAGES: micro-rotations with OPTIMIZED ROUNDING
    // -------------------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < STAGES; i = i + 1) begin : micro_rot
            wire vec_d;
            wire rot_d;
            wire current_d;
            
            wire signed [WIDTH-1:0] X_shift_base;
            wire signed [WIDTH-1:0] Y_shift_base;
            wire signed [WIDTH-1:0] X_rnd;
            wire signed [WIDTH-1:0] Y_rnd;

            // Zero-Adder Rounding Logic: (X >>> i) + X[i-1]
            if (i == 0) begin
                assign X_shift_base = X_st[i];
                assign Y_shift_base = Y_st[i];
                assign X_rnd = {WIDTH{1'b0}};
                assign Y_rnd = {WIDTH{1'b0}};
            end else begin
                assign X_shift_base = X_st[i] >>> i;
                assign Y_shift_base = Y_st[i] >>> i;
                assign X_rnd = {{(WIDTH-1){1'b0}}, X_st[i][i-1]};
                assign Y_rnd = {{(WIDTH-1){1'b0}}, Y_st[i][i-1]};
            end

            assign vec_d = Y_st[i][WIDTH-1];
            assign rot_d = force_d_in_st[i] ? d_st[i][i] : d_latch[i];
            assign current_d = mode_st[i] ? vec_d : rot_d;

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    X_st[i+1]          <= {WIDTH{1'b0}};
                    Y_st[i+1]          <= {WIDTH{1'b0}};
                    d_st[i+1]          <= {STAGES{1'b0}};
                    mode_st[i+1]       <= 1'b0;
                    force_d_in_st[i+1] <= 1'b0;
                    d_latch[i]         <= 1'b0;
                end else begin
                    mode_st[i+1]       <= mode_st[i];
                    force_d_in_st[i+1] <= force_d_in_st[i];
                    if (force_d_in_st[i]) begin
                        d_st[i+1] <= d_st[i];
                    end else if (mode_st[i]) begin
                        d_st[i+1] <= d_st[i] | (vec_d << i);
                    end else begin
                        d_st[i+1] <= d_st[i];
                    end

                    if (mode_st[i])
                        d_latch[i] <= vec_d;

                    if (current_d) begin
                        X_st[i+1] <= X_st[i] - Y_shift_base - Y_rnd;
                        Y_st[i+1] <= Y_st[i] + X_shift_base + X_rnd;
                    end else begin
                        X_st[i+1] <= X_st[i] + Y_shift_base + Y_rnd;
                        Y_st[i+1] <= Y_st[i] - X_shift_base - X_rnd;
                    end
                end
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Final stage: CSD scaling with ADDER TREE SEPARATION
    // CSD @ STAGES=10, S_FRAC_BITS=14: +0+00-00-00-0+
    // => 2^-1 + 2^-3 - 2^-6 - 2^-9 - 2^-12 + 2^-14
    // -------------------------------------------------------------------------
    wire signed [WIDTH-1:0] X_unscaled = X_st[STAGES];
    wire signed [WIDTH-1:0] Y_unscaled = Y_st[STAGES];

    // =========================================================================
    // 🌟 關鍵優化：先用超迷你的 5-bit 加法器把 Rounding Bits 算完 🌟
    // =========================================================================
    // 最大正值為 3，最大負值為 -3，5-bit (範圍 -16 到 15) 絕對安全且極度快速
    wire signed [4:0] x_rnd_sum_small =
          $signed({4'b0, X_unscaled[0]})
        + $signed({4'b0, X_unscaled[2]})
        - $signed({4'b0, X_unscaled[5]})
        - $signed({4'b0, X_unscaled[8]})
        - $signed({4'b0, X_unscaled[11]})
        + $signed({4'b0, X_unscaled[13]});

    wire signed [4:0] y_rnd_sum_small =
          $signed({4'b0, Y_unscaled[0]})
        + $signed({4'b0, Y_unscaled[2]})
        - $signed({4'b0, Y_unscaled[5]})
        - $signed({4'b0, Y_unscaled[8]})
        - $signed({4'b0, Y_unscaled[11]})
        + $signed({4'b0, Y_unscaled[13]});

    // 安全地 sign-extend 回 17-bit
    wire signed [WIDTH-1:0] x_rnd_sum = { {(WIDTH-5){x_rnd_sum_small[4]}}, x_rnd_sum_small };
    wire signed [WIDTH-1:0] y_rnd_sum = { {(WIDTH-5){y_rnd_sum_small[4]}}, y_rnd_sum_small };

    // =========================================================================
    // 主加法樹：從 12 個運算元大幅縮減至 7 個運算元，消除 Top-level 延遲瓶頸
    // =========================================================================
    wire signed [WIDTH-1:0] X_scaled =
          (X_unscaled >>> 1)  
        + (X_unscaled >>> 3)  
        - (X_unscaled >>> 6)  
        - (X_unscaled >>> 9)  
        - (X_unscaled >>> 12) 
        + (X_unscaled >>> 14) 
        + x_rnd_sum;

    wire signed [WIDTH-1:0] Y_scaled =
          (Y_unscaled >>> 1)  
        + (Y_unscaled >>> 3)  
        - (Y_unscaled >>> 6)  
        - (Y_unscaled >>> 9)  
        - (Y_unscaled >>> 12) 
        + (Y_unscaled >>> 14) 
        + y_rnd_sum;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            X_out <= {WIDTH{1'b0}};
            Y_out <= {WIDTH{1'b0}};
            d_out <= {STAGES{1'b0}};
        end else begin
            X_out <= X_scaled;
            Y_out <= Y_scaled;
            d_out <= d_st[STAGES];
        end
    end

endmodule