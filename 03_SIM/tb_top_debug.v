`timescale 1ns / 1ps

module tb_top_debug;

  localparam CLK_HALF = 5;

  reg clk, rst_n, InValid;
  reg signed [17:0] InData_row1, InData_row2, InData_row3;
  wire signed [17:0] OutData_row1, OutData_row2, OutData_row3;
  wire OutValid;

  integer cycle;

  qrd_top uut (
      .clk(clk), .rst_n(rst_n), .InValid(InValid),
      .InData_row1(InData_row1), .InData_row2(InData_row2), .InData_row3(InData_row3),
      .OutData_row1(OutData_row1), .OutData_row2(OutData_row2), .OutData_row3(OutData_row3),
      .OutValid(OutValid)
  );

  initial begin clk = 0; forever #(CLK_HALF) clk = ~clk; end

  task show_M;
    input string tag;
    begin
      $display("%s @cyc=%0d st=%0d iter=%0d ph=%0d | R: %0d %0d %0d / %0d %0d / %0d",
        tag, cycle, uut.state, uut.iter_cnt, uut.phase_timer,
        uut.M_11, uut.M_12, uut.M_13, uut.M_22, uut.M_23, uut.M_33);
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

    repeat (120) begin
      @(posedge clk);
      cycle++;
      if (uut.qr_active && uut.iter_cnt == 0 && (
          uut.phase_timer == 29 || uut.phase_timer == 30 || uut.phase_timer == 31 ||
          uut.phase_timer == 44 || uut.phase_timer == 45))
        show_M("QR_CAP");
      if (uut.rot_pipe_active && uut.iter_cnt == 0 && (
          uut.phase_timer == 29 || uut.phase_timer == 30 || uut.phase_timer == 31 ||
          uut.phase_timer == 44 || uut.phase_timer == 45 ||
          uut.phase_timer == 32 || uut.phase_timer == 33 || uut.phase_timer == 48))
        show_M("ROT_CAP");
      if (uut.rot_pipe_active && uut.iter_cnt == 0 && (
          uut.phase_timer == 48 || uut.phase_timer == 50)) begin
        show_M("ROT_END");
        $display("  U row0: %0d %0d %0d", uut.U_buf[0][0], uut.U_buf[0][1], uut.U_buf[0][2]);
        $display("  U row1: %0d %0d %0d", uut.U_buf[1][0], uut.U_buf[1][1], uut.U_buf[1][2]);
        $display("  U row2: %0d %0d %0d", uut.U_buf[2][0], uut.U_buf[2][1], uut.U_buf[2][2]);
      end
      if (uut.qr_active && uut.iter_cnt == 0 && uut.phase_timer == 45)
        show_M("QR_END");
      if (uut.state == uut.ST_ROT_PIPE && uut.iter_cnt == 0 && uut.phase_timer == 0)
        show_M("ROT_START");
    end
    $finish;
  end
endmodule
