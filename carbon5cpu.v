module Add_32 (
    output signed [0:31] Output,
    output carryOut,
    input signed [0:31] A,
    input signed [0:31] B,
    input carry
);
    // Explicit 33-bit concatenation operation preserves the single-bit carry link
    assign {carryOut, Output} = A + B + carry;
endmodule //Add_32

module Sub_32 (
    output signed [0:31] Output,
    output carryOut,
    input signed [0:31] A,
    input signed [0:31] B,
    input carry
);
    // Standard Two's Complement borrow logic
    assign {carryOut, Output} = A + (~B) + carry;
endmodule //Sub_32

module Mult_32 (
    output signed [0:31] outLow,            
    output signed [0:31] outHigh,  
    input signed [0:31] A,
    input signed [0:31] B,
    input carryIn // Changed from 32-bit vector to 1-bit input
);
    wire signed [0:63] rawProduct;
    assign rawProduct = A * B;
    
    wire signed [0:63] finalResult;
    // Sign-extend the single-bit carry across the product matrix boundary
    assign finalResult = rawProduct + {{63{1'b0}}, carryIn};
    
    // Adjusted slices to follow Big-Endian [0:31] ordering mapping rules
    assign outLow  = finalResult[32:63];
    assign outHigh = finalResult[0:31];
endmodule //Mult_32

module Div_32 (
    output signed [0:31] Quotient,
    output signed [0:31] Remainder,
    input signed [0:31] A,                     
    input signed [0:31] B,
    input carryIn // Changed from 32-bit vector to 1-bit input for uniform interface
);
    assign Quotient  = (B != 32'd0) ? (A / B) : 32'd0;
    assign Remainder = (B != 32'd0) ? ((A % B) + {{31{1'b0}}, carryIn}) : 32'd0;
endmodule //Div_32

module Bsl_32 (
    output [0:31] Output,   
    output carryOut,
    input  [0:31] A,
    input  [0:31] Shift_Amount
);
    reg [0:31] fullOutput;

    always @(*) begin
        fullOutput = fullOutput << Shift_Amount;
    end

    assign Output   = fullOutput[0:31];
    assign carryOut = fullOutput[31]; 
endmodule //Bsl_32

module Bsr_32 (
    output [0:31] Output,   
    output carryOut,
    input  [0:31] A,
    input  [0:31] Shift_Amount
);
    reg [0:31] fullOutput;

    always @(*) begin
        fullOutput = fullOutput >> Shift_Amount;
    end

    assign Output   = fullOutput[0:31];
    assign carryOut = fullOutput[31]; 
endmodule //Bsr_32


module ALU_32 (
    output signed [0:31] ALUOutput,
    output signed [0:31] ALUCarry,
    output reg ZeroFlag,
    output reg CarryFlag,
    output reg NegativeFlag,

    input signed [0:31] a,
    input signed [0:31] b,
    input carry, // Unified 1-bit carry interface
    input [0:2] state
);
    wire signed [0:31] addOut, subOut, multOutLow, multOutHigh, divQuotient, divRemainder, bslOut, bsrOut;
    wire addCarry, subCarry, bslCarry, bsrCarry;

    // Structural Instantiations passing the single-bit chain links directly
    Add_32 addUnit(.Output(addOut), .carryOut(addCarry), .A(a), .B(b), .carry(carry));

    Sub_32 subUnit(.Output(subOut), .carryOut(subCarry), .A(a), .B(b), .carry(carry));

    Mult_32 multUnit(.outLow(multOutLow), .outHigh(multOutHigh), .A(a), .B(b), .carryIn(carry));

    // Handle internal signs extraction for Division blocks
    wire [0:31] abs_a = a[0] ? (-a) : a;
    wire [0:31] abs_b = b[0] ? (-b) : b;
    wire [0:31] raw_divWire;
    wire [0:31] raw_divRemainder;

    Div_32 div (.Quotient(raw_divWire), .Remainder(raw_divRemainder), .A(abs_a), .B(abs_b), .carryIn(carry));

    Bsl_32 bslUnit(.Output(bslOut), .carryOut(bslCarry), .A(a), .Shift_Amount(b));

    Bsr_32 bsrUnit(.Output(bsrOut), .carryOut(bsrCarry), .A(a), .Shift_Amount(b));

    reg signed [0:31] rOutput;
    reg signed [0:31] rCarry;
    reg rCarryOutBit; // Track the single active bit mapping out to the system bus

    always @(*) begin
        case (state)
            3'd0: begin 
                rOutput = addOut;  
                rCarry = {{31{1'b0}}, addCarry}; 
                rCarryOutBit = addCarry; 
            end
            3'd1: begin 
                rOutput = subOut;  
                rCarry = {{31{1'b0}}, subCarry}; 
                rCarryOutBit = subCarry; 
            end
            3'd2: begin 
                rOutput = multOutLow;  
                rCarry = multOutHigh; 
                rCarryOutBit = |multOutHigh; // Reduction OR sets carry bit if high-overflow happens
            end
            3'd3: begin 
                rOutput = raw_divWire;  
                rCarry = raw_divRemainder; 
                rCarryOutBit = |raw_divRemainder; 
            end
            3'd4: begin 
                rOutput = bslOut;  
                rCarry = {{31{1'b0}}, bslCarry}; 
                rCarryOutBit = bslCarry; 
            end
            3'd5: begin 
                rOutput = bsrOut;  
                rCarry = {{31{1'b0}}, bsrCarry}; 
                rCarryOutBit = bsrCarry; 
            end
            default: begin 
                rOutput = 32'd0; 
                rCarry = 32'd0; 
                rCarryOutBit = 1'b0; 
            end
        endcase

        // Evaluate Status Flags based on current results array output
        if (rOutput == 32'd0) begin
            ZeroFlag = 1'b1;
        end else begin
            ZeroFlag = 1'b0;
        end

        if (rOutput[0] == 1'b1) begin // Check the sign bit (Bit 0 in [0:31] specification syntax)
            NegativeFlag = 1'b1;
        end else begin
            NegativeFlag = 1'b0;
        end

        // Clean 1-bit state link ready to connect to the next instruction block
        CarryFlag = rCarryOutBit;
    end

    assign ALUCarry  = rCarry; 
    assign ALUOutput = rOutput;
endmodule



module RAM_32 (
    output [127:0] dataOut,     // Reads full 128-bit cache line
    input  [127:0] dataIn,      // Writes full 128-bit cache line
    input  [27:0]  address,     // Line tag address (Address[31:4])
    input          writeEnable,
    input          clock    
);
    // 2048 entries, each holding one 128-bit (16-byte) cache line
    reg [127:0] ram [0:2047];

    always @(posedge clock) begin
        if (writeEnable) begin 
            ram[address] <= dataIn; 
        end 
    end

    assign dataOut = ram[address];
endmodule
//use ts later

module test_RAM_32 (
    output [31:0] dataOut,     // Reads full 128-bit cache line
    input  [31:0] dataIn,      // Writes full 128-bit cache line
    input  [31:0]  address,     // Line tag address (Address[31:4])
    input          writeEnable,
    input          clock    
);
    // its small cus i dont want to use too much memory for testing
    reg [31:0] ram [0:127];

    always @(posedge clock) begin
        if (writeEnable) begin 
            ram[address] <= dataIn; 
        end 
    end

    assign dataOut = ram[address];
endmodule

// 1024-word Instruction ROM module
module Instruction_ROM_32 #(
    parameter FILE_NAME = "instructions_default.mem"
) (
    output reg [7:0] instruction,
    input [31:0] address
);
    reg [7:0] rom [0:127];

    initial begin
        $readmemh(FILE_NAME, rom);
    end

    always @(*) begin
        instruction <= rom[address];
    end
endmodule //Instruction_ROM_32

module Opcode_Multiplexer_Decode (
    input [7:0] opcode,
    output reg  ADD, SUB, MUL, DIV, BSL, BSR, IDC, DEC, 
                MOVE, PUSH, POP, CALL, RET, JPE, JNE, JPL, 
                JPG, JMPR, HLT, CMP, VAR1, VAR2, VAR3, VAR4
);
    always @(*) begin
        // Reset all control signals to 0 by default to prevent latches
        {ADD, SUB, MUL, DIV, BSL, BSR, IDC, DEC, 
         MOVE, PUSH, POP, CALL, RET, JPE, JNE, JPL, 
         JPG, JMPR, HLT, CMP, VAR1, VAR2, VAR3, VAR4} = 1'b0;

        case (opcode[7:2])//last 2 bytes are used for variants
            6'b001000: ADD = 1'b1;
            6'b001001: SUB = 1'b1;   
            6'b001010: MUL = 1'b1;
            6'b001011: DIV = 1'b1;
            6'b001100: BSL = 1'b1;
            6'b001101: BSR = 1'b1;
            6'b001110: IDC = 1'b1;
            6'b001111: DEC = 1'b1;
            //alu commands start with 001
            6'b010000: MOVE = 1'b1; //move data
            //move commands start with 01
            6'b011000: PUSH = 1'b1; //push to stack
            6'b011001: POP = 1'b1; //pop from stack
            //stack commands start with 011
            6'b100000: CALL = 1'b1; //call subroutine
            6'b100001: RET = 1'b1; //return from subroutine
            //func commands start with 100
            6'b101000: JPE = 1'b1; //jump if equal
            6'b101001: JNE = 1'b1; //jump if not equal
            6'b101010: JPL = 1'b1; //jump if less
            6'b101011: JPG = 1'b1; //jump if greater
            6'b101100: JMPR = 1'b1; //unconditional jump
            6'b101101: CMP = 1'b1; //compare args
            //jump commands start with 101
            6'b111111: HLT = 1'b1; //halt execution
            
            default: ;
        endcase

        case (opcode[1:0]) //last 2 bits are used for variants
            2'b00: VAR1 = 1'b1;
            2'b01: VAR2 = 1'b1;
            2'b10: VAR3 = 1'b1;
            2'b11: VAR4 = 1'b1;
            default: ;
        endcase
    end
endmodule

module Central_Unit (
    output reg signed [31:0] output1 = 32'd0,
    output reg halt = 1'b0,
    input wire clock,
    input wire signed [31:0] Input1
);
    parameter low = 32'd0;
    
    reg [7:0] opcode = low;
    reg [31:0] programCounter = low;
    reg [31:0] stackPointer = low;
    reg [31:0] basePointer = low;
    reg [31:0] accumulator = low;
    reg [31:0] accumulatorExtended = low;
    reg [31:0] counter = low;

    reg [31:0] registers [0:7]; // 8 general-purpose registers
    reg [2:0] decayCounter = low; //what stage of inst execution counter
    reg [2:0] intDecay = low; //loading a constant takes 4 stages, so this counts the stage
    reg [7:0] inst = low; //what the inst rom is currently outputing
    reg [31:0] aluInputA = low;
    reg [31:0] aluInputB = low;
    reg [31:0] ramAddress = low;

    reg thread = low;

    wire [31:0] dataBus = low;

    //microcode control regs

    //special purpose registeres to databus
    reg pcDBmc = low;
    reg spDBmc = low;
    reg bpDBmc = low;
    reg acDBmc = low;
    reg aoDBmc = low;
    reg cnDBmc = low;
    
    //general purpose registers mcs
    reg r0DBmc = low;
    reg r1DBmc = low;
    reg r2DBmc = low;
    reg r3DBmc = low;
    reg r4DBmc = low;
    reg r5DBmc = low;
    reg r6DBmc = low;
    reg r7DBmc = low;

    //conection to inst
    reg instDBmc = low;

    //ALU io to databus
    reg [2:0] aluStateMc = 3'd7;
    reg DBaluAmc = low;
    reg DBaluBmc = low;
    reg aluOutDBmc = low;
    reg aluDest = low;

    //RAM io to databus
    reg DBmemDataIn = low;
    reg DBmemAds = low;
    reg memOutDB = low;
    reg memWriteEnable = low;

    //databus to special purpose registers
    reg DBpcmc = low;
    reg DBspmc = low;
    reg DBbpmc = low;
    reg DBacmc = low;
    reg DBaomc = low;
    reg DBcnmc = low;

    //general regs
    reg DBr0mc = low;
    reg DBr1mc = low;
    reg DBr2mc = low;
    reg DBr3mc = low;
    reg DBr4mc = low;
    reg DBr5mc = low;
    reg DBr6mc = low;
    reg DBr7mc = low;

    //connection to address generator
    reg DBagmc = low;

    wire [7:0] inst1 = low;

    Instruction_ROM_32 #(.FILE_NAME("D:/programs/Cpu folder/thread1Program.txt")) instRom_T1 (
        .instruction(inst1), .address(programCounter)
    );

    wire [31:0] ALUOutput = low;
    wire [31:0] ALUCarry = low;
    wire [31:0] ALUInputA = low;
    wire [31:0] ALUInputB = low;
    reg carryIn = low;
    reg [0:2] aluState = low;
    wire carryFlag = low;
    wire zeroFlag = low;
    wire negativeFlag = low;
    
    ALU_32 ALU (
        .ALUOutput(ALUOutput), .ALUCarry(ALUCarry),
        .CarryFlag(carryFlag), .ZeroFlag(zeroFlag), .NegativeFlag(negativeFlag),
        .a(ALUInputA), .b(ALUInputB), .carry(carryIn), .state(aluState)
    );

    wire [31:0] memAddress = low;
    wire [31:0] memOut = low;
    wire [31:0] memIn = low;
    wire memWriteEnableWire = low;
    reg memFlag = low;

    test_RAM_32 RAM (
        .dataOut(memAddress),
        .dataIn(memOut),
        .address(memAddress),
        .writeEnable(memWriteEnableWire),
        .clock(clock)
    );

    reg [31:0] instInput1 = low;

    task registerToDataBus;
        input [7:0] registerName;
        case (registerName)
            8'd1: pcDBmc <= 1'd1;
            8'd2: spDBmc <= 1'd1;
            8'd3: bpDBmc <= 1'd1;
            8'd4: acDBmc <= 1'd1;
            8'd5: aoDBmc <= 1'd1;
            8'd6: cnDBmc <= 1'd1;

            8'd10:r0DBmc <= 1'd1;
            8'd11:r1DBmc <= 1'd1;
            8'd12:r2DBmc <= 1'd1;
            8'd13:r3DBmc <= 1'd1;
            8'd14:r4DBmc <= 1'd1;
            8'd15:r5DBmc <= 1'd1;
            8'd16:r6DBmc <= 1'd1;
            8'd17:r7DBmc <= 1'd1;
        endcase
    endtask

    task dataBusToRegister;
        input [7:0] registerName;
        case (registerName)
            8'd1: DBpcmc <= 1'd1;
            8'd2: DBspmc <= 1'd1;
            8'd3: DBbpmc <= 1'd1;
            8'd4: DBacmc <= 1'd1;
            8'd5: DBaomc <= 1'd1;
            8'd6: DBcnmc <= 1'd1;

            8'd10:DBr0mc <= 1'd1;
            8'd11:DBr1mc <= 1'd1;
            8'd12:DBr2mc <= 1'd1;
            8'd13:DBr3mc <= 1'd1;
            8'd14:DBr4mc <= 1'd1;
            8'd15:DBr5mc <= 1'd1;
            8'd16:DBr6mc <= 1'd1;
            8'd17:DBr7mc <= 1'd1;
        endcase
    endtask

    task loadConstant;
        if (intDecay == 3'd0) begin
            intDecay <= 3'd5;
        end else begin
            intDecay <= intDecay - 1;
            instDBmc <= 1'b1;
        end
    endtask

    always@(posedge clock) begin
        if (!thread) begin //decode thread
            case (opcode[7:5]) //the first 3 bits indicate what type of opcode
                3'b001: begin //ALU ------------------------------------------------------------------
                    if (decayCounter == 0) begin
                        decayCounter <= 3'd5;
                    end else if (decayCounter == 4) begin
                        registerToDataBus(inst1); //connect reg to alu input A
                        aluDest <= inst1; //save the reg name
                        DBaluAmc <= 1'b1;
                    end else if (decayCounter == 3) begin
                        if (opcode[1:0] == 2'b00) begin //2nd input is a reg
                            if (opcode[4:3] == 2'b11) begin//its a inc or dec inst
                                if (opcode[2:2] == 1'b1) begin
                                    aluInputB <= -32'sd1;
                                end else begin
                                    aluInputB <= 32'sd1;
                                end
                            end else begin
                                registerToDataBus(inst1); //connect reg to alu input B
                                DBaluBmc <= 1'b1;
                            end 
                        end else begin
                            if (intDecay != 1) begin
                                loadConstant;
                            end else begin
                                intDecay <= 3'd0;
                                decayCounter <= decayCounter - 1;
                                DBaluBmc = 1'b1;
                            end
                        end
                    end else if (decayCounter == 2) begin
                        case (opcode[4:2])
                            3'd0: aluState <= 3'd0; //add
                            3'd1: aluState <= 3'd1; //sub
                            3'd2: aluState <= 3'd2; //mul
                            3'd3: aluState <= 3'd3; //div
                            3'd4: aluState <= 3'd4; //bsr
                            3'd5: aluState <= 3'd5; //bsl
                            default: aluState <= 3'd7;
                        endcase
                    end else if(decayCounter == 1) begin
                        dataBusToRegister(aluDest);
                        aluOutDBmc <= 1'b1;
                    end
                    if (intDecay == 3'd0 && (decayCounter != 3'd3 || opcode[1:0] == 2'b00)) begin
                        decayCounter <= decayCounter - 1'b1;
                    end
                end
                3'b010: begin //MOV ------------------------------------------------------------------
                    if (decayCounter == 0) begin
                        decayCounter <= 3;
                    end else if (decayCounter == 2) begin
                        instInput1 <= inst1; //save current reg
                    end else if (decayCounter == 1) begin
                        case (opcode[1:0])
                            2'b00: begin //reg to reg
                                registerToDataBus(instInput1);
                                dataBusToRegister(inst1);
                            end
                            2'b01: begin //constant to reg
                                if (intDecay != 1) begin
                                    loadConstant;
                                end else begin
                                    intDecay <= 3'd0;
                                    dataBusToRegister(instInput1);
                                    decayCounter <= decayCounter - 1;
                                end
                            end
                            2'b10: begin //ram to reg
                                if (intDecay != 1) begin
                                    loadConstant;
                                    memFlag <= low;
                                end else begin
                                    if (memFlag == 1'b0) begin
                                        DBmemAds <= 1'b1;
                                        memFlag <= 1'b1;
                                    end else begin
                                        memOutDB <= 1'b1;
                                        dataBusToRegister(instInput1);
                                        decayCounter <= decayCounter - 1;
                                        intDecay <= 3'd0;
                                    end
                                end
                            end
                            2'b11: begin //reg to ram
                                if (intDecay != 1) begin
                                    loadConstant;
                                    memFlag <= low;
                                end else begin
                                    if (memFlag == 1'b0) begin
                                        DBmemAds <= 1'b1;
                                        memWriteEnable = 1'b1;
                                        memFlag <= 1'b1;
                                    end else begin
                                        DBmemDataIn <= 1'b1;
                                        registerToDataBus(instInput1);
                                        decayCounter <= decayCounter - 1;
                                        intDecay <= 3'd0;
                                    end
                                end
                            end
                        endcase
                        if (intDecay == 3'd0 && (opcode[1:1] != 1'b1) && memFlag != 1'b0) begin
                            decayCounter <= decayCounter - 1'b1;
                        end
                    end
                end
                3'b101: begin //JMP ------------------------------------------------------------------
                    if (decayCounter == 0) begin
                        decayCounter <= 2;
                    end else if (decayCounter == 2) begin
                        instInput1 <= inst1;
                    end else if (decayCounter == 1) begin
                        case (opcode[4:2])
                            3'd0: begin
                                if (zeroFlag == 1'b1) begin
                                    programCounter <= instInput1;
                                end
                            end
                            3'd1: begin
                                
                            end
                        endcase
                    end
                end
            endcase
        end
    end

endmodule //Control_Unit

`timescale 1ns / 1ns

module Main;

    reg               clock;
    reg signed [31:0] Input1;
    wire signed [31:0] output1;
    wire                halt;

    // Instantiate CPU Core
    Central_Unit uut (
        .output1(output1),
        .halt(halt),
        .clock(clock),
        .Input1(Input1)
    );

    // Task to print the complete internal state of both CPU threads
    task print_cpu_state;
        begin
            $display("Clock: %0t ns", $time);
            $display("--------------------------------------------------");
            $display("============================================================");
        end
    endtask

    // Generate 100MHz Clock (10ns period)
    always #5 clock = ~clock;

    initial begin
        // Initialize Testbench Signals
        clock  = 1'b0;
        Input1 = 32'd0;

        $display("====================================================================================================");
        $display("                                        Starting...");
        $display("====================================================================================================");

        // Enforce 5000 ns Safety Timeout
        #500;
        $display("[Time %0t ns] TIMEOUT REACHED", $time);
        print_cpu_state();
        $finish;
    end

    // Instantly terminate simulation if either thread's instruction bus reads HLT (0xFF)
    always @(posedge clock) begin
        print_cpu_state();
        if (halt) begin
            $display("HALT INST REACHED at Time %0t  ===========================================================================================", $time);
            $display("GLOBAL:");
            $display("  Output Signal   : %d (0x%h)", output1, output1);
            $display("==================================================");
            $finish;
        end
    end

    // Dynamic Output Logging on Output Bus Changes
    always @(output1) begin
        $display("[Time %0t ns] CPU Output updated: %d (0x%h)", $time, output1, output1);
    end

endmodule
