`timescale 1ns / 1ps
// ============================================================
// tb_scale.v - Self-checking test of the N x N design
//   Part 1: 20 random matrix pairs, no fault  -> C correct, no error flags
//   Part 2: weight bit-0 flip in every PE     -> C wrong, both checkers flag it,
//                                                traditional ABFT names the right column
//   Change N below (2, 4 or 8) and re-run.
// ============================================================
module tb_scale;
    parameter N = 4;

    reg              clk = 0, rst = 1, start = 0;
    reg [8*N*N-1:0]  a_flat, b_flat;
    reg [2:0]        f_type = 0;
    reg [7:0]        f_pe = 0;
    reg [3:0]        f_bit = 0;
    wire             done, light_err, trad_err;
    wire [N-1:0]     trad_col, trad_row;

    abft_core_n #(.N(N)) dut (
        .clk(clk), .rst(rst), .start(start), .a_flat(a_flat), .b_flat(b_flat),
        .f_type(f_type), .f_pe(f_pe), .f_bit(f_bit),
        .done(done), .light_err(light_err), .trad_err(trad_err),
        .trad_col(trad_col), .trad_row(trad_row)
    );

    always #5 clk = ~clk;

    integer gold [0:N*N-1];
    integer x, y, z, t, p, wrong, fails, seed, masked;

    task new_matrices;
        begin
            for (t = 0; t < N*N; t = t + 1) begin
                a_flat[8*t +: 8] = $random(seed);
                b_flat[8*t +: 8] = $random(seed);
            end
            for (x = 0; x < N; x = x + 1)
                for (y = 0; y < N; y = y + 1) begin
                    gold[N*x + y] = 0;
                    for (z = 0; z < N; z = z + 1)
                        gold[N*x + y] = gold[N*x + y] + a_flat[8*(N*x+z) +: 8] * b_flat[8*(N*z+y) +: 8];
                end
        end
    endtask

    task run_once;
        begin
            @(negedge clk) start = 1;
            @(negedge clk) start = 0;
            wait (done == 1'b1);
            @(negedge clk);
            wrong = 0;
            for (t = 0; t < N*N; t = t + 1)
                if (dut.c_mat[t] !== gold[t]) wrong = wrong + 1;
        end
    endtask

    initial begin
        seed = 7; fails = 0; masked = 0;
        repeat (5) @(posedge clk);
        rst = 0;

        // ---------- Part 1: no fault ----------
        f_type = 0;
        for (p = 0; p < 20; p = p + 1) begin
            new_matrices; run_once;
            if (wrong != 0 || light_err !== 1'b0 || trad_err !== 1'b0) begin
                $display("FAIL (no fault) test %0d: wrong=%0d light=%b trad=%b", p, wrong, light_err, trad_err);
                fails = fails + 1;
            end
        end
        $display("N=%0d Part 1 (no fault, 20 tests): %s", N, (fails == 0) ? "PASSED" : "FAILED");

        // ---------- Part 2: one fault in every PE ----------
        f_type = 1; f_bit = 0;
        for (p = 0; p < N*N; p = p + 1) begin
            f_pe = p;
            new_matrices; run_once;
            if (wrong == 0) masked = masked + 1;   // fault had no effect on this data
            else if (light_err !== 1'b1 || trad_err !== 1'b1 || trad_col !== (1 << (p % N))) begin
                $display("FAIL (fault in PE %0d): wrong=%0d light=%b trad=%b col=%b", p, wrong, light_err, trad_err, trad_col);
                fails = fails + 1;
            end
        end
        f_type = 0;
        $display("N=%0d Part 2 (fault in each of %0d PEs, %0d masked): %s", N, N*N, masked, (fails == 0) ? "PASSED" : "FAILED");
        $display("=== N=%0d: %s (%0d failures) ===", N, (fails == 0) ? "ALL TESTS PASSED" : "SOME TESTS FAILED", fails);
        $finish;
    end
endmodule
