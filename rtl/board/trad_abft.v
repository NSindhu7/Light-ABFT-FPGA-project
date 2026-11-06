// ============================================================
// trad_abft.v - Traditional ABFT (Huang & Abraham 1984), detection +
// localization, for cost comparison with Light ABFT.
//   Expected row checksums : exp_row[x] = sum_z A[x][z] * SV_B[z]  (4 multipliers)
//   Expected col checksums : exp_col[y] = sum_z SV_A[z] * B[z][y]  (4 multipliers)
//   Corner                 : SV_A . SV_B                           (1 multiplier)
//   => 2N+1 = 9 multipliers for N = 4  (Light ABFT: 1)
//   Actual row/col sums of C are compared with the expected ones;
//   err_row / err_col show WHERE the error is.
// ============================================================
module trad_abft (
    input  wire         clk,
    input  wire         rst,
    input  wire         clear,
    input  wire         load_svb,
    input  wire         accumulate,
    input  wire         mac_en,
    input  wire [1:0]   mac_idx,
    input  wire [3:0]   cnt,
    input  wire [31:0]  a_left,
    input  wire [127:0] a_flat,
    input  wire [127:0] b_flat,
    input  wire [71:0]  c_bottom,
    output wire [3:0]   err_row,
    output wire [3:0]   err_col,
    output wire         err
);
    reg [9:0]  sva [0:3];
    reg [9:0]  svb [0:3];
    reg [23:0] exp_row [0:3];
    reg [23:0] exp_col [0:3];
    reg [23:0] act_row [0:3];
    reg [23:0] act_col [0:3];
    reg [23:0] corner;
    integer k, m, x, y;

    always @(posedge clk) begin
        if (rst) begin
            for (m = 0; m < 4; m = m + 1) svb[m] <= 10'd0;
        end else if (load_svb) begin
            for (m = 0; m < 4; m = m + 1)
                svb[m] <= b_flat[8*(4*m+0) +: 8] + b_flat[8*(4*m+1) +: 8]
                        + b_flat[8*(4*m+2) +: 8] + b_flat[8*(4*m+3) +: 8];
        end
    end

    always @(posedge clk) begin
        if (rst || clear) begin
            for (k = 0; k < 4; k = k + 1) begin
                sva[k]     <= 10'd0;
                exp_row[k] <= 24'd0;
                exp_col[k] <= 24'd0;
                act_row[k] <= 24'd0;
                act_col[k] <= 24'd0;
            end
            corner <= 24'd0;
        end else begin
            if (accumulate) begin
                for (k = 0; k < 4; k = k + 1)
                    sva[k] <= sva[k] + a_left[8*k +: 8];
                for (y = 0; y < 4; y = y + 1) begin
                    act_col[y] <= act_col[y] + c_bottom[18*y +: 18];
                    // C[x][y] leaves column y during cycle x + y + 4
                    if ((cnt >= y + 4) && (cnt <= y + 7))
                        act_row[cnt - y - 4] <= act_row[cnt - y - 4] + c_bottom[18*y +: 18];
                end
            end
            if (mac_en) begin
                for (x = 0; x < 4; x = x + 1)
                    exp_row[x] <= exp_row[x] + a_flat[8*(4*x + mac_idx) +: 8] * svb[mac_idx];
                for (y = 0; y < 4; y = y + 1)
                    exp_col[y] <= exp_col[y] + sva[mac_idx] * b_flat[8*(4*mac_idx + y) +: 8];
                corner <= corner + sva[mac_idx] * svb[mac_idx];
            end
        end
    end

    genvar g;
    generate
        for (g = 0; g < 4; g = g + 1) begin : g_cmp
            assign err_row[g] = (act_row[g] != exp_row[g]);
            assign err_col[g] = (act_col[g] != exp_col[g]);
        end
    endgenerate

    // Checksum consistency: the corner must equal the sum of the row checksums
    wire corner_err = (corner != (exp_row[0] + exp_row[1] + exp_row[2] + exp_row[3]));

    assign err = (|err_row) | (|err_col) | corner_err;
endmodule
