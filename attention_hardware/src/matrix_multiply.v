module matrix_multiply #(
    parameter N        = 3,
    parameter D        = 4,
    parameter PARALLEL = 0  
)(
    input clk,
    input reset,
    input start,
    input  signed [7:0]  X [0:N-1][0:D-1],
    input  signed [7:0]  W [0:D-1][0:D-1],
    output reg signed [15:0] Y [0:N-1][0:D-1],
    output reg done
);

    localparam IDLE    = 2'd0;
    localparam COMPUTE = 2'd1;
    localparam STORE   = 2'd2;
    localparam DONE_ST = 2'd3;

    reg [1:0] state;

    reg [$clog2(N)-1:0] i;
    reg [$clog2(D)-1:0] j;
    reg [$clog2(D)-1:0] k;

    reg signed [15:0] acc;

    // full dot product of the current (i, j); only used when PARALLEL=1,
    integer kk;
    reg signed [15:0] dot_cur;
    always @(*) begin
        dot_cur = 0;
        for (kk = 0; kk < D; kk = kk + 1)
            dot_cur = dot_cur + X[i][kk] * W[kk][j];
    end

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
                    if (PARALLEL) begin
                        Y[i][j] <= dot_cur;

                        if (j == D-1) begin
                            j <= 0;
                            if (i == N-1)
                                state <= DONE_ST;
                            else
                                i <= i + 1;
                        end else begin
                            j <= j + 1;
                        end
                    end else begin
                        acc <= acc + (X[i][k] * W[k][j]);

                        if (k == D-1) begin
                            k     <= 0;
                            state <= STORE;
                        end else begin
                            k <= k + 1;
                        end
                    end
                end

                STORE: begin
                    Y[i][j] <= acc;
                    acc      <= 0;

                    if (j == D-1) begin
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
                    done  <= 1;
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule
