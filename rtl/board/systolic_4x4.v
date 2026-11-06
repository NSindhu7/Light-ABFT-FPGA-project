// ============================================================
// systolic_4x4.v - 4x4 weight-stationary systolic array
//   PE(z,y) stores B[z][y]; row z gets column z of A (skewed);
//   column y outputs column y of C at the bottom.
//   f_pe = 4*z + y selects which PE receives the injected fault.
// ============================================================
module systolic_4x4 (
    input  wire         clk,
    input  wire         rst,
    input  wire         load_b,
    input  wire [127:0] b_flat,
    input  wire [2:0]   f_type,
    input  wire [3:0]   f_pe,
    input  wire [3:0]   f_bit,
    input  wire [31:0]  a_left,
    output wire [71:0]  c_bottom
);
    wire [7:0]  a_bus [0:3][0:4];
    wire [17:0] s_bus [0:4][0:3];

    genvar z, y;
    generate
        for (z = 0; z < 4; z = z + 1) begin : g_row
            assign a_bus[z][0] = a_left[8*z +: 8];
        end
        for (y = 0; y < 4; y = y + 1) begin : g_top
            assign s_bus[0][y]          = 18'd0;
            assign c_bottom[18*y +: 18] = s_bus[4][y];
        end
        for (z = 0; z < 4; z = z + 1) begin : g_r
            for (y = 0; y < 4; y = y + 1) begin : g_c
                pe u_pe (
                    .clk    (clk),
                    .rst    (rst),
                    .load_b (load_b),
                    .b_in   (b_flat[8*(4*z+y) +: 8]),
                    .f_sel  (f_pe == (4*z + y)),
                    .f_type (f_type),
                    .f_bit  (f_bit),
                    .a_in   (a_bus[z][y]),
                    .sum_in (s_bus[z][y]),
                    .a_out  (a_bus[z][y+1]),
                    .sum_out(s_bus[z+1][y])
                );
            end
        end
    endgenerate
endmodule
