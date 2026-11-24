-- Top level (pipelined version).
library ieee;
use ieee.std_logic_1164.all;

-- Top-level ports: OMemC's write control (we, addr), OMemC's read data (dataOUT)
-- and done.
entity circuito is
  port (
    clk     : in  std_logic;
    reset   : in  std_logic;
    done    : out std_logic;
    we      : out std_logic;
    addr    : out std_logic_vector(3 downto 0);
    dataOUT : out std_logic_vector(31 downto 0)
    );
end circuito;

architecture structural of circuito is

  -- Course memories, declared as components so any memory set can be swapped in.
  component IMemB is
    port (
      clk   : in  std_logic;
      addr  : in  std_logic_vector(9 downto 0);
      data0 : out std_logic_vector(7 downto 0);
      data1 : out std_logic_vector(7 downto 0);
      data2 : out std_logic_vector(7 downto 0);
      data3 : out std_logic_vector(7 downto 0));
  end component;

  component WMemA is
    port (
      clk   : in  std_logic;
      addr  : in  std_logic_vector(9 downto 0);
      data0 : out std_logic_vector(7 downto 0);
      data1 : out std_logic_vector(7 downto 0);
      data2 : out std_logic_vector(7 downto 0);
      data3 : out std_logic_vector(7 downto 0));
  end component;

  component OMemC is
    port (
      clk     : in  std_logic;
      addr    : in  std_logic_vector(9 downto 0);
      we      : in  std_logic;
      dataIN  : in  std_logic_vector(31 downto 0);
      dataOUT : out std_logic_vector(31 downto 0));
  end component;

  -- Our two blocks: control unit and datapath.
  component control is
    port (
      clk       : in  std_logic;
      reset     : in  std_logic;
      sel       : out std_logic;
      ld_p      : out std_logic;
      ld_s      : out std_logic;
      ld_acc    : out std_logic;
      first     : out std_logic;
      addrIMemB : out std_logic_vector(3 downto 0);
      addrWMemA : out std_logic_vector(7 downto 0);
      addrOMemC : out std_logic_vector(3 downto 0);
      we        : out std_logic;
      done      : out std_logic);
  end component;

  component datapath is
    port (
      clk            : in  std_logic;
      a0, a1, a2, a3 : in  std_logic_vector(7 downto 0);
      b0, b1, b2, b3 : in  std_logic_vector(7 downto 0);
      sel            : in  std_logic;
      ld_p           : in  std_logic;
      ld_s           : in  std_logic;
      ld_acc         : in  std_logic;
      first          : in  std_logic;
      dataOUT        : out std_logic_vector(31 downto 0));
  end component;

  -- Addresses (short from control, padded to the BRAM's 10 bits) and memory data.
  signal addrIMemB, addrOMemC : std_logic_vector(3 downto 0);
  signal addrWMemA            : std_logic_vector(7 downto 0);
  signal addrIMemB_full, addrWMemA_full, addrOMemC_full : std_logic_vector(9 downto 0);
  signal IMemB_data0, IMemB_data1, IMemB_data2, IMemB_data3 : std_logic_vector(7 downto 0);
  signal WMemA_data0, WMemA_data1, WMemA_data2, WMemA_data3 : std_logic_vector(7 downto 0);
  signal OMemC_dataIN, OMemC_dataOUT : std_logic_vector(31 downto 0);
  signal we_i : std_logic;

  -- Control signals from control to datapath.
  signal sel, ld_p, ld_s, ld_acc, first : std_logic;

begin

  -- The BRAM macro always has a 10-bit address; pad with zeros.
  addrIMemB_full <= "000000" & addrIMemB;
  addrWMemA_full <= "00" & addrWMemA;
  addrOMemC_full <= "000000" & addrOMemC;

  -- The three memories.
  inst_IMemB : IMemB
    port map (clk => clk, addr => addrIMemB_full,
              data0 => IMemB_data0, data1 => IMemB_data1,
              data2 => IMemB_data2, data3 => IMemB_data3);

  inst_WMemA : WMemA
    port map (clk => clk, addr => addrWMemA_full,
              data0 => WMemA_data0, data1 => WMemA_data1,
              data2 => WMemA_data2, data3 => WMemA_data3);

  inst_OMemC : OMemC
    port map (clk => clk, addr => addrOMemC_full, we => we_i,
              dataIN => OMemC_dataIN, dataOUT => OMemC_dataOUT);

  -- Control unit: generates addresses, we, done and the datapath controls.
  inst_control : control
    port map (clk => clk, reset => reset,
              sel => sel, ld_p => ld_p, ld_s => ld_s,
              ld_acc => ld_acc, first => first,
              addrIMemB => addrIMemB, addrWMemA => addrWMemA, addrOMemC => addrOMemC,
              we => we_i, done => done);

  -- Datapath: a0..a3 from WMemA, b0..b3 from IMemB, result to OMemC.
  inst_datapath : datapath
    port map (clk => clk,
              a0 => WMemA_data0, a1 => WMemA_data1, a2 => WMemA_data2, a3 => WMemA_data3,
              b0 => IMemB_data0, b1 => IMemB_data1, b2 => IMemB_data2, b3 => IMemB_data3,
              sel => sel, ld_p => ld_p, ld_s => ld_s,
              ld_acc => ld_acc, first => first,
              dataOUT => OMemC_dataIN);

  -- Top-level outputs. dataOUT is OMemC's read port: the BRAM is in write-first
  -- mode, so C[m] appears on it one clock cycle after the write (we = 1).
  -- Reading OMemC also keeps synthesis from removing it as unused.
  we      <= we_i;
  addr    <= addrOMemC;
  dataOUT <= OMemC_dataOUT;

end structural;
