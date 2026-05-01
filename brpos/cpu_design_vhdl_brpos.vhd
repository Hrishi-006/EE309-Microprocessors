-- ============================================================================
--  FILE        : cpu_design_vhdl_brpos.vhd
--  DESCRIPTION : WashU-2 CPU -- 16-bit Accumulator-Based Multi-Cycle Processor
-- ============================================================================
--
--  ARCHITECTURE OVERVIEW
--  ---------------------
--  The WashU-2 is a 16-bit, accumulator-based, multi-cycle CPU.
--  It is NOT pipelined; each instruction takes 4-7 clock cycles controlled
--  by a Finite State Machine (FSM) with 17 states.
--
--  Key Registers:
--    ACC   (16-bit) - Accumulator: holds the working data / ALU result
--    PC    (16-bit) - Program Counter: points to the NEXT instruction to fetch
--    iReg  (16-bit) - Instruction Register: holds the current 16-bit instruction
--    IAR   (16-bit) - Indirect Address Register: for indirect load/store
--    THIS  (16-bit) - Saved PC: address of the instruction being executed
--    tick  (4-bit)  - Sub-cycle counter: tracks clock cycles within a state
--
--  Instruction Format (16-bit word):
--    [15:12] = opcode   (4 bits  - selects instruction type)
--    [11:0]  = operand  (12 bits - immediate value or memory address)
--
--  Address Computation:
--    opAdr  = THIS[15:12] & iReg[11:0]   -- page-relative operand address
--    target = THIS + sign_extend(iReg[7:0]) -- PC-relative branch target
--
--  Bus Interface:
--    aBus  (address bus)  : 16-bit output, CPU drives memory address
--    dBus  (data bus)     : 16-bit bidirectional, shared between CPU & memory
--    en    (enable)       : '1' = CPU wants to access memory
--    rw    (read/write)   : '1' = read, '0' = write
--
--  Instruction Set:
--    Opcode  Mnemonic   Cycles  Description
--    ------  --------   ------  ----------------------------------------
--    0x0000  HALT         4     Stop execution
--    0x0001  NEGATE       4     ACC = two's complement of ACC
--    0x01xx  BRANCH       4     PC = THIS + sign_extend(offset)
--    0x02xx  BRZERO       4     Branch if ACC == 0
--    0x03xx  BRPOS        4     Branch if ACC > 0 (unsigned positive)
--    0x04xx  BRNEG        4     Branch if ACC < 0 (bit 15 set)
--    0x05xx  BRIND        5     PC = memory[target] (indirect branch)
--    0x1xxx  CLOAD        4     ACC = sign_extend(imm[11:0])
--    0x2xxx  DLOAD        5     ACC = memory[page:adr]
--    0x3xxx  ILOAD        7     ACC = memory[memory[page:adr]]
--    0x5xxx  DSTORE       4     memory[page:adr] = ACC
--    0x6xxx  ISTORE       6     memory[memory[page:adr]] = ACC
--    0x8xxx  ADD          5     ACC = ACC + memory[page:adr]
--    0xCxxx  AND          5     ACC = ACC AND memory[page:adr]
--
--  Execution Flow (every instruction):
--    1. FETCH state: read instruction from memory[PC] into iReg (3 cycles)
--    2. DECODE: determine next state from iReg opcode
--    3. EXECUTE: perform the operation (1-4 cycles depending on instruction)
--    4. WRAPUP: return to fetch (or pauseState if pause is asserted)
--
-- ============================================================================

-- ============================================================================
-- SECTION 1: LIBRARY IMPORTS
-- ============================================================================
-- ieee.std_logic_1164 : provides std_logic and std_logic_vector types
-- ieee.numeric_std    : provides unsigned/signed types and arithmetic operators
-- ============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- ============================================================================
-- SECTION 2: ENTITY (PORT) DECLARATION
-- ============================================================================
-- Inputs:
--   clk       - System clock (all state changes on rising_edge)
--   reset     - Synchronous reset ('1' = active, clears all registers)
--   pause     - Pause input ('1' = freeze CPU after current instruction)
--   regSelect - 2-bit debug mux selector for dispReg output
--               "00" = iReg, "01" = THIS, "10" = ACC, "11" = IAR
--   dBus      - 16-bit bidirectional data bus (shared with memory)
--
-- Outputs:
--   en        - Memory enable ('1' = CPU wants memory access this cycle)
--   rw        - Read/Write ('1' = read from memory, '0' = write to memory)
--   aBus      - 16-bit address bus (CPU drives the memory address)
--   dispReg   - 16-bit debug output showing selected internal register
--   dBus      - CPU drives data bus during DSTORE/ISTORE write cycles
-- ============================================================================
entity washu2_cpu is
    port (
        clk, reset : in std_logic;
        -- Memory interface signals
        en, rw     : out std_logic;
        aBus       : out std_logic_vector(15 downto 0);
        dBus       : inout std_logic_vector(15 downto 0);
        -- Console/debug interface signals
        pause      : in std_logic;
        regSelect  : in std_logic_vector(1 downto 0);
        dispReg    : out std_logic_vector(15 downto 0)
    );
end washu2_cpu;

-- ============================================================================
-- SECTION 3: ARCHITECTURE
-- ============================================================================
-- Contains:
--   3A. State machine type definition (17 enumerated states)
--   3B. Register/signal declarations
--   3C. Address computation (opAdr, target)
--   3D. Console debug multiplexer
--   3E. ALU (combinational arithmetic/logic)
--   3F. Main sequential process (clocked FSM)
--       - decode() function (instruction decoder)
--       - wrapup() procedure (end-of-instruction cleanup)
--       - Reset logic
--       - Fetch state (3-cycle instruction read)
--       - Execution states (branch, load, store, arithmetic)
--   3G. Memory control process (combinational bus control)
-- ============================================================================
architecture cpuArch of washu2_cpu is

    -- ========================================================================
    -- 3A. STATE MACHINE TYPE DEFINITION
    -- ========================================================================
    -- The CPU uses a 17-state FSM with enumerated type.
    -- VHDL enumerated types are automatically encoded by the synthesizer.
    --
    -- State descriptions:
    --   resetState - Initial state after reset, transitions to fetch
    --   pauseState - CPU paused, waits for pause='0'
    --   fetch      - Fetch instruction from memory[PC] (3 cycles)
    --   halt       - CPU stopped, no more execution
    --   negate     - ACC = ~ACC + 1 (two's complement)
    --   branch     - Unconditional branch to target
    --   brZero     - Branch if ACC = 0
    --   brPos      - Branch if ACC > 0 and ACC(15) = '0'
    --   brNeg      - Branch if ACC(15) = '1' (negative)
    --   brInd      - Indirect branch: PC = memory[target]
    --   cLoad      - Load sign-extended 12-bit constant into ACC
    --   dLoad      - Direct load: ACC = memory[opAdr]
    --   iLoad      - Indirect load: ACC = memory[memory[opAdr]]
    --   dStore     - Direct store: memory[opAdr] = ACC
    --   iStore     - Indirect store: memory[memory[opAdr]] = ACC
    --   add        - ACC = ACC + memory[opAdr]
    --   andd       - ACC = ACC AND memory[opAdr]
    -- ========================================================================
    type state_type is (
        resetState, pauseState, fetch, halt, negate, branch, 
        brZero, brPos, brNeg, brInd, cLoad, dLoad, 
        iLoad, dStore, iStore, add, andd
    );

    -- ========================================================================
    -- 3B. REGISTER AND SIGNAL DECLARATIONS
    -- ========================================================================
    -- state  (state_type) - Current FSM state (enumerated)
    -- tick   (4-bit)      - Sub-cycle counter within each state (0-15)
    -- pc     (16-bit)     - Program counter: address of NEXT instruction
    -- iReg   (16-bit)     - Instruction register: current instruction word
    -- iar    (16-bit)     - Indirect address register: pointer for ILOAD/ISTORE
    -- acc    (16-bit)     - Accumulator: main working register
    -- alu    (16-bit)     - ALU output: combinationally computed result
    -- this   (16-bit)     - Saved PC: address of instruction being executed
    -- opAdr  (16-bit)     - Operand address: THIS(15:12) & iReg(11:0)
    -- target (16-bit)     - Branch target: THIS + sign_extend(iReg(7:0))
    -- ========================================================================
    signal state    : state_type; 
    signal tick     : std_logic_vector(3 downto 0); 
    signal pc       : std_logic_vector(15 downto 0);
    signal iReg     : std_logic_vector(15 downto 0);
    signal iar      : std_logic_vector(15 downto 0);
    signal acc      : std_logic_vector(15 downto 0);
    signal alu      : std_logic_vector(15 downto 0);
    signal this     : std_logic_vector(15 downto 0);
    signal opAdr    : std_logic_vector(15 downto 0);
    signal target   : std_logic_vector(15 downto 0);

begin

    -- ========================================================================
    -- 3C. ADDRESS COMPUTATION (Concurrent / Combinational)
    -- ========================================================================
    --
    -- opAdr: Used by DLOAD, DSTORE, ADD, AND, ILOAD, ISTORE
    --   Concatenates the 4-bit page number from THIS(15:12) with the 12-bit
    --   operand from iReg(11:0). Memory access is within the same 4K page
    --   as the current instruction.
    --   Example: THIS=0x0004, iReg=0x2010 -> opAdr = 0x0010
    --
    -- target: Used by BRANCH, BRZERO, BRPOS, BRNEG, BRIND
    --   Adds a sign-extended 8-bit offset (iReg(7:0)) to THIS.
    --   resize(signed(...), 16) sign-extends the 8-bit value to 16 bits,
    --   allowing forward (+0 to +127) or backward (-128 to -1) relative jumps.
    --   Example: THIS=0x0005, iReg(7:0)=0xFE (-2) -> target = 0x0003
    -- ========================================================================
    opAdr <= this(15 downto 12) & iReg(11 downto 0);
    target <= std_logic_vector(unsigned(this) + unsigned(resize(signed(iReg(7 downto 0)), 16)));

    -- ========================================================================
    -- 3D. CONSOLE/DEBUG OUTPUT MULTIPLEXER (Concurrent / Combinational)
    -- ========================================================================
    -- Allows external observation of internal registers via regSelect input.
    -- The selected register value appears on the dispReg output.
    --
    --   regSelect  Register  Purpose
    --   ---------  --------  ----------------------------------------
    --   "00"       iReg      Current instruction word
    --   "01"       this      Address of current instruction (saved PC)
    --   "10"       acc       Accumulator (data/result register)
    --   "11"       iar       Indirect address register
    -- ========================================================================
    with regSelect select
        dispReg <= iReg when "00", 
                   this  when "01",
                   acc   when "10", 
                   iar   when others;

    -- ========================================================================
    -- 3E. ALU (Arithmetic Logic Unit) -- Concurrent / Combinational
    -- ========================================================================
    -- The ALU computes a result based on the current state.
    -- Operations use only the lower 12 bits of operands (bits 11:0),
    -- with the upper 4 bits always set to "0000". This matches the
    -- 12-bit operand field in the instruction format.
    --
    -- ALU operations:
    --   negate: alu = "0000" & (~acc(11:0) + 1)   (two's complement negation)
    --   add:    alu = "0000" & (acc(11:0) + dBus(11:0))  (12-bit addition)
    --   andd:   alu = "0000" & (acc(11:0) AND dBus(11:0)) (12-bit bitwise AND)
    --   others: alu = x"0000"
    --
    -- The result is stored into ACC by the sequential process during execution.
    -- ========================================================================
    alu <= "0000" & std_logic_vector(unsigned(not acc(11 downto 0)) + 1) when state = negate else
           "0000" & std_logic_vector(unsigned(acc(11 downto 0)) + unsigned(dBus(11 downto 0))) when state = add else
           "0000" & (acc(11 downto 0) and dBus(11 downto 0)) when state = andd else
           (others => '0');

    -- ========================================================================
    -- 3F. MAIN SEQUENTIAL PROCESS (Clocked -- rising_edge(clk))
    -- ========================================================================
    -- This is the heart of the CPU. On every rising clock edge, it:
    --   1. Checks for reset (clears all registers)
    --   2. Advances the tick counter
    --   3. Executes the current state's logic
    --
    -- Contains two local subprograms:
    --   decode()  - Function: converts 16-bit instruction -> state_type
    --   wrapup()  - Procedure: end-of-instruction cleanup (reset tick, next state)
    --
    -- Execution flow for each instruction:
    --
    --   FETCH (3 cycles -- every instruction starts here):
    --     tick 0: Memory control puts PC on aBus, enables read
    --     tick 1: iReg <= dBus (latch instruction from memory)
    --     tick 2: Decode iReg -> next state, save THIS = PC, increment PC
    --
    -- After fetch, the CPU enters the instruction-specific state.
    -- Each state reads/writes registers and calls wrapup when complete.
    --
    -- ---- BRANCH INSTRUCTIONS (single-cycle execute) ----
    --
    --   BRANCH (tick 0):  pc <= target, wrapup
    --   BRZERO (tick 0):  if acc = 0 then pc <= target, wrapup
    --   BRPOS  (tick 0):  if acc(15)='0' and acc/=0 then pc <= target, wrapup
    --   BRNEG  (tick 0):  if acc(15)='1' then pc <= target, wrapup
    --   BRIND  (2 cycles):
    --     tick 0: Memory reads from target address
    --     tick 1: pc <= dBus (load from memory), wrapup
    --
    -- ---- LOAD INSTRUCTIONS ----
    --
    --   CLOAD (tick 0):
    --     acc <= sign_extend(iReg(11:0))
    --     Bit 11 is replicated into bits 15:12 for sign extension
    --     Example: iReg=0x1005 -> operand=0x005 -> acc=0x0005
    --     wrapup
    --
    --   DLOAD (2 cycles):
    --     tick 0: Memory reads from opAdr
    --     tick 1: acc <= dBus, wrapup
    --
    --   ILOAD (4 cycles -- two memory reads):
    --     tick 0: Memory reads pointer from opAdr
    --     tick 1: iar <= dBus (save pointer)
    --     tick 2: Memory reads data from IAR
    --     tick 3: acc <= dBus, wrapup
    --
    -- ---- STORE INSTRUCTIONS ----
    --
    --   DSTORE (tick 0):
    --     Memory control writes ACC to memory[opAdr], wrapup
    --
    --   ISTORE (3 cycles):
    --     tick 0: Memory reads pointer from opAdr
    --     tick 1: iar <= dBus (save pointer)
    --     tick 2: Memory control writes ACC to memory[IAR], wrapup
    --
    -- ---- ARITHMETIC / LOGIC INSTRUCTIONS ----
    --
    --   NEGATE (tick 0): acc <= alu (~acc(11:0)+1), wrapup
    --   ADD (2 cycles):
    --     tick 0: Memory reads operand from opAdr
    --     tick 1: acc <= alu (acc+dBus), wrapup
    --   AND (2 cycles):
    --     tick 0: Memory reads operand from opAdr
    --     tick 1: acc <= alu (acc AND dBus), wrapup
    --
    -- ========================================================================
    process (clk)

        -- ====================================================================
        -- DECODE FUNCTION: Instruction Word -> FSM State
        -- ====================================================================
        -- Converts a 16-bit instruction into the corresponding execution state.
        -- Called at fetch tick 2 to determine the next state.
        --
        -- Decoding hierarchy:
        --   instr(15:12) = x"0" (special instructions):
        --     instr(11:8) = x"0":
        --       instr(11:0) = x"000" -> halt
        --       instr(11:0) = x"001" -> negate
        --       else                 -> halt (undefined)
        --     instr(11:8) = x"1" -> branch
        --     instr(11:8) = x"2" -> brZero
        --     instr(11:8) = x"3" -> brPos
        --     instr(11:8) = x"4" -> brNeg
        --     instr(11:8) = x"5" -> brInd
        --   instr(15:12) = x"1" -> cLoad
        --   instr(15:12) = x"2" -> dLoad
        --   instr(15:12) = x"3" -> iLoad
        --   instr(15:12) = x"5" -> dStore
        --   instr(15:12) = x"6" -> iStore
        --   instr(15:12) = x"8" -> add
        --   instr(15:12) = x"c" -> andd
        --   others               -> halt (undefined opcode)
        -- ====================================================================
        function decode(instr: std_logic_vector(15 downto 0)) return state_type is
        begin
            case instr(15 downto 12) is
                when x"0" =>
                    case instr(11 downto 8) is
                        when x"0" =>
                            if instr(11 downto 0) = x"000" then
                                return halt;
                            elsif instr(11 downto 0) = x"001" then
                                return negate;
                            else
                                return halt;
                            end if;
                        when x"1" => return branch;
                        when x"2" => return brZero;
                        when x"3" => return brPos;
                        when x"4" => return brNeg;
                        when x"5" => return brInd;
                        when others => return halt;
                    end case;
                when x"1" => return cLoad;
                when x"2" => return dLoad;
                when x"3" => return iLoad;
                when x"5" => return dStore;
                when x"6" => return iStore;
                when x"8" => return add;
                when x"c" => return andd;
                when others => return halt;
            end case;
        end function decode;

        -- ====================================================================
        -- WRAPUP PROCEDURE: End-of-Instruction Cleanup
        -- ====================================================================
        -- Called at the end of every instruction's execution.
        -- Resets the tick counter to 0 and transitions to:
        --   pauseState (if pause = '1')
        --   fetch      (normal case -- go get the next instruction)
        -- ====================================================================
        procedure wrapup is
        begin
            if pause = '1' then
                state <= pauseState;
            else
                state <= fetch;
            end if;
            tick <= x"0";
        end procedure wrapup;

    begin
        if rising_edge(clk) then
            if reset = '1' then
                -- RESET: Clear all registers to initial values
                -- CPU will transition to fetch on the next clock cycle
                state <= resetState;
                tick <= x"0";
                pc <= (others => '0');
                this <= (others => '0');
                iReg <= (others => '0');
                acc <= (others => '0');
                iar <= (others => '0');
            else
                -- Default: advance tick counter each cycle
                tick <= std_logic_vector(unsigned(tick) + 1);

                -- ---- Control states ----

                if state = resetState then
                    -- After reset, move to fetch to begin execution
                    state <= fetch;
                    tick <= x"0";

                elsif state = pauseState then
                    -- Wait in pause until pause input is deasserted
                    if pause = '0' then
                        state <= fetch;
                        tick <= x"0";
                    end if;

                -- ---- Fetch state (3 cycles) ----

                elsif state = fetch then
                    if tick = x"1" then
                        -- tick 1: Latch instruction word from data bus into iReg
                        --         (Memory was read at tick 0 by memory control)
                        iReg <= dBus;
                    elsif tick = x"2" then
                        -- tick 2: Decode the instruction and begin execution
                        --         Save current PC as THIS (instruction address)
                        --         Advance PC to point to the next instruction
                        state <= decode(iReg);
                        tick <= x"0";
                        this <= pc;
                        pc <= std_logic_vector(unsigned(pc) + 1);
                    end if;

                -- ---- Execution states ----

                else
                    case state is

                        -- ==== Branch Instructions ====

                        -- BRANCH: Unconditional jump to target address
                        when branch =>
                            pc <= target;
                            wrapup;

                        -- BRZERO: Branch to target only if accumulator is zero
                        when brZero =>
                            if acc = x"0000" then
                                pc <= target;
                            end if;
                            wrapup;

                        -- BRPOS: Branch if accumulator is positive (bit 15='0', non-zero)
                        -- ============================================================
                        -- TODO: Implement the BRPOS instruction here.
                        --
                        -- Goal: Jump to the branch target address ONLY when the
                        --       accumulator holds a strictly positive value (> 0).
                        --
                        -- How to determine "positive" in this CPU:
                        --   1. Check the SIGN BIT: acc(15) must be '0'
                        --      - acc(15) = '0' means the number is non-negative (>= 0)
                        --      - acc(15) = '1' means the number is negative (< 0)
                        --   2. Check for NON-ZERO: acc must not equal x"0000"
                        --      - This eliminates zero, since zero is NOT positive
                        --   Both conditions must be TRUE for the branch to be taken.
                        --
                        -- If branch is taken:
                        --   - Set pc <= target  (redirect execution to branch address)
                        --   - 'target' is already computed as: THIS + sign_extend(offset)
                        --
                        -- If branch is NOT taken:
                        --   - Do nothing to pc (it already points to the next instruction)
                        --
                        -- After the branch decision (taken or not), call wrapup to
                        -- reset the tick counter and return to the fetch state.
                        --
                        -- Hint: Use an if-then statement with both conditions combined
                        --       using 'and', followed by wrapup outside the if block.
                        -- ============================================================
                        when brPos =>
									 if (acc(15) = '0' and acc /= x"0000") then
											pc <= target; 
									 end if;
                            wrapup;

                        -- BRNEG: Branch if accumulator is negative (bit 15='1')
                        when brNeg =>
                            if acc(15) = '1' then
                                pc <= target;
                            end if;
                            wrapup;

                        -- BRIND: Indirect branch -- load PC from memory[target]
                        --   tick 0: Memory read initiated (by memory control)
                        --   tick 1: Latch the address from dBus into PC
                        when brInd =>
                            if tick = x"1" then
                                pc <= dBus;
                                wrapup;
                            end if;

                        -- ==== Load Instructions ====

                        -- CLOAD: Load sign-extended 12-bit constant into accumulator
                        --   iReg(11:0) is the 12-bit immediate value
                        --   Bit 11 is replicated into bits 15:12 for sign extension
                        --   Example: CLOAD 5 (iReg=0x1005) -> acc = 0x0005
                        --   Example: CLOAD -1 (iReg=0x1FFF) -> acc = 0xFFFF
                        when cLoad =>
                            acc <= (15 downto 12 => iReg(11)) & iReg(11 downto 0);
                            wrapup;

                        -- DLOAD: Direct load -- read memory[opAdr] into accumulator
                        --   tick 0: Memory read initiated from opAdr
                        --   tick 1: Latch data from dBus into ACC
                        when dLoad =>
                            if tick = x"1" then
                                acc <= dBus;
                                wrapup;
                            end if;

                        -- ILOAD: Indirect load -- two memory reads
                        --   tick 0: Read pointer from memory[opAdr]
                        --   tick 1: Save pointer into IAR
                        --   tick 2: Read data from memory[IAR]
                        --   tick 3: Latch data from dBus into ACC
                        when iLoad =>
                            if tick = x"1" then
                                iar <= dBus;
                            elsif tick = x"3" then
                                acc <= dBus;
                                wrapup;
                            end if;

                        -- ==== Store Instructions ====

                        -- DSTORE: Direct store -- write ACC to memory[opAdr]
                        --   The memory control process handles the actual write
                        --   (sets en='1', rw='0', aBus=opAdr, dBus=ACC at tick 0)
                        --   This state just calls wrapup to return to fetch.
                        when dStore =>
                            wrapup;

                        -- ISTORE: Indirect store -- two steps
                        --   tick 0: Read pointer from memory[opAdr]
                        --   tick 1: Save pointer into IAR
                        --   tick 2: Memory control writes ACC to memory[IAR], wrapup
                        when iStore =>
                            if tick = x"1" then
                                iar <= dBus;
                            elsif tick = x"2" then
                                wrapup;
                            end if;

                        -- ==== Arithmetic and Logic Instructions ====

                        -- NEGATE: Two's complement negation of accumulator
                        --   acc = "0000" & (~acc(11:0) + 1) (computed by ALU)
                        when negate =>
                            acc <= alu;
                            wrapup;

                        -- ADD / AND: Arithmetic/logic with memory operand
                        --   tick 0: Memory read from opAdr (by memory control)
                        --   tick 1: acc <= alu result
                        --           ADD: acc(11:0) + dBus(11:0)
                        --           AND: acc(11:0) AND dBus(11:0)
                        when add | andd =>
                            if tick = x"1" then
                                acc <= alu;
                                wrapup;
                            end if;

                        -- Default: Undefined state -> go to halt
                        when others =>
                            state <= halt;
                    end case;
                end if;
            end if;
        end if;
    end process;

    -- ========================================================================
    -- 3G. MEMORY CONTROL PROCESS (Combinational)
    -- ========================================================================
    -- This process generates memory interface signals (en, rw, aBus, dBus)
    -- based on the current state and tick value.
    --
    -- Default values (no memory access):
    --   en = '0', rw = '1', aBus = x"0000", dBus = 'Z' (high-impedance)
    --
    -- For each state, memory is accessed at specific tick values:
    --
    --   State            Tick  en  rw  aBus     dBus      Action
    --   ---------------  ----  --  --  -------  --------  -------------------------
    --   fetch            0     1   1   PC       (read)    Read instruction from PC
    --   brInd            0     1   1   target   (read)    Read branch target addr
    --   dLoad/add/andd   0     1   1   opAdr    (read)    Read operand from memory
    --   iLoad            0     1   1   opAdr    (read)    Read pointer from memory
    --   iLoad            2     1   1   IAR      (read)    Read data via pointer
    --   dStore           0     1   0   opAdr    ACC       Write ACC to memory
    --   iStore           0     1   1   opAdr    (read)    Read pointer from memory
    --   iStore           2     1   0   IAR      ACC       Write ACC via pointer
    --
    -- Note: rw='1' = READ, rw='0' = WRITE
    -- When writing (rw='0'), the CPU drives dBus with the ACC value.
    -- When reading (rw='1'), dBus is set to 'Z' so memory can drive it.
    -- ========================================================================
    process (iReg, pc, iar, acc, this, opAdr, state, tick)
    begin
        -- Default: no memory access
        en <= '0';
        rw <= '1';
        aBus <= (others => '0');
        dBus <= (others => 'Z');

        case state is

            -- FETCH: Read instruction word from memory[PC]
            -- CPU puts PC on address bus at tick 0, memory responds at tick 1
            when fetch =>
                if tick = x"0" then
                    en <= '1';
                    aBus <= pc;
                end if;

            -- BRIND: Read the branch target address from memory
            when brInd =>
                if tick = x"0" then
                    en <= '1';
                    aBus <= target;
                end if;

            -- DLOAD, ADD, AND: Read operand from memory[opAdr]
            when dLoad | add | andd =>
                if tick = x"0" then
                    en <= '1';
                    aBus <= opAdr;
                end if;

            -- ILOAD: Two-step indirect read
            --   tick 0: Read pointer value from memory[opAdr]
            --   tick 2: Read actual data from memory[IAR]
            when iLoad =>
                if tick = x"0" then
                    en <= '1';
                    aBus <= opAdr;
                elsif tick = x"2" then
                    en <= '1';
                    aBus <= iar;
                end if;

            -- DSTORE: Write ACC to memory[opAdr]
            --   tick 0: Put address on aBus, set rw='0', drive dBus with ACC
            when dStore =>
                if tick = x"0" then
                    en <= '1';
                    rw <= '0';
                    aBus <= opAdr;
                    dBus <= acc;
                end if;

            -- ISTORE: Two-step indirect write
            --   tick 0: Read pointer value from memory[opAdr]
            --   tick 2: Write ACC to memory[IAR]
            when iStore =>
                if tick = x"0" then
                    en <= '1';
                    aBus <= opAdr;
                elsif tick = x"2" then
                    en <= '1';
                    rw <= '0';
                    aBus <= iar;
                    dBus <= acc;
                end if;

            when others =>
                -- No memory access for halt, negate, branch, brZero, brPos, brNeg
                null;
        end case;
    end process;

end cpuArch;
