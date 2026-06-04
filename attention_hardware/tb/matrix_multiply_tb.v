module matrix_multiply_tb;

    reg clk;
    reg reset;
    reg start;

    reg signed [7:0] X [0:2][0:3];
    reg signed [7:0] W [0:3][0:3];
    wire signed [15:0] Y [0:2][0:3];
    wire done;

    matrix_multiply #(.N(3), .D(4)) uut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .X(X),
        .W(W),
        .Y(Y),
        .done(done)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer r, c;

    initial begin
        X[0][0]=1; X[0][1]=0; X[0][2]=1; X[0][3]=0;
        X[1][0]=0; X[1][1]=1; X[1][2]=0; X[1][3]=1;
        X[2][0]=1; X[2][1]=1; X[2][2]=0; X[2][3]=0;

        W[0][0]= 1; W[0][1]= 0; W[0][2]= 1; W[0][3]= 0;
        W[1][0]= 0; W[1][1]= 1; W[1][2]= 0; W[1][3]= 1;
        W[2][0]= 1; W[2][1]= 0; W[2][2]=-1; W[2][3]= 0;
        W[3][0]= 0; W[3][1]= 1; W[3][2]= 0; W[3][3]=-1;

        reset = 1;
        start = 0;
        @(posedge clk); #1;
        reset = 0;

        start = 1;
        @(posedge clk); #1;
        start = 0;

        wait(done == 1);
        #10;

        $display("Q matrix (should match Python output):");
        for (r = 0; r < 3; r = r + 1) begin
            $display("Row %0d: %4d %4d %4d %4d",
                r, Y[r][0], Y[r][1], Y[r][2], Y[r][3]);
        end

        $display("\nExpected:");
        $display("Row 0:    2    0    0    0");
        $display("Row 1:    0    2    0    0");
        $display("Row 2:    1    1    1    1");

        $finish;
    end

endmodule
