// ============================================================
// abft_core.v - 4x4 systolic array + Light ABFT + Traditional ABFT
//   Used directly by the fault-campaign testbench and wrapped by top.v
//   for the board.
//   Matrices: A, B = constant matrix + data_sw (data_sw = 0 -> sum(C) = 852)
//   Fault inputs: f_type (0 none, 1 weight flip, 2 prod stuck-0,
//                 3 prod stuck-1, 4 Light-ABFT checker fault),
//                 f_pe (4*z + y), f_bit.
// ============================================================
module abft_core (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [3:0]  data_sw,
    input  wire [2:0]  f_type,
    input  wire [3:0]  f_pe,
    input  wire [3:0]  f_bit,
    output wire        done,
    output reg         light_err,
    output reg         trad_err,
    output reg  [3:0]  trad_col,
    output reg  [3:0]  trad_row
);
    // A[x][z] at [8*(4*x+z) +: 8]; each line is one row RIGHT-TO-LEFT
    localparam [127:0] A_FLAT = {
        8'd16, 8'd15, 8'd14, 8'd13,
        8'd12, 8'd11, 8'd10, 8'd9,
        8'd8,  8'd7,  8'd6,  8'd5,
        8'd4,  8'd3,  8'd2,  8'd1
    };
    // B[z][y] at [8*(4*z+y) +: 8]; rows: 1 0 2 1 / 3 1 4 2 / 2 2 1 0 / 1 3 0 2
    localparam [127:0] B_FLAT = {
        8'd2,  8'd0,  8'd3,  8'd1,
        8'd0,  8'd1,  8'd2,  8'd2,
        8'd2,  8'd4,  8'd1,  8'd3,
        8'd1,  8'd2,  8'd0,  8'd1
    };

    wire [127:0] a_flat, b_flat;
    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : g_mat
            assign a_flat[8*gi +: 8] = A_FLAT[8*gi +: 8] + {4'd0, data_sw};
            assign b_flat[8*gi +: 8] = B_FLAT[8*gi +: 8] + {4'd0, data_sw};
        end
    endgenerate

    // ---------------- FSM ----------------
    localparam S_IDLE = 3'd0, S_LOAD = 3'd1, S_RUN = 3'd2,
               S_CHECK = 3'd3, S_FINISH = 3'd4, S_DONE = 3'd5;

    reg [2:0] state;
    reg [3:0] cnt;
    reg [1:0] mac_idx;
    wire      light_mm, t_err;
    wire [3:0] t_row, t_col;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; cnt <= 4'd0; mac_idx <= 2'd0;
            light_err <= 1'b0; trad_err <= 1'b0;
            trad_col <= 4'd0;  trad_row <= 4'd0;
        end else begin
            case (state)
                S_IDLE:   if (start) state <= S_LOAD;
                S_LOAD:   begin cnt <= 4'd0; state <= S_RUN; end
                S_RUN:    if (cnt == 4'd11) begin
                              mac_idx <= 2'd0; state <= S_CHECK;
                          end else cnt <= cnt + 4'd1;
                S_CHECK:  if (mac_idx == 2'd3) state <= S_FINISH;
                          else mac_idx <= mac_idx + 2'd1;
                S_FINISH: begin
                              light_err <= light_mm;
                              trad_err  <= t_err;
                              trad_col  <= t_col;
                              trad_row  <= t_row;
                              state     <= S_DONE;
                          end
                S_DONE:   if (start) state <= S_LOAD;
                default:  state <= S_IDLE;
            endcase
        end
    end

    assign done = (state == S_DONE);

    // ---------------- input skewing ----------------
    reg [31:0] a_left;
    integer z;
    always @* begin
        a_left = 32'd0;
        if (state == S_RUN)
            for (z = 0; z < 4; z = z + 1)
                if ((cnt >= z) && (cnt <= z + 3))
                    a_left[8*z +: 8] = a_flat[8*(4*(cnt - z) + z) +: 8];
    end

    // ---------------- datapath ----------------
    wire [71:0] c_bottom;

    systolic_4x4 u_array (
        .clk(clk), .rst(rst), .load_b(state == S_LOAD), .b_flat(b_flat),
        .f_type(f_type), .f_pe(f_pe), .f_bit(f_bit),
        .a_left(a_left), .c_bottom(c_bottom)
    );

    light_abft u_abft (
        .clk(clk), .rst(rst), .clear(state == S_LOAD), .load_svb(state == S_LOAD),
        .accumulate(state == S_RUN), .mac_en(state == S_CHECK), .mac_idx(mac_idx),
        .a_left(a_left), .b_flat(b_flat), .c_bottom(c_bottom),
        .f_type(f_type), .f_pe(f_pe), .f_bit(f_bit),
        .L(), .sum_c(), .mismatch(light_mm)
    );

    trad_abft u_trad (
        .clk(clk), .rst(rst), .clear(state == S_LOAD), .load_svb(state == S_LOAD),
        .accumulate(state == S_RUN), .mac_en(state == S_CHECK), .mac_idx(mac_idx),
        .cnt(cnt), .a_left(a_left), .a_flat(a_flat), .b_flat(b_flat),
        .c_bottom(c_bottom), .err_row(t_row), .err_col(t_col), .err(t_err)
    );

    // ---------------- capture C (simulation / debug) ----------------
    reg [17:0] c_mat [0:3][0:3];
    integer yy;
    always @(posedge clk) begin
        if (state == S_RUN)
            for (yy = 0; yy < 4; yy = yy + 1)
                if ((cnt >= yy + 4) && (cnt <= yy + 7))
                    c_mat[cnt - yy - 4][yy] <= c_bottom[18*yy +: 18];
    end
endmodule
