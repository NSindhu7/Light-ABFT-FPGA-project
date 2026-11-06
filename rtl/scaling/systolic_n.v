// ============================================================
// systolic_n.v - N x N weight-stationary systolic array
//   PE(z,y) stores B[z][y]; row z gets column z of A (skewed);
//   column y outputs column y of C. f_pe = N*z + y selects the faulty PE.
//   Flat buses: a_left row z at [8*z +: 8]; B[z][y] at [8*(N*z+y) +: 8];
//               c_bottom column y at [SW*y +: SW]
// ============================================================
module systolic_n #(parameter N = 4, parameter SW = 18) (
    input  wire              clk,
    input  wire              rst,
    input  wire              load_b,
    input  wire [8*N*N-1:0]  b_flat,
    input  wire [2:0]        f_type,
    input  wire [7:0]        f_pe,
    input  wire [3:0]        f_bit,
    input  wire [8*N-1:0]    a_left,
    output wire [SW*N-1:0]   c_bottom
);
    wire [7:0]    a_bus [0:N-1][0:N];
    wire [SW-1:0] s_bus [0:N][0:N-1];

    genvar z, y;
    generate
        for (z = 0; z < N; z = z + 1) begin : g_row
            assign a_bus[z][0] = a_left[8*z +: 8];
        end
        for (y = 0; y < N; y = y + 1) begin : g_top
            assign s_bus[0][y]          = {SW{1'b0}};
            assign c_bottom[SW*y +: SW] = s_bus[N][y];
        end
        for (z = 0; z < N; z = z + 1) begin : g_r
            for (y = 0; y < N; y = y + 1) begin : g_c
                pe_n #(.SW(SW)) u_pe (
                    .clk(clk), .rst(rst), .load_b(load_b),
                    .b_in(b_flat[8*(N*z+y) +: 8]),
                    .f_sel(f_pe == (N*z + y)), .f_type(f_type), .f_bit(f_bit),
                    .a_in(a_bus[z][y]), .sum_in(s_bus[z][y]),
                    .a_out(a_bus[z][y+1]), .sum_out(s_bus[z+1][y])
                );
            end
        end
    endgenerate
endmodule
