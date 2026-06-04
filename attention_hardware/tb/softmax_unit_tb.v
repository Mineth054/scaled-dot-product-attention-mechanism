module softmax_unit_tb;

    reg clk;
    reg reset;
    reg start;

    reg  signed [15:0] S_scaled [0:2][0:2];
    wire        [15:0] A        [0:2][0:2];
    wire done;

    softmax_unit #(.N(3)) uut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .S_scaled(S_scaled),
        .A(A),
        .done(done)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer r, c;

    initial begin
        S_scaled[0][0]=0; S_scaled[0][1]=2; S_scaled[0][2]=1;
        S_scaled[1][0]=0; S_scaled[1][1]=0; S_scaled[1][2]=1;
        S_scaled[2][0]=1; S_scaled[2][1]=1; S_scaled[2][2]=2;

        reset = 1; start = 0;
        @(posedge clk); #1;
        reset = 0;

        start = 1;
        @(posedge clk); #1;
        start = 0;

        wait(done == 1);
        #10;

        $display("=== Attention weights (scaled by 256) ===");
        for (r = 0; r < 3; r = r + 1)
            $display("Row %0d: %4d %4d %4d",
                r, A[r][0], A[r][1], A[r][2]);

        $display("\nAs percentages:");
        for (r = 0; r < 3; r = r + 1)
            $display("Row %0d: %3.0f%% %3.0f%% %3.0f%%",
                r, A[r][0]*100.0/256,
                   A[r][1]*100.0/256,
                   A[r][2]*100.0/256);

        $display("\nExpected (from Python):");
        $display("Row 0:  9%% 67%% 24%%");
        $display("Row 1: 21%% 21%% 58%%");
        $display("Row 2: 21%% 21%% 58%%");

        $finish;
    end

endmodule
