// 3x3 iterative QR eigen-solver — 3-PE CORDIC systolic array
//
// Formats: Q6.11 (17-bit total, 11-bit fractional), CORDIC STAGES = 10
// Per iteration:
//   ST_QR       — vector T, capture R; PEs hold Q (d_latch)
//   ST_ROT_PIPE — Fully pipelined Rotation phase (43 cycles):
//                 Feed R^T, then immediately feed U^T (+3 cycles offset).
//                 Capture T^(i+1) -> M_Regs (Optimized 6 Registers).
//                 Capture U^(i+1) -> U_buf (Dense 9 Registers).

module qrd_top (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 InValid,
    input  wire signed [16:0]   InData_row1,
    input  wire signed [16:0]   InData_row2,
    input  wire signed [16:0]   InData_row3,
    output reg  signed [16:0]   OutData_row1,
    output reg  signed [16:0]   OutData_row2,
    output reg  signed [16:0]   OutData_row3,
    output reg                  OutValid
);

    // -------------------------------------------------------------------------
    // Timing (gen_top_timing.py: L=12, OFF=3)
    // -------------------------------------------------------------------------
    localparam integer CORDIC_STAGES = 10;
    localparam PE_LAT                = CORDIC_STAGES + 2;
    localparam ROT_PIPE_OFFSET       = 3;

    localparam VEC_CYCLE11           = 1;
    localparam VEC_CYCLE12           = VEC_CYCLE11 + PE_LAT;
    localparam VEC_CYCLE22           = VEC_CYCLE12 + 1 + PE_LAT;

    localparam CAP_r11               = VEC_CYCLE12 + PE_LAT;
    localparam CAP_r12               = VEC_CYCLE12 + 1 + PE_LAT;
    localparam CAP_r13               = VEC_CYCLE12 + 2 + PE_LAT;
    localparam CAP_r22               = VEC_CYCLE22 + PE_LAT;
    localparam CAP_r23               = VEC_CYCLE22 + 1 + PE_LAT;
    localparam CAP_r33               = VEC_CYCLE22 + 1 + PE_LAT;

    localparam CAP_u_pe22_a       = CAP_r22 + 2;
    localparam CAP_u_pe22_b       = CAP_r23 + 2;
    localparam CAP_u_pe22_c       = CAP_r23 + 3;

    localparam QR_CYCLES             = CAP_r33 + 1;
    localparam ROT_PIPE_CYCLES       = QR_CYCLES + ROT_PIPE_OFFSET;

    // 1.0 in Q6.11
    localparam signed [16:0] FIX_ONE = 17'sd2048;

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    localparam ST_IDLE     = 3'd0;
    localparam ST_QR       = 3'd1;
    localparam ST_ROT_PIPE = 3'd2;
    localparam ST_DONE     = 3'd3;

    localparam ITER_MAX = 7;

    reg [2:0] state;
    reg [2:0] iter_cnt;
    reg [7:0] phase_timer;
    reg [1:0] load_col;
    reg [1:0] out_phase;

    wire qr_active       = (state == ST_QR);
    wire rot_pipe_active = (state == ST_ROT_PIPE);
    wire array_run       = qr_active | rot_pipe_active;

    // -------------------------------------------------------------------------
    // Buffers & Registers
    // -------------------------------------------------------------------------
    reg signed [16:0] M_11, M_12, M_13, M_22, M_23, M_33;
    reg signed [16:0] U_buf [0:2][0:2];
    reg signed [16:0] col_in [0:2][0:2];
    reg signed [16:0] row3_col0_hold;

    // -------------------------------------------------------------------------
    // 3-PE systolic array
    // -------------------------------------------------------------------------
    wire signed [16:0] pe11_x, pe11_y, pe12_y;
    wire signed [16:0] pe11_xo, pe11_yo, pe12_xo, pe12_yo, pe22_xo, pe22_yo;
    wire [CORDIC_STAGES-1:0] pe11_d, pe12_d, pe22_d;

    wire pe11_mode = qr_active && (phase_timer == VEC_CYCLE11);
    wire pe12_mode = qr_active && (phase_timer == VEC_CYCLE12);
    wire pe22_mode = qr_active && (phase_timer == VEC_CYCLE22);

    wire signed [16:0] du_dout;

    du_delay #(.WIDTH(17), .DEPTH(PE_LAT)) u_du (
        .clk(clk), .rst_n(rst_n), .en(array_run),
        .din(pe11_yo), .dout(du_dout)
    );

    cordic_pe #(
        .WIDTH(17),
        .STAGES(CORDIC_STAGES)
    ) PE11 (
        .clk(clk), .rst_n(rst_n), .mode(pe11_mode),
        .X_in(pe11_x), .Y_in(pe11_y), .d_in({CORDIC_STAGES{1'b0}}),
        .X_out(pe11_xo), .Y_out(pe11_yo), .d_out(pe11_d)
    );

    cordic_pe #(
        .WIDTH(17),
        .STAGES(CORDIC_STAGES)
    ) PE12 (
        .clk(clk), .rst_n(rst_n), .mode(pe12_mode),
        .X_in(pe11_xo), .Y_in(pe12_y), .d_in({CORDIC_STAGES{1'b0}}),
        .X_out(pe12_xo), .Y_out(pe12_yo), .d_out(pe12_d)
    );

    cordic_pe #(
        .WIDTH(17),
        .STAGES(CORDIC_STAGES)
    ) PE22 (
        .clk(clk), .rst_n(rst_n), .mode(pe22_mode),
        .X_in(du_dout), .Y_in(pe12_yo), .d_in({CORDIC_STAGES{1'b0}}),
        .X_out(pe22_xo), .Y_out(pe22_yo), .d_out(pe22_d)
    );

    // -------------------------------------------------------------------------
    // Streaming matrix load
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_col <= 0;
            col_in[0][0] <= 0; col_in[1][0] <= 0; col_in[2][0] <= 0;
            col_in[0][1] <= 0; col_in[1][1] <= 0; col_in[2][1] <= 0;
            col_in[0][2] <= 0; col_in[1][2] <= 0; col_in[2][2] <= 0;
            row3_col0_hold <= 0;
        end else begin
            if (InValid && iter_cnt == 0 && load_col < 3) begin
                col_in[0][load_col] <= InData_row1;
                col_in[1][load_col] <= InData_row2;
                col_in[2][load_col] <= InData_row3;
                load_col <= load_col + 1'b1;
            end
            if (state == ST_DONE) load_col <= 0;

            if (qr_active && phase_timer == VEC_CYCLE11)
                row3_col0_hold <= (iter_cnt == 0) ? col_in[2][0] : M_13;
        end
    end

    // -------------------------------------------------------------------------
    // Transpose Buffer Mapping
    // -------------------------------------------------------------------------
    wire [1:0] rot_tri_idx =
        (phase_timer >= 1 && phase_timer <= 3) ? (phase_timer - 1) :
        (phase_timer >= 4 && phase_timer <= 6) ? (phase_timer - 4) :
        (phase_timer >= VEC_CYCLE12 && phase_timer <= VEC_CYCLE12 + 2) ?
            (phase_timer - VEC_CYCLE12) :
        (phase_timer >= VEC_CYCLE12 + 3 && phase_timer <= VEC_CYCLE12 + 5) ?
            (phase_timer - VEC_CYCLE12 - 3) : 2'd0;

    wire signed [16:0] rot_m_r1 = (rot_tri_idx == 0) ? M_11 : 17'sd0;
    wire signed [16:0] rot_m_r2 = (rot_tri_idx == 0) ? M_12 : (rot_tri_idx == 1) ? M_22 : 17'sd0;
    wire signed [16:0] rot_m_r3 = (rot_tri_idx == 0) ? M_13 : (rot_tri_idx == 1) ? M_23 : M_33;

    wire signed [16:0] rot_u_r1 = (rot_tri_idx == 0) ? U_buf[0][0] : (rot_tri_idx == 1) ? U_buf[1][0] : U_buf[2][0];
    wire signed [16:0] rot_u_r2 = (rot_tri_idx == 0) ? U_buf[0][1] : (rot_tri_idx == 1) ? U_buf[1][1] : U_buf[2][1];
    wire signed [16:0] rot_u_r3 = (rot_tri_idx == 0) ? U_buf[0][2] : (rot_tri_idx == 1) ? U_buf[1][2] : U_buf[2][2];

    wire use_input_cols = (iter_cnt == 0);
    wire [1:0] qr_feed_col =
        (phase_timer >= 1 && phase_timer <= 3) ? (phase_timer - 1) :
        (phase_timer >= VEC_CYCLE12 + 1 && phase_timer <= VEC_CYCLE12 + 2) ?
            (phase_timer - VEC_CYCLE12) : 2'd0;

    wire signed [16:0] mat_r1 = use_input_cols ? col_in[0][qr_feed_col] :
                                (qr_feed_col == 0) ? M_11 : (qr_feed_col == 1) ? M_12 : M_13;
    wire signed [16:0] mat_r2 = use_input_cols ? col_in[1][qr_feed_col] :
                                (qr_feed_col == 0) ? M_12 : (qr_feed_col == 1) ? M_22 : M_23;
    wire signed [16:0] mat_r3 = use_input_cols ? col_in[2][qr_feed_col] :
                                (qr_feed_col == 0) ? M_13 : (qr_feed_col == 1) ? M_23 : M_33;

    // -------------------------------------------------------------------------
    // Feed controller
    // -------------------------------------------------------------------------
    reg signed [16:0] n_pe11_x, n_pe11_y, n_pe12_y;

    always @(*) begin
        n_pe11_x = 17'sd0;
        n_pe11_y = 17'sd0;
        n_pe12_y = 17'sd0;

        if (qr_active) begin
            if (phase_timer >= 1 && phase_timer <= 3) begin
                n_pe11_x = mat_r1;
                n_pe11_y = mat_r2;
            end
            if (phase_timer >= VEC_CYCLE12 && phase_timer <= VEC_CYCLE12 + 2) begin
                n_pe12_y = (phase_timer == VEC_CYCLE12) ? row3_col0_hold : mat_r3;
            end
        end else if (rot_pipe_active) begin
            if (phase_timer >= 1 && phase_timer <= 3) begin
                n_pe11_x = rot_m_r1;
                n_pe11_y = rot_m_r2;
            end else if (phase_timer >= 4 && phase_timer <= 6) begin
                n_pe11_x = rot_u_r1;
                n_pe11_y = rot_u_r2;
            end

            if (phase_timer >= VEC_CYCLE12 && phase_timer <= VEC_CYCLE12 + 2)
                n_pe12_y = rot_m_r3;
            else if (phase_timer >= VEC_CYCLE12 + 3 && phase_timer <= VEC_CYCLE12 + 5)
                n_pe12_y = rot_u_r3;
        end
    end

    assign pe11_x = n_pe11_x;
    assign pe11_y = n_pe11_y;
    assign pe12_y = n_pe12_y;

    // -------------------------------------------------------------------------
    // Capture Logic (Unified Assignment)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            M_11 <= 0; M_12 <= 0; M_13 <= 0;
            M_22 <= 0; M_23 <= 0; M_33 <= 0;
            U_buf[0][0] <= FIX_ONE; U_buf[0][1] <= 0; U_buf[0][2] <= 0;
            U_buf[1][0] <= 0; U_buf[1][1] <= FIX_ONE; U_buf[1][2] <= 0;
            U_buf[2][0] <= 0; U_buf[2][1] <= 0; U_buf[2][2] <= FIX_ONE;
        end else if (state == ST_IDLE && InValid) begin
            U_buf[0][0] <= FIX_ONE; U_buf[0][1] <= 0; U_buf[0][2] <= 0;
            U_buf[1][0] <= 0; U_buf[1][1] <= FIX_ONE; U_buf[1][2] <= 0;
            U_buf[2][0] <= 0; U_buf[2][1] <= 0; U_buf[2][2] <= FIX_ONE;
        end else if (qr_active) begin
            case (phase_timer)
                CAP_r11: M_11 <= pe12_xo;
                CAP_r12: M_12 <= pe12_xo;
                CAP_r13: M_13 <= pe12_xo;
                CAP_r22: M_22 <= pe22_xo;
                CAP_r23: begin M_23 <= pe22_xo; M_33 <= pe22_yo; end
            endcase
        end else if (rot_pipe_active) begin
            case (phase_timer)
                CAP_r11: M_11 <= pe12_xo;
                CAP_r12: M_12 <= pe12_xo;
                CAP_r13: M_13 <= pe12_xo;
                CAP_r22: M_22 <= pe22_xo;
                CAP_r23: begin M_23 <= pe22_xo; M_33 <= pe22_yo; end
            endcase

            case (phase_timer)
                CAP_r11 + ROT_PIPE_OFFSET: U_buf[0][0] <= pe12_xo;
                CAP_u_pe22_a: begin U_buf[0][1] <= pe22_xo; U_buf[0][2] <= pe22_yo; end
                CAP_r12 + ROT_PIPE_OFFSET: U_buf[1][0] <= pe12_xo;
                CAP_u_pe22_b: begin U_buf[1][1] <= pe22_xo; U_buf[1][2] <= pe22_yo; end
                CAP_r13 + ROT_PIPE_OFFSET: U_buf[2][0] <= pe12_xo;
                CAP_u_pe22_c: begin U_buf[2][1] <= pe22_xo; U_buf[2][2] <= pe22_yo; end
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // FSM & Output Streaming
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            iter_cnt     <= 0;
            phase_timer  <= 0;
            out_phase    <= 0;
            OutValid     <= 1'b0;
            OutData_row1 <= 0; OutData_row2 <= 0; OutData_row3 <= 0;
        end else begin
            if (state != ST_DONE) OutValid <= 1'b0;

            case (state)
                ST_IDLE: begin
                    phase_timer <= 0;
                    if (InValid) begin
                        iter_cnt    <= 0;
                        state       <= ST_QR;
                        phase_timer <= 0;
                    end
                end

                ST_QR: begin
                    if (phase_timer == QR_CYCLES - 1) begin
                        state       <= ST_ROT_PIPE;
                        phase_timer <= 0;
                    end else
                        phase_timer <= phase_timer + 1;
                end

                ST_ROT_PIPE: begin
                    if (phase_timer == ROT_PIPE_CYCLES - 1) begin
                        if (iter_cnt == ITER_MAX - 1) begin
                            state        <= ST_DONE;
                            out_phase    <= 2'd0;
                            OutData_row1 <= M_11;
                            OutData_row2 <= M_22;
                            OutData_row3 <= M_33;
                            OutValid     <= 1'b1;
                        end else begin
                            iter_cnt    <= iter_cnt + 1;
                            state       <= ST_QR;
                            phase_timer <= 0;
                        end
                    end else
                        phase_timer <= phase_timer + 1;
                end

                ST_DONE: begin
                    OutValid <= 1'b1;
                    case (out_phase)
                        2'd0: begin
                            OutData_row1 <= U_buf[0][0];
                            OutData_row2 <= U_buf[1][0];
                            OutData_row3 <= U_buf[2][0];
                            out_phase    <= 2'd1;
                        end
                        2'd1: begin
                            OutData_row1 <= U_buf[0][1];
                            OutData_row2 <= U_buf[1][1];
                            OutData_row3 <= U_buf[2][1];
                            out_phase    <= 2'd2;
                        end
                        2'd2: begin
                            OutData_row1 <= U_buf[0][2];
                            OutData_row2 <= U_buf[1][2];
                            OutData_row3 <= U_buf[2][2];
                            out_phase    <= 2'd3;
                        end
                        2'd3: begin
                            OutValid     <= 1'b0;
                            OutData_row1 <= 17'sd0;
                            OutData_row2 <= 17'sd0;
                            OutData_row3 <= 17'sd0;
                            state        <= ST_IDLE;
                            out_phase    <= 2'd0;
                        end
                    endcase
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
