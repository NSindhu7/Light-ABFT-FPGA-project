`timescale 1ns / 1ps
// ============================================================
// tb_campaign.v - Automated fault-injection campaign
//
// For every fault site and every data pattern (data_sw = 0..15):
//   run one matrix multiplication, compare C with the golden C,
//   and record what Light ABFT and Traditional ABFT reported.
//
// Fault types:
//   1 = weight bit flip      (16 PEs x 8 bits)
//   2 = product stuck-at-0   (16 PEs x 16 bits)
//   3 = product stuck-at-1   (16 PEs x 16 bits)
//   4 = fault inside Light ABFT checker (4 SV_B registers x 10 bits)
//
// Outcome per run (Light ABFT):
//   DETECTED    = C wrong, error flagged
//   MISSED      = C wrong, no error flagged       (silent data corruption)
//   MASKED      = C correct, no error flagged     (fault had no effect)
//   FALSE_ALARM = C correct, error flagged
//
// Every run is written to fault_campaign.csv; a summary is printed at the end.
//
// Experiment 1 (added): every corrupted output is classified into the paper's
// error categories (Section 5, Table 2): SINGLE, PARTIAL_LINE, FULL_LINE,
// FULL_MATRIX, RANDOM.
// ============================================================
module tb_campaign;
    reg        clk = 0, rst = 1, start = 0;
    reg  [3:0] data = 4'd0;
    reg  [2:0] f_type = 3'd0;
    reg  [3:0] f_pe = 4'd0, f_bit = 4'd0;
    wire       done, light_err, trad_err;
    wire [3:0] trad_col, trad_row;

    abft_core dut (
        .clk(clk), .rst(rst), .start(start), .data_sw(data),
        .f_type(f_type), .f_pe(f_pe), .f_bit(f_bit),
        .done(done), .light_err(light_err), .trad_err(trad_err),
        .trad_col(trad_col), .trad_row(trad_row)
    );

    always #5 clk = ~clk;

    integer A0 [0:15];   // A0[4*x + z]
    integer B0 [0:15];   // B0[4*z + y]
    integer gold [0:15]; // gold[4*x + y]
    integer x, y, z, d, t, p, b, i, npe, nbits, fcsv, corrupted, located;
    integer runs [0:4], corr [0:4], det [0:4], miss [0:4], msk [0:4], fa [0:4];
    integer tdet [0:4], tloc [0:4], tfa [0:4];
    integer s_corr, s_det, s_tdet, s_tloc, s_runs, s_fa;
    // Experiment 1: error-pattern categories (0 single, 1 partial line,
    // 2 full line, 3 full matrix, 4 random), per fault type 1-3
    integer cat [0:4];
    integer cat_t [1:3][0:4];
    integer nwrong, row_mask, col_mask, nrows, ncols, pattern, j;
    real    pc;
    real    r1, r2, r3, r4;

    task make_golden(input integer dd);
        begin
            for (x = 0; x < 4; x = x + 1)
                for (y = 0; y < 4; y = y + 1) begin
                    gold[4*x + y] = 0;
                    for (z = 0; z < 4; z = z + 1)
                        gold[4*x + y] = gold[4*x + y] + (A0[4*x + z] + dd) * (B0[4*z + y] + dd);
                end
        end
    endtask

    task run_once;
        begin
            @(negedge clk) start = 1;
            @(negedge clk) start = 0;
            wait (done == 1'b1);
            @(negedge clk);
        end
    endtask

    task record(input integer tt);
        begin
            corrupted = 0;
            for (i = 0; i < 16; i = i + 1)
                if (dut.c_mat[i / 4][i % 4] !== gold[i]) corrupted = 1;

            // ---- Experiment 1: classify the error pattern ----
            nwrong = 0; row_mask = 0; col_mask = 0;
            for (i = 0; i < 16; i = i + 1)
                if (dut.c_mat[i / 4][i % 4] !== gold[i]) begin
                    nwrong   = nwrong + 1;
                    row_mask = row_mask | (1 << (i / 4));
                    col_mask = col_mask | (1 << (i % 4));
                end
            nrows = 0; ncols = 0;
            for (j = 0; j < 4; j = j + 1) begin
                if (row_mask & (1 << j)) nrows = nrows + 1;
                if (col_mask & (1 << j)) ncols = ncols + 1;
            end
            pattern = -1;
            if (nwrong == 1)                       pattern = 0;  // single
            else if (nwrong == 16)                 pattern = 3;  // full matrix
            else if (nrows == 1 || ncols == 1)     pattern = (nwrong == 4) ? 2 : 1;  // full / partial line
            else if (nwrong > 0)                   pattern = 4;  // random
            if (pattern >= 0 && tt >= 1 && tt <= 3) begin
                cat[pattern] = cat[pattern] + 1;
                cat_t[tt][pattern] = cat_t[tt][pattern] + 1;
            end

            located = (tt >= 1 && tt <= 3) && (trad_col == (4'b0001 << (p % 4)));

            runs[tt] = runs[tt] + 1;
            if (corrupted) begin
                corr[tt] = corr[tt] + 1;
                if (light_err) det[tt]  = det[tt] + 1;
                else           miss[tt] = miss[tt] + 1;
                if (trad_err)  tdet[tt] = tdet[tt] + 1;
                if (trad_err && located) tloc[tt] = tloc[tt] + 1;
            end else begin
                if (light_err) fa[tt]  = fa[tt] + 1;
                else           msk[tt] = msk[tt] + 1;
                if (trad_err)  tfa[tt] = tfa[tt] + 1;
            end

            $fwrite(fcsv, "%0d,%0d,%0d,%0d,%0d,%0d,", tt, p, b, d, corrupted, light_err);
            if (corrupted && light_err)        $fwrite(fcsv, "DETECTED");
            else if (corrupted && !light_err)  $fwrite(fcsv, "MISSED");
            else if (!corrupted && light_err)  $fwrite(fcsv, "FALSE_ALARM");
            else                               $fwrite(fcsv, "MASKED");
            $fwrite(fcsv, ",%0d,%b,", trad_err, trad_col);
            if (pattern == 0)      $fwrite(fcsv, "SINGLE\n");
            else if (pattern == 1) $fwrite(fcsv, "PARTIAL_LINE\n");
            else if (pattern == 2) $fwrite(fcsv, "FULL_LINE\n");
            else if (pattern == 3) $fwrite(fcsv, "FULL_MATRIX\n");
            else if (pattern == 4) $fwrite(fcsv, "RANDOM\n");
            else                   $fwrite(fcsv, "NONE\n");
        end
    endtask

    initial begin
        // Same matrices as abft_core.v
        for (i = 0; i < 16; i = i + 1) A0[i] = i + 1;
        B0[0]=1;  B0[1]=0;  B0[2]=2;  B0[3]=1;
        B0[4]=3;  B0[5]=1;  B0[6]=4;  B0[7]=2;
        B0[8]=2;  B0[9]=2;  B0[10]=1; B0[11]=0;
        B0[12]=1; B0[13]=3; B0[14]=0; B0[15]=2;

        for (i = 0; i <= 4; i = i + 1) begin
            runs[i]=0; corr[i]=0; det[i]=0; miss[i]=0; msk[i]=0; fa[i]=0;
            tdet[i]=0; tloc[i]=0; tfa[i]=0;
            cat[i]=0;
        end
        for (t = 1; t <= 3; t = t + 1)
            for (i = 0; i <= 4; i = i + 1) cat_t[t][i] = 0;

        fcsv = $fopen("fault_campaign.csv", "w");
        $fwrite(fcsv, "fault_type,pe,bit,data,c_corrupted,light_error,light_outcome,trad_error,trad_col,error_pattern\n");

        repeat (5) @(posedge clk);
        rst = 0;

        // ---------- Baseline: no fault, all 16 data patterns ----------
        f_type = 3'd0; p = 0; b = 0;
        for (d = 0; d < 16; d = d + 1) begin
            data = d; make_golden(d);
            run_once;
            record(0);
        end

        // ---------- Fault campaign ----------
        for (t = 1; t <= 4; t = t + 1) begin
            npe   = (t == 4) ? 4 : 16;
            nbits = (t == 1) ? 8 : ((t == 4) ? 10 : 16);
            for (p = 0; p < npe; p = p + 1)
                for (b = 0; b < nbits; b = b + 1)
                    for (d = 0; d < 16; d = d + 1) begin
                        data = d; f_type = t; f_pe = p; f_bit = b;
                        make_golden(d);
                        run_once;
                        record(t);
                    end
            $display("Fault type %0d finished (%0d runs)", t, runs[t]);
        end
        f_type = 3'd0;
        $fclose(fcsv);

        // ---------- Summary ----------
        $display("\n================ FAULT CAMPAIGN SUMMARY ================");
        $display("Baseline (no fault): runs=%0d  C wrong=%0d  Light false alarms=%0d  Trad false alarms=%0d",
                 runs[0], corr[0], fa[0], tfa[0]);
        $display("Type 1 = weight bit flip, 2 = product stuck-at-0, 3 = product stuck-at-1, 4 = Light checker fault");
        for (t = 1; t <= 4; t = t + 1)
            $display("Type %0d: runs=%0d  C_wrong=%0d  DETECTED=%0d  MISSED=%0d  MASKED=%0d  FALSE_ALARM=%0d | Trad detected=%0d  Trad located=%0d",
                     t, runs[t], corr[t], det[t], miss[t], msk[t], fa[t], tdet[t], tloc[t]);

        s_corr = corr[1] + corr[2] + corr[3];
        s_det  = det[1]  + det[2]  + det[3];
        s_tdet = tdet[1] + tdet[2] + tdet[3];
        s_tloc = tloc[1] + tloc[2] + tloc[3];
        s_runs = runs[1] + runs[2] + runs[3] + runs[4];
        s_fa   = fa[1] + fa[2] + fa[3] + fa[4];

        r1 = (s_corr > 0) ? 100.0 * s_det  / s_corr : 0.0;
        r2 = (s_corr > 0) ? 100.0 * s_tdet / s_corr : 0.0;
        r3 = (s_corr > 0) ? 100.0 * s_tloc / s_corr : 0.0;
        r4 = 100.0 * s_fa / s_runs;

        $display("--------------------------------------------------------");
        $display("Array faults (types 1-3): runs with wrong C = %0d", s_corr);
        $display("  Light ABFT detection rate        = %0.2f %%", r1);
        $display("  Traditional ABFT detection rate  = %0.2f %%", r2);
        $display("  Traditional ABFT correct column  = %0.2f %%", r3);
        $display("Light ABFT false-alarm rate (all %0d fault runs) = %0.2f %%", s_runs, r4);
        $display("Light ABFT false alarms by type: 3 -> %0d, 4 -> %0d ; Traditional false alarms: 3 -> %0d, 4 -> %0d",
                 fa[3], fa[4], tfa[3], tfa[4]);

        // ---------- Experiment 1: error-pattern distribution ----------
        $display("--------------------------------------------------------");
        $display("ERROR PATTERN DISTRIBUTION (array faults, corrupted runs = %0d)", s_corr);
        $display("Pattern        Count    Ours     Paper (Table 2)");
        pc = (s_corr > 0) ? 100.0 * cat[0] / s_corr : 0.0;
        $display("Single         %5d   %6.2f %%   27.07 %%", cat[0], pc);
        pc = (s_corr > 0) ? 100.0 * cat[1] / s_corr : 0.0;
        $display("Partial line   %5d   %6.2f %%   43.28 %%", cat[1], pc);
        pc = (s_corr > 0) ? 100.0 * cat[2] / s_corr : 0.0;
        $display("Full line      %5d   %6.2f %%   26.68 %%", cat[2], pc);
        pc = (s_corr > 0) ? 100.0 * cat[3] / s_corr : 0.0;
        $display("Full matrix    %5d   %6.2f %%    0.25 %%", cat[3], pc);
        pc = (s_corr > 0) ? 100.0 * cat[4] / s_corr : 0.0;
        $display("Random         %5d   %6.2f %%    2.72 %%", cat[4], pc);
        for (t = 1; t <= 3; t = t + 1)
            $display("  Type %0d: single=%0d partial=%0d full_line=%0d full_matrix=%0d random=%0d",
                     t, cat_t[t][0], cat_t[t][1], cat_t[t][2], cat_t[t][3], cat_t[t][4]);
        $display("Detailed results: fault_campaign.csv");
        $display("========================================================\n");
        $finish;
    end
endmodule
