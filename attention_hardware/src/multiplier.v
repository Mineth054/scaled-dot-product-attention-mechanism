module multiplier #(
    parameter WIDTH = 8
)(
    input  signed [WIDTH-1:0]   a,
    input  signed [WIDTH-1:0]   b,
    output signed [2*WIDTH-1:0] result
);

    wire sign_result;
    assign sign_result = a[WIDTH-1] ^ b[WIDTH-1];

    wire [WIDTH-1:0] abs_a;
    wire [WIDTH-1:0] abs_b;
    assign abs_a = a[WIDTH-1] ? (~a + 1'b1) : a;
    assign abs_b = b[WIDTH-1] ? (~b + 1'b1) : b;

    wire [2*WIDTH-1:0] partial [0:WIDTH-1];

    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin
            assign partial[i] = abs_b[i] ?
                ({{{WIDTH}{1'b0}}, abs_a} << i) :
                {2*WIDTH{1'b0}};
        end
    endgenerate

    wire [2*WIDTH-1:0] unsigned_result;

    integer j;
    reg [2*WIDTH-1:0] sum;
    always @(*) begin
        sum = 0;
        for (j = 0; j < WIDTH; j = j + 1)
            sum = sum + partial[j];
    end
    assign unsigned_result = sum;

    // negate if signs differ
    assign result = sign_result ?
                    (~unsigned_result + 1'b1) :
                    unsigned_result;

endmodule
