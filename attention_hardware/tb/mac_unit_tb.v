module mac_unit_tb;

    reg clk;
    reg reset;
    reg enable;
    reg  signed [7:0]  a;
    reg  signed [7:0]  b;
    wire signed [15:0] result;

    mac_unit uut(
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .a(a),
        .b(b),
        .result(result)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        reset  = 1;
        enable = 0;
        a = 0;
        b = 0;
        #10;

        reset = 0;
        #1;

        enable = 1;

        a = 8'sd1; b = 8'sd4;
        @(posedge clk); #1;

        a = 8'sd2; b = 8'sd5;
        @(posedge clk); #1;

        a = 8'sd3; b = 8'sd6;
        @(posedge clk); #1;

        enable = 0;
        @(posedge clk); #1;

        $display("Test 1: [1,2,3].[4,5,6]   = %d (expected 32)",  result);

        reset = 1; #10;
        reset = 0; #1;

        enable = 1;

        a = -8'sd1; b =  8'sd4;
        @(posedge clk); #1;

        a =  8'sd2; b = -8'sd5;
        @(posedge clk); #1;

        a = -8'sd3; b =  8'sd6;
        @(posedge clk); #1;

        enable = 0;
        @(posedge clk); #1;

        $display("Test 2: [-1,2,-3].[4,-5,6] = %d (expected -32)", result);

        $finish;
    end

endmodule
