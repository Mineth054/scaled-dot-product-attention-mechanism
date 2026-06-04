module softmax_unit #(
    parameter N         = 3,
    parameter LUT_DEPTH = 16,
    parameter SUM_MAX   = N * 1024,
    parameter SUM_BITS  = $clog2(SUM_MAX + 1),
    parameter IDX_BITS  = $clog2(LUT_DEPTH)
)(
    input clk,
    input reset,
    input start,
    input  signed [15:0] S_scaled [0:N-1][0:N-1],
    output reg    [15:0] A        [0:N-1][0:N-1],
    output reg done
);

    reg [15:0] exp_lut [0:LUT_DEPTH-1];
    reg [31:0] recip_lut [0:SUM_MAX];

    integer k;
    initial begin
        $readmemh("data/recip_lut.txt", recip_lut);
        exp_lut[0]  = 1024;
        exp_lut[1]  = 377;
        exp_lut[2]  = 139;
        exp_lut[3]  = 51;
        exp_lut[4]  = 19;
        exp_lut[5]  = 7;
        exp_lut[6]  = 3;
        for (k = 7; k < LUT_DEPTH; k = k + 1)
            exp_lut[k] = 1;
    end

    localparam IDLE       = 3'd0;
    localparam FIND_MAX   = 3'd1;
    localparam CALC_EXP   = 3'd2;
    localparam CALC_SUM   = 3'd3;
    localparam NORMALIZE  = 3'd4;
    localparam NORM_STORE = 3'd5;
    localparam DONE_ST    = 3'd6;

    reg [2:0] state;

    reg [IDX_BITS-1:0] norm_i;
    reg [IDX_BITS-1:0] norm_j;

    reg signed [15:0]         row_max  [0:N-1];
    reg        [15:0]         exp_vals [0:N-1][0:N-1];
    reg        [SUM_BITS-1:0] row_sum  [0:N-1];

    reg signed [15:0]         row_max_comb [0:N-1];
    reg        [SUM_BITS-1:0] row_sum_comb [0:N-1];

    integer mi, mj;
    always @(*) begin
        for (mi = 0; mi < N; mi = mi + 1) begin
            row_max_comb[mi] = S_scaled[mi][0];
            row_sum_comb[mi] = exp_vals[mi][0];
            for (mj = 1; mj < N; mj = mj + 1) begin
                if (S_scaled[mi][mj] > row_max_comb[mi])
                    row_max_comb[mi] = S_scaled[mi][mj];
                row_sum_comb[mi] = row_sum_comb[mi] + exp_vals[mi][mj];
            end
        end
    end

    reg  [15:0] mul_a;
    reg  [31:0] mul_b;
    wire [47:0] mul_result;

    unsigned_multiplier #(
        .WIDTHA(16),
        .WIDTHB(32)
    ) norm_mul (
        .a      (mul_a),
        .b      (mul_b),
        .result (mul_result)
    );

    function [IDX_BITS-1:0] lut_index;
        input signed [15:0] diff;
        reg signed [15:0] neg_diff;
        begin
            if (diff >= 0) begin
                lut_index = {IDX_BITS{1'b0}};
            end else if (diff <= -(LUT_DEPTH-1)) begin
                lut_index = LUT_DEPTH-1;
            end else begin
                neg_diff  = -diff;
                lut_index = neg_diff[IDX_BITS-1:0];
            end
        end
    endfunction

    integer i, j;

    always @(posedge clk) begin
        if (reset) begin
            state  <= IDLE;
            done   <= 0;
            norm_i <= 0;
            norm_j <= 0;
            mul_a  <= 0;
            mul_b  <= 0;
        end else begin
            case (state)

                IDLE: begin
                    done <= 0;
                    if (start)
                        state <= FIND_MAX;
                end

                FIND_MAX: begin
                    for (i = 0; i < N; i = i + 1)
                        row_max[i] <= row_max_comb[i];
                    state <= CALC_EXP;
                end

                CALC_EXP: begin
                    for (i = 0; i < N; i = i + 1)
                        for (j = 0; j < N; j = j + 1)
                            exp_vals[i][j] <= exp_lut[
                                lut_index(S_scaled[i][j] - row_max[i])
                            ];
                    state <= CALC_SUM;
                end

                CALC_SUM: begin
                    for (i = 0; i < N; i = i + 1)
                        row_sum[i] <= row_sum_comb[i];
                    norm_i <= 0;
                    norm_j <= 0;
                    state  <= NORMALIZE;
                end

                NORMALIZE: begin
                    mul_a <= exp_vals[norm_i][norm_j];
                    mul_b <= recip_lut[row_sum[norm_i]];
                    state <= NORM_STORE;
                end

                NORM_STORE: begin
                    // bits [27:12] gives prob*256
                    A[norm_i][norm_j] <= mul_result[27:12];

                    if (norm_j == N-1) begin
                        norm_j <= 0;
                        if (norm_i == N-1) begin
                            state <= DONE_ST;
                        end else begin
                            norm_i <= norm_i + 1;
                            state  <= NORMALIZE;
                        end
                    end else begin
                        norm_j <= norm_j + 1;
                        state  <= NORMALIZE;
                    end
                end

                DONE_ST: begin
                    done <= 1;
                end

            endcase
        end
    end

endmodule
