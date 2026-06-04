module unsigned_multiplier #(
    parameter WIDTHA = 16,
    parameter WIDTHB = 32
)(
    input  [WIDTHA-1:0]        a,
    input  [WIDTHB-1:0]        b,
    output [WIDTHA+WIDTHB-1:0] result
);

    wire [WIDTHA+WIDTHB-1:0] b_ext;
    assign b_ext = { {WIDTHA{1'b0}}, b };

    wire [WIDTHA+WIDTHB-1:0] partial [0:WIDTHA-1];

    genvar i;
    generate
        for (i = 0; i < WIDTHA; i = i + 1) begin : gen_partial
            assign partial[i] = a[i] ? (b_ext << i)
                                     : {(WIDTHA+WIDTHB){1'b0}};
        end
    endgenerate

    integer j;
    reg [WIDTHA+WIDTHB-1:0] sum;
    always @(*) begin
        sum = {(WIDTHA+WIDTHB){1'b0}};
        for (j = 0; j < WIDTHA; j = j + 1)
            sum = sum + partial[j];
    end

    assign result = sum;

endmodule
