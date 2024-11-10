/*
 * Copyright (c) 2024 CL-123-abc
 * SPDX-License-Identifier: Apache-2.0
 */

/* Module name: tt_um_stochastic_integrator_tt9_CL123abc
 * Module description: 
 * Stochastic integrator using Euler's method of integration, so the result is a gradually acculumating integration. 
 * No auto reset, so have to manually reset.
 * References in docs.
 * More details on the submodules are found after this module below.
 * INPUTS: 
 * ui_in[0] for serial input of input a
 * ui_in[1] for serial input of input b
 * OUTPUTS:
 * uo_out[0] for serial output of sequential integrators' integrator a value
 * uo_out[1] for serial output of sequential integrators' integrator b value
 * uo_out[2] for serial output of sequential integrators' integrator c value
 * uo_out[3] for serial output of system integrators' integrator a value
 * uo_out[4] for serial output of system integrators' integrator b value
 * uo_out[5] for serial output of ODE integrators' integrator a value
 * uo_out[6] for serial output of ODE integrators' integrator b value
 * uo_out[7] for output of seq integrator c sn bitstream
 */

`default_nettype none

module tt_um_stochastic_integrator_tt9_CL123abc(
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);
	
wire [8:0] input_value_a, input_value_b;
reg [17:0] clk_counter; // synchronizes all the timers in the module, it is 18 bits because I copied the other code, will update but shouldn't matter as long as its large enough
reg [8:0] integrator_a_output_value, integrator_b_output_value, integrator_c_output_value;
reg [8:0] system_integrator_a_output_value, system_integrator_b_output_value;
reg [8:0] test_integrator_a_output_value, test_integrator_b_output_value;
wire [30:0] lfsr_output;
wire [8:0] integrator_a_counter_value, integrator_b_counter_value, integrator_c_counter_value;
wire [8:0] system_integrator_a_counter_value, system_integrator_b_counter_value;
wire [8:0] test_integrator_a_counter_value, test_integrator_b_counter_value;
wire input_sn_bit_a, input_sn_bit_b, input_sn_bit_half1, input_sn_bit_half2;
wire integrator_a_sn_bit, integrator_b_sn_bit, integrator_c_sn_bit;
wire system_integrator_a_sn_bit, system_integrator_b_sn_bit;
wire test_integrator_a_sn_bit, test_integrator_b_sn_bit;
wire uo_out_wire_0, uo_out_wire_1, uo_out_wire_2, uo_out_wire_3, uo_out_wire_4, uo_out_wire_5, uo_out_wire_6;
parameter MAX_COUNTER = 9'd511;
parameter HALF_COUNTER = 9'd256;
parameter SET_INTERVAL = 18'd16;

//Convert serial input to values
serial_to_value_input serial_input(.clk(clk), .clk_counter(clk_counter), .rst_n(rst_n), 
		.input_bit_1(ui_in[0]), .output_bitseq_1(input_value_a), .input_bit_2(ui_in[1]), .output_bitseq_2(input_value_b));

//LFSR generates the psuedorandom numbers (must be 9bits to compare) 
lfsr my_lfsr(.clk(clk), .rst_n(rst_n), .lfsr(lfsr_output));

// Three Integrators In sequence \\
// While input b (dec) is 0, generates the equations t, (t^2)/2, (t^3)/6
// Generating input SC bitstreams
		
comparator input_a_sng_comparator(.bits_a(input_value_a), .bits_b(lfsr_output[8:0]), .bit_out(input_sn_bit_a));  
comparator input_b_sng_comparator(.bits_a(input_value_b), .bits_b({lfsr_output[5:0], lfsr_output[18:16]}), .bit_out(input_sn_bit_b)); 
comparator input_halfprob1_sng_comparator(.bits_a(HALF_COUNTER), .bits_b({lfsr_output[11:5],lfsr_output[25:24]}), .bit_out(input_sn_bit_half1));
comparator input_halfprob2_sng_comparator(.bits_a(HALF_COUNTER), .bits_b({lfsr_output[22:20],lfsr_output[30:25]}), .bit_out(input_sn_bit_half2));
		
// Generating t value and corresponding SC bitstream
counter integrator_a_counter(.clk(clk), .rst_n(rst_n), .sn_bit_inc(input_sn_bit_a), 
                           .sn_bit_dec(input_sn_bit_b), .value_output(integrator_a_counter_value));  
comparator integrator_a_sng_comparator(.bits_a(integrator_a_counter_value), .bits_b(lfsr_output[30:22]), .bit_out(integrator_a_sn_bit));
		
// Generating (t^2)/2 value and corresponding SC bitstream
counter integrator_b_counter(.clk(clk), .rst_n(rst_n), .sn_bit_inc(integrator_a_sn_bit), 
                               .sn_bit_dec(input_sn_bit_b), .value_output(integrator_b_counter_value));  
comparator integrator_b_sng_comparator(.bits_a(integrator_b_counter_value), .bits_b({lfsr_output[15:13],lfsr_output[6:1]}), 
                                         .bit_out(integrator_b_sn_bit));  
		
// Generating (t^3)/6 value and corresponding SC bitstream
counter integrator_c_counter(.clk(clk), .rst_n(rst_n), .sn_bit_inc(integrator_b_sn_bit), 
                           .sn_bit_dec(input_sn_bit_b), .value_output(integrator_c_counter_value));  
comparator integrator_c_sng_comparator(.bits_a(integrator_c_counter_value), .bits_b({lfsr_output[24:19],lfsr_output[14:12]}), 
                            .bit_out(integrator_c_sn_bit));  
	
// Systems of ODEs \\
// Solving dy1/dt = y2 - 0.5, dy2/dt = 0.5 - y1
modified_counter system_integrator_a_counter(.clk(clk), .rst_n(rst_n), .sn_bit_inc(system_integrator_b_sn_bit), .sn_bit_dec(input_sn_bit_half1), 
.inc_mul(9'b1), .dec_mul(9'b1), .initial_value(9'b0), .value_output(system_integrator_a_counter_value)); 
comparator system_integrator_a_sng_comparator(.bits_a(system_integrator_a_counter_value), .bits_b(lfsr_output[30:22]), 
                 .bit_out(system_integrator_a_sn_bit));
modified_counter system_integrator_b_counter(.clk(clk), .rst_n(rst_n), .sn_bit_inc(input_sn_bit_half2), .sn_bit_dec(system_integrator_a_sn_bit), 
 .inc_mul(9'b1), .dec_mul(9'b1), .initial_value(HALF_COUNTER), .value_output(system_integrator_b_counter_value)); 
comparator system_integrator_b_sng_comparator(.bits_a(system_integrator_b_counter_value), .bits_b({lfsr_output[15:13],lfsr_output[6:1]}), 
                 .bit_out(system_integrator_b_sn_bit));

// Second order ODE \\
// Solving a stochastic ODE with equation d2y/dt2 + 2 dy/dt + y = 0
// Generates first integration, z(t) = (t+1)*e^-t
modified_counter test_integrator_a_counter(.clk(clk), .rst_n(rst_n), .sn_bit_inc(!(test_integrator_b_sn_bit)), .sn_bit_dec(input_sn_bit_a), 
.inc_mul(9'b1), .dec_mul(9'b1), .initial_value(MAX_COUNTER), .value_output(test_integrator_a_counter_value)); 
comparator test_integrator_a_sng_comparator(.bits_a(test_integrator_a_counter_value), .bits_b(lfsr_output[30:22]), 
                 .bit_out(test_integrator_a_sn_bit));
		
// Using modified counter, generates second integration, y(t) = t*e^-t
modified_counter test_integrator_b_counter(.clk(clk), .rst_n(rst_n), .sn_bit_inc(test_integrator_a_sn_bit), 
.sn_bit_dec(test_integrator_b_sn_bit), .inc_mul(9'b1), .dec_mul(9'b10), .initial_value(9'd0), .value_output(test_integrator_b_counter_value));  
comparator test_integrator_b_sng_comparator(.bits_a(test_integrator_b_counter_value), .bits_b({lfsr_output[15:13],lfsr_output[6:1]}), .bit_out(test_integrator_b_sn_bit));

//Serial outputs
value_to_serial_output integrator_a_output(.clk(clk), .rst_n(rst_n), .input_bits(integrator_a_output_value), .output_bit(uo_out_wire_0));
value_to_serial_output integrator_b_output(.clk(clk), .rst_n(rst_n), .input_bits(integrator_b_output_value), .output_bit(uo_out_wire_1));
value_to_serial_output integrator_c_output(.clk(clk), .rst_n(rst_n), .input_bits(integrator_c_output_value), .output_bit(uo_out_wire_2));
value_to_serial_output system_integrator_a_output(.clk(clk), .rst_n(rst_n), .input_bits(system_integrator_a_output_value), .output_bit(uo_out_wire_3));
value_to_serial_output system_integrator_b_output(.clk(clk), .rst_n(rst_n), .input_bits(system_integrator_b_output_value), .output_bit(uo_out_wire_4));
value_to_serial_output test_integrator_a_output(.clk(clk), .rst_n(rst_n), .input_bits(test_integrator_a_output_value), .output_bit(uo_out_wire_5));
value_to_serial_output test_integrator_b_output(.clk(clk), .rst_n(rst_n), .input_bits(test_integrator_b_output_value), .output_bit(uo_out_wire_6));

// Clock Sequential Block
always@(posedge clk or posedge rst_n) begin
    if (rst_n) begin
        clk_counter <= 0;
    end
    else begin
        clk_counter <= clk_counter + 1'b1;
    end
end
	
// Output Sequential Block
always@(posedge clk or posedge rst_n)begin
    if (rst_n) begin
        integrator_a_output_value <= 0;
        integrator_b_output_value <= 0;
        integrator_c_output_value <= 0;
        
        system_integrator_a_output_value <= 0;
        system_integrator_b_output_value <= 0;
        
        test_integrator_a_output_value <= 0;
        test_integrator_b_output_value <= 0;
    end
	else if ((clk_counter%(SET_INTERVAL)) == 0) begin // see the integration result after SET_INTERVAL
        integrator_a_output_value <= integrator_a_counter_value; 
        integrator_b_output_value <= integrator_b_counter_value;
        integrator_c_output_value <= integrator_c_counter_value;
        
        system_integrator_a_output_value <= system_integrator_a_counter_value;
        system_integrator_b_output_value <= system_integrator_b_counter_value;
        
        test_integrator_a_output_value <= test_integrator_a_counter_value;
        test_integrator_b_output_value <= test_integrator_b_counter_value;
    end
end

  // PIN LAYOUT
  // All output pins must be assigned. If not used, assign to 0.

	assign uo_out[0] = uo_out_wire_0;
	assign uo_out[1] = uo_out_wire_1; 
	assign uo_out[2] = uo_out_wire_2;
	assign uo_out[3] = uo_out_wire_3;
	assign uo_out[4] = uo_out_wire_4;
	assign uo_out[5] = uo_out_wire_5;
	assign uo_out[6] = uo_out_wire_6;
	assign uo_out[7] = integrator_c_sn_bit; 
    assign uio_out[7:0] = 0;    
    assign uio_oe[7:0]  = 0;
  
  // List all unused inputs to prevent warnings
    wire _unused = &{ena, ui_in[7:2], uio_in, 1'b0}; 
endmodule

/* SUBMODULES:
     *
     * /////////////////////////////////////////////////////////////////////////////
	 * SUBMODULE NAME:
	 * serial_to_value_input (.clk(), .clk_counter(), .rst_n(), 
	    					  .input_bit_1(), .output_bitseq_1(), 
	    					  .input_bit_2(), .output_bitseq_2());
     * SUBMODULE DESCRIPTION: 
     * Takes in serial input (10bit) carrying the 9bit probability 
	 * and gives the 9bit value as output. The last bit in the 10 is the dummy bit.
     * INPUTS:
     * .clk() takes in the clk of the whole circuit.
	 * .clk_counter() takes in the global clock counter that is controlled by the main code.
     * .rst_n() takes in the reset of the whole circuit.
	 * .input_bit_1() takes in the serial bitstream of input 1, 1 bit per clk cycle. 
     * .input_bit_2() takes in the serial bitstream of input 2, 1 bit per clk cycle. 
     * OUTPUTS:
     * .output_bitseq_1() outputs the 9bit value of input 1.
	 * .output_bitseq_2() outputs the 9bit value of input 1.
     * \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
	 *
	 * /////////////////////////////////////////////////////////////////////////////
	 * SUBMODULE NAME:
     * lfsr (.clk(), .rst_n(), .lfsr());
     * SUBMODULE DESCRIPTION:
	 * Generates and runs the LFSR, which is 31 bits long and has a seed of 31'd134995 in this code.
     * INPUTS:
     * .clk() takes in the clk of the whole circuit.
	 * .rst_n() takes in the reset of the whole circuit.
     * OUTPUTS:
	 * .lfsr() outputs the entire LFSR contents in 31-bit.
     * \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
	 *
     * /////////////////////////////////////////////////////////////////////////////
	 * SUBMODULE NAME:
     * comparator(bits_a, bits_b, bit_out)
	 * SUBMODULE DESCRIPTION:
     * Takes in the 9-bit values of a and b and outputs 1 when a>b.
     * INPUTS:
     * .bits_a() takes in a 9-bit value.
	 * .bits_b() takes in a 9-bit value.
     * OUTPUTS:
	 * .bit_out() outputs the 1-bit value that makes the sn bitstream.
     * \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
	 * /////////////////////////////////////////////////////////////////////////////
	 * SUBMODULE NAME:
     * counter(clk, rst_n, sn_bit_inc, sn_bit_dec, value_output)
	 * SUBMODULE DESCRIPTION:
     * The integrator counter that can increment and decrement. When the inc == dec, no change in value.
	 * As a default, it can only inc and dec by 1 per input and always starts at 0.
     * INPUTS:
	 * .clk() takes in the clk of the whole circuit.
	 * .rst_n() takes in the reset of the whole circuit.
     * .sn_bit_inc() takes in a 1 bit input, if inc == 1 and dec == 0, counter increments
     * .sn_bit_dec() takes in a 1 bit input, if inc == 0 and dec == 1, counter decrements
     * OUTPUTS:
	 * .value_output() outputs the current value of the counter
     * \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
	 * /////////////////////////////////////////////////////////////////////////////
	 * SUBMODULE NAME:
     * modified_counter(clk, rst_n, sn_bit_inc, sn_bit_dec, inc_mul, dec_mul, initial_value, value_output)
	 * The integrator counter that can increment and decrement. When the inc == dec, no change in value.
	 * Can set the value of inc/dec and the initial value of the counter.
	 * INPUTS:
     * .clk() takes in the clk of the whole circuit.
	 * .rst_n() takes in the reset of the whole circuit.
     * .sn_bit_inc() takes in a 1 bit input, if inc == 1 and dec == 0, counter increments.
     * .sn_bit_dec() takes in a 1 bit input, if inc == 0 and dec == 1, counter decrements.
	 * .inc_mul() takes in a 9-bit value and sets the value for each increment.
     * .dec_mul() takes in a 9-bit value and sets the value for each decrement.
	 * .initial_value() takes in a 9-bit value and sets the counter's value at reset.
     * OUTPUTS:
	 * .value_output() outputs the current value of the counter.
     * \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
	 *
     * /////////////////////////////////////////////////////////////////////////////
	 * SUBMODULE NAME:
     * value_to_serial_output(.clk(), .rst_n(), .input_bits(), .output_bit());
     * SUBMODULE DESCRIPTION:
	 * Outputs each bit in the 9bit input as a serial bitstream with an added 10th bit as 0 as a dummy bit.
     * INPUTS:
     * .clk() takes in the clk of the whole circuit.
     * .rst_n() takes in the rst_n of the whole circuit.
	 * .input_bits() takes in a 9bit value, here that is the probability of 1s in the SN bitstream.
     * OUTPUTS:
	 * .output_bit() outputs each bit in the 9bit value and then outputs 0 for the 10th bit.
     * \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
	 *
 
*/

module serial_to_value_input(clk, clk_counter, rst_n, input_bit_1, output_bitseq_1, input_bit_2, output_bitseq_2);
input wire [17:0] clk_counter;
input wire clk, rst_n, input_bit_1, input_bit_2;
output reg [8:0] output_bitseq_1, output_bitseq_2; 
reg [8:0] output_bitcounter_1, output_bitcounter_2;
reg loop; 
reg [3:0] output_case;
reg [4:0] adjustment;
	
parameter MAX_CLK_CYCLES = 18'd131072;

	always @(posedge clk or posedge rst_n) begin
    	if(rst_n) begin 
    		output_bitseq_1 <= 9'd0;
    		output_bitseq_2 <= 9'b0;
    		output_bitcounter_1 <= 9'd0;
    		output_bitcounter_2 <= 9'b0;
    		loop <= 1'b0;
			output_case <= 4'b0;
    		adjustment <= 5'd9;
    	end
    	else begin
			if (loop == 0) begin
				if (clk_counter == 0) begin
					case (output_case)
                    4'd0: adjustment <= 5'd9;
                    4'd1: adjustment <= 5'd16;
                    4'd2: adjustment <= 5'd13;
                    4'd3: adjustment <= 5'd10; 
                    4'd4: adjustment <= 5'd17; 
                    4'd5: adjustment <= 5'd14;
                    4'd6: adjustment <= 5'd11;   
                    4'd7: adjustment <= 5'd18;   
                    4'd8: adjustment <= 5'd17; 
                    4'd9: adjustment <= 5'd12;   
                    default:;
					endcase
				end
				output_bitcounter_1 <= (output_bitcounter_1 >> 1);
				output_bitcounter_1[8] <= input_bit_1;
				output_bitcounter_2 <= (output_bitcounter_2 >> 1);
				output_bitcounter_2[8] <= input_bit_2;
				if(clk_counter[4:0] == adjustment) begin
					output_bitseq_1 <= output_bitcounter_1;
					output_bitseq_2 <= output_bitcounter_2;
					loop <= 1;
				end
			end
			else if (loop == 1) begin
				if (clk_counter == MAX_CLK_CYCLES) begin
					if(output_case == 4'd9)
						output_case <= 4'd0;
					else 
						output_case <= output_case + 4'd1;
				loop <= 0;
				end
			end
		end
	end
endmodule

module lfsr(clk, rst_n, lfsr);
input wire clk, rst_n;
output reg [30:0] lfsr;

    always@(posedge clk or posedge rst_n) begin
        if (rst_n)
            lfsr <= 31'd134995;
        else begin
            lfsr[0] <= lfsr[27] ^ lfsr[30];
            lfsr[30:1] <= lfsr[29:0];
            end
        end
endmodule


module comparator(bits_a, bits_b, bit_out);
input wire [8:0] bits_a, bits_b;
output wire bit_out;

assign bit_out = (bits_a > bits_b);
endmodule

module counter(clk, rst_n, sn_bit_inc, sn_bit_dec, value_output);
input wire clk, rst_n, sn_bit_inc, sn_bit_dec;
output reg [8:0] value_output; 
//This value will change with every input, 
//so to store the integration result, need to capture the result somewhere else, timed to clk_counter

parameter MAX_LIMIT = 9'd511;
parameter MIN_LIMIT = 9'd0;
    
    always@(posedge clk or posedge rst_n) begin
        if (rst_n) begin
            value_output <= 0; 
        end
        else begin
            if (sn_bit_dec == 1 && sn_bit_inc == 0) begin
                if (value_output == MIN_LIMIT) begin //min limit
                    //stay at min limit
                end 
                else begin
                    value_output <= value_output - 1'b1;
                end
            end
            else if (sn_bit_dec == 0 && sn_bit_inc == 1) begin
                if (value_output == MAX_LIMIT) begin //max limit
                    //stay at max limit
                end
                else begin
                    value_output <= value_output + 1'b1;
                end
            end
            // If sn_bit_dec == sn_bit_inc == (0 or 1) then no change
            // Add reset?
        end
    end
endmodule

module modified_counter(clk, rst_n, sn_bit_inc, sn_bit_dec, inc_mul, dec_mul, initial_value, value_output);
input wire clk, rst_n, sn_bit_inc, sn_bit_dec;
input wire [8:0] inc_mul, dec_mul;
input wire [8:0] initial_value;
output reg [8:0] value_output; 
reg init_flag; // I would just use initial value for the async reset because the initial value is set and isn't going to change but
			   // theres a warning so I am using a init flag instead.

parameter MAX_LIMIT = 9'd511;
parameter MIN_LIMIT = 9'd0;
            // If sn_bit_dec == sn_bit_inc == (0 or 1) then no change
            // Add reset?
	
    always@(posedge clk or posedge rst_n) begin
        if (rst_n) begin
            value_output <= 0;
			init_flag <= 1;
        end
        else begin
			if (init_flag == 1) begin
            	if (sn_bit_dec == 1 && sn_bit_inc == 0) begin
					if (initial_value == MIN_LIMIT) begin //min limit
                    	//stay at min limit
						value_output <= initial_value;
                	end 
                	else begin
                    	value_output <= initial_value - dec_mul;
                	end
            	end
            	else if (sn_bit_dec == 0 && sn_bit_inc == 1) begin
					if (initial_value == MAX_LIMIT) begin //max limit
                    	//stay at max limit
						value_output <= initial_value;
                	end
                	else begin
                    	value_output <= initial_value + inc_mul;
                	end
            	end
				init_flag <= 0;
			end
			else begin //How to keep in limit when dec_mul/inc_mul is changeable and can jump over limit?
				if (sn_bit_dec == 1 && sn_bit_inc == 0) begin
					if (value_output == MIN_LIMIT) begin //min limit
                    	//stay at min limit
                	end 
					else begin 
                    	value_output <= value_output - dec_mul;
                	end
            	end
            	else if (sn_bit_dec == 0 && sn_bit_inc == 1) begin
					if (value_output == MAX_LIMIT) begin //max limit
                    	//stay at max limit
                	end
                	else begin
                    	value_output <= value_output + inc_mul;
                	end
            	end
			end
        end
    end
endmodule

module value_to_serial_output(clk, rst_n, input_bits, output_bit);
input wire clk, rst_n;
input wire [8:0] input_bits;
reg [8:0] bitseq;
reg [3:0] counter;
output reg output_bit;
parameter NUMBER_OF_BITS = 4'd9;

	always@(posedge clk or posedge rst_n) begin
		if(rst_n) begin
            bitseq <= 0;
            counter <= 0;
            output_bit <= 0;
        end
        else begin
			case(counter)
			0: begin
				output_bit <= input_bits[0];
                bitseq <= input_bits >> 1;
                counter <= counter + 1;
			end
			NUMBER_OF_BITS: begin
				output_bit <= 0;
                counter <= 0;
			end
			default: begin
				bitseq <= bitseq >> 1;
                output_bit <= bitseq[0];
                counter <= counter + 1;
			end
			endcase
         end
    end
endmodule
