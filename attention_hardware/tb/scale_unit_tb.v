module scale_unit_tb;

    reg clk;
    reg reset;
    reg start;

    reg  signed [31:0] S        [0:2][0:2];
    wire signed [31:0] S_scaled [0:2][0:2];
    wire done;

    // D=4: S_scaled = S * 16 / 2 = S * 8 in Q27.4 (exact)
    reg signed [31:0] S_scaled_exp [0:2][0:2];

    scale_unit #(.N(3), .D(4)) uut (
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
    integer errors;

    initial begin
        S[0][0]=0; S[0][1]=4; S[0][2]=2;
        S[1][0]=0; S[1][1]=0; S[1][2]=2;
        S[2][0]=2; S[2][1]=2; S[2][2]=-4;

        S_scaled_exp[0][0]=0;  S_scaled_exp[0][1]=32; S_scaled_exp[0][2]=16;
        S_scaled_exp[1][0]=0;  S_scaled_exp[1][1]=0;  S_scaled_exp[1][2]=16;
        S_scaled_exp[2][0]=16; S_scaled_exp[2][1]=16; S_scaled_exp[2][2]=-32;

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
                if (S_scaled[r][c] !== S_scaled_exp[r][c]) begin
                    $display("FAIL: S_scaled[%0d][%0d] = %0d, expected %0d",
                             r, c, S_scaled[r][c], S_scaled_exp[r][c]);
                    errors = errors + 1;
                end
            end
        end

        if (errors == 0) begin
            $display("scale_unit_tb PASS: all 9 elements match");
            $finish;
        end else begin
            $fatal(1, "scale_unit_tb FAIL: %0d mismatches", errors);
        end
    end

endmodule
