`timescale 1ns / 1ps

module tb_cordic_pe;

  localparam PE_LATENCY = 12;
  localparam NUM_VEC_TESTS = 5;
  localparam NUM_ROT_TESTS = 1;

  reg clk;
  reg rst_n;
  reg mode;
  reg signed [16:0] X_in;
  reg signed [16:0] Y_in;
  reg [9:0] d_in;

  wire signed [16:0] X_out;
  wire signed [16:0] Y_out;
  wire [9:0] d_out;

  cordic_pe uut (
      .clk(clk),
      .rst_n(rst_n),
      .mode(mode),
      .X_in(X_in),
      .Y_in(Y_in),
      .d_in(d_in),
      .X_out(X_out),
      .Y_out(Y_out),
      .d_out(d_out)
  );

  integer pass_cnt;
  integer fail_cnt;

  // Auto-generated golden vectors (gen_cordic_pe_vectors.py)
  reg signed [16:0] vec_x_in   [0:NUM_VEC_TESTS-1];
  reg signed [16:0] vec_y_in   [0:NUM_VEC_TESTS-1];
  reg signed [16:0] vec_x_exp  [0:NUM_VEC_TESTS-1];
  reg signed [16:0] vec_y_exp  [0:NUM_VEC_TESTS-1];
  reg [9:0]        vec_d_exp  [0:NUM_VEC_TESTS-1];

  reg signed [16:0] rot_x_in   [0:NUM_ROT_TESTS-1];
  reg signed [16:0] rot_y_in   [0:NUM_ROT_TESTS-1];
  reg [9:0]        rot_d_in   [0:NUM_ROT_TESTS-1];
  reg signed [16:0] rot_x_exp  [0:NUM_ROT_TESTS-1];
  reg signed [16:0] rot_y_exp  [0:NUM_ROT_TESTS-1];

  // Coupled stream: vec@0, rot@1, rot@2 (gen_cordic_pe_vectors.py)
  reg signed [16:0] cpl_vec_x_in, cpl_vec_y_in;
  reg signed [16:0] cpl_vec_x_exp, cpl_vec_y_exp;
  reg [9:0]        cpl_vec_d_exp;
  reg signed [16:0] cpl_rot1_x_in, cpl_rot1_y_in;
  reg signed [16:0] cpl_rot1_x_exp, cpl_rot1_y_exp;
  reg signed [16:0] cpl_rot2_x_in, cpl_rot2_y_in;
  reg signed [16:0] cpl_rot2_x_exp, cpl_rot2_y_exp;

  initial begin
    vec_x_in[0] = 17'sd13417; vec_y_in[0] = 17'sd897;
    vec_x_exp[0] = 17'sd13447; vec_y_exp[0] = -17'sd10; vec_d_exp[0] = 10'h10e;

    vec_x_in[1] = 17'sd2105; vec_y_in[1] = 17'sd1962;
    vec_x_exp[1] = 17'sd2877; vec_y_exp[1] = -17'sd4; vec_d_exp[1] = 10'h022;

    vec_x_in[2] = 17'sd4198; vec_y_in[2] = -17'sd4903;
    vec_x_exp[2] = 17'sd6454; vec_y_exp[2] = -17'sd2; vec_d_exp[2] = 10'h363;

    vec_x_in[3] = -17'sd3072; vec_y_in[3] = 17'sd1536;
    vec_x_exp[3] = 17'sd3435; vec_y_exp[3] = 17'sd1; vec_d_exp[3] = 10'h295;

    vec_x_in[4] = 17'sd1024; vec_y_in[4] = -17'sd512;
    vec_x_exp[4] = 17'sd1145; vec_y_exp[4] = 17'sd1; vec_d_exp[4] = 10'h295;

    rot_x_in[0] = 17'sd897; rot_y_in[0] = 17'sd13417; rot_d_in[0] = 10'h363;
    rot_x_exp[0] = -17'sd9603; rot_y_exp[0] = 17'sd9413;

    cpl_vec_x_in = 17'sd4198; cpl_vec_y_in = -17'sd4903;
    cpl_vec_x_exp = 17'sd6454; cpl_vec_y_exp = -17'sd2; cpl_vec_d_exp = 10'h363;
    cpl_rot1_x_in = 17'sd897; cpl_rot1_y_in = 17'sd2105;
    cpl_rot1_x_exp = -17'sd1015; cpl_rot1_y_exp = 17'sd2051;
    cpl_rot2_x_in = 17'sd1962; cpl_rot2_y_in = 17'sd1607;
    cpl_rot2_x_exp = 17'sd58; cpl_rot2_y_exp = 17'sd2536;
  end

  initial clk = 0;
  always #5 clk = ~clk;

  task wait_cycles;
    input integer n;
    integer k;
    begin
      for (k = 0; k < n; k = k + 1) @(posedge clk);
    end
  endtask

  task check_result;
    input [8*64:1] test_name;
    input signed [16:0] x_exp;
    input signed [16:0] y_exp;
    input [9:0] d_exp;
    input check_d;
    begin
      if (X_out !== x_exp || Y_out !== y_exp || (check_d && d_out !== d_exp)) begin
        $display("[FAIL] %s", test_name);
        $display("       exp X=%0d Y=%0d d=0x%03x", x_exp, y_exp, d_exp);
        $display("       got X=%0d Y=%0d d=0x%03x", X_out, Y_out, d_out);
        fail_cnt = fail_cnt + 1;
      end else begin
        $display("[PASS] %s", test_name);
        pass_cnt = pass_cnt + 1;
      end
    end
  endtask

  task apply_vectoring;
    input signed [16:0] x_val;
    input signed [16:0] y_val;
    begin
      mode = 1'b1;
      d_in = 10'd0;
      X_in = x_val;
      Y_in = y_val;
      @(posedge clk);
      X_in = 17'sd0;
      Y_in = 17'sd0;
      wait_cycles(PE_LATENCY - 1);
    end
  endtask

  task apply_rotation;
    input signed [16:0] x_val;
    input signed [16:0] y_val;
    input [9:0] d_val;
    begin
      mode = 1'b0;
      d_in = d_val;
      X_in = x_val;
      Y_in = y_val;
      @(posedge clk);
      X_in = 17'sd0;
      Y_in = 17'sd0;
      wait_cycles(PE_LATENCY - 1);
    end
  endtask

  // Coupled QR step: vector @ cycle 0, rotation @ 1 and @ 2 (d_in = 0)
  task apply_coupled_qr_step;
    input signed [16:0] vx, vy;
    input signed [16:0] r1x, r1y;
    input signed [16:0] r2x, r2y;
    input signed [16:0] vx_exp, vy_exp;
    input [9:0]        vd_exp;
    input signed [16:0] r1x_exp, r1y_exp;
    input signed [16:0] r2x_exp, r2y_exp;
    begin
      mode = 1'b1;
      d_in = 10'd0;
      X_in = vx;
      Y_in = vy;
      @(posedge clk);

      mode = 1'b0;
      d_in = 10'd0;
      X_in = r1x;
      Y_in = r1y;
      @(posedge clk);

      X_in = r2x;
      Y_in = r2y;
      @(posedge clk);

      X_in = 17'sd0;
      Y_in = 17'sd0;
      mode = 1'b0;

      // vec out @12, rot1 @13, rot2 @14
      wait_cycles(PE_LATENCY - 3);
      check_result("coupled vectoring @0", vx_exp, vy_exp, vd_exp, 1'b1);
      wait_cycles(1);
      check_result("coupled rotation @1", r1x_exp, r1y_exp, 10'h000, 1'b0);
      wait_cycles(1);
      check_result("coupled rotation @2", r2x_exp, r2y_exp, 10'h000, 1'b0);
    end
  endtask

  integer i;

  initial begin
    pass_cnt = 0;
    fail_cnt = 0;

    rst_n = 1'b0;
    mode  = 1'b0;
    X_in  = 17'sd0;
    Y_in  = 17'sd0;
    d_in  = 10'd0;

    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    wait_cycles(2);

    $display("========================================");
    $display(" cordic_pe testbench");
    $display(" PE latency = %0d cycles", PE_LATENCY);
    $display("========================================");

    for (i = 0; i < NUM_VEC_TESTS; i = i + 1) begin
      apply_vectoring(vec_x_in[i], vec_y_in[i]);
      check_result("vectoring", vec_x_exp[i], vec_y_exp[i], vec_d_exp[i], 1'b1);
      wait_cycles(1);
    end

    for (i = 0; i < NUM_ROT_TESTS; i = i + 1) begin
      apply_rotation(rot_x_in[i], rot_y_in[i], rot_d_in[i]);
      check_result("rotation (standalone d_in)", rot_x_exp[i], rot_y_exp[i], 10'h000, 1'b0);
      wait_cycles(1);
    end

    apply_coupled_qr_step(
        cpl_vec_x_in, cpl_vec_y_in,
        cpl_rot1_x_in, cpl_rot1_y_in,
        cpl_rot2_x_in, cpl_rot2_y_in,
        cpl_vec_x_exp, cpl_vec_y_exp, cpl_vec_d_exp,
        cpl_rot1_x_exp, cpl_rot1_y_exp,
        cpl_rot2_x_exp, cpl_rot2_y_exp
    );

    $display("========================================");
    $display(" Summary: %0d passed, %0d failed", pass_cnt, fail_cnt);
    $display("========================================");

    if (fail_cnt != 0) $fatal(1, "Simulation failed.");
    else $display("All tests passed.");

    #20;
    $finish;
  end

endmodule
