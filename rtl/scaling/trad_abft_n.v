// ============================================================
// trad_abft_n.v - Traditional ABFT (row + column checksums) for N x N
//   exp_row[x] = sum_z A[x][z]*SV_B[z]   (N multipliers)
//   exp_col[y] = sum_z SV_A[z]*B[z][y]   (N multipliers)
//   corner     = SV_A . SV_B             (1 multiplier)  -> 2N+1 multipliers
// ============================================================
module trad_abft_n #(parameter N = 4, SW = 18, VW = 10, CW = 24, IW = 2, CNTW = 5) (
    input  wire              clk,
    input  wire              rst,
    input  wire              clear,
    input  wire              load_svb,
    input  wire              accumulate,
    input  wire              mac_en,
    input  wire [IW-1:0]     mac_idx,
    input  wire [CNTW-1:0]   cnt,
    input  wire [8*N-1:0]    a_left,
    input  wire [8*N*N-1:0]  a_flat,
    input  wire [8*N*N-1:0]  b_flat,
    input  wire [SW*N-1:0]   c_bottom,
    output wire [N-1:0]      err_row,
    output wire [N-1:0]      err_col,
    output wire              err
);
    reg [VW-1:0] sva [0:N-1];
    reg [VW-1:0] svb [0:N-1];
    reg [CW-1:0] exp_row [0:N-1];
    reg [CW-1:0] exp_col [0:N-1];
    reg [CW-1:0] act_row [0:N-1];
    reg [CW-1:0] act_col [0:N-1];
    reg [CW-1:0] corner;
    reg [VW-1:0] rs;
    reg [CW-1:0] row_total;
    integer k, m, x, y, q;

    always @(posedge clk) begin
        if (rst) begin
            for (m = 0; m < N; m = m + 1) svb[m] <= {VW{1'b0}};
        end else if (load_svb) begin
            for (m = 0; m < N; m = m + 1) begin
                rs = {VW{1'b0}};
                for (y = 0; y < N; y = y + 1)
                    rs = rs + b_flat[8*(N*m+y) +: 8];
                svb[m] <= rs;
            end
        end
    end

    always @(posedge clk) begin
        if (rst || clear) begin
            for (k = 0; k < N; k = k + 1) begin
                sva[k] <= {VW{1'b0}};
                exp_row[k] <= {CW{1'b0}}; exp_col[k] <= {CW{1'b0}};
                act_row[k] <= {CW{1'b0}}; act_col[k] <= {CW{1'b0}};
            end
            corner <= {CW{1'b0}};
        end else begin
            if (accumulate) begin
                for (k = 0; k < N; k = k + 1)
                    sva[k] <= sva[k] + a_left[8*k +: 8];
                for (y = 0; y < N; y = y + 1) begin
                    act_col[y] <= act_col[y] + c_bottom[SW*y +: SW];
                    // C[x][y] leaves column y during cycle x + y + N
                    if ((cnt >= y + N) && (cnt <= y + 2*N - 1))
                        act_row[cnt - y - N] <= act_row[cnt - y - N] + c_bottom[SW*y +: SW];
                end
            end
            if (mac_en) begin
                for (x = 0; x < N; x = x + 1)
                    exp_row[x] <= exp_row[x] + a_flat[8*(N*x + mac_idx) +: 8] * svb[mac_idx];
                for (y = 0; y < N; y = y + 1)
                    exp_col[y] <= exp_col[y] + sva[mac_idx] * b_flat[8*(N*mac_idx + y) +: 8];
                corner <= corner + sva[mac_idx] * svb[mac_idx];
            end
        end
    end

    always @* begin
        row_total = {CW{1'b0}};
        for (q = 0; q < N; q = q + 1) row_total = row_total + exp_row[q];
    end

    genvar g;
    generate
        for (g = 0; g < N; g = g + 1) begin : g_cmp
            assign err_row[g] = (act_row[g] != exp_row[g]);
            assign err_col[g] = (act_col[g] != exp_col[g]);
        end
    endgenerate

    assign err = (|err_row) | (|err_col) | (corner != row_total);
endmodule
