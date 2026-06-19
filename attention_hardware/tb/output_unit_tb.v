module output_unit_tb;

    reg clk;
    reg reset;
    reg start;

    reg  [15:0]        A [0:2][0:2];
    reg  signed [15:0] V [0:2][0:3];
    wire signed [31:0] O [0:2][0:3];
    wire done;

    // exact integer expectation: O = A x V with A in Q.8 raw units
    reg signed [31:0] O_exp [0:2][0:3];

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
    integer errors;

    initial begin
        A[0][0]=23;  A[0][1]=170; A[0][2]=62;
        A[1][0]=54;  A[1][1]=54;  A[1][2]=147;
        A[2][0]=54;  A[2][1]=54;  A[2][2]=147;

        V[0][0]=2; V[0][1]=0; V[0][2]=0; V[0][3]=0;
        V[1][0]=0; V[1][1]=2; V[1][2]=0; V[1][3]=0;
        V[2][0]=1; V[2][1]=1; V[2][2]=1; V[2][3]=1;

        O_exp[0][0]=108; O_exp[0][1]=402; O_exp[0][2]=62;  O_exp[0][3]=62;
        O_exp[1][0]=255; O_exp[1][1]=255; O_exp[1][2]=147; O_exp[1][3]=147;
        O_exp[2][0]=255; O_exp[2][1]=255; O_exp[2][2]=147; O_exp[2][3]=147;

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
                if (O[r][c] !== O_exp[r][c]) begin
                    $display("FAIL: O[%0d][%0d] = %0d, expected %0d",
                             r, c, O[r][c], O_exp[r][c]);
                    errors = errors + 1;
                end
            end
        end

        if (errors == 0) begin
            $display("output_unit_tb PASS: all 12 elements match");
            $finish;
        end else begin
            $fatal(1, "output_unit_tb FAIL: %0d mismatches", errors);
        end
    end

endmodule
