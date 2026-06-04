module score_unit #(
    parameter N = 3,
    parameter D = 4
)(
    input clk,
    input reset,
    input start,
    input  signed [15:0] Q [0:N-1][0:D-1],
    input  signed [15:0] K [0:N-1][0:D-1],
    output reg signed [31:0] S [0:N-1][0:N-1],
    output reg done
);

    localparam IDLE    = 2'd0;
    localparam COMPUTE = 2'd1;
    localparam STORE   = 2'd2;
    localparam DONE_ST = 2'd3;

    reg [1:0] state;

    reg [$clog2(N)-1:0] i;
    reg [$clog2(N)-1:0] j;
    reg [$clog2(D)-1:0] k;

    reg signed [31:0] acc;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            done  <= 0;
            i     <= 0;
            j     <= 0;
            k     <= 0;
            acc   <= 0;
        end else begin
            case (state)

                IDLE: begin
                    done <= 0;
                    if (start) begin
                        i     <= 0;
                        j     <= 0;
                        k     <= 0;
                        acc   <= 0;
                        state <= COMPUTE;
                    end
                end

                COMPUTE: begin
                    acc <= acc + (Q[i][k] * K[j][k]);

                    if (k == D-1) begin
                        k     <= 0;
                        state <= STORE;
                    end else begin
                        k <= k + 1;
                    end
                end

                STORE: begin
                    S[i][j] <= acc;
                    acc      <= 0;

                    if (j == N-1) begin
                        j <= 0;
                        if (i == N-1) begin
                            state <= DONE_ST;
                        end else begin
                            i     <= i + 1;
                            state <= COMPUTE;
                        end
                    end else begin
                        j     <= j + 1;
                        state <= COMPUTE;
                    end
                end

                DONE_ST: begin
                    done <= 1;
                end

            endcase
        end
    end

endmodule
