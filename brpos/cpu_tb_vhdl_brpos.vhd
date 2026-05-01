-- ============================================================================
--  FILE        : cpu_tb_vhdl_brpos.vhd
--  DESCRIPTION : Testbench for the WashU-2 CPU (washu2_cpu)
-- ============================================================================
--
--  ARCHITECTURE OVERVIEW
--  ---------------------
--  The WashU-2 is a 16-bit, accumulator-based, multi-cycle CPU.
--  It is NOT pipelined; each instruction takes 4-7 clock cycles through
--  an FSM (Finite State Machine) with 17 states.
--
--  Key registers inside the CPU:
--    ACC   - Accumulator   : holds the working data value (result of ALU ops)
--    PC    - Program Counter: points to the NEXT instruction to fetch
--    iReg  - Instruction Reg: holds the currently fetched 16-bit instruction
--    IAR   - Indirect Addr  : used for indirect load/store addressing
--    THIS  - Saved PC       : address of the instruction being executed
--
--  Instruction format (16-bit word):
--    [15:12] = opcode   (4 bits  - selects the instruction type)
--    [11:0]  = operand  (12 bits - immediate value or memory address)
--
--  Bus interface:
--    aBus  (address bus)  : 16-bit, CPU drives the memory address
--    dBus  (data bus)     : 16-bit, bidirectional (CPU reads/writes data)
--    en    (enable)       : '1' when CPU wants to access memory
--    rw    (read/write)   : '1' = read from memory, '0' = write to memory
--
--  INSTRUCTION SET
--  ---------------
--    Opcode  Mnemonic   Description
--    ------  --------   ----------------------------------------
--    0x0000  HALT       Stop execution
--    0x0001  NEGATE     ACC = two's complement of ACC (negate)
--    0x01xx  BRANCH     PC = THIS + sign_extend(offset[7:0])
--    0x02xx  BRZERO     Branch if ACC == 0
--    0x03xx  BRPOS      Branch if ACC > 0
--    0x04xx  BRNEG      Branch if ACC < 0
--    0x05xx  BRIND      PC = memory[target]  (indirect branch)
--    0x1xxx  CLOAD imm  ACC = sign_extend(imm[11:0])  (load constant)
--    0x2xxx  DLOAD adr  ACC = memory[page:adr]  (direct load)
--    0x3xxx  ILOAD adr  ACC = memory[memory[page:adr]]  (indirect load)
--    0x5xxx  DSTORE adr memory[page:adr] = ACC  (direct store)
--    0x6xxx  ISTORE adr memory[memory[page:adr]] = ACC  (indirect store)
--    0x8xxx  ADD adr    ACC = ACC + memory[page:adr]
--    0xCxxx  AND adr    ACC = ACC AND memory[page:adr]
--
--  TEST PROGRAM SUMMARY
--  --------------------
--  This testbench loads a 12-instruction program that computes:
--    Step 1: Store constant 5  into mem[0x10]
--    Step 2: Store constant 6  into mem[0x11]
--    Step 3: Compute 5 + 6 = 11, store into mem[0x12]
--    Step 4: Compute 9 + 11 = 20, store into mem[0x13]
--    Step 5: Halt
--
--  Expected final memory results:
--    mem[0x10] = 5   (constant 5)
--    mem[0x11] = 6   (constant 6)
--    mem[0x12] = 11  (5 + 6)
--    mem[0x13] = 20  (9 + 11)
--
-- ============================================================================

-- ============================================================================
-- SECTION 1: LIBRARY IMPORTS
-- ============================================================================
-- ieee.std_logic_1164 : provides std_logic and std_logic_vector types
-- ieee.numeric_std    : provides unsigned/signed types and arithmetic
-- std.textio          : provides text I/O for report formatting
-- ============================================================================
library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

-- ============================================================================
-- SECTION 2: ENTITY DECLARATION
-- ============================================================================
-- The testbench entity has NO ports - it is a self-contained simulation
-- environment. All signals are generated internally.
-- ============================================================================
entity cpu_tb is
end cpu_tb;

-- ============================================================================
-- SECTION 3: ARCHITECTURE
-- ============================================================================
-- Contains:
--   3A. Component declaration (CPU interface definition)
--   3B. Signal declarations  (wires connecting testbench to CPU)
--   3C. Memory declaration   (256-word RAM with preloaded program)
--   3D. Bus hold signals     (tri-state data bus management)
--   3E. Concurrent logic     (bus arbitration, CPU instantiation)
--   3F. Clock generator      (10 ns period = 100 MHz)
--   3G. Stimulus process     (reset sequence + result display)
--   3H. Memory process       (synchronous read/write behavior)
-- ============================================================================

architecture behavior of cpu_tb is

    -- ========================================================================
    -- 3A. COMPONENT DECLARATION
    -- ========================================================================
    -- This declares the interface of the washu2_cpu module so we can
    -- instantiate it below. Must match the entity ports in cpu_design_vhdl.vhd.
    --
    -- Port descriptions:
    --   clk       : system clock input
    --   reset     : synchronous reset ('1' = reset active)
    --   en        : memory enable output ('1' = CPU wants memory access)
    --   rw        : read/write output ('1' = read, '0' = write)
    --   abus      : 16-bit address bus output (CPU drives memory address)
    --   dbus      : 16-bit data bus (bidirectional, shared between CPU & memory)
    --   pause     : pause input ('1' = halt CPU in pauseState)
    --   regselect : 2-bit input to select which register appears on dispreg
    --               "00" = iReg, "01" = THIS, "10" = ACC, "11" = IAR
    --   dispreg   : 16-bit output showing the selected internal register
    -- ========================================================================
    component washu2_cpu
    port (
        clk       : in    std_logic;
        reset     : in    std_logic;
        en        : out   std_logic;
        rw        : out   std_logic;
        abus      : out   std_logic_vector(15 downto 0);
        dbus      : inout std_logic_vector(15 downto 0);
        pause     : in    std_logic;
        regselect : in    std_logic_vector(1 downto 0);
        dispreg   : out   std_logic_vector(15 downto 0)
    );
    end component;

    -- ========================================================================
    -- 3B. SIGNAL DECLARATIONS
    -- ========================================================================
    -- These signals connect the testbench to the CPU instance.
    -- Inputs to the CPU are driven by the testbench (clk, reset, pause, etc.)
    -- Outputs from the CPU are observed by the testbench (en, rw, abus, etc.)
    -- ========================================================================

    -- Clock: 10 ns period (5 ns high, 5 ns low) => 100 MHz
    signal   clk        : std_logic := '0';
    constant clk_period : time := 10 ns;

    -- Reset: starts HIGH (active) to initialize the CPU, then goes LOW
    signal reset : std_logic := '1';

    -- Memory interface signals driven by the CPU
    signal en   : std_logic;                        -- memory enable
    signal rw   : std_logic;                        -- read='1', write='0'
    signal abus : std_logic_vector(15 downto 0);    -- address bus
    signal dbus : std_logic_vector(15 downto 0);    -- bidirectional data bus

    -- Console/debug interface
    signal pause     : std_logic := '0';                    -- not used in this test
    signal regselect : std_logic_vector(1 downto 0) := "00"; -- register select for debug
    signal dispreg   : std_logic_vector(15 downto 0);        -- selected register output

    -- ========================================================================
    -- 3C. MEMORY DECLARATION (256 x 16-bit words)
    -- ========================================================================
    -- This simulates the external RAM connected to the CPU.
    -- Addresses 0x00-0x0B hold the program instructions.
    -- Addresses 0x10-0x13 are the data region where results are stored.
    -- All other addresses are initialized to 0x0000.
   
    type memory_type is array (0 to 255) of std_logic_vector(15 downto 0);
    signal memory : memory_type := (
        -- ============================================================
        -- TODO: Write a test program to verify the BRPOS instruction.
        --
        -- BRPOS branches ONLY when ACC is strictly positive (> 0).
        -- You need to test all 3 cases to fully verify it:
        --
        --   Case 1: ACC is POSITIVE (e.g. 5)  --> BRPOS should BRANCH
        --   Case 2: ACC is ZERO    (0)        --> BRPOS should NOT branch
        --   Case 3: ACC is NEGATIVE (e.g. -1) --> BRPOS should NOT branch
        --
        -- INSTRUCTION ENCODING REFERENCE:
        --   CLOAD value : 0x1xxx  (load 12-bit sign-extended constant)
        --     Example: CLOAD 5   = x"1005"  --> ACC = 5
        --     Example: CLOAD 0   = x"1000"  --> ACC = 0
        --     Example: CLOAD -1  = x"1FFF"  --> ACC = 0xFFFF (-1)
        --
        --   BRPOS +N   : 0x03xx  (branch if ACC > 0, offset = xx)
        --     Example: BRPOS +2  = x"0302"  --> jump forward by 2 from THIS
        --     NOTE: opcode = 0x0, sub-opcode = 0x3, offset = N
        --     
        --
        --   DSTORE addr: 0x5xxx  (store ACC to memory address)
        --     Example: DSTORE 0x10 = x"5010"  --> mem[0x10] = ACC
        --
        --   HALT       : 0x0000  (stop CPU execution)
        --
        -- TEST STRATEGY:
        --   For each case, use this pattern:
        --     1. CLOAD a value to set ACC (positive, zero, or negative)
        --     2. BRPOS +2 to attempt a branch (skip the next instruction)
        --     3. Place an instruction that should execute ONLY if branch
        --        was NOT taken (e.g., CLOAD a marker, then DSTORE)
        --     4. Continue to the next test case
        --
        --   To detect whether BRPOS branched or not, use marker values.
        --   If branch was TAKEN: the marker CLOAD is skipped, so the old
        --     value (or 0) gets stored.
        --   If branch was NOT taken: the marker CLOAD executes, and its
        --     known value gets stored -- proving the branch didn't skip.
        --
        -- EXPECTED RESULTS (verify these in the report section below):
        --   mem[0x10] = 0   (DSTORE was skipped  --> BRPOS took the branch)
        --   mem[0x11] = 77  (DSTORE executed      --> BRPOS did NOT branch)
        --   mem[0x12] = 88  (DSTORE executed      --> BRPOS did NOT branch)
        -- ============================================================

        -- Your test program goes here:
        -- addr => instruction,   -- comment
        --  ...
		  0  => x"1005",   -- CLOAD 0x05       | ACC = 5
        1  => x"0302",   -- BRPOS +2	      | PC <- target if ACC > 0
		  2  => x"1077",   -- CLOAD 0x77       | ACC = 77
        3  => x"5010",   -- DSTORE 0x10      | mem[0x10] = ACC
		  
        4  => x"1000",   -- CLOAD 0x00       | ACC = 0
        5  => x"0302",   -- BRPOS +2	      | PC <- target if ACC > 0
		  6  => x"1077",   -- CLOAD 0x77       | ACC = 77
        7  => x"5011",   -- DSTORE 0x11      | mem[0x11] = ACC
		  
		  8  => x"1FFF",   -- CLOAD 0xFF       | ACC = -1
        9  => x"0302",   -- BRPOS +2	      | PC <- target if ACC > 0
		  10 => x"1088",   -- CLOAD 0x88       | ACC = 88
        11 => x"5012",   -- DSTORE 0x12      | mem[0x12] = ACC
		  
		  12 => x"0000",   -- HALT
        others => x"0000"
    );

    -- ========================================================================
    -- 3D. BUS HOLD SIGNALS
    -- ========================================================================
    -- The data bus (dbus) is bidirectional - both the CPU and memory can drive
    -- it. We need logic to decide who drives the bus at any given time.
    --
    -- Problem: The CPU expects read data to remain on the bus for multiple
    -- clock cycles (it reads dBus one cycle AFTER the memory enable).
    -- Solution: After a memory read, we HOLD the last-read value on the bus
    -- (dbus_oe stays '1') until the CPU does a write (which takes over the bus).
    --
    -- dbus_out : latched value from the last memory read
    -- dbus_oe  : '1' = memory is driving the bus, '0' = bus released
    -- cpu_writing : '1' when CPU is performing a write (en=1, rw=0)
    -- ========================================================================
    signal dbus_out    : std_logic_vector(15 downto 0) := (others => '0');
    signal dbus_oe     : std_logic := '0';
    signal cpu_writing : std_logic;

begin

    -- ========================================================================
    -- 3E. CONCURRENT SIGNAL ASSIGNMENTS
    -- ========================================================================

    -- Detect when the CPU is driving the bus (write operation)
    -- cpu_writing = '1' when en='1' AND rw='0' (i.e., write mode)
    cpu_writing <= en and (not rw);

    -- Tri-state bus arbitration:
    -- If memory has valid data (dbus_oe='1') AND CPU is NOT writing:
    --   => memory drives the bus with dbus_out (last read value)
    -- Otherwise:
    --   => bus is high-impedance 'Z' (CPU may drive it during writes)
    dbus <= dbus_out when (cpu_writing = '0' and dbus_oe = '1')
            else (others => 'Z');

    -- ========================================================================
    -- CPU INSTANTIATION
    -- ========================================================================
    -- Connect all testbench signals to the CPU's ports.
    -- The CPU reads instructions/data from memory via abus/dbus,
    -- and writes results back through the same bus.
    -- ========================================================================
    uut: washu2_cpu
        port map(
            clk       => clk,
            reset     => reset,
            en        => en,
            rw        => rw,
            abus      => abus,
            dbus      => dbus,
            pause     => pause,
            regselect => regselect,
            dispreg   => dispreg
        );

    -- ========================================================================
    -- 3F. CLOCK GENERATOR PROCESS
    -- ========================================================================
    -- Generates a continuous 100 MHz clock (10 ns period).
    -- The clock toggles every 5 ns: LOW for 5 ns, HIGH for 5 ns.
    -- This clock drives both the CPU and the memory process.
    -- The process runs forever (while true) - simulation ends via the
    -- stimulus process using "assert false severity failure".
    -- ========================================================================
    clk_process : process
    begin
        while true loop
            clk <= '0';
            wait for clk_period / 2;   -- LOW phase: 5 ns
            clk <= '1';
            wait for clk_period / 2;   -- HIGH phase: 5 ns
        end loop;
    end process;

    -- ========================================================================
    -- 3G. STIMULUS PROCESS
    -- ========================================================================
    -- Controls the simulation sequence:
    --   1. Assert reset for 15 ns to initialize the CPU
    --   2. Release reset - CPU begins fetching instructions from address 0x00
    --   3. Wait while CPU executes the program (12 instructions)
    --   4. Cycle through regselect values to observe internal registers
    --   5. Display final memory contents to verify correctness
    --   6. End simulation
    --
    -- Timing breakdown:
    --   0-15 ns    : reset held HIGH (CPU in resetState)
    --   15 ns      : reset released (CPU transitions to fetch state)
    --   15-215 ns  : CPU runs, regselect="00" (display iReg)
    --   215-415 ns : regselect="01" (display THIS / saved PC)
    --   415-615 ns : regselect="10" (display ACC)
    --   615-1615 ns: regselect="11" (display IAR), CPU finishes all instructions
    --   1615 ns    : display results and end simulation
    -- ========================================================================
    stim_proc : process
    begin
        -- Step 1: Hold reset active for 15 ns
        --         This puts the CPU into resetState, clearing all registers:
        --         PC=0, ACC=0, iReg=0, IAR=0, THIS=0, tick=0
        reset <= '1';
        wait for 15 ns;

        -- Step 2: Release reset - CPU starts executing from address 0x00
        --         CPU transitions: resetState -> fetch -> (execute instructions)
        reset <= '0';
        report "Reset deasserted -- CPU begins execution from address 0x00";

        -- Step 3: Let CPU run while cycling through debug register views
        --         The CPU processes all 12 instructions during this time.
        --         Each instruction takes 4-7 clock cycles (40-70 ns).
        --         Total program execution takes roughly 700-800 ns.

        wait for 200 ns;
        regselect <= "01";  -- View THIS register (address of current instruction)

        wait for 200 ns;
        regselect <= "10";  -- View ACC register (accumulator value)

        wait for 200 ns;
        regselect <= "11";  -- View IAR register (indirect address register)

        wait for 1000 ns;   -- Extra wait to ensure all instructions complete

        -- Step 5: End simulation
        --         VHDL has no $finish like Verilog; we use an assertion failure
        --         to stop the simulator. The "Failure:" message is normal and
        --         expected - it is the standard way to terminate VHDL simulation.
        assert false report "End of simulation" severity failure;
    end process;

    -- ========================================================================
    -- 3H. MEMORY PROCESS (Synchronous Read / Synchronous Write)
    -- ========================================================================
    -- This process simulates the external memory (RAM) connected to the CPU.
    -- It operates on the rising edge of the clock.
    --
    -- How the CPU-memory interaction works per instruction:
    --
    --   FETCH (every instruction starts here):
    --     Cycle 0: CPU sets en='1', rw='1', aBus=PC (request read)
    --     Cycle 1: Memory places data on dbus, CPU latches it into iReg
    --     Cycle 2: CPU decodes iReg, transitions to execute state
    --
    --   READ (DLOAD, ADD, AND, etc.):
    --     Cycle 0: CPU sets en='1', rw='1', aBus=operand_address
    --     Cycle 1: Memory places data on dbus, CPU reads it into ACC/ALU
    --
    --   WRITE (DSTORE, ISTORE):
    --     Cycle 0: CPU sets en='1', rw='0', aBus=address, dBus=ACC
    --              Memory captures dbus value into memory array
    --
    -- Bus hold behavior:
    --   After a READ:  dbus_oe='1', dbus_out holds last value (bus stays driven)
    --   After a WRITE: dbus_oe='0' (memory releases bus, CPU was driving it)
    --   Otherwise:     dbus_oe and dbus_out hold their previous values
    --
    -- Address mapping:
    --   Only the lower 8 bits of abus are used: abus(7 downto 0)
    --   This gives a 256-word address space (0x00 to 0xFF)
    -- ========================================================================
    memory_proc : process(clk)
    begin
        if rising_edge(clk) then
            if en = '1' and rw = '1' then
                -- MEMORY READ: CPU requested data from memory
                -- Latch the memory word at the requested address into dbus_out
                -- Set dbus_oe='1' so the bus arbitration drives this value onto dbus
                dbus_out <= memory(to_integer(unsigned(abus(7 downto 0))));
                dbus_oe  <= '1';

            elsif en = '1' and rw = '0' then
                -- MEMORY WRITE: CPU is writing ACC to memory
                -- Capture the value on dbus (driven by CPU) into the memory array
                -- Set dbus_oe='0' because CPU is driving the bus, not memory
                memory(to_integer(unsigned(abus(7 downto 0)))) <= dbus;
                dbus_oe <= '0';
            end if;
            -- If en='0' or no memory access: hold dbus_oe and dbus_out unchanged
            -- This keeps the last-read value on the bus for the CPU to sample
        end if;
    end process;

end behavior;

