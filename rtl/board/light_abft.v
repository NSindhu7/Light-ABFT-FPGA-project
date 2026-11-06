// ============================================================
// light_abft.v - Light ABFT (paper Section 6, Fig. 8)
//   L = SV_A . SV_B (ONE multiplier, 4 cycles), compared with sum(C).
//   f_type = 4 : fault inside this checker (bit flip in SV_B[f_pe[1:0]],
//                bit f_bit) - used to measure false detections.
// ============================================================
module light_abft (
    input  wire         clk,
    input  wire         rst,
    input  wire         clear,
    input  wire         load_svb,
    input  wire         accumulate,
    input  wire         mac_en,
    input  wire [1:0]   mac_idx,
    input  wire [31:0]  a_left,
    input  wire [127:0] b_flat,
    input  wire [71:0]  c_bottom,
    input  wire [2:0]   f_type,
    input  wire [3:0]   f_pe,
    input  wire [3:0]   f_bit,
    output reg  [23:0]  L,
    output reg  [23:0]  sum_c,
    output wire         mismatch
);
    reg [9:0] sva [0:3];
    reg [9:0] svb [0:3];
    integer k, m;

    always @(posedge clk) begin
        if (rst) begin
            for (m = 0; m < 4; m = m + 1) svb[m] <= 10'd0;
        end else if (load_svb) begin
            for (m = 0; m < 4; m = m + 1)
                svb[m] <= b_flat[8*(4*m+0) +: 8] + b_flat[8*(4*m+1) +: 8]
                        + b_flat[8*(4*m+2) +: 8] + b_flat[8*(4*m+3) +: 8];
        end
    end

    // SV_B value used by the MAC, with optional checker fault
    wire       chk_fault = (f_type == 3'd4) && (f_pe[1:0] == mac_idx);
    wire [9:0] svb_sel   = svb[mac_idx] ^ (chk_fault ? (10'd1 << f_bit) : 10'd0);

    always @(posedge clk) begin
        if (rst || clear) begin
            for (k = 0; k < 4; k = k + 1) sva[k] <= 10'd0;
            L     <= 24'd0;
            sum_c <= 24'd0;
        end else begin
            if (accumulate) begin
                for (k = 0; k < 4; k = k + 1)
                    sva[k] <= sva[k] + a_left[8*k +: 8];
                sum_c <= sum_c + c_bottom[17:0]  + c_bottom[35:18]
                               + c_bottom[53:36] + c_bottom[71:54];
            end
            if (mac_en)
                L <= L + sva[mac_idx] * svb_sel;
        end
    end

    assign mismatch = (sum_c != L);
endmodule
