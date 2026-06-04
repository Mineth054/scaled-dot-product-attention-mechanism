module projection_unit #(
    parameter N = 3,
    parameter D = 4
)(
    input clk,
    input reset,
    input start,
    input  signed [7:0]  X  [0:N-1][0:D-1],
    input  signed [7:0]  WQ [0:D-1][0:D-1],
    input  signed [7:0]  WK [0:D-1][0:D-1],
    input  signed [7:0]  WV [0:D-1][0:D-1],
    output signed [15:0] Q  [0:N-1][0:D-1],
    output signed [15:0] K  [0:N-1][0:D-1],
    output signed [15:0] V  [0:N-1][0:D-1],
    output done
);

    wire done_q, done_k, done_v;
    assign done = done_q & done_k & done_v;

    matrix_multiply #(.N(N), .D(D)) proj_q (
        .clk(clk),
        .reset(reset),
        .start(start),
        .X(X),
        .W(WQ),
        .Y(Q),
        .done(done_q)
    );

    matrix_multiply #(.N(N), .D(D)) proj_k (
        .clk(clk),
        .reset(reset),
        .start(start),
        .X(X),
        .W(WK),
        .Y(K),
        .done(done_k)
    );

    matrix_multiply #(.N(N), .D(D)) proj_v (
        .clk(clk),
        .reset(reset),
        .start(start),
        .X(X),
        .W(WV),
        .Y(V),
        .done(done_v)
    );

endmodule
