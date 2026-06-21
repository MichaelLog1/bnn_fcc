// MODULE: neuron_processor
//
// DESCRIPTION:
// Computes a single BNN neuron activation. A neuron's output is determined by the
// population count (popcount) of the bitwise XNOR between its input bits and weight
// bits, compared against a threshold:
//
//     activation = (popcount(inputs XNOR weights) >= threshold)
//
// Inputs and weights are consumed PARALLEL_INPUTS bits at a time over
// CHUNKS = ceil(NUM_INPUTS / PARALLEL_INPUTS) accepted beats. The popcount of each
// beat is computed in a single cycle with $countones and accumulated. After the last
// beat, the result is registered for one cycle on out/out_valid, and the raw
// accumulated popcount is exposed on the popcount port (used by the output layer for
// argmax, where the threshold comparison is irrelevant).
//
// HANDSHAKE:
// A beat is accepted whenever (in_valid && in_ready). in_ready is always asserted:
// the processor can absorb one beat per cycle and never needs to stall its producer.
// Gaps are allowed; cycles without in_valid are simply ignored. The first beat after
// reset (or after a result is produced) is treated as chunk 0 of the next neuron, so
// neurons can be streamed back-to-back with no bubble.
//
// PADDING:
// The processor counts all PARALLEL_INPUTS bits of every beat, including any padding
// on the final (partial) chunk. BNN padding is neutral by construction: inputs are
// padded with 0s and weights with 1s, and XNOR(0,1) = 0 contributes nothing to the
// popcount. The producer is responsible for supplying that padding.

module neuron_processor #(
    parameter  int PARALLEL_INPUTS = 8,
    parameter  int NUM_INPUTS      = 784,  // fan-in (nodes in previous layer)
    // Max popcount equals the number of bits actually accumulated, which rounds the
    // fan-in up to a whole number of PARALLEL_INPUTS-wide chunks (the final chunk's
    // neutral padding bits are still counted). Size the result to that worst case.
    localparam int POPCOUNT_WIDTH  =
        $clog2(((NUM_INPUTS + PARALLEL_INPUTS - 1) / PARALLEL_INPUTS) * PARALLEL_INPUTS + 1)
) (
    input logic clk,
    input logic rst,  // synchronous, active high

    // Input chunk stream (inputs/weights valid when in_valid is asserted)
    input  logic [PARALLEL_INPUTS-1:0] inputs,
    input  logic [PARALLEL_INPUTS-1:0] weights,
    input  logic [               31:0] threshold,
    input  logic                       in_valid,
    output logic                       in_ready,

    // Result (asserted for one cycle after the final chunk is accepted)
    output logic                      out_valid,
    output logic                      out,       // thresholded activation
    output logic [POPCOUNT_WIDTH-1:0] popcount   // raw popcount (for output-layer argmax)
);

    localparam int CHUNKS      = (NUM_INPUTS + PARALLEL_INPUTS - 1) / PARALLEL_INPUTS;
    localparam int CHUNK_CNT_W = $clog2(CHUNKS + 1);

    // Population count accumulator and beat (chunk) counter.
    logic [POPCOUNT_WIDTH-1:0] count_r;
    logic [   CHUNK_CNT_W-1:0] beat_r;

    // Popcount of the current beat and the running accumulation including it.
    logic [POPCOUNT_WIDTH-1:0] chunk_pop;
    logic [POPCOUNT_WIDTH-1:0] acc;

    assign in_ready  = 1'b1;
    assign chunk_pop = POPCOUNT_WIDTH'($countones(inputs ~^ weights));
    assign acc       = count_r + chunk_pop;

    always_ff @(posedge clk) begin
        if (rst) begin
            count_r   <= '0;
            beat_r    <= '0;
            out_valid <= 1'b0;
            out       <= 1'b0;
            popcount  <= '0;
        end else begin
            out_valid <= 1'b0;  // default: single-cycle pulse

            if (in_valid && in_ready) begin
                if (beat_r == CHUNK_CNT_W'(CHUNKS - 1)) begin
                    // Final chunk of this neuron: emit result, rearm for the next.
                    out_valid <= 1'b1;
                    out       <= (acc >= threshold);
                    popcount  <= acc;
                    count_r   <= '0;
                    beat_r    <= '0;
                end else begin
                    count_r <= acc;
                    beat_r  <= beat_r + 1'b1;
                end
            end
        end
    end

endmodule
