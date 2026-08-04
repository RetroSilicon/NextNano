-------------------------------------------------------------------------------
-- BRAM modules for Gowin FPGA (Tang Nano 20K)
-- 
-- Gowin synthesis will infer these as DPB (True Dual Port Block SRAM)
-- Based on Gowin UG285 - BSRAM & SSRAM User Guide
--
-- Required modules for ZX Spectrum Next:
--   dpram        - base true dual-port RAM 
--   dpram2       - dual-port RAM with one write port
--   sdpram_128_8 - simple dual-port RAM 128 x 8
--   spram_320_9  - single-port RAM 320 x 9  
--   sdpbram_16k_8 - simple dual-port BRAM 16K x 8
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- dpram - True Dual Port RAM
-- Both ports can read and write, independent clocks
-- Gowin will infer this as DPB primitive
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dpram is
    generic (
        addr_width_a  : integer := 8;
        data_width_a  : integer := 8;
        addr_width_b  : integer := 8;
        data_width_b  : integer := 8;
        mem_init_file : string := " "  -- ignored, kept for compatibility
    );
    port (
        clock0      : in  std_logic;
        clock1      : in  std_logic;
        
        address_a   : in  std_logic_vector(addr_width_a-1 downto 0);
        data_a      : in  std_logic_vector(data_width_a-1 downto 0) := (others => '0');
        enable_a    : in  std_logic := '1';
        wren_a      : in  std_logic := '0';
        q_a         : out std_logic_vector(data_width_a-1 downto 0);
        cs_a        : in  std_logic := '1';

        address_b   : in  std_logic_vector(addr_width_b-1 downto 0) := (others => '0');
        data_b      : in  std_logic_vector(data_width_b-1 downto 0) := (others => '0');
        enable_b    : in  std_logic := '1';
        wren_b      : in  std_logic := '0';
        q_b         : out std_logic_vector(data_width_b-1 downto 0);
        cs_b        : in  std_logic := '1'
    );
end entity;

architecture rtl of dpram is
    type ram_type is array (0 to 2**addr_width_a - 1) of std_logic_vector(data_width_a-1 downto 0);
    shared variable ram : ram_type := (others => (others => '0'));
    
    signal q0 : std_logic_vector(data_width_a-1 downto 0);
    signal q1 : std_logic_vector(data_width_b-1 downto 0);
begin

    q_a <= q0 when cs_a = '1' else (others => '1');
    q_b <= q1 when cs_b = '1' else (others => '1');

    -- Port A: synchronous read/write
    process(clock0)
    begin
        if rising_edge(clock0) then
            if enable_a = '1' then
                if wren_a = '1' and cs_a = '1' then
                    ram(to_integer(unsigned(address_a))) := data_a;
                end if;
                q0 <= ram(to_integer(unsigned(address_a)));
            end if;
        end if;
    end process;

    -- Port B: synchronous read/write
    process(clock0)
    begin
        if falling_edge(clock0) then
            if enable_b = '1' then
                if wren_b = '1' and cs_b = '1' then
                    ram(to_integer(unsigned(address_b))) := data_b;
                end if;
                q1 <= ram(to_integer(unsigned(address_b)));
            end if;
        end if;
    end process;

end rtl;

-------------------------------------------------------------------------------
-- dpram2 - Dual port RAM with one write port (port A) and read-only port (port B)
-- 
-- Used in zxnext.vhd for:
--   - copper_inst_msb_ram, copper_inst_lsb_ram (Copper co-processor)
--   - bank5_ram (16KB ULA video RAM)
--   - bank7_ram (8KB video RAM)  
--   - palette_utm (ULA/Tilemap palette)
--   - palette_l2s (Layer2/Sprites palette)
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dpram2 is
    generic (
        addr_width_g : integer := 8;
        data_width_g : integer := 8;
        init_file_g  : string  := " "  -- ignored, kept for compatibility
    );
    port (
        clk_a_i  : in  std_logic;
        we_i     : in  std_logic;
        addr_a_i : in  std_logic_vector(addr_width_g-1 downto 0);
        data_a_i : in  std_logic_vector(data_width_g-1 downto 0);
        data_a_o : out std_logic_vector(data_width_g-1 downto 0);
        --
        clk_b_i  : in  std_logic;
        addr_b_i : in  std_logic_vector(addr_width_g-1 downto 0);
        data_b_o : out std_logic_vector(data_width_g-1 downto 0)
    );
end entity;

architecture rtl of dpram2 is
begin

    ram_inst: entity work.dpram
    generic map (
        addr_width_a  => addr_width_g,
        data_width_a  => data_width_g,
        addr_width_b  => addr_width_g,
        data_width_b  => data_width_g
    )
    port map (
        clock0    => clk_a_i,
        clock1    => clk_b_i,
        
        address_a => addr_a_i,
        data_a    => data_a_i,
        wren_a    => we_i,
        q_a       => data_a_o,

        address_b => addr_b_i,
        q_b       => data_b_o
    );

end rtl;

-------------------------------------------------------------------------------
-- sdpram_128_8 - Simple Dual Port RAM 128 x 8
-- One write port, one read port, same clock
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdpram_128_8 is
    port (
        DPRA : in  std_logic_vector(6 downto 0);
        DPO  : out std_logic_vector(7 downto 0);
        CLK  : in  std_logic;
        WE   : in  std_logic;
        A    : in  std_logic_vector(6 downto 0);
        D    : in  std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of sdpram_128_8 is
    type ram_type is array (0 to 127) of std_logic_vector(7 downto 0);
    signal ram : ram_type := (others => (others => '0'));
begin

    process(CLK)
    begin
        if falling_edge(CLK) then
            if WE = '1' then
                ram(to_integer(unsigned(A))) <= D;
            end if;
        end if;
    end process;

    -- Asynchronous read
    DPO <= ram(to_integer(unsigned(DPRA)));

end rtl;

-------------------------------------------------------------------------------
-- sdpram_64_9 - Simple Dual Port RAM 64 x 9
-- One write port, one read port, same clock
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdpram_64_9 is
    port (
        DPRA : in  std_logic_vector(5 downto 0);
        DPO  : out std_logic_vector(8 downto 0);
        CLK  : in  std_logic;
        WE   : in  std_logic;
        A    : in  std_logic_vector(5 downto 0);
        D    : in  std_logic_vector(8 downto 0)
    );
end entity;

architecture rtl of sdpram_64_9 is
    type ram_type is array (0 to 63) of std_logic_vector(8 downto 0);
    signal ram : ram_type := (others => (others => '0'));
begin

    process(CLK)
    begin
        if rising_edge(CLK) then
            if WE = '1' then
                ram(to_integer(unsigned(A))) <= D;
            end if;
        end if;
    end process;

    -- Asynchronous read
    DPO <= ram(to_integer(unsigned(DPRA)));

end rtl;

-------------------------------------------------------------------------------
-- sdpram_16_9 - Simple Dual Port RAM 16 x 9
-- One write port, one read port, same clock
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdpram_16_9 is
    port (
        DPRA : in  std_logic_vector(3 downto 0);
        DPO  : out std_logic_vector(8 downto 0);
        CLK  : in  std_logic;
        WE   : in  std_logic;
        A    : in  std_logic_vector(3 downto 0);
        D    : in  std_logic_vector(8 downto 0)
    );
end entity;

architecture rtl of sdpram_16_9 is
    type ram_type is array (0 to 15) of std_logic_vector(8 downto 0);
    signal ram : ram_type := (others => (others => '0'));
begin

    process(CLK)
    begin
        if rising_edge(CLK) then
            if WE = '1' then
                ram(to_integer(unsigned(A))) <= D;
            end if;
        end if;
    end process;

    -- Asynchronous read
    DPO <= ram(to_integer(unsigned(DPRA)));

end rtl;

-------------------------------------------------------------------------------
-- spram_320_9 - Single Port RAM 320 x 9 (uses 512 depth internally)
-- One port for both read and write
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spram_320_9 is
    port (
        CLK  : in  std_logic;
        WE   : in  std_logic;
        SPO  : out std_logic_vector(8 downto 0);
        A    : in  std_logic_vector(8 downto 0);
        D    : in  std_logic_vector(8 downto 0)
    );
end entity;

architecture rtl of spram_320_9 is
    type ram_type is array (0 to 511) of std_logic_vector(8 downto 0);
    signal ram : ram_type := (others => (others => '0'));
begin

    process(CLK)
    begin
        if falling_edge(CLK) then
            if WE = '1' then
                ram(to_integer(unsigned(A))) <= D;
            end if;
        end if;
    end process;

    -- Asynchronous read
    SPO <= ram(to_integer(unsigned(A)));

end rtl;

-------------------------------------------------------------------------------
-- sdpbram_16k_8 - Simple Dual Port BRAM 16K x 8
-- Port A: write only, Port B: read only, independent clocks
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdpbram_16k_8 is
    port (
        WEA    : in  std_logic;
        ADDRA  : in  std_logic_vector(13 downto 0);
        DINA   : in  std_logic_vector(7 downto 0);
        CLKA   : in  std_logic;
        --
        ENB    : in  std_logic;
        ADDRB  : in  std_logic_vector(13 downto 0);
        DOUTB  : out std_logic_vector(7 downto 0);
        CLKB   : in  std_logic
    );
end entity;

architecture rtl of sdpbram_16k_8 is
    type ram_type is array (0 to 16383) of std_logic_vector(7 downto 0);
    shared variable ram : ram_type := (others => (others => '0'));
begin

    -- Port A: write only
    process(CLKB)
    begin
        if falling_edge(CLKB) then
            if WEA = '1' then
                ram(to_integer(unsigned(ADDRA))) := DINA;
            end if;
        end if;
    end process;

    -- Port B: read only
    process(CLKB)
    begin
        if rising_edge(CLKB) then
            if ENB = '1' then
                DOUTB <= ram(to_integer(unsigned(ADDRB)));
            end if;
        end if;
    end process;

end rtl;

-- ============================================================================
-- keyjoy_sdpram_64_6 - Simple Dual Port RAM 64x6 (async read, sync write)
-- Replacement for Xilinx distributed RAM used in membrane_stick
-- Initialized with Sinclair/Cursor joystick mappings
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity keyjoy_sdpram_64_6 is
    port (
        -- Async read port (keymap)
        DPRA : in  std_logic_vector(5 downto 0);
        DPO  : out std_logic_vector(5 downto 0);
        -- Sync write port (cpu)
        CLK  : in  std_logic;
        WE   : in  std_logic;
        A    : in  std_logic_vector(5 downto 0);
        D    : in  std_logic_vector(5 downto 0)
    );
end entity;

architecture rtl of keyjoy_sdpram_64_6 is
    type ram_t is array(0 to 63) of std_logic_vector(5 downto 0);
    
    -- Sinclair/Cursor joystick mapping from keyjoy_sdpram_64_6.mif
    signal ram : ram_t := (
        -- 0-7
        0  => "100011",
        1  => "100100",
        2  => "100010",
        3  => "100001",
        4  => "100000",
        5  => "011001",
        6  => "011000",
        7  => "011010",
        -- 8-15
        8  => "011011",
        9  => "011100",
        10 => "100010",
        11 => "011100",
        12 => "100100",
        13 => "100011",
        14 => "100000",
        15 => "111111",
        -- 16-31
        16 to 31 => "000111",
        -- 32-39
        32 => "100011",
        33 => "100100",
        34 => "100010",
        35 => "100001",
        36 => "100000",
        37 => "011001",
        38 => "011000",
        39 => "011010",
        -- 40-47
        40 => "011011",
        41 => "011100",
        42 => "100010",
        43 => "011100",
        44 => "100100",
        45 => "100011",
        46 => "100000",
        47 => "111111",
        -- 48-63
        48 to 63 => "000111"
    );
begin
    -- Synchronous write
    process(CLK)
    begin
        if rising_edge(CLK) then
            if WE = '1' then
                ram(to_integer(unsigned(A))) <= D;
            end if;
        end if;
    end process;
    
    -- Asynchronous read
    DPO <= ram(to_integer(unsigned(DPRA)));
    
end architecture;