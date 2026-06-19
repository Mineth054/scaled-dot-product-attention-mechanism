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

    reg signed [15:0] Q_exp [0:2][0:3];
    reg signed [15:0] K_exp [0:2][0:3];
    reg signed [15:0] V_exp [0:2][0:3];

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
    integer errors;

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

        Q_exp[0][0]=2; Q_exp[0][1]=0; Q_exp[0][2]=0; Q_exp[0][3]=0;
        Q_exp[1][0]=0; Q_exp[1][1]=2; Q_exp[1][2]=0; Q_exp[1][3]=0;
        Q_exp[2][0]=1; Q_exp[2][1]=1; Q_exp[2][2]=1; Q_exp[2][3]=1;

        K_exp[0][0]=0; K_exp[0][1]=0; K_exp[0][2]=0; K_exp[0][3]=2;
        K_exp[1][0]=2; K_exp[1][1]=0; K_exp[1][2]=0; K_exp[1][3]=0;
        K_exp[2][0]=1; K_exp[2][1]=1; K_exp[2][2]=1; K_exp[2][3]=1;

        V_exp[0][0]=2; V_exp[0][1]=0; V_exp[0][2]=0; V_exp[0][3]=0;
        V_exp[1][0]=0; V_exp[1][1]=2; V_exp[1][2]=0; V_exp[1][3]=0;
        V_exp[2][0]=1; V_exp[2][1]=1; V_exp[2][2]=1; V_exp[2][3]=1;

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
            for (c = 0; c < 4; c = c + 1) begin
                if (Q[r][c] !== Q_exp[r][c]) begin
                    $display("FAIL: Q[%0d][%0d] = %0d, expected %0d",
                             r, c, Q[r][c], Q_exp[r][c]);
                    errors = errors + 1;
                end
                if (K[r][c] !== K_exp[r][c]) begin
                    $display("FAIL: K[%0d][%0d] = %0d, expected %0d",
                             r, c, K[r][c], K_exp[r][c]);
                    errors = errors + 1;
                end
                if (V[r][c] !== V_exp[r][c]) begin
                    $display("FAIL: V[%0d][%0d] = %0d, expected %0d",
                             r, c, V[r][c], V_exp[r][c]);
                    errors = errors + 1;
                end
            end
        end

        if (errors == 0) begin
            $display("projection_unit_tb PASS: all 36 elements match");
            $finish;
        end else begin
            $fatal(1, "projection_unit_tb FAIL: %0d mismatches", errors);
        end
    end

endmodule
