module scale_unit_tb;

    reg clk;
    reg reset;
    reg start;

    reg  signed [31:0] S        [0:2][0:2];
    wire signed [15:0] S_scaled [0:2][0:2];
    wire done;

    scale_unit #(.N(3)) uut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .S(S),
        .S_scaled(S_scaled),
        .done(done)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer r, c;

    initial begin
        S[0][0]=0; S[0][1]=4; S[0][2]=2;
        S[1][0]=0; S[1][1]=0; S[1][2]=2;
        S[2][0]=2; S[2][1]=2; S[2][2]=4;

        reset = 1; start = 0;
        @(posedge clk); #1;
        reset = 0;

        start = 1;
        @(posedge clk); #1;
        start = 0;

        wait(done == 1);
        #10;

        $display("=== Scaled scores ===");
        for (r = 0; r < 3; r = r + 1)
            $display("Row %0d: %4d %4d %4d",
                r, S_scaled[r][0], S_scaled[r][1], S_scaled[r][2]);

        $display("\nExpected:");
        $display("Row 0:    0    2    1");
        $display("Row 1:    0    0    1");
        $display("Row 2:    1    1    2");

        $finish;
    end

endmodule
