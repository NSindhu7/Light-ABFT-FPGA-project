// ============================================================
// light_abft_n.v - Light ABFT for an N x N array
//   L = SV_A . SV_B computed with ONE multiplier over N cycles,
//   compared with the sum of all elements of C.
//   f_type 4 = bit flip in SV_B[f_pe mod N] (checker fault)
// ============================================================
module light_abft_n #(parameter N = 4, SW = 18, VW = 10, CW = 24, IW = 2) (
    input  wire              clk,
    input  wire              rst,
    input  wire              clear,
    input  wire              load_svb,
    input  wire              accumulate,
    input  wire              mac_en,
    input  wire [IW-1:0]     mac_idx,
    input  wire [8*N-1:0]    a_left,
    input  wire [8*N*N-1:0]  b_flat,
    input  wire [SW*N-1:0]   c_bottom,
    input  wire [2:0]        f_type,
    input  wire [7:0]        f_pe,
    input  wire [3:0]        f_bit,
    output reg  [CW-1:0]     L,
    output reg  [CW-1:0]     sum_c,
    output wire              mismatch
);
    reg [VW-1:0] sva [0:N-1];
    reg [VW-1:0] svb [0:N-1];
    reg [VW-1:0] rs;
    reg [CW-1:0] col_sum;
    integer k, m, y, q;

    // Input checksum of B (row sums), computed when B is loaded
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

    // Sum of the N outputs leaving the array this cycle
    always @* begin
        col_sum = {CW{1'b0}};
        for (q = 0; q < N; q = q + 1)
            col_sum = col_sum + c_bottom[SW*q +: SW];
    end

    wire          chk_fault = (f_type == 3'd4) && (f_pe[IW-1:0] == mac_idx);
    wire [VW-1:0] svb_sel   = svb[mac_idx] ^ (chk_fault ? ({{(VW-1){1'b0}}, 1'b1} << f_bit) : {VW{1'b0}});

    always @(posedge clk) begin
        if (rst || clear) begin
            for (k = 0; k < N; k = k + 1) sva[k] <= {VW{1'b0}};
            L     <= {CW{1'b0}};
            sum_c <= {CW{1'b0}};
        end else begin
            if (accumulate) begin
                for (k = 0; k < N; k = k + 1)
                    sva[k] <= sva[k] + a_left[8*k +: 8];
                sum_c <= sum_c + col_sum;
            end
            if (mac_en)
                L <= L + sva[mac_idx] * svb_sel;
        end
    end

    assign mismatch = (sum_c != L);
endmodule
