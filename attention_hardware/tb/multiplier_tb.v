module multiplier_tb;

    reg  signed [7:0]  a;
    reg  signed [7:0]  b;
    wire signed [15:0] result;

    multiplier uut (
        .a(a),
        .b(b),
        .result(result)
    );

    initial begin
        a = 8'sd10;  b = 8'sd20;
        #10;
        $display("Test 1: %d x %d = %d", a, b, result);

        a = 8'sd10;  b = -8'sd20;
        #10;
        $display("Test 2: %d x %d = %d", a, b, result);

        a = -8'sd10; b = -8'sd20;
        #10;
        $display("Test 3: %d x %d = %d", a, b, result);

        $finish;
    end

endmodule
