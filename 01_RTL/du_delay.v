// Fixed-latency delay unit (DU) for inter-row alignment in the systolic mesh.
// Path: PE11 Y_out -> PE22 X_in (VEC22 = ROT12_1 + PE_LAT = 27).
module du_delay #(
    parameter WIDTH = 17,
    parameter DEPTH = 12
) (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 en,
    input  wire signed [WIDTH-1:0] din,
    output wire signed [WIDTH-1:0] dout
);

    reg signed [WIDTH-1:0] shift [0:DEPTH-1];
    integer i;

    assign dout = shift[DEPTH-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < DEPTH; i = i + 1)
                shift[i] <= {WIDTH{1'b0}};
        end else if (en) begin
            shift[0] <= din;
            for (i = 1; i < DEPTH; i = i + 1)
                shift[i] <= shift[i - 1];
        end
    end

endmodule
