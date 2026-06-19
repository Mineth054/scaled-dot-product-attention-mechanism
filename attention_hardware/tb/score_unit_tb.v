module score_unit_tb;

    reg clk;
    reg reset;
    reg start;

    reg signed [15:0] Q [0:2][0:3];
    reg signed [15:0] K [0:2][0:3];

    wire signed [31:0] S [0:2][0:2];
    wire done;

    reg signed [31:0] S_exp [0:2][0:2];

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
    integer errors;

    initial begin
        Q[0][0]=2; Q[0][1]=0; Q[0][2]=0; Q[0][3]=0;
        Q[1][0]=0; Q[1][1]=2; Q[1][2]=0; Q[1][3]=0;
        Q[2][0]=1; Q[2][1]=1; Q[2][2]=1; Q[2][3]=1;

        K[0][0]=0; K[0][1]=0; K[0][2]=0; K[0][3]=2;
        K[1][0]=2; K[1][1]=0; K[1][2]=0; K[1][3]=0;
        K[2][0]=1; K[2][1]=1; K[2][2]=1; K[2][3]=1;

        S_exp[0][0]=0; S_exp[0][1]=4; S_exp[0][2]=2;
        S_exp[1][0]=0; S_exp[1][1]=0; S_exp[1][2]=2;
        S_exp[2][0]=2; S_exp[2][1]=2; S_exp[2][2]=4;

        reset = 1; start = 0;
        @(posedge clk); #1;
        reset = 0;

        start = 1;
        @(posedge clk); #1;
        start = 0;

        wait(done == 1);
        #10;

        errors = 0;
        for (r = 0; r < 3; r = r + 1) begin
            for (c = 0; c < 3; c = c + 1) begin
                if (S[r][c] !== S_exp[r][c]) begin
                    $display("FAIL: S[%0d][%0d] = %0d, expected %0d",
                             r, c, S[r][c], S_exp[r][c]);
                    errors = errors + 1;
                end
            end
        end

        if (errors == 0) begin
            $display("score_unit_tb PASS: all 9 elements match");
            $finish;
        end else begin
            $fatal(1, "score_unit_tb FAIL: %0d mismatches", errors);
        end
    end

endmodule
