// MODULE: neuron_processor_tb
//
// DESCRIPTION:
// Self-checking testbench for the neuron_processor. It drives randomized and directed
// input/weight chunk streams, models the expected popcount and thresholded activation
// in software, and compares against the DUT via a scoreboard queue. It exercises:
//   - multi-chunk accumulation (CHUNKS > 1)
//   - back-to-back neurons (no idle cycle between results)
//   - randomized in_valid gaps (slow producer)
//   - threshold boundary conditions (popcount == threshold-1 / threshold / threshold+1)
//   - all-match (popcount = max) and all-mismatch (popcount = 0) extremes
//   - synchronous reset in the middle of a neuron
// A functional covergroup tracks popcount range and the threshold boundary cases.
//
// Change PARALLEL_INPUTS / NUM_INPUTS below to sweep configurations. The reference
// model is independent of those values, so the same TB verifies any legal setting.

`timescale 1ns / 100ps

module neuron_processor_tb;

    // ---- DUT configuration (edit to sweep) ----------------------------------
    localparam int PARALLEL_INPUTS = 8;
    localparam int NUM_INPUTS      = 20;  // CHUNKS = ceil(20/8) = 3 (multi-chunk)

    // ---- Test configuration -------------------------------------------------
    localparam int      NUM_RANDOM_NEURONS = 2000;
    localparam real     VALID_PROBABILITY  = 0.7;  // producer valid rate (gap injection)
    localparam realtime CLK_PERIOD         = 10ns;
    localparam realtime TIMEOUT            = 5ms;

    // ---- Derived ------------------------------------------------------------
    localparam int CHUNKS         = (NUM_INPUTS + PARALLEL_INPUTS - 1) / PARALLEL_INPUTS;
    localparam int MAX_POPCOUNT   = CHUNKS * PARALLEL_INPUTS;  // all bits matched
    localparam int POPCOUNT_WIDTH = $clog2(MAX_POPCOUNT + 1);

    logic clk = 1'b0;
    logic rst;

    logic [PARALLEL_INPUTS-1:0] inputs;
    logic [PARALLEL_INPUTS-1:0] weights;
    logic [               31:0] threshold;
    logic                       in_valid;
    logic                       in_ready;

    logic                      out_valid;
    logic                      out;
    logic [POPCOUNT_WIDTH-1:0] popcount;

    neuron_processor #(
        .PARALLEL_INPUTS(PARALLEL_INPUTS),
        .NUM_INPUTS     (NUM_INPUTS)
    ) DUT (
        .clk      (clk),
        .rst      (rst),
        .inputs   (inputs),
        .weights  (weights),
        .threshold(threshold),
        .in_valid (in_valid),
        .in_ready (in_ready),
        .out_valid(out_valid),
        .out      (out),
        .popcount (popcount)
    );

    // ---- Scoreboard ---------------------------------------------------------
    typedef struct {
        int unsigned id;
        int unsigned popcount;
        bit          out;
        int unsigned threshold;
    } expected_t;

    expected_t exp_q[$];
    int unsigned neuron_id;
    int unsigned checks;
    int unsigned errors;

    // ---- Functional coverage ------------------------------------------------
    // Sampled explicitly from the monitor (with arguments) to avoid a race with the
    // scoreboard updates on the same clock event.
    covergroup cg with function sample(int pop, int boundary, bit o);
        cp_popcount: coverpoint pop {
            bins zero    = {0};
            bins low     = {[1 : MAX_POPCOUNT/3]};
            bins mid     = {[MAX_POPCOUNT/3 + 1 : 2*MAX_POPCOUNT/3]};
            bins high    = {[2*MAX_POPCOUNT/3 + 1 : MAX_POPCOUNT-1]};
            bins maximum = {MAX_POPCOUNT};
        }
        cp_boundary: coverpoint boundary {
            bins below_thresh = {[-1000 : -2]};
            bins just_below   = {-1};
            bins at_thresh    = {0};
            bins just_above   = {1};
            bins above_thresh = {[2 : 1000]};
        }
        cp_out: coverpoint o;
        cross cp_out, cp_boundary;
    endgroup
    cg cov = new();

    // ---- Clock --------------------------------------------------------------
    initial forever #(CLK_PERIOD / 2) clk <= ~clk;

    // Returns 1 with probability p.
    function automatic bit chance(real p);
        return ($urandom < (p * (2.0 ** 32)));
    endfunction

    // ---- Driver task --------------------------------------------------------
    // Streams CHUNKS beats for one neuron and pushes the expected result. If
    // threshold_override >= 0, that exact threshold is used; otherwise it is chosen
    // relative to the realized popcount via thresh_offset to hit boundary cases.
    task automatic drive_neuron(input bit randomize_data,
                                input bit [PARALLEL_INPUTS-1:0] fixed_in,
                                input bit [PARALLEL_INPUTS-1:0] fixed_w,
                                input int thresh_offset,
                                input longint threshold_override);
        int unsigned pop = 0;
        bit [PARALLEL_INPUTS-1:0] in_beats[CHUNKS];
        bit [PARALLEL_INPUTS-1:0] w_beats [CHUNKS];
        longint thr;

        // Pre-roll the data so the threshold can be derived from the popcount.
        for (int c = 0; c < CHUNKS; c++) begin
            in_beats[c] = randomize_data ? $urandom : fixed_in;
            w_beats[c]  = randomize_data ? $urandom : fixed_w;
            pop += $countones(in_beats[c] ~^ w_beats[c]);
        end

        if (threshold_override >= 0) thr = threshold_override;
        else begin
            thr = int'(pop) + thresh_offset;
            if (thr < 0) thr = 0;
        end

        // Stream the beats with randomized gaps.
        for (int c = 0; c < CHUNKS; c++) begin
            while (!chance(VALID_PROBABILITY)) begin
                in_valid <= 1'b0;
                @(posedge clk);
            end
            in_valid  <= 1'b1;
            inputs    <= in_beats[c];
            weights   <= w_beats[c];
            threshold <= 32'(thr);
            @(posedge clk iff in_ready);
        end
        in_valid <= 1'b0;

        exp_q.push_back('{
            id        : neuron_id,
            popcount  : pop,
            out       : (pop >= thr),
            threshold : 32'(thr)
        });
        neuron_id++;
    endtask

    // ---- Monitor / checker --------------------------------------------------
    initial begin : monitor
        forever begin
            @(posedge clk iff out_valid);
            assert (exp_q.size() > 0)
            else $fatal(1, "[%0t] out_valid with no expected result queued", $realtime);

            begin
                expected_t e = exp_q.pop_front();
                checks++;

                cov.sample(int'(popcount), int'(popcount) - int'(e.threshold), out);

                assert (popcount == e.popcount)
                else begin
                    errors++;
                    $error("[%0t] neuron %0d: popcount actual=%0d expected=%0d",
                           $realtime, e.id, popcount, e.popcount);
                end
                assert (out == e.out)
                else begin
                    errors++;
                    $error("[%0t] neuron %0d: out actual=%b expected=%b (pop=%0d thr=%0d)",
                           $realtime, e.id, out, e.out, e.popcount, e.threshold);
                end
            end
        end
    end

    // ---- Stimulus -----------------------------------------------------------
    initial begin : stimulus
        $timeformat(-9, 0, " ns", 0);
        neuron_id = 0;
        checks    = 0;
        errors    = 0;

        rst       <= 1'b1;
        inputs    <= '0;
        weights   <= '0;
        threshold <= '0;
        in_valid  <= 1'b0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst <= 1'b0;
        repeat (2) @(posedge clk);

        // --- Directed extremes -----------------------------------------------
        // All match -> popcount = MAX_POPCOUNT. Boundary at exactly threshold.
        drive_neuron(0, '1, '1, 0, MAX_POPCOUNT);      // pop==thr -> out=1
        drive_neuron(0, '1, '1, 0, MAX_POPCOUNT + 1);  // pop<thr  -> out=0
        // All mismatch -> popcount = 0.
        drive_neuron(0, '1, '0, 0, 0);                 // pop==thr==0 -> out=1
        drive_neuron(0, '1, '0, 0, 1);                 // pop<thr     -> out=0

        // --- Directed threshold boundaries on random data --------------------
        for (int i = 0; i < 200; i++) begin
            drive_neuron(1, '0, '0, -1, -1);  // thr = pop-1 -> out=1
            drive_neuron(1, '0, '0,  0, -1);  // thr = pop   -> out=1
            drive_neuron(1, '0, '0,  1, -1);  // thr = pop+1 -> out=0
        end

        // --- Reset in the middle of a neuron ---------------------------------
        wait (exp_q.size() == 0);  // drain prior results so the check below is meaningful
        in_valid  <= 1'b1;
        inputs    <= '1;
        weights   <= '1;
        threshold <= 1;
        @(posedge clk iff in_ready);  // accept one beat of a CHUNKS-long neuron
        in_valid <= 1'b0;
        rst      <= 1'b1;
        @(posedge clk);
        rst <= 1'b0;
        @(posedge clk);
        assert (exp_q.size() == 0)
        else $error("Scoreboard not drained before post-reset test");
        // A fresh neuron must compute correctly (no leftover accumulation).
        drive_neuron(0, '1, '1, 0, MAX_POPCOUNT);

        // --- Bulk randomized -------------------------------------------------
        for (int i = 0; i < NUM_RANDOM_NEURONS; i++) begin
            drive_neuron(1, '0, '0, 0, $urandom_range(0, MAX_POPCOUNT + 2));
        end

        // Drain.
        wait (exp_q.size() == 0);
        repeat (5) @(posedge clk);

        $display("\n==================== neuron_processor_tb ====================");
        $display("Config: PARALLEL_INPUTS=%0d NUM_INPUTS=%0d CHUNKS=%0d",
                 PARALLEL_INPUTS, NUM_INPUTS, CHUNKS);
        $display("Checks run: %0d", checks);
        $display("Coverage:   %0.2f%%", cov.get_inst_coverage());
        if (errors == 0) $display("RESULT: PASSED");
        else $display("RESULT: FAILED (%0d errors)", errors);
        $display("=============================================================\n");

        $finish;
    end

    initial begin : watchdog
        #TIMEOUT;
        $fatal(1, "Simulation timed out after %0t", TIMEOUT);
    end

endmodule
