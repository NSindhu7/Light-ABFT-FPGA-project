// ============================================================
// pe.v - One Processing Element (weight-stationary MAC)
//   sum_out = sum_in + a_in * b      (a passed right, sum passed down)
//
// Fault injection (active only when f_sel = 1, i.e. this PE is targeted):
//   f_type = 1 : bit flip in the stored weight b      (persistent upset)
//   f_type = 2 : multiplier output bit stuck-at-0
//   f_type = 3 : multiplier output bit stuck-at-1
//   f_bit selects which bit.
// ============================================================
module pe (
    input  wire        clk,
    input  wire        rst,
    input  wire        load_b,
    input  wire [7:0]  b_in,
    input  wire        f_sel,
    input  wire [2:0]  f_type,
    input  wire [3:0]  f_bit,
    input  wire [7:0]  a_in,
    input  wire [17:0] sum_in,
    output reg  [7:0]  a_out,
    output reg  [17:0] sum_out
);
    reg  [7:0]  b_reg;

    wire [7:0]  b_mask   = 8'd1 << f_bit;
    wire [7:0]  b_eff    = (f_sel && f_type == 3'd1) ? (b_reg ^ b_mask) : b_reg;

    wire [15:0] prod_raw = a_in * b_eff;
    wire [15:0] p_mask   = 16'd1 << f_bit;
    wire [15:0] prod     = (f_sel && f_type == 3'd2) ? (prod_raw & ~p_mask) :
                           (f_sel && f_type == 3'd3) ? (prod_raw |  p_mask) :
                                                        prod_raw;

    always @(posedge clk) begin
        if (rst) begin
            b_reg   <= 8'd0;
            a_out   <= 8'd0;
            sum_out <= 18'd0;
        end else begin
            if (load_b)
                b_reg <= b_in;
            a_out   <= a_in;
            sum_out <= sum_in + prod;
        end
    end
endmodule
