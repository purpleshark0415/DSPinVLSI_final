`timescale 1ns / 1ps

// Top-level testbench for workstation (VCS via 01_RTL/file.f).
// Reads input.txt and golden_output.txt from 00_TESTBED (no Python at sim time).
//
// Default vector path: ../00_TESTBED/  (relative to 01_RTL cwd)
// Override:           +datadir=/path/to/vectors/

module tb_top;

  localparam CLK_HALF       = 1.05;
  localparam TIMEOUT_CYCLES = 1200;
  localparam PATH_LEN       = 512;

  reg clk;
  reg rst_n;
  reg InValid;
  reg signed [16:0] InData_row1;
  reg signed [16:0] InData_row2;
  reg signed [16:0] InData_row3;

  wire signed [16:0] OutData_row1;
  wire signed [16:0] OutData_row2;
  wire signed [16:0] OutData_row3;
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
  integer wait_cycles;
  integer fd;
  integer status;
  integer col;
  integer phase;
  integer t0, t1, t2;

  reg signed [16:0] in_col [0:2][0:2];
  reg signed [16:0] golden_out [0:3][0:2];

  reg [8*PATH_LEN:1] datadir;
  reg [8*PATH_LEN:1] fpath;

  task automatic check_out;
    input integer ph;
    input signed [16:0] exp_r1;
    input signed [16:0] exp_r2;
    input signed [16:0] exp_r3;
    begin
      if (OutData_row1 !== exp_r1 || OutData_row2 !== exp_r2 || OutData_row3 !== exp_r3) begin
        $display("FAIL out phase %0d @ cycle %0d", ph, cycle);
        $display("  exp: r1=%0d r2=%0d r3=%0d", exp_r1, exp_r2, exp_r3);
        $display("  got: r1=%0d r2=%0d r3=%0d", OutData_row1, OutData_row2, OutData_row3);
        fail_cnt = fail_cnt + 1;
      end else begin
        $display("PASS out phase %0d @ cycle %0d", ph, cycle);
        pass_cnt = pass_cnt + 1;
      end
    end
  endtask

`ifdef GATE
    // Gate-level simulation: back-annotate timing from SDF
    initial begin
        $sdf_annotate("../02_SYN/Netlist/qrd_top_syn.sdf", uut);
    end
`endif

  initial begin
    clk = 1'b0;
    forever #(CLK_HALF) clk = ~clk;
  end

// --- FSDB Dump ---
`ifdef RTL_FSDB
    initial begin
        $fsdbDumpfile("./tb_top.fsdb");
        $fsdbDumpvars(0, tb_top);
    end
`endif
`ifdef GLS_FSDB
    initial begin
        $fsdbDumpfile("./tb_top_gls.fsdb");
        $fsdbDumpvars(0, tb_top);
    end
`endif

  initial begin
    pass_cnt    = 0;
    fail_cnt    = 0;
    cycle       = 0;
    wait_cycles = 0;

    if (!$value$plusargs("datadir=%s", datadir))
      datadir = "../00_TESTBED/";

    $sformat(fpath, "%0sinput.txt", datadir);
    fd = $fopen(fpath, "r");
    if (fd == 0)
      $fatal(1, "tb_top: cannot open %0s", fpath);
    for (col = 0; col < 3; col = col + 1) begin
      status = $fscanf(fd, "%d %d %d\n", t0, t1, t2);
      if (status != 3)
        $fatal(1, "tb_top: expected 3 lines in %0s", fpath);
      in_col[col][0] = t0;
      in_col[col][1] = t1;
      in_col[col][2] = t2;
    end
    $fclose(fd);
    $display("tb_top: loaded input from %0s", fpath);

    $sformat(fpath, "%0sgolden_output.txt", datadir);
    fd = $fopen(fpath, "r");
    if (fd == 0)
      $fatal(1, "tb_top: cannot open %0s", fpath);
    for (phase = 0; phase < 4; phase = phase + 1) begin
      status = $fscanf(fd, "%d %d %d\n", t0, t1, t2);
      if (status != 3)
        $fatal(1, "tb_top: expected 4 lines in %0s", fpath);
      golden_out[phase][0] = t0;
      golden_out[phase][1] = t1;
      golden_out[phase][2] = t2;
    end
    $fclose(fd);
    $display("tb_top: loaded golden from %0s", fpath);

    rst_n = 1'b0;
    InValid = 1'b0;
    InData_row1 = 0;
    InData_row2 = 0;
    InData_row3 = 0;
    #(CLK_HALF * 4);
    rst_n = 1'b1;
    @(posedge clk);

    // Stream 3 matrix columns
    InValid = 1'b1;
    InData_row1 = in_col[0][0];
    InData_row2 = in_col[0][1];
    InData_row3 = in_col[0][2];
    @(posedge clk);
    cycle = cycle + 1;

    InData_row1 = in_col[1][0];
    InData_row2 = in_col[1][1];
    InData_row3 = in_col[1][2];
    @(posedge clk);
    cycle = cycle + 1;

    InData_row1 = in_col[2][0];
    InData_row2 = in_col[2][1];
    InData_row3 = in_col[2][2];
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

    check_out(0, golden_out[0][0], golden_out[0][1], golden_out[0][2]);
    @(posedge clk);
    cycle = cycle + 1;
    check_out(1, golden_out[1][0], golden_out[1][1], golden_out[1][2]);
    @(posedge clk);
    cycle = cycle + 1;
    check_out(2, golden_out[2][0], golden_out[2][1], golden_out[2][2]);
    @(posedge clk);
    cycle = cycle + 1;
    check_out(3, golden_out[3][0], golden_out[3][1], golden_out[3][2]);

    repeat (4) begin
      @(posedge clk);
      cycle = cycle + 1;
    end

    $display("");
    $display("=== tb_top summary: %0d passed, %0d failed ===", pass_cnt, fail_cnt);
    if (fail_cnt != 0)
      $fatal(1, "Simulation failed");
    $finish;
  end

endmodule
