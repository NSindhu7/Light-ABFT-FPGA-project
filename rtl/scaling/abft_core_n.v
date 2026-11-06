// ============================================================
// abft_core_n.v - N x N systolic array + Light ABFT + Traditional ABFT
//   Change N to scale the whole design (tested sizes: 2, 4, 8).
//   Sequence: LOAD (1) -> RUN (3N cycles) -> CHECK (N cycles) -> FINISH (1) -> DONE
//   A and B come in as flat buses: A[x][z] at [8*(N*x+z) +: 8], B[z][y] at [8*(N*z+y) +: 8]
// ============================================================
module abft_core_n #(parameter N = 4) (
    input  wire             clk,
    input  wire             rst,
    input  wire             start,
    input  wire [8*N*N-1:0] a_flat,
    input  wire [8*N*N-1:0] b_flat,
    input  wire [2:0]       f_type,
    input  wire [7:0]       f_pe,
    input  wire [3:0]       f_bit,
    output wire             done,
    output reg              light_err,
    output reg              trad_err,
    output reg  [N-1:0]     trad_col,
    output reg  [N-1:0]     trad_row
);
    localparam LG   = $clog2(N);
    localparam SW   = 16 + LG;            // partial sums / C elements
    localparam VW   = 8 + LG;             // summation vectors
    localparam CW   = 17 + 3*LG;          // checksums, L, sum(C)
    localparam IW   = (LG < 1) ? 1 : LG;  // index into N
    localparam CNTW = $clog2(3*N) + 1;    // RUN counter

    localparam S_IDLE = 3'd0, S_LOAD = 3'd1, S_RUN = 3'd2,
               S_CHECK = 3'd3, S_FINISH = 3'd4, S_DONE = 3'd5;

    reg [2:0]      state;
    reg [CNTW-1:0] cnt;
    reg [IW-1:0]   mac_idx;
    wire           light_mm, t_err;
    wire [N-1:0]   t_row, t_col;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; cnt <= {CNTW{1'b0}}; mac_idx <= {IW{1'b0}};
            light_err <= 1'b0; trad_err <= 1'b0;
            trad_col <= {N{1'b0}}; trad_row <= {N{1'b0}};
        end else begin
            case (state)
                S_IDLE:   if (start) state <= S_LOAD;
                S_LOAD:   begin cnt <= {CNTW{1'b0}}; state <= S_RUN; end
                S_RUN:    if (cnt == 3*N - 1) begin
                              mac_idx <= {IW{1'b0}}; state <= S_CHECK;
                          end else cnt <= cnt + 1'b1;
                S_CHECK:  if (mac_idx == N - 1) state <= S_FINISH;
                          else mac_idx <= mac_idx + 1'b1;
                S_FINISH: begin
                              light_err <= light_mm; trad_err <= t_err;
                              trad_col  <= t_col;    trad_row <= t_row;
                              state     <= S_DONE;
                          end
                S_DONE:   if (start) state <= S_LOAD;
                default:  state <= S_IDLE;
            endcase
        end
    end
    assign done = (state == S_DONE);

    // Input skewing: during RUN cycle cnt, row z receives A[cnt - z][z]
    reg [8*N-1:0] a_left;
    integer z;
    always @* begin
        a_left = {8*N{1'b0}};
        if (state == S_RUN)
            for (z = 0; z < N; z = z + 1)
                if ((cnt >= z) && (cnt <= z + N - 1))
                    a_left[8*z +: 8] = a_flat[8*(N*(cnt - z) + z) +: 8];
    end

    wire [SW*N-1:0] c_bottom;

    systolic_n #(.N(N), .SW(SW)) u_array (
        .clk(clk), .rst(rst), .load_b(state == S_LOAD), .b_flat(b_flat),
        .f_type(f_type), .f_pe(f_pe), .f_bit(f_bit),
        .a_left(a_left), .c_bottom(c_bottom)
    );

    light_abft_n #(.N(N), .SW(SW), .VW(VW), .CW(CW), .IW(IW)) u_light (
        .clk(clk), .rst(rst), .clear(state == S_LOAD), .load_svb(state == S_LOAD),
        .accumulate(state == S_RUN), .mac_en(state == S_CHECK), .mac_idx(mac_idx),
        .a_left(a_left), .b_flat(b_flat), .c_bottom(c_bottom),
        .f_type(f_type), .f_pe(f_pe), .f_bit(f_bit),
        .L(), .sum_c(), .mismatch(light_mm)
    );

    trad_abft_n #(.N(N), .SW(SW), .VW(VW), .CW(CW), .IW(IW), .CNTW(CNTW)) u_trad (
        .clk(clk), .rst(rst), .clear(state == S_LOAD), .load_svb(state == S_LOAD),
        .accumulate(state == S_RUN), .mac_en(state == S_CHECK), .mac_idx(mac_idx),
        .cnt(cnt), .a_left(a_left), .a_flat(a_flat), .b_flat(b_flat),
        .c_bottom(c_bottom), .err_row(t_row), .err_col(t_col), .err(t_err)
    );

    // Capture C for simulation: C[x][y] at c_mat[N*x + y], leaves column y at cycle x + y + N
    reg [SW-1:0] c_mat [0:N*N-1];
    integer yy;
    always @(posedge clk) begin
        if (state == S_RUN)
            for (yy = 0; yy < N; yy = yy + 1)
                if ((cnt >= yy + N) && (cnt <= yy + 2*N - 1))
                    c_mat[N*(cnt - yy - N) + yy] <= c_bottom[SW*yy +: SW];
    end
endmodule
