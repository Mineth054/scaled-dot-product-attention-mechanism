module matrix_multiply_tb;

    reg clk;
    reg reset;
    reg start;

    reg signed [7:0] X [0:2][0:3];
    reg signed [7:0] W [0:3][0:3];
    wire signed [15:0] Y [0:2][0:3];
    wire done;

    reg signed [15:0] Y_exp [0:2][0:3];

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
    integer errors;

    initial begin
        X[0][0]=1; X[0][1]=0; X[0][2]=1; X[0][3]=0;
        X[1][0]=0; X[1][1]=1; X[1][2]=0; X[1][3]=1;
        X[2][0]=1; X[2][1]=1; X[2][2]=0; X[2][3]=0;

        W[0][0]= 1; W[0][1]= 0; W[0][2]= 1; W[0][3]= 0;
        W[1][0]= 0; W[1][1]= 1; W[1][2]= 0; W[1][3]= 1;
        W[2][0]= 1; W[2][1]= 0; W[2][2]=-1; W[2][3]= 0;
        W[3][0]= 0; W[3][1]= 1; W[3][2]= 0; W[3][3]=-1;

        Y_exp[0][0]=2; Y_exp[0][1]=0; Y_exp[0][2]=0; Y_exp[0][3]=0;
        Y_exp[1][0]=0; Y_exp[1][1]=2; Y_exp[1][2]=0; Y_exp[1][3]=0;
        Y_exp[2][0]=1; Y_exp[2][1]=1; Y_exp[2][2]=1; Y_exp[2][3]=1;

        reset = 1;
        start = 0;
        @(posedge clk); #1;
        reset = 0;

        start = 1;
        @(posedge clk); #1;
        start = 0;

        wait(done == 1);
        #10;

        errors = 0;
        for (r = 0; r < 3; r = r + 1) begin
            for (c = 0; c < 4; c = c + 1) begin
                if (Y[r][c] !== Y_exp[r][c]) begin
                    $display("FAIL: Y[%0d][%0d] = %0d, expected %0d",
                             r, c, Y[r][c], Y_exp[r][c]);
                    errors = errors + 1;
                end
            end
        end

        if (errors == 0) begin
            $display("matrix_multiply_tb PASS: all 12 elements match");
            $finish;
        end else begin
            $fatal(1, "matrix_multiply_tb FAIL: %0d mismatches", errors);
        end
    end

endmodule
