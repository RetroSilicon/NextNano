library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity keyjoy_sdpram_64_6  is
port
(
	DPRA : in  std_logic_vector(5 downto 0);
	DPO  : out std_logic_vector(5 downto 0);
	CLK  : in  std_logic;
	WE   : in  std_logic;
	A    : in  std_logic_vector(5 downto 0);
	D    : in  std_logic_vector(5 downto 0)
);
end entity;

architecture rtl of keyjoy_sdpram_64_6 is
begin

	ram: work.dpram
	generic map
	(
		addr_width_a => 6,
		data_width_a => 6,
		addr_width_b => 6,
		data_width_b => 6,
		mem_init_file  => "rtl/mister/keyjoy_sdpram_64_6.mif"
	)
	port map
	(
		clock0    => CLK,
		address_a => DPRA,
		q_a       => DPO,

		clock1    => CLK,
		wren_b    => WE,
		address_b => A,
		data_b    => D
	);

end rtl;

------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdpram_128_8 is
port
(
	DPRA : in  std_logic_vector(6 downto 0);
	DPO  : out std_logic_vector(7 downto 0);
	CLK  : in  std_logic;
	WE   : in  std_logic;
	A    : in  std_logic_vector(6 downto 0);
	D    : in  std_logic_vector(7 downto 0)
);
end entity;

architecture rtl of sdpram_128_8 is
begin

	ram : work.mlab
	generic map
	(
		addr_width  => 7,
		data_width  => 8
	)
	port map
	(
		clk       => CLK,
		rdaddress => DPRA,
		q         => DPO,
		wraddress => A,
		data      => D,
		wren      => WE
	);

end rtl;

------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spram_320_9 is
port
(
	CLK  : in  std_logic;
	WE   : in  std_logic;
	SPO  : out std_logic_vector(8 downto 0);
	A    : in  std_logic_vector(8 downto 0);
	D    : in  std_logic_vector(8 downto 0)
);
end entity;

architecture rtl of spram_320_9 is
begin

	ram : work.mlab
	generic map
	(
		addr_width  => 9,
		data_width  => 9
	)
	port map
	(
		clk       => CLK,
		rdaddress => A,
		q         => SPO,
		wraddress => A,
		data      => D,
		wren      => WE
	);

end rtl; 

------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdpbram_16k_8 is
port
(
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
begin

	ram: work.dpram
	generic map (
		addr_width_a  => 14,
		data_width_a  => 8,
		addr_width_b  => 14,
		data_width_b  => 8
	)
	port map
	(
		clock0		=> CLKA,
		clock1		=> CLKB,
		
		address_a	=> ADDRA,
		data_a		=> DINA,
		wren_a		=> WEA,

		address_b	=> ADDRB,
		q_b			=> DOUTB
	);

end rtl; 

------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdpram_16_9 is
port
(
	DPRA : in  std_logic_vector(3 downto 0);
	DPO  : out std_logic_vector(8 downto 0);
	CLK  : in  std_logic;
	WE   : in  std_logic;
	A    : in  std_logic_vector(3 downto 0);
	D    : in  std_logic_vector(8 downto 0)
);
end entity;

architecture rtl of sdpram_16_9 is
begin

	ram : work.mlab
	generic map
	(
		addr_width  => 4,
		data_width  => 9
	)
	port map
	(
		clk       => CLK,
		rdaddress => DPRA,
		q         => DPO,
		wraddress => A,
		data      => D,
		wren      => WE
	);

end rtl;

------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdpram_64_9 is
port
(
	DPRA  : IN  STD_LOGIC_VECTOR(5 downto 0);
	CLK   : IN STD_LOGIC;
	WE    : IN  STD_LOGIC;
	DPO   : OUT STD_LOGIC_VECTOR(8 downto 0);
	A     : IN  STD_LOGIC_VECTOR(5 downto 0);
	D     : IN  STD_LOGIC_VECTOR(8 downto 0)

);
end entity;

architecture rtl of sdpram_64_9 is
begin

	ram : work.mlab
	generic map
	(
		addr_width  => 6,
		data_width  => 9
	)
	port map
	(
		clk       => CLK,
		rdaddress => DPRA,
		q         => DPO,
		wraddress => A,
		data      => D,
		wren      => WE
	);

end rtl;

------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity tdpram is
generic (
	addr_width_g : integer := 8;
	data_width_g : integer := 8
);
port (
	clk_a_i  : in  std_logic;
	we_a_i   : in  std_logic;
	addr_a_i : in  std_logic_vector(addr_width_g-1 downto 0);
	data_a_i : in  std_logic_vector(data_width_g-1 downto 0);
	data_a_o : out std_logic_vector(data_width_g-1 downto 0);
	--
	clk_b_i  : in  std_logic;
	we_b_i   : in  std_logic;
	addr_b_i : in  std_logic_vector(addr_width_g-1 downto 0);
	data_b_i : in  std_logic_vector(data_width_g-1 downto 0);
	data_b_o : out std_logic_vector(data_width_g-1 downto 0)
);
end entity;

architecture rtl of tdpram is
begin

ram: work.dpram
generic map (
	addr_width_a  => addr_width_g,
	data_width_a  => data_width_g,
	addr_width_b  => addr_width_g,
	data_width_b  => data_width_g
)
port map
(
	clock0		=> clk_a_i,
	clock1		=> clk_b_i,
	
	address_a	=> addr_a_i,
	data_a		=> data_a_i,
	wren_a		=> we_a_i,
	q_a			=> data_a_o,

	address_b	=> addr_b_i,
	data_b		=> data_b_i,
	wren_b		=> we_b_i,
	q_b			=> data_b_o
);

end architecture; 

------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dpram2 is
generic (
	addr_width_g : integer := 8;
	data_width_g : integer := 8;
	init_file_g  : string  := " "
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

	ram: work.dpram
	generic map (
		addr_width_a  => addr_width_g,
		data_width_a  => data_width_g,
		addr_width_b  => addr_width_g,
		data_width_b  => data_width_g,
		mem_init_file => init_file_g
	)
	port map
	(
		clock0		=> clk_a_i,
		clock1		=> clk_b_i,
		
		address_a	=> addr_a_i,
		data_a		=> data_a_i,
		wren_a		=> we_i,
		q_a			=> data_a_o,

		address_b	=> addr_b_i,
		q_b			=> data_b_o
	);

end rtl;

----------------------
-- Dual port Block RAM different parameters and clocks on ports
--------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

entity dpram is
	generic (
		addr_width_a  : integer := 8;
		data_width_a  : integer := 8;
		addr_width_b  : integer := 8;
		data_width_b  : integer := 8;
		mem_init_file : string := " "
	);
	PORT
	(
		clock0		: in  STD_LOGIC;
		clock1		: in  STD_LOGIC;
		
		address_a	: in  STD_LOGIC_VECTOR (addr_width_a-1 DOWNTO 0);
		data_a		: in  STD_LOGIC_VECTOR (data_width_a-1 DOWNTO 0) := (others => '0');
		enable_a		: in  STD_LOGIC := '1';
		wren_a		: in  STD_LOGIC := '0';
		q_a			: out STD_LOGIC_VECTOR (data_width_a-1 DOWNTO 0);
		cs_a        : in  std_logic := '1';

		address_b	: in  STD_LOGIC_VECTOR (addr_width_b-1 DOWNTO 0) := (others => '0');
		data_b		: in  STD_LOGIC_VECTOR (data_width_b-1 DOWNTO 0) := (others => '0');
		enable_b		: in  STD_LOGIC := '1';
		wren_b		: in  STD_LOGIC := '0';
		q_b			: out STD_LOGIC_VECTOR (data_width_b-1 DOWNTO 0);
		cs_b        : in  std_logic := '1'
	);
end entity;


ARCHITECTURE SYN OF dpram IS

	signal q0 : std_logic_vector((data_width_a - 1) downto 0);
	signal q1 : std_logic_vector((data_width_b - 1) downto 0);

BEGIN
	q_a<= q0 when cs_a = '1' else (others => '1');
	q_b<= q1 when cs_b = '1' else (others => '1');

	altsyncram_component : altsyncram
	GENERIC MAP (
		address_reg_b => "CLOCK1",
		clock_enable_input_a => "NORMAL",
		clock_enable_input_b => "NORMAL",
		clock_enable_output_a => "BYPASS",
		clock_enable_output_b => "BYPASS",
		indata_reg_b => "CLOCK1",
		intended_device_family => "Cyclone V",
		lpm_type => "altsyncram",
		numwords_a => 2**addr_width_a,
		numwords_b => 2**addr_width_b,
		operation_mode => "BIDIR_DUAL_PORT",
		outdata_aclr_a => "NONE",
		outdata_aclr_b => "NONE",
		outdata_reg_a => "UNREGISTERED",
		outdata_reg_b => "UNREGISTERED",
		power_up_uninitialized => "FALSE",
		read_during_write_mode_port_a => "NEW_DATA_NO_NBE_READ",
		read_during_write_mode_port_b => "NEW_DATA_NO_NBE_READ",
		init_file => mem_init_file, 
		widthad_a => addr_width_a,
		widthad_b => addr_width_b,
		width_a => data_width_a,
		width_b => data_width_b,
		width_byteena_a => 1,
		width_byteena_b => 1,
		wrcontrol_wraddress_reg_b => "CLOCK1"
	)
	PORT MAP (
		address_a => address_a,
		address_b => address_b,
		clock0 => clock0,
		clock1 => clock1,
		clocken0 => enable_a,
		clocken1 => enable_b,
		data_a => data_a,
		data_b => data_b,
		wren_a => wren_a and cs_a,
		wren_b => wren_b and cs_b,
		q_a => q0,
		q_b => q1
	);

END SYN;

------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mlab is
	generic (
		addr_width  : integer := 8;
		data_width  : integer := 8
	);
	port
	(
		clk       : in  std_logic;
		rdaddress : in  std_logic_vector(addr_width-1 downto 0);
		q         : out std_logic_vector(data_width-1 downto 0);
		wraddress : in  std_logic_vector(addr_width-1 downto 0);
		data      : in  std_logic_vector(data_width-1 downto 0);
		wren      : in  std_logic
	);
end entity;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;

architecture rtl of mlab is
begin

	altdpram_component : altdpram
	GENERIC MAP (
		indata_aclr => "OFF",
		indata_reg => "INCLOCK",
		intended_device_family => "Cyclone V",
		lpm_type => "altdpram",
		outdata_aclr => "OFF",
		outdata_reg => "UNREGISTERED",
		ram_block_type => "MLAB",
		rdaddress_aclr => "OFF",
		rdaddress_reg => "UNREGISTERED",
		rdcontrol_aclr => "OFF",
		rdcontrol_reg => "UNREGISTERED",
		width => data_width,
		widthad => addr_width,
		width_byteena => 1,
		wraddress_aclr => "OFF",
		wraddress_reg => "INCLOCK",
		wrcontrol_aclr => "OFF",
		wrcontrol_reg => "INCLOCK"
	)
	PORT MAP (
		data => data,
		inclock => clk,
		rdaddress => rdaddress,
		wraddress => wraddress,
		wren => wren,
		q => q
	);

end rtl;
