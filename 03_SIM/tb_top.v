`timescale 1ns / 1ps

module tb_top;

  localparam CLK_HALF = 5;
  localparam TIMEOUT_CYCLES = 1200;

  reg clk;
  reg rst_n;
  reg InValid;
  reg signed [17:0] InData_row1;
  reg signed [17:0] InData_row2;
  reg signed [17:0] InData_row3;

  wire signed [17:0] OutData_row1;
  wire signed [17:0] OutData_row2;
  wire signed [17:0] OutData_row3;
  wire OutValid;

  qrd_top uut (
      .clk(clk),
      .rst_n(rst_n),
      .InValid(InValid),
      .InData_row1(InData_row1),
      .InData_row2(InData_row2),
      .InData_row3(InData_row3),
      .OutData_row1(OutData_row1),
      .OutData_row2(OutData_row2),
      .OutData_row3(OutData_row3),
      .OutValid(OutValid)
  );

  integer pass_cnt;
  integer fail_cnt;
  integer cycle;
  integer out_idx;
  integer wait_cycles;

  // Golden: Matrix(:,:,8) — gen_top_vectors.py (bit-true HW model)
  reg signed [17:0] in_col0 [0:2];
  reg signed [17:0] in_col1 [0:2];
  reg signed [17:0] in_col2 [0:2];

  reg signed [17:0] golden_eig [0:2];
  reg signed [17:0] golden_u_r0 [0:2];
  reg signed [17:0] golden_u_r1 [0:2];
  reg signed [17:0] golden_u_r2 [0:2];

  task automatic check_out;
    input integer phase;
    input signed [17:0] exp_r1;
    input signed [17:0] exp_r2;
    input signed [17:0] exp_r3;
    begin
      if (OutData_row1 !== exp_r1 || OutData_row2 !== exp_r2 || OutData_row3 !== exp_r3) begin
        $display("FAIL out phase %0d @ cycle %0d", phase, cycle);
        $display("  exp: r1=%0d r2=%0d r3=%0d", exp_r1, exp_r2, exp_r3);
        $display("  got: r1=%0d r2=%0d r3=%0d", OutData_row1, OutData_row2, OutData_row3);
        fail_cnt = fail_cnt + 1;
      end else begin
        $display("PASS out phase %0d @ cycle %0d", phase, cycle);
        pass_cnt = pass_cnt + 1;
      end
    end
  endtask

  initial begin
    clk = 1'b0;
    forever #(CLK_HALF) clk = ~clk;
  end

  initial begin
    pass_cnt = 0;
    fail_cnt = 0;
    cycle = 0;
    out_idx = 0;
    wait_cycles = 0;

    // Matrix(:,:,8) quantized columns @ Q6.12 (gen_top_vectors.py, cell 4)
    in_col0[0] = 18'sd1990;   in_col0[1] = 18'sd1890;   in_col0[2] = -18'sd3112;
    in_col1[0] = 18'sd1890;   in_col1[1] = 18'sd4725;   in_col1[2] = 18'sd5324;
    in_col2[0] = -18'sd3112;  in_col2[1] = 18'sd5324;  in_col2[2] = 18'sd28281;

    // gen_top_vectors.py — notebook cell 4 (integer, round-half-up)
    golden_eig[0] = 18'sd29673;
    golden_eig[1] = 18'sd5326;
    golden_eig[2] = 18'sd1;

    // RTL ST_DONE streams U columns
    golden_u_r0[0] = 18'sd400;    golden_u_r0[1] = -18'sd814;  golden_u_r0[2] = -18'sd3983;
    golden_u_r1[0] = 18'sd2330;   golden_u_r1[1] = 18'sd3329;  golden_u_r1[2] = -18'sd457;
    golden_u_r2[0] = 18'sd3345;   golden_u_r2[1] = -18'sd2232; golden_u_r2[2] = 18'sd787;

    rst_n = 1'b0;
    InValid = 1'b0;
    InData_row1 = 0;
    InData_row2 = 0;
    InData_row3 = 0;
    #(CLK_HALF * 4);
    rst_n = 1'b1;
    @(posedge clk);  // sync after reset (avoid #(CLK_HALF) landing on posedge)

    // Stream 3 matrix columns (symmetric Matrix(:,:,8))
    InValid = 1'b1;
    InData_row1 = in_col0[0];
    InData_row2 = in_col0[1];
    InData_row3 = in_col0[2];
    @(posedge clk);
    cycle = cycle + 1;

    InData_row1 = in_col1[0];
    InData_row2 = in_col1[1];
    InData_row3 = in_col1[2];
    @(posedge clk);
    cycle = cycle + 1;

    InData_row1 = in_col2[0];
    InData_row2 = in_col2[1];
    InData_row3 = in_col2[2];
    @(posedge clk);
    cycle = cycle + 1;
    InValid = 1'b0;

    while (!OutValid && wait_cycles < TIMEOUT_CYCLES) begin
      @(posedge clk);
      cycle = cycle + 1;
      wait_cycles = wait_cycles + 1;
    end

    if (!OutValid) begin
      $display("FAIL: timeout waiting for OutValid after %0d cycles", wait_cycles);
      fail_cnt = fail_cnt + 1;
      $finish;
    end

    $display("OutValid first asserted at cycle %0d (waited %0d after input)", cycle, wait_cycles);

    check_out(0, golden_eig[0], golden_eig[1], golden_eig[2]);
    @(posedge clk);
    cycle = cycle + 1;
    check_out(1, golden_u_r0[0], golden_u_r0[1], golden_u_r0[2]);
    @(posedge clk);
    cycle = cycle + 1;
    check_out(2, golden_u_r1[0], golden_u_r1[1], golden_u_r1[2]);
    @(posedge clk);
    cycle = cycle + 1;
    check_out(3, golden_u_r2[0], golden_u_r2[1], golden_u_r2[2]);

    $display("");
    $display("=== tb_top Matrix(:,:,8) summary: %0d passed, %0d failed ===", pass_cnt, fail_cnt);
    if (fail_cnt != 0)
      $fatal(1, "Simulation failed");
    $finish;
  end

endmodule
