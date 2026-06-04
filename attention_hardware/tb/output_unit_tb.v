module output_unit_tb;

    reg clk;
    reg reset;
    reg start;

    reg  [15:0]        A [0:2][0:2];
    reg  signed [15:0] V [0:2][0:3];
    wire signed [31:0] O [0:2][0:3];
    wire done;

    output_unit #(.N(3), .D(4)) uut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .A(A),
        .V(V),
        .O(O),
        .done(done)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer r, c;

    initial begin
        A[0][0]=23;  A[0][1]=170; A[0][2]=62;
        A[1][0]=54;  A[1][1]=54;  A[1][2]=147;
        A[2][0]=54;  A[2][1]=54;  A[2][2]=147;

        V[0][0]=2; V[0][1]=0; V[0][2]=0; V[0][3]=0;
        V[1][0]=0; V[1][1]=2; V[1][2]=0; V[1][3]=0;
        V[2][0]=1; V[2][1]=1; V[2][2]=1; V[2][3]=1;

        reset = 1; start = 0;
        @(posedge clk); #1;
        reset = 0;

        start = 1;
        @(posedge clk); #1;
        start = 0;

        wait(done == 1);
        #10;

        $display("=== Output matrix O = A x V ===");
        $display("(raw values, divide by 256 for actual)");
        for (r = 0; r < 3; r = r + 1)
            $display("Row %0d: %6d %6d %6d %6d",
                r, O[r][0], O[r][1], O[r][2], O[r][3]);

        $display("\nAs decimals:");
        for (r = 0; r < 3; r = r + 1)
            $display("Row %0d: %5.2f  %5.2f  %5.2f  %5.2f",
                r, O[r][0]/256.0, O[r][1]/256.0,
                   O[r][2]/256.0, O[r][3]/256.0);

        $display("\nExpected (from Python):");
        $display("Row 0:  0.42  1.58  0.24  0.24");
        $display("Row 1:  1.00  1.00  0.58  0.58");
        $display("Row 2:  1.00  1.00  0.58  0.58");

        $finish;
    end

endmodule
