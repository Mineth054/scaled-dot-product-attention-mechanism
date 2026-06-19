// Synthesizable attention core: softmax(X*WQ * (X*WK)^T / sqrt(D)) * (X*WV).
// All file I/O lives in the testbench; inputs arrive on ports and the
// result leaves on the O port. One start pulse runs one attention pass;
// done holds high until the next start, and the FSM returns to IDLE so
// back-to-back passes need no reset.
module top_level #(
    parameter N        = 3,
    parameter D        = 4,
    parameter PARALLEL = 0  // 1: one dot product per cycle in the matmul units
)(
    input clk,
    input reset,
    input start,
    input  signed [7:0] X  [0:N-1][0:D-1],
    input  signed [7:0] WQ [0:D-1][0:D-1],
    input  signed [7:0] WK [0:D-1][0:D-1],
    input  signed [7:0] WV [0:D-1][0:D-1],
    output signed [31:0] O [0:N-1][0:D-1],  // x256 of the true output
    output reg done
);

    wire signed [15:0] Q [0:N-1][0:D-1];
    wire signed [15:0] K [0:N-1][0:D-1];
    wire signed [15:0] V [0:N-1][0:D-1];

    wire signed [31:0] S        [0:N-1][0:N-1];
    wire signed [31:0] S_scaled [0:N-1][0:N-1];  // Q27.4
    wire        [15:0] A        [0:N-1][0:N-1];

    reg proj_start, score_start, scale_start;
    reg softmax_start, output_start;

    wire proj_done, score_done, scale_done;
    wire softmax_done, output_done;

    localparam IDLE    = 3'd0;
    localparam PROJ    = 3'd1;
    localparam SCORE   = 3'd2;
    localparam SCALE   = 3'd3;
    localparam SOFTMAX = 3'd4;
    localparam OUTPUT  = 3'd5;
    localparam DONE_ST = 3'd6;

    reg [2:0] state;

    projection_unit #(.N(N), .D(D), .PARALLEL(PARALLEL)) proj (
        .clk   (clk),
        .reset (reset),
        .start (proj_start),
        .X     (X),
        .WQ    (WQ),
        .WK    (WK),
        .WV    (WV),
        .Q     (Q),
        .K     (K),
        .V     (V),
        .done  (proj_done)
    );

    score_unit #(.N(N), .D(D), .PARALLEL(PARALLEL)) score (
        .clk   (clk),
        .reset (reset),
        .start (score_start),
        .Q     (Q),
        .K     (K),
        .S     (S),
        .done  (score_done)
    );

    scale_unit #(.N(N), .D(D)) scale (
        .clk      (clk),
        .reset    (reset),
        .start    (scale_start),
        .S        (S),
        .S_scaled (S_scaled),
        .done     (scale_done)
    );

    softmax_unit #(.N(N)) softmax (
        .clk      (clk),
        .reset    (reset),
        .start    (softmax_start),
        .S_scaled (S_scaled),
        .A        (A),
        .done     (softmax_done)
    );

    output_unit #(.N(N), .D(D), .PARALLEL(PARALLEL)) out (
        .clk   (clk),
        .reset (reset),
        .start (output_start),
        .A     (A),
        .V     (V),
        .O     (O),
        .done  (output_done)
    );

    // each *_start is a single-cycle pulse on the stage transition
    always @(posedge clk) begin
        if (reset) begin
            state         <= IDLE;
            done          <= 0;
            proj_start    <= 0;
            score_start   <= 0;
            scale_start   <= 0;
            softmax_start <= 0;
            output_start  <= 0;
        end else begin
            proj_start    <= 0;
            score_start   <= 0;
            scale_start   <= 0;
            softmax_start <= 0;
            output_start  <= 0;

            case (state)

                IDLE: begin
                    if (start) begin
                        done       <= 0;
                        proj_start <= 1;
                        state      <= PROJ;
                    end
                end

                PROJ: begin
                    if (proj_done) begin
                        score_start <= 1;
                        state       <= SCORE;
                    end
                end

                SCORE: begin
                    if (score_done) begin
                        scale_start <= 1;
                        state       <= SCALE;
                    end
                end

                SCALE: begin
                    if (scale_done) begin
                        softmax_start <= 1;
                        state         <= SOFTMAX;
                    end
                end

                SOFTMAX: begin
                    if (softmax_done) begin
                        output_start <= 1;
                        state        <= OUTPUT;
                    end
                end

                OUTPUT: begin
                    if (output_done)
                        state <= DONE_ST;
                end

                DONE_ST: begin
                    done  <= 1;
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule
