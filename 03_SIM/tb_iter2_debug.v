`timescale 1ns / 1ps

// Trace iter_cnt==1 (2nd iteration) QR end and ROT end vs bit-true golden.

module tb_iter2_debug;

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

  task dump_M;
    input string tag;
    begin
      $display("%s cyc=%0d iter=%0d st=%0d ph=%0d | M: %0d %0d %0d / %0d %0d / %0d",
        tag, cycle, uut.iter_cnt, uut.state, uut.phase_timer,
        uut.M_11, uut.M_12, uut.M_13, uut.M_22, uut.M_23, uut.M_33);
    end
  endtask

  task dump_U;
    begin
      $display("  U row0: %0d %0d %0d", uut.U_buf[0][0], uut.U_buf[0][1], uut.U_buf[0][2]);
      $display("  U row1: %0d %0d %0d", uut.U_buf[1][0], uut.U_buf[1][1], uut.U_buf[1][2]);
      $display("  U row2: %0d %0d %0d", uut.U_buf[2][0], uut.U_buf[2][1], uut.U_buf[2][2]);
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

    repeat (250) begin
      @(posedge clk);
      cycle++;

      // 2nd iteration QR complete (iter_cnt==1, ph=45)
      if (uut.qr_active && uut.iter_cnt == 1 && uut.phase_timer == 45) begin
        dump_M("ITER2_QR_END");
      end

      // 2nd iteration ROT settled (iter_cnt==1, ph=50)
      if (uut.rot_pipe_active && uut.iter_cnt == 1 && uut.phase_timer == 50) begin
        dump_M("ITER2_ROT_END");
        dump_U;
      end
    end
    $finish;
  end
endmodule
