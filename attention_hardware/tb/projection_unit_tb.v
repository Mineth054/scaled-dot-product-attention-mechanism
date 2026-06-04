module projection_unit_tb;

    reg clk;
    reg reset;
    reg start;

    reg signed [7:0] X  [0:2][0:3];
    reg signed [7:0] WQ [0:3][0:3];
    reg signed [7:0] WK [0:3][0:3];
    reg signed [7:0] WV [0:3][0:3];

    wire signed [15:0] Q [0:2][0:3];
    wire signed [15:0] K [0:2][0:3];
    wire signed [15:0] V [0:2][0:3];
    wire done;

    projection_unit #(.N(3), .D(4)) uut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .X(X),
        .WQ(WQ),
        .WK(WK),
        .WV(WV),
        .Q(Q),
        .K(K),
        .V(V),
        .done(done)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer r, c;

    initial begin
        X[0][0]=1; X[0][1]=0; X[0][2]=1; X[0][3]=0;
        X[1][0]=0; X[1][1]=1; X[1][2]=0; X[1][3]=1;
        X[2][0]=1; X[2][1]=1; X[2][2]=0; X[2][3]=0;

        WQ[0][0]= 1; WQ[0][1]= 0; WQ[0][2]= 1; WQ[0][3]= 0;
        WQ[1][0]= 0; WQ[1][1]= 1; WQ[1][2]= 0; WQ[1][3]= 1;
        WQ[2][0]= 1; WQ[2][1]= 0; WQ[2][2]=-1; WQ[2][3]= 0;
        WQ[3][0]= 0; WQ[3][1]= 1; WQ[3][2]= 0; WQ[3][3]=-1;

        WK[0][0]= 0; WK[0][1]= 1; WK[0][2]= 0; WK[0][3]= 1;
        WK[1][0]= 1; WK[1][1]= 0; WK[1][2]= 1; WK[1][3]= 0;
        WK[2][0]= 0; WK[2][1]=-1; WK[2][2]= 0; WK[2][3]= 1;
        WK[3][0]= 1; WK[3][1]= 0; WK[3][2]=-1; WK[3][3]= 0;

        WV[0][0]= 1; WV[0][1]= 0; WV[0][2]= 0; WV[0][3]= 1;
        WV[1][0]= 0; WV[1][1]= 1; WV[1][2]= 1; WV[1][3]= 0;
        WV[2][0]= 1; WV[2][1]= 0; WV[2][2]= 0; WV[2][3]=-1;
        WV[3][0]= 0; WV[3][1]= 1; WV[3][2]=-1; WV[3][3]= 0;

        reset = 1; start = 0;
        @(posedge clk); #1;
        reset = 0;

        start = 1;
        @(posedge clk); #1;
        start = 0;

        wait(done == 1);
        #10;

        $display("=== Q matrix ===");
        for (r = 0; r < 3; r = r + 1)
            $display("Row %0d: %4d %4d %4d %4d",
                r, Q[r][0], Q[r][1], Q[r][2], Q[r][3]);

        $display("\nExpected Q:");
        $display("Row 0:    2    0    0    0");
        $display("Row 1:    0    2    0    0");
        $display("Row 2:    1    1    1    1");

        $display("\n=== K matrix ===");
        for (r = 0; r < 3; r = r + 1)
            $display("Row %0d: %4d %4d %4d %4d",
                r, K[r][0], K[r][1], K[r][2], K[r][3]);

        $display("\nExpected K:");
        $display("Row 0:    0    0    0    2");
        $display("Row 1:    2    0    0    0");
        $display("Row 2:    1    1    1    1");

        $display("\n=== V matrix ===");
        for (r = 0; r < 3; r = r + 1)
            $display("Row %0d: %4d %4d %4d %4d",
                r, V[r][0], V[r][1], V[r][2], V[r][3]);

        $display("\nExpected V:");
        $display("Row 0:    2    0    0    0");
        $display("Row 1:    0    2    0    0");
        $display("Row 2:    1    1    1    1");

        $finish;
    end

endmodule
