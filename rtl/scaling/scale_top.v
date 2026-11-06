// ============================================================
// scale_top.v - Synthesis wrapper for the scaling experiment (out-of-context)
//   Matrices come in as ports so Vivado cannot pre-compute anything.
//   Fault injection is tied off, so its logic is removed from the resource counts.
//   Set N with: Settings -> General -> Generics/Parameters (N=2, 4 or 8)
// ============================================================
module scale_top #(parameter N = 4) (
    input  wire             clk,
    input  wire             rst,
    input  wire             start,
    input  wire [8*N*N-1:0] a_flat,
    input  wire [8*N*N-1:0] b_flat,
    output wire             done,
    output wire             light_err,
    output wire             trad_err,
    output wire [N-1:0]     trad_col
);
    abft_core_n #(.N(N)) u_core (
        .clk(clk), .rst(rst), .start(start), .a_flat(a_flat), .b_flat(b_flat),
        .f_type(3'd0), .f_pe(8'd0), .f_bit(4'd0),
        .done(done), .light_err(light_err), .trad_err(trad_err),
        .trad_col(trad_col), .trad_row()
    );
endmodule
