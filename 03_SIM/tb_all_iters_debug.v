`timescale 1ns / 1ps

// Dump M_regs and U_buf after each iteration QR (ph=45) and ROT (ph=50).

module tb_all_iters_debug;

  localparam CLK_HALF = 5;

  reg clk, rst_n, InValid;
  reg signed [17:0] InData_row1, InData_row2, InData_row3;

  integer cycle;

  qrd_top uut (
      .clk(clk), .rst_n(rst_n), .InValid(InValid),
      .InData_row1(InData_row1), .InData_row2(InData_row2), .InData_row3(InData_row3),
      .OutData_row1(), .OutData_row2(), .OutData_row3(), .OutValid()
  );

  initial begin clk = 0; forever #(CLK_HALF) clk = ~clk; end

  task dump_checkpoint;
    input string phase;
    input integer iter;
    begin
      $display("RTL %s iter=%0d cyc=%0d | M %0d %0d %0d %0d %0d %0d",
        phase, iter, cycle,
        uut.M_11, uut.M_12, uut.M_13, uut.M_22, uut.M_23, uut.M_33);
      if (phase == "ROT")
        $display("RTL U iter=%0d | %0d %0d %0d | %0d %0d %0d | %0d %0d %0d",
          iter,
          uut.U_buf[0][0], uut.U_buf[0][1], uut.U_buf[0][2],
          uut.U_buf[1][0], uut.U_buf[1][1], uut.U_buf[1][2],
          uut.U_buf[2][0], uut.U_buf[2][1], uut.U_buf[2][2]);
    end
  endtask

  initial begin
    cycle = 0;
    rst_n = 0; InValid = 0;
    InData_row1 = 0; InData_row2 = 0; InData_row3 = 0;
    #(CLK_HALF*4); rst_n = 1;
    @(posedge clk);

    InValid = 1;
    InData_row1 = 18'sd1990; InData_row2 = 18'sd1890; InData_row3 = -18'sd3112;
    @(posedge clk); cycle++;
    InData_row1 = 18'sd1890; InData_row2 = 18'sd4725; InData_row3 = 18'sd5324;
    @(posedge clk); cycle++;
    InData_row1 = -18'sd3112; InData_row2 = 18'sd5324; InData_row3 = 18'sd28281;
    @(posedge clk); cycle++;
    InValid = 0;

    repeat (750) begin
      @(posedge clk);
      cycle++;
      // QR complete: all captures done when ROT starts (ph=0)
      if (uut.rot_pipe_active && uut.phase_timer == 0)
        dump_checkpoint("QR", uut.iter_cnt);
      if (uut.rot_pipe_active && uut.phase_timer == 50)
        dump_checkpoint("ROT", uut.iter_cnt);
    end
    $finish;
  end
endmodule
