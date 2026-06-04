module top_level_tb;

    localparam N = 3;
    localparam D = 4;
    localparam integer TOLERANCE_ABS = 32;
    localparam integer TOLERANCE_PCT = 1;

    reg clk;
    reg reset;
    reg start;
    wire done;

    top_level #(.N(N), .D(D)) uut (
        .clk   (clk),
        .reset (reset),
        .start (start),
        .done  (done)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/attention.vcd");
        $dumpvars(0, top_level_tb);
    end

    reg signed [31:0] O_expected [0:N*D-1];

    integer r, c, idx;
    integer errors;
    integer diff;
    integer abs_want;
    reg signed [31:0] got;
    reg signed [31:0] want;

    initial begin
        $readmemh("data/O_expected.txt", O_expected);

        reset = 1;
        start = 0;
        @(posedge clk); #1;
        reset = 0;

        start = 1;
        @(posedge clk); #1;
        start = 0;

        wait(done == 1);
        #10;

        $display("");
        $display("=== Attention RTL output vs golden (abs<=%0d or rel<=%0d%%) ===", TOLERANCE_ABS, TOLERANCE_PCT);

        errors = 0;
        for (r = 0; r < N; r = r + 1) begin
            for (c = 0; c < D; c = c + 1) begin
                idx      = r * D + c;
                got      = uut.O[r][c];
                want     = O_expected[idx];
                diff     = (got > want) ? (got - want) : (want - got);
                abs_want = (want >= 0)  ? want         : -want;
                if ((diff <= TOLERANCE_ABS) || (diff * 100 <= TOLERANCE_PCT * abs_want)) begin
                    $display("  O[%0d][%0d]: got=%0d expected=%0d diff=%0d  PASS",
                             r, c, got, want, diff);
                end else begin
                    $display("  O[%0d][%0d]: got=%0d expected=%0d diff=%0d  FAIL",
                             r, c, got, want, diff);
                    errors = errors + 1;
                end
            end
        end

        $display("");
        if (errors == 0) begin
            $display("=== PASS: all %0d outputs within tolerance ===", N*D);
            $display("Output written to data/output.txt");
            $display("Waveform written to sim/attention.vcd");
            $finish;
        end else begin
            $display("=== FAIL: %0d/%0d outputs outside tolerance ===", errors, N*D);
            $fatal(1, "top_level_tb mismatch");
        end
    end

endmodule
