module scale_unit #(
    parameter N      = 3,
    parameter D      = 4,   // head dimension; scale factor is 1/sqrt(D)
    parameter FRAC   = 4,   // fractional bits of S_scaled (Q11.4)
    parameter RSHIFT = 8    // extra precision bits in the reciprocal constant
)(
    input clk,
    input reset,
    input start,
    input  signed [31:0] S        [0:N-1][0:N-1],
    output reg signed [31:0] S_scaled [0:N-1][0:N-1],  // Q27.4
    output reg done
);

    // RECIP = round(2^(RSHIFT+FRAC) / sqrt(D)), evaluated at elaboration
    // using only integer math: 2^(R+F)/sqrt(D) = sqrt(2^(2(R+F)) / D).
    function integer recip_sqrt;
        input integer d;
        integer target, r;
        begin
            target = (1 << (2 * (RSHIFT + FRAC))) / d;
            r = 0;
            while ((r + 1) * (r + 1) <= target)
                r = r + 1;
            // round to nearest: r+1 is closer when (r+0.5)^2 < target
            if (r * r + r < target)
                r = r + 1;
            recip_sqrt = r;
        end
    endfunction

    localparam integer RECIP = recip_sqrt(D);  // 2048 exactly for D=4
    localparam signed [47:0] ROUND = 1 << (RSHIFT - 1);

    // S_scaled = round(S * 2^FRAC / sqrt(D)); constant multiply reduces to
    // shifts/adds in synthesis. Headroom: |S|/sqrt(D) must fit Q27.4.
    wire signed [47:0] scaled_full [0:N-1][0:N-1];

    genvar gi, gj;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : g_row
            for (gj = 0; gj < N; gj = gj + 1) begin : g_col
                assign scaled_full[gi][gj] =
                    (($signed({{16{S[gi][gj][31]}}, S[gi][gj]}) * RECIP) + ROUND) >>> RSHIFT;
            end
        end
    endgenerate

    integer i, j;

    always @(posedge clk) begin
        if (reset) begin
            done <= 0;
        end else begin
            done <= 0;
            if (start) begin
                for (i = 0; i < N; i = i + 1)
                    for (j = 0; j < N; j = j + 1)
                        S_scaled[i][j] <= scaled_full[i][j][31:0];
                done <= 1;
            end
        end
    end

endmodule
