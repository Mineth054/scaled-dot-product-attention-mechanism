// Self-checking integration testbench. Owns all file I/O: loads the input
// matrices and golden vector, drives the synthesizable top_level via ports,
// writes data/output.txt and sim/attention.vcd.
//
// N, D and PARALLEL can be overridden at compile time, e.g.
//   iverilog -g2012 -DN=4 -DD=8 -DPARALLEL=1 ...
`ifndef N
 `define N 3
`endif
`ifndef D
 `define D 4
`endif
`ifndef PARALLEL
 `define PARALLEL 0
`endif

module top_level_tb;

    localparam N        = `N;
    localparam D        = `D;
    localparam PARALLEL = `PARALLEL;

    // A carries +/-1 LSB (1/256) error per weight, so the output error
    // budget is proportional to the output scale: tol = ABS + PCT% of
    // max|O_expected|. The ABS floor covers the committed small case.
    localparam integer TOLERANCE_ABS = 32;
    localparam integer TOLERANCE_PCT = 2;

    reg clk;
    reg reset;
    reg start;
    wire done;

    reg signed [7:0] X  [0:N-1][0:D-1];
    reg signed [7:0] WQ [0:D-1][0:D-1];
    reg signed [7:0] WK [0:D-1][0:D-1];
    reg signed [7:0] WV [0:D-1][0:D-1];
    wire signed [31:0] O [0:N-1][0:D-1];

    top_level #(.N(N), .D(D), .PARALLEL(PARALLEL)) uut (
        .clk   (clk),
        .reset (reset),
        .start (start),
        .X     (X),
        .WQ    (WQ),
        .WK    (WK),
        .WV    (WV),
        .O     (O),
        .done  (done)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/attention.vcd");
        $dumpvars(0, top_level_tb);
    end

    // flat memories for $readmemh, copied into the 2-D port arrays
    reg signed [7:0]  X_mem  [0:N*D-1];
    reg signed [7:0]  WQ_mem [0:D*D-1];
    reg signed [7:0]  WK_mem [0:D*D-1];
    reg signed [7:0]  WV_mem [0:D*D-1];
    reg signed [31:0] O_expected [0:N*D-1];
    reg signed [31:0] O_first    [0:N*D-1];

    integer r, c, idx;
    integer errors;
    integer diff;
    integer omax, tol;
    integer fp;
    integer cycles_start, cycles_first;
    reg signed [31:0] got;
    reg signed [31:0] want;

    task pulse_start;
        begin
            start = 1;
            @(posedge clk); #1;
            start = 0;
        end
    endtask

    initial begin
        $readmemh("data/X.txt",  X_mem);
        $readmemh("data/WQ.txt", WQ_mem);
        $readmemh("data/WK.txt", WK_mem);
        $readmemh("data/WV.txt", WV_mem);
        $readmemh("data/O_expected.txt", O_expected);

        for (r = 0; r < N; r = r + 1)
            for (c = 0; c < D; c = c + 1)
                X[r][c] = X_mem[r*D + c];
        for (r = 0; r < D; r = r + 1)
            for (c = 0; c < D; c = c + 1) begin
                WQ[r][c] = WQ_mem[r*D + c];
                WK[r][c] = WK_mem[r*D + c];
                WV[r][c] = WV_mem[r*D + c];
            end

        omax = 0;
        for (idx = 0; idx < N*D; idx = idx + 1) begin
            if (O_expected[idx] >= 0 && O_expected[idx] > omax)
                omax = O_expected[idx];
            if (O_expected[idx] < 0 && -O_expected[idx] > omax)
                omax = -O_expected[idx];
        end
        tol = TOLERANCE_ABS + (TOLERANCE_PCT * omax) / 100;

        reset = 1;
        start = 0;
        @(posedge clk); #1;
        reset = 0;

        // ─── pass 1 ───
        cycles_start = $time;
        pulse_start;
        wait(done == 1);
        cycles_first = ($time - cycles_start) / 10;
        #10;

        for (idx = 0; idx < N*D; idx = idx + 1)
            O_first[idx] = O[idx / D][idx % D];

        // write the hardware output for validate.py
        fp = $fopen("data/output.txt", "w");
        for (r = 0; r < N; r = r + 1) begin
            for (c = 0; c < D; c = c + 1)
                $fwrite(fp, "%0d ", O[r][c]);
            $fwrite(fp, "\n");
        end
        $fclose(fp);

        $display("");
        $display("=== Attention RTL output vs golden (tol = %0d + %0d%% of max|O| = %0d) ===",
                 TOLERANCE_ABS, TOLERANCE_PCT, tol);

        errors = 0;
        for (r = 0; r < N; r = r + 1) begin
            for (c = 0; c < D; c = c + 1) begin
                idx  = r * D + c;
                got  = O[r][c];
                want = O_expected[idx];
                diff = (got > want) ? (got - want) : (want - got);
                if (diff <= tol) begin
                    $display("  O[%0d][%0d]: got=%0d expected=%0d diff=%0d  PASS",
                             r, c, got, want, diff);
                end else begin
                    $display("  O[%0d][%0d]: got=%0d expected=%0d diff=%0d  FAIL",
                             r, c, got, want, diff);
                    errors = errors + 1;
                end
            end
        end

        // ─── pass 2: back-to-back rerun without reset must reproduce ───
        pulse_start;
        wait(done == 1);
        #10;

        for (idx = 0; idx < N*D; idx = idx + 1) begin
            if (O[idx / D][idx % D] !== O_first[idx]) begin
                $display("  RERUN MISMATCH at O[%0d][%0d]: %0d vs %0d",
                         idx / D, idx % D, O[idx / D][idx % D], O_first[idx]);
                errors = errors + 1;
            end
        end

        $display("");
        $display("Latency: %0d cycles (N=%0d, D=%0d, PARALLEL=%0d)",
                 cycles_first, N, D, PARALLEL);
        if (errors == 0) begin
            $display("=== PASS: all %0d outputs within tolerance, rerun bit-identical ===", N*D);
            $display("Output written to data/output.txt");
            $display("Waveform written to sim/attention.vcd");
            $finish;
        end else begin
            $display("=== FAIL: %0d errors ===", errors);
            $fatal(1, "top_level_tb mismatch");
        end
    end

endmodule
