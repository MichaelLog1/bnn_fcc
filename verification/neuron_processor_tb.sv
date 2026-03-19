`timescale 1ns / 100ps

module neuron_processor_tb;

    localparam bit PARALLELIZE_LAYERS = 1'b0;
    localparam int PARALLEL_NEURONS = 1;
    localparam int PARALLEL_INPUTS = 4;
    localparam int NUM_INPUTS = 10;

    logic clk = 1'b0;
    logic rst;

    logic [PARALLEL_INPUTS-1:0] inputs;
    logic [PARALLEL_INPUTS-1:0] weights;
    logic [               31:0] threshold;

    logic valid_in;
    logic valid_out;

    logic out;

    neuron_processor #(
        .PARALLEL_INPUTS (PARALLEL_INPUTS),
        .PARALLEL_NEURONS(PARALLEL_NEURONS),
        .NUM_INPUTS(NUM_INPUTS)
    ) DUT (
        .clk(clk),
        .rst(rst),

        .inputs    (inputs),
        .weights   (weights),
        .threshold(threshold),
        .valid_in(valid_in),
        .valid_out(valid_out),
        .out(out)
    );

    // function automatic int popcount_xnor(
    //     int current_count,
    //     input logic [PARALLEL_INPUTS-1:0] a,
    //     input logic [PARALLEL_INPUTS-1:0] b
    // );
    //     popcount_xnor = current_count + $countones(a ~^ b);
    // endfunction
    
    initial begin : generate_clock
        forever #5 clk <= ~clk;
    end

    initial begin : apply_tests
        $timeformat(-9, 0, " ns", 0);

        rst           <= 1'b1;
        inputs        <= '0;
        weights       <= '0;
        valid_in  <= 1'b0;
        threshold     <= 32'b10;


        repeat (5) @(posedge clk);
        @(negedge clk);
        rst <= 1'b0;
        repeat (5) @(posedge clk);

        @(posedge clk);
        valid_in  <= 1'b1;
        inputs        <= 4'b0011;
        weights       <= 4'b1010;
        // should be 2

        @(posedge clk)
        valid_in <= 1'b0;
        inputs        <= 4'b1111;
        weights       <= 4'b1000;
        //should be 0

        @(posedge clk);
        valid_in  <= 1'b1;
        inputs        <= 4'b0111;
        weights       <= 4'b1100;
        //should be 1

        @(posedge clk);
        valid_in  <= 1'b1;
        inputs        <= 4'b1111;
        weights       <= 4'b0000;
        //should be 0
        @(posedge clk);
        valid_in  <= 1'b0;
        repeat (80) @(posedge clk);
       
        valid_in <= 1'b0;
        disable generate_clock;
        $display("Tests completed.");
    end

    // initial begin : check_results
    //     int expected = 0;

    //     forever begin
    //         @(posedge clk);

    //         if (inputs_valid && weights_valid && rd_en) begin
    //             expected = popcount_xnor(expected, inputs, weights);

    //             $display("[%0t] XNOR=%b popcount=%0d",
    //                     $time, inputs ~^ weights, expected);

    //         end
    //         if (out_valid) begin
    //             if (expected >= threshold) begin
    //                 assert (out === 1'b1)
    //                     else $error("[%0t] ERROR: popcount >= threshold (%0d > %0d) but out=%b",
    //                                 $time, expected, threshold, out);
    //             end else begin
    //                 assert (out === 1'b0)
    //                     else $error("[%0t] ERROR: popcount < threshold (%0d <= %0d) but out=%b",
    //                                 $time, expected, threshold, out);
    //             end

    //             $display("[%0t] popcount=%0d threshold=%0d out=%b",
    //                     $time, expected, threshold, out);
    //         end
    //     end
    // end

endmodule