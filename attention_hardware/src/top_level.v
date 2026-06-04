module top_level #(
    parameter N = 3,
    parameter D = 4
)(
    input clk,
    input reset,
    input start,
    output reg done
);

    reg signed [7:0] X  [0:N-1][0:D-1];
    reg signed [7:0] WQ [0:D-1][0:D-1];
    reg signed [7:0] WK [0:D-1][0:D-1];
    reg signed [7:0] WV [0:D-1][0:D-1];

    wire signed [15:0] Q [0:N-1][0:D-1];
    wire signed [15:0] K [0:N-1][0:D-1];
    wire signed [15:0] V [0:N-1][0:D-1];

    wire signed [31:0] S        [0:N-1][0:N-1];
    wire signed [15:0] S_scaled [0:N-1][0:N-1];
    wire        [15:0] A        [0:N-1][0:N-1];
    wire signed [31:0] O        [0:N-1][0:D-1];

    reg proj_start, score_start, scale_start;
    reg softmax_start, output_start;

    wire proj_done, score_done, scale_done;
    wire softmax_done, output_done;

    localparam IDLE    = 4'd0;
    localparam LOAD    = 4'd1;
    localparam PROJ    = 4'd2;
    localparam SCORE   = 4'd3;
    localparam SCALE   = 4'd4;
    localparam SOFTMAX = 4'd5;
    localparam OUTPUT  = 4'd6;
    localparam WRITE   = 4'd7;
    localparam DONE_ST = 4'd8;

    reg [3:0] state;

    projection_unit #(.N(N), .D(D)) proj (
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

    score_unit #(.N(N), .D(D)) score (
        .clk   (clk),
        .reset (reset),
        .start (score_start),
        .Q     (Q),
        .K     (K),
        .S     (S),
        .done  (score_done)
    );

    scale_unit #(.N(N)) scale (
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

    output_unit #(.N(N), .D(D)) out (
        .clk   (clk),
        .reset (reset),
        .start (output_start),
        .A     (A),
        .V     (V),
        .O     (O),
        .done  (output_done)
    );

    integer r, c;

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
                    done <= 0;
                    if (start)
                        state <= LOAD;
                end

                LOAD: begin
                    $readmemh("data/X.txt",  X);
                    $readmemh("data/WQ.txt", WQ);
                    $readmemh("data/WK.txt", WK);
                    $readmemh("data/WV.txt", WV);
                    state <= PROJ;
                end

                PROJ: begin
                    proj_start <= 1;
                    if (proj_done)
                        state <= SCORE;
                end

                SCORE: begin
                    score_start <= 1;
                    if (score_done)
                        state <= SCALE;
                end

                SCALE: begin
                    scale_start <= 1;
                    if (scale_done)
                        state <= SOFTMAX;
                end

                SOFTMAX: begin
                    softmax_start <= 1;
                    if (softmax_done)
                        state <= OUTPUT;
                end

                OUTPUT: begin
                    output_start <= 1;
                    if (output_done)
                        state <= WRITE;
                end

                WRITE: begin
                    begin : write_block
                        integer fp;
                        fp = $fopen("data/output.txt", "w");
                        for (r = 0; r < N; r = r + 1) begin
                            for (c = 0; c < D; c = c + 1) begin
                                $fwrite(fp, "%0d ", O[r][c]);
                            end
                            $fwrite(fp, "\n");
                        end
                        $fclose(fp);
                    end
                    state <= DONE_ST;
                end

                DONE_ST: begin
                    done <= 1;
                end

            endcase
        end
    end

endmodule
