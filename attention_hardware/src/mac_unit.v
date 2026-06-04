module mac_unit(
    input clk,
    input reset,
    input enable,
    input  signed [7:0]  a,
    input  signed [7:0]  b,
    output reg signed [15:0] result
);

    wire signed [15:0] product;

    multiplier mul(
        .a(a),
        .b(b),
        .result(product)
    );

    always @(posedge clk) begin
        if (reset) begin
            result <= 0;
        end else if (enable) begin
            result <= result + product;
        end
    end

endmodule
