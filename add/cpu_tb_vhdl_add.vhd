        -- ============================================================================
--  FILE        : cpu_tb_vhdl_add.vhd
--  DESCRIPTION : Student Testbench for WashU-2 CPU (Addition Test Only)
-- ============================================================================
--
--  INSTRUCTIONS FOR STUDENTS:
--  -----------------------------------
--  This testbench is for verifying your ADD operation implementation in the CPU design.
--  You must write a minimal instruction sequence (test program) in the memory initialization
--  that:
--    1. Loads two values into memory (e.g., mem[0x10] = 7, mem[0x11] = 8)
--    2. Loads the first value into ACC (using DLOAD or CLOAD)
--    3. Adds the second value to ACC (using ADD)
--    4. Stores the result to another memory location (using DSTORE)
--    5. Halts the CPU (using HALT)
--  After simulation, check that the result in memory matches the expected sum.
--
--  Example (pseudocode, not actual VHDL):
--    mem[0x00] = CLOAD 0x0000   -- (optional, clear ACC)
--    mem[0x01] = DLOAD 0x10     -- ACC = mem[0x10] (7)
--    mem[0x02] = ADD 0x11       -- ACC = ACC + mem[0x11] (8)
--    mem[0x03] = DSTORE 0x12    -- mem[0x12] = ACC (should be 15)
--    mem[0x04] = HALT
--    mem[0x10] = 7
--    mem[0x11] = 8
--    mem[0x12] = 0 (result will be written here)
--
--  Write the actual instruction encodings in your VHDL memory initialization.
-- ============================================================================

-- ...existing library imports, entity, architecture, and component declaration...

-- In the memory initialization section, REMOVE the old test program and
-- REPLACE it with your own minimal addition test as described above.
--
-- ...rest of the testbench code remains unchanged...
-- ============================================================================
library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

-- ============================================================================
-- SECTION 2: ENTITY DECLARATION
-- ============================================================================
entity cpu_tb is
end cpu_tb;

-- ============================================================================
-- SECTION 3: ARCHITECTURE
-- ============================================================================
architecture behavior of cpu_tb is

    -- ========================================================================
    -- 3A. COMPONENT DECLARATION
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
    signal   clk        : std_logic := '0';
    constant clk_period : time := 10 ns;

    signal reset : std_logic := '1';

    signal en   : std_logic;
    signal rw   : std_logic;
    signal abus : std_logic_vector(15 downto 0);
    signal dbus : std_logic_vector(15 downto 0);

    signal pause     : std_logic := '0';
    signal regselect : std_logic_vector(1 downto 0) := "00";
    signal dispreg   : std_logic_vector(15 downto 0);

    -- ========================================================================
    -- 3C. MEMORY DECLARATION (256 x 16-bit words)
    -- ========================================================================
    --

    --
    -- ========================================================================

type memory_type is array (0 to 255) of std_logic_vector(15 downto 0);

signal memory : memory_type := (
    -- ============================================================
    -- ADD TEST: 7 + 8 = 15 (0x000F)
    -- ============================================================

    0  => x"1000",   -- CLOAD 0x00      | ACC = 0x0000 (clear)
    1  => x"1007",   -- CLOAD 0x07      | ACC = 7
    2  => x"5010",   -- DSTORE 0x10     | mem[0x10] = 7

    3  => x"1008",   -- CLOAD 0x08      | ACC = 8
    4  => x"5011",   -- DSTORE 0x11     | mem[0x11] = 8

    5  => x"2010",   -- DLOAD 0x10      | ACC = mem[0x10] = 7
    6  => x"8011",   -- ADD 0x11        | ACC = 7 + 8 = 15

    7  => x"5012",   -- DSTORE 0x12     | mem[0x12] = 15

    8  => x"0000",   -- HALT

    others => x"0000"
);

    -- ========================================================================
    -- 3D. BUS HOLD SIGNALS
    -- ========================================================================
    signal dbus_out    : std_logic_vector(15 downto 0) := (others => '0');
    signal dbus_oe     : std_logic := '0';
    signal cpu_writing : std_logic;

begin

    -- ========================================================================
    -- 3E. CONCURRENT SIGNAL ASSIGNMENTS
    -- ========================================================================
    cpu_writing <= en and (not rw);

    dbus <= dbus_out when (cpu_writing = '0' and dbus_oe = '1')
            else (others => 'Z');

    -- ========================================================================
    -- CPU INSTANTIATION
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
    clk_process : process
    begin
        while true loop
            clk <= '0';
            wait for clk_period / 2;
            clk <= '1';
            wait for clk_period / 2;
        end loop;
    end process;

    -- ========================================================================
    -- 3G. STIMULUS PROCESS
    -- ========================================================================
    stim_proc : process
    begin
        -- Step 1: Hold reset active
        reset <= '1';
        wait for 15 ns;

        -- Step 2: Release reset
        reset <= '0';
        report "Reset deasserted -- CPU begins execution from address 0x00";

        -- Step 3: Let CPU run
        wait for 200 ns;
        regselect <= "01";

        wait for 200 ns;
        regselect <= "10";

        wait for 200 ns;
        regselect <= "11";

        wait for 1000 ns;   -- Extra wait to ensure all instructions complete

         -- Step 4: Display the final simulation results
         report "";
         report "============================================================";
         report "         ADD Instruction Complete Testbench Results";
         report "============================================================";
         report "";
         report "  ALU operation: alu = ""0000"" & (acc(11:0) AND dBus(11:0))";
         report "";
         report "  TEST 1: 0x07 ADD 0x08 = 0x0F ";
         report "    mem[0x12] = " & integer'image(to_integer(unsigned(memory(18)))) & " (expected: 15)";
         assert memory(18) = x"000F"
             report "    >>> FAIL: mem[0x10] should be 255 (0xFF AND 0xFF)" severity error;
         if memory(18) = x"000F" then
             report "    >>> PASS";
         end if;

         report "";
         report "============================================================";
         report "  Simulation complete -- ADD verified.";
         report "============================================================";

        -- Step 5: End simulation
        assert false report "End of simulation" severity failure;
    end process;

    -- ========================================================================
    -- 3H. MEMORY PROCESS (Synchronous Read / Synchronous Write)
    -- ========================================================================
    memory_proc : process(clk)
    begin
        if rising_edge(clk) then
            if en = '1' and rw = '1' then
                dbus_out <= memory(to_integer(unsigned(abus(7 downto 0))));
                dbus_oe  <= '1';
            elsif en = '1' and rw = '0' then
                memory(to_integer(unsigned(abus(7 downto 0)))) <= dbus;
                dbus_oe <= '0';
            end if;
        end if;
    end process;

end behavior;