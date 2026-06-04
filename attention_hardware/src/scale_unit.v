module scale_unit #(
    parameter N = 3
)(
    input clk,
    input reset,
    input start,
    input  signed [31:0] S      [0:N-1][0:N-1],
    output reg signed [15:0] S_scaled [0:N-1][0:N-1],
    output reg done
);

    integer i, j;

    always @(posedge clk) begin
        if (reset) begin
            done <= 0;
        end else if (start) begin
            // d_k=4 so sqrt is 2, shift right by 1
            for (i = 0; i < N; i = i + 1) begin
                for (j = 0; j < N; j = j + 1) begin
                    S_scaled[i][j] <= S[i][j] >>> 1;
                end
            end
            done <= 1;
        end
    end

endmodule
