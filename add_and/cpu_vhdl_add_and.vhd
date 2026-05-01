-- ============================================================================
--  FILE        : cpu_design_vhdl_add.vhd
--  DESCRIPTION : WashU-2 CPU (VHDL) -- Student Version (ADD operation removed)
-- ============================================================================
-- ...existing code up to architecture declaration...
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
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
architecture cpuArch of washu2_cpu is
    -- ...existing declarations...
    type state_type is (
        resetState, pauseState, fetch, halt, negate, branch, 
        brZero, brPos, brNeg, brInd, cLoad, dLoad, 
        iLoad, dStore, iStore, add, andd
    );
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
    opAdr <= this(15 downto 12) & iReg(11 downto 0);
    target <= std_logic_vector(unsigned(this) + unsigned(resize(signed(iReg(7 downto 0)), 16)));
    with regSelect select
        dispReg <= iReg when "00", 
                   this  when "01",
                   acc   when "10", 
                   iar   when others;
    -- ========================================================================
    -- 3C. ADDRESS COMPUTATION (Concurrent / Combinational)
    -- ...existing code...

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
    -- STUDENT TASK: Implement the ADD operation below.
    -- Hint: For the ADD operation, you need to add the lower 12 bits of the accumulator (acc) and the data bus (dBus),
    -- and concatenate the result with 4 leading zeros to form a 16-bit value. Use VHDL's unsigned arithmetic and type conversions.
    --
    -- After implementing the ADD operation, write a short instruction sequence (test program)
    -- in your testbench memory to verify that addition works correctly. For example:
    --   - Load two values into memory
    --   - Use CLOAD and DLOAD to bring them into ACC
    --   - Use ADD to add them
    --   - Store the result and check the memory contents
    -- ========================================================================
    alu <= "0000" & std_logic_vector(unsigned(not acc(11 downto 0)) + 1) when state = negate else
           -- TODO: Implement the ADD operation for the ALU here
           "0000" & std_logic_vector(unsigned(acc(11 downto 0))+ unsigned(dBus(11 downto 0))) when state= add else
           "0000" & (acc(11 downto 0) and dBus(11 downto 0)) when state = andd else
           (others => '0');

    -- ...rest of the architecture and processes unchanged...
	 
	     process (clk)
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
                       when branch =>
                            pc <= target;
                            wrapup;

                        -- BRZERO: Branch to target only if accumulator is zero
                        when brZero =>
                            if acc = x"0000" then
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
