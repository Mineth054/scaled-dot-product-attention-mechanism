module output_unit #(
    parameter N = 3,
    parameter D = 4
)(
    input clk,
    input reset,
    input start,
    input  [15:0]        A [0:N-1][0:N-1],
    input  signed [15:0] V [0:N-1][0:D-1],
    output reg signed [31:0] O [0:N-1][0:D-1],
    output reg done
);

    localparam IDLE    = 3'd0;
    localparam LOAD    = 3'd1;
    localparam WAIT    = 3'd2;
    localparam ACC     = 3'd3;
    localparam STORE   = 3'd4;
    localparam DONE_ST = 3'd5;

    reg [2:0] state;

    reg [$clog2(N)-1:0] i;
    reg [$clog2(D)-1:0] j;
    reg [$clog2(N)-1:0] k;

    reg signed [31:0] acc;

    reg  signed [15:0] mul_a;
    reg  signed [15:0] mul_b;
    wire signed [31:0] mul_result;

    multiplier #(.WIDTH(16)) out_mul (
        .a      (mul_a),
        .b      (mul_b),
        .result (mul_result)
    );

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            done  <= 0;
            i     <= 0;
            j     <= 0;
            k     <= 0;
            acc   <= 0;
            mul_a <= 0;
            mul_b <= 0;
        end else begin
            case (state)

                IDLE: begin
                    done <= 0;
                    if (start) begin
                        i     <= 0;
                        j     <= 0;
                        k     <= 0;
                        acc   <= 0;
                        state <= LOAD;
                    end
                end

                LOAD: begin
                    mul_a <= $signed({1'b0, A[i][k]});
                    mul_b <= V[k][j];
                    state <= WAIT;
                end

                WAIT: begin
                    state <= ACC;
                end

                ACC: begin
                    acc <= acc + mul_result;

                    if (k == N-1) begin
                        k     <= 0;
                        state <= STORE;
                    end else begin
                        k     <= k + 1;
                        state <= LOAD;
                    end
                end

                STORE: begin
                    // A is scaled by 256, divide in post-processing
                    O[i][j] <= acc;
                    acc      <= 0;

                    if (j == D-1) begin
                        j <= 0;
                        if (i == N-1) begin
                            state <= DONE_ST;
                        end else begin
                            i     <= i + 1;
                            state <= LOAD;
                        end
                    end else begin
                        j     <= j + 1;
                        state <= LOAD;
                    end
                end

                DONE_ST: begin
                    done <= 1;
                end

            endcase
        end
    end

endmodule
