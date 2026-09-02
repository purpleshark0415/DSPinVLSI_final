`timescale 1ns / 1ps

// Multi-pattern testbench for qrd_top.
// - Tests Matrix(:,:,1..11) in one run (11 patterns total).
// - Reads input_all.txt and golden_output_all.txt from 00_TESTBED (no Python at sim time).
// - Sends next matrix only after previous iteration outputs are fully checked.
//
// Default vector path: ../00_TESTBED/  (relative to 01_RTL cwd)
// Override:           +datadir=/path/to/vectors/

module tb_top_all;

  localparam CLK_HALF       = 1.05;
  localparam TIMEOUT_CYCLES = 2000;
  localparam PATH_LEN       = 512;

  localparam NUM_PATTERNS   = 11;
  localparam NUM_COLS       = 3;
  localparam NUM_ROWS       = 3;
  localparam NUM_PHASES     = 4; // eig + Ucol0 + Ucol1 + Ucol2

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
  integer pat;
  integer col;
  integer phase;
  integer t0, t1, t2;

  reg signed [16:0] in_col      [0:NUM_PATTERNS-1][0:NUM_COLS-1][0:NUM_ROWS-1];
  reg signed [16:0] golden_out  [0:NUM_PATTERNS-1][0:NUM_PHASES-1][0:NUM_ROWS-1];

  reg [8*PATH_LEN:1] datadir;
  reg [8*PATH_LEN:1] fpath;

  task automatic check_out;
    input integer p_idx;
    input integer ph;
    input signed [16:0] exp_r1;
    input signed [16:0] exp_r2;
    input signed [16:0] exp_r3;
    begin
      if (OutData_row1 !== exp_r1 || OutData_row2 !== exp_r2 || OutData_row3 !== exp_r3) begin
        $display("FAIL pat %0d phase %0d @ cycle %0d", p_idx+1, ph, cycle);
        $display("  exp: r1=%0d r2=%0d r3=%0d", exp_r1, exp_r2, exp_r3);
        $display("  got: r1=%0d r2=%0d r3=%0d", OutData_row1, OutData_row2, OutData_row3);
        fail_cnt = fail_cnt + 1;
      end else begin
        $display("PASS pat %0d phase %0d @ cycle %0d", p_idx+1, ph, cycle);
        pass_cnt = pass_cnt + 1;
      end
    end
  endtask

`ifdef GATE
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
        $fsdbDumpfile("./tb_top_all.fsdb");
        $fsdbDumpvars(0, tb_top_all);
    end
`endif
`ifdef GLS_FSDB
    initial begin
        $fsdbDumpfile("./tb_top_all_gls.fsdb");
        $fsdbDumpvars(0, tb_top_all);
    end
`endif

  initial begin
    pass_cnt    = 0;
    fail_cnt    = 0;
    cycle       = 0;

    if (!$value$plusargs("datadir=%s", datadir))
      datadir = "../00_TESTBED/";

    // ---- load inputs: 11 patterns * 3 columns ----
    $sformat(fpath, "%0sinput_all.txt", datadir);
    fd = $fopen(fpath, "r");
    if (fd == 0)
      $fatal(1, "tb_top_all: cannot open %0s", fpath);
    for (pat = 0; pat < NUM_PATTERNS; pat = pat + 1) begin
      for (col = 0; col < NUM_COLS; col = col + 1) begin
        status = $fscanf(fd, "%d %d %d\n", t0, t1, t2);
        if (status != 3)
          $fatal(1, "tb_top_all: expected %0d lines in %0s", NUM_PATTERNS*NUM_COLS, fpath);
        in_col[pat][col][0] = t0;
        in_col[pat][col][1] = t1;
        in_col[pat][col][2] = t2;
      end
    end
    $fclose(fd);
    $display("tb_top_all: loaded input from %0s", fpath);

    // ---- load goldens: 11 patterns * 4 phases ----
    $sformat(fpath, "%0sgolden_output_all.txt", datadir);
    fd = $fopen(fpath, "r");
    if (fd == 0)
      $fatal(1, "tb_top_all: cannot open %0s", fpath);
    for (pat = 0; pat < NUM_PATTERNS; pat = pat + 1) begin
      for (phase = 0; phase < NUM_PHASES; phase = phase + 1) begin
        status = $fscanf(fd, "%d %d %d\n", t0, t1, t2);
        if (status != 3)
          $fatal(1, "tb_top_all: expected %0d lines in %0s", NUM_PATTERNS*NUM_PHASES, fpath);
        golden_out[pat][phase][0] = t0;
        golden_out[pat][phase][1] = t1;
        golden_out[pat][phase][2] = t2;
      end
    end
    $fclose(fd);
    $display("tb_top_all: loaded golden from %0s", fpath);

    // ---- reset ----
    rst_n = 1'b0;
    InValid = 1'b0;
    InData_row1 = 0;
    InData_row2 = 0;
    InData_row3 = 0;
    #(CLK_HALF * 4);
    rst_n = 1'b1;
    @(posedge clk);

    // ---- run patterns 1..11 ----
    for (pat = 0; pat < NUM_PATTERNS; pat = pat + 1) begin
      wait_cycles = 0;
      $display("");
      $display("=== pattern %0d/%0d ===", pat+1, NUM_PATTERNS);

      // IMPORTANT:
      // - Pattern 1 starts right after reset (iter_cnt already 0): stream 3 columns.
      // - After a completed run, iter_cnt is still ITER_MAX-1 until *after* the first
      //   InValid cycle, so patterns 2..11 need a 1-cycle "arm" InValid before the
      //   3 real columns.

      InValid = 1'b1;
      if (pat != 0) begin
        InData_row1 = 17'sd0;
        InData_row2 = 17'sd0;
        InData_row3 = 17'sd0;
        @(posedge clk); cycle = cycle + 1;
      end

      InData_row1 = in_col[pat][0][0];
      InData_row2 = in_col[pat][0][1];
      InData_row3 = in_col[pat][0][2];
      @(posedge clk); cycle = cycle + 1;

      InData_row1 = in_col[pat][1][0];
      InData_row2 = in_col[pat][1][1];
      InData_row3 = in_col[pat][1][2];
      @(posedge clk); cycle = cycle + 1;

      InData_row1 = in_col[pat][2][0];
      InData_row2 = in_col[pat][2][1];
      InData_row3 = in_col[pat][2][2];
      @(posedge clk); cycle = cycle + 1;
      InValid = 1'b0;

      // Wait for iteration done
      while (!OutValid && wait_cycles < TIMEOUT_CYCLES) begin
        @(posedge clk);
        cycle = cycle + 1;
        wait_cycles = wait_cycles + 1;
      end

      if (!OutValid) begin
        $display("FAIL: timeout waiting for OutValid for pattern %0d after %0d cycles", pat+1, wait_cycles);
        fail_cnt = fail_cnt + 1;
        $finish;
      end

      $display("OutValid first asserted at cycle %0d (waited %0d after input)", cycle, wait_cycles);

      check_out(pat, 0, golden_out[pat][0][0], golden_out[pat][0][1], golden_out[pat][0][2]);
      @(posedge clk); cycle = cycle + 1;
      check_out(pat, 1, golden_out[pat][1][0], golden_out[pat][1][1], golden_out[pat][1][2]);
      @(posedge clk); cycle = cycle + 1;
      check_out(pat, 2, golden_out[pat][2][0], golden_out[pat][2][1], golden_out[pat][2][2]);
      @(posedge clk); cycle = cycle + 1;
      check_out(pat, 3, golden_out[pat][3][0], golden_out[pat][3][1], golden_out[pat][3][2]);

      // Ensure "one iteration ended" before next input (extra guard cycles, same as tb_top)
      repeat (4) begin
        @(posedge clk);
        cycle = cycle + 1;
      end
    end

    $display("");
    $display("=== tb_top_all summary: %0d passed, %0d failed ===", pass_cnt, fail_cnt);
    if (fail_cnt != 0)
      $fatal(1, "Simulation failed");
    $finish;
  end

endmodule

