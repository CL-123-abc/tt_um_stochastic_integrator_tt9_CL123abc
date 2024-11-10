# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: MIT
#import the coco functionality

#import cocotb 
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
n_clock = 1000000
            
#Start the test
@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")
    # Set the clock period to 10 us (100 KHz)
    clock = Clock(dut.clk, 20, units="ns")
    #Start the clock
    cocotb.start_soon(clock.start())
    
    # Run through the reset sequence. Start low, go high, go back to low. The teset begins when the reset goes low.
    dut._log.info("Reset")
    
    #Set inputs for enable, ui_in and uio_in
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    
    #Set reset to 0
    dut.rst_n.value = 0
    
    #wait 5 clock cycle
    await ClockCycles(dut.clk,5)
    
    #Set reset to 1
    dut.rst_n.value = 1
    
    #wait for five clock cycles.
    await ClockCycles(dut.clk, 5)
    
    #Set reset to 0
    dut.rst_n.value = 0
    
    #True test begins here
    dut._log.info("Test project behavior")
    await ClockCycles(dut.clk,1) 
    test_out_prob = 0
    #Set input sample
    input_array1 = [1,1,1,1,1,1,1,1,1,1] # Max
    input_array2 = [0,0,0,0,0,0,0,0,0,0] # Min 
    # 10th bit is not read
    #Compare output to theory for each clock cycle

    for i in range(0,n_clock):
        dut.ui_in[0].value = input_array1[i%10]
        dut.ui_in[1].value = input_array2[i%10]
        # Wait for 1 clock cycles to see the output values
        await ClockCycles(dut.clk, 1) 
        
        #The following assertion is just an example of how to check the output values.
    
        # Test (assert) that we are getting the expected output.
        
        #assert test_out_prob == out_prob[i]
      
