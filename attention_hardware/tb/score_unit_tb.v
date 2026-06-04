module score_unit_tb;

    reg clk;
    reg reset;
    reg start;

    reg signed [15:0] Q [0:2][0:3];
    reg signed [15:0] K [0:2][0:3];

    wire signed [31:0] S [0:2][0:2];
    wire done;

    score_unit #(.N(3), .D(4)) uut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .Q(Q),
        .K(K),
        .S(S),
        .done(done)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer r, c;

    initial begin
        Q[0][0]=2; Q[0][1]=0; Q[0][2]=0; Q[0][3]=0;
        Q[1][0]=0; Q[1][1]=2; Q[1][2]=0; Q[1][3]=0;
        Q[2][0]=1; Q[2][1]=1; Q[2][2]=1; Q[2][3]=1;

        K[0][0]=0; K[0][1]=0; K[0][2]=0; K[0][3]=2;
        K[1][0]=2; K[1][1]=0; K[1][2]=0; K[1][3]=0;
        K[2][0]=1; K[2][1]=1; K[2][2]=1; K[2][3]=1;

        reset = 1; start = 0;
        @(posedge clk); #1;
        reset = 0;

        start = 1;
        @(posedge clk); #1;
        start = 0;

        wait(done == 1);
        #10;

        $display("=== Score matrix S = Q x Kt ===");
        for (r = 0; r < 3; r = r + 1)
            $display("Row %0d: %4d %4d %4d",
                r, S[r][0], S[r][1], S[r][2]);

        $display("\nExpected:");
        $display("Row 0:    0    4    2");
        $display("Row 1:    0    0    2");
        $display("Row 2:    2    2    4");

        $finish;
    end

endmodule
