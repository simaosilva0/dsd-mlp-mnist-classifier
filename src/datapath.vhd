-- Datapath (pipelined version).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity datapath is
  port (
    clk     : in  std_logic;
    a0, a1, a2, a3 : in std_logic_vector(7 downto 0);
    b0, b1, b2, b3 : in std_logic_vector(7 downto 0);
    sel     : in  std_logic;   -- 0: lanes 0/1, 1: lanes 2/3
    ld_p    : in  std_logic;
    ld_s    : in  std_logic;
    ld_acc  : in  std_logic;
    first   : in  std_logic;   -- start a new row
    dataOUT : out std_logic_vector(31 downto 0)
    );
end datapath;

architecture behavioral of datapath is

  constant ACC_W : integer := 22;

  signal m1_a, m1_b, m2_a, m2_b : signed(7 downto 0);
  signal mul1, mul2              : signed(15 downto 0);
  signal sum_pair                : signed(16 downto 0);
  signal acc_op                  : signed(ACC_W - 1 downto 0);
  signal sum_acc                 : signed(ACC_W - 1 downto 0);

  signal r1, r2 : signed(15 downto 0)        := (others => '0');
  signal r3     : signed(16 downto 0)        := (others => '0');
  signal acc    : signed(ACC_W - 1 downto 0) := (others => '0');

begin

  m1_a <= signed(a0) when sel = '0' else signed(a2);
  m1_b <= signed(b0) when sel = '0' else signed(b2);
  m2_a <= signed(a1) when sel = '0' else signed(a3);
  m2_b <= signed(b1) when sel = '0' else signed(b3);

  mul1 <= m1_a * m1_b;
  mul2 <= m2_a * m2_b;

  sum_pair <= resize(r1, 17) + resize(r2, 17);

  acc_op  <= (others => '0') when first = '1' else acc;
  sum_acc <= acc_op + resize(r3, ACC_W);

  process (clk)
  begin
    if rising_edge(clk) then
      if ld_p = '1' then
        r1 <= mul1;
        r2 <= mul2;
      end if;
      if ld_s = '1' then
        r3 <= sum_pair;
      end if;
      if ld_acc = '1' then
        acc <= sum_acc;
      end if;
    end if;
  end process;

  -- ReLU
  dataOUT <= (others => '0') when acc(ACC_W - 1) = '1'
             else std_logic_vector(resize(unsigned(acc), 32));

end behavioral;
