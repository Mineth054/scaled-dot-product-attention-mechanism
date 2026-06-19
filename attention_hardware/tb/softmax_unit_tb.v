module softmax_unit_tb;

    reg clk;
    reg reset;
    reg start;

    reg  signed [31:0] S_scaled [0:2][0:2];
    wire        [15:0] A        [0:2][0:2];
    wire done;

    reg [15:0] A_exp [0:2][0:2];

    softmax_unit #(.N(3)) uut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .S_scaled(S_scaled),
        .A(A),
        .done(done)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer r, c;
    integer errors;

    task run_and_check;
        input [127:0] label;
        begin
            reset = 1; start = 0;
            @(posedge clk); #1;
            reset = 0;

            start = 1;
            @(posedge clk); #1;
            start = 0;

            wait(done == 1);
            #10;

            for (r = 0; r < 3; r = r + 1) begin
                for (c = 0; c < 3; c = c + 1) begin
                    if (A[r][c] !== A_exp[r][c]) begin
                        $display("FAIL (%0s): A[%0d][%0d] = %0d, expected %0d",
                                 label, r, c, A[r][c], A_exp[r][c]);
                        errors = errors + 1;
                    end
                end
            end
        end
    endtask

    initial begin
        errors = 0;

        // --- vector 1: integer exponents (Q11.4 values 0, 2.0, 1.0) ---
        // row 0: exps [139,1024,377], sum 1540, recip 680 -> [23,170,63]
        // rows 1,2: exps [377,377,1024], sum 1778, recip 589 -> [54,54,147]
        S_scaled[0][0]=0;  S_scaled[0][1]=32; S_scaled[0][2]=16;
        S_scaled[1][0]=0;  S_scaled[1][1]=0;  S_scaled[1][2]=16;
        S_scaled[2][0]=16; S_scaled[2][1]=16; S_scaled[2][2]=32;

        A_exp[0][0]=23; A_exp[0][1]=170; A_exp[0][2]=63;
        A_exp[1][0]=54; A_exp[1][1]=54;  A_exp[1][2]=147;
        A_exp[2][0]=54; A_exp[2][1]=54;  A_exp[2][2]=147;

        run_and_check("integer");

        // --- vector 2: fractional exponents (0.3125, 0, 0.6875) ---
        // diffs -6/16, -11/16, 0 -> exps [704,515,1024], sum 2243,
        // recip 467 -> [80,59,117]
        S_scaled[0][0]=5; S_scaled[0][1]=0; S_scaled[0][2]=11;
        S_scaled[1][0]=5; S_scaled[1][1]=0; S_scaled[1][2]=11;
        S_scaled[2][0]=5; S_scaled[2][1]=0; S_scaled[2][2]=11;

        for (r = 0; r < 3; r = r + 1) begin
            A_exp[r][0]=80; A_exp[r][1]=59; A_exp[r][2]=117;
        end

        run_and_check("fractional");

        if (errors == 0) begin
            $display("softmax_unit_tb PASS: both vectors match");
            $finish;
        end else begin
            $fatal(1, "softmax_unit_tb FAIL: %0d mismatches", errors);
        end
    end

endmodule
